"""Migration check: the Alembic head matches the models (runs on SQLite in CI)."""

from __future__ import annotations

import asyncio
from pathlib import Path

import pytest
from alembic import command
from alembic.autogenerate import compare_metadata
from alembic.config import Config
from alembic.runtime.migration import MigrationContext
from alembic.script import ScriptDirectory
from sqlalchemy import create_engine

from app.core.config import get_settings
from app.models import Base

BACKEND = Path(__file__).resolve().parents[1]


def _head() -> str:
    cfg = Config(str(BACKEND / "alembic.ini"))
    cfg.set_main_option("script_location", str(BACKEND / "migrations"))
    head = ScriptDirectory.from_config(cfg).get_current_head()
    assert head is not None
    return head


HEAD = _head()


Steps = tuple[tuple[str, str], ...]


def _run_upgrade(url: str, steps: Steps = (("upgrade", "head"),)) -> None:
    cfg = Config(str(BACKEND / "alembic.ini"))
    cfg.set_main_option("script_location", str(BACKEND / "migrations"))
    settings = get_settings()
    old = settings.DATABASE_URL
    settings.DATABASE_URL = url
    try:
        for op, rev in steps:
            getattr(command, op)(cfg, rev)
    finally:
        settings.DATABASE_URL = old


@pytest.mark.filterwarnings("ignore")
def test_migrations_match_models(tmp_path: Path) -> None:
    db = tmp_path / "mig.db"
    # env.py calls asyncio.run(); run it in a worker thread with no running loop.
    asyncio.run(asyncio.to_thread(_run_upgrade, f"sqlite+aiosqlite:///{db.as_posix()}"))
    engine = create_engine(f"sqlite:///{db.as_posix()}")
    with engine.connect() as conn:
        diff = compare_metadata(MigrationContext.configure(conn), Base.metadata)
    engine.dispose()
    assert diff == [], diff


@pytest.mark.filterwarnings("ignore")
def test_catalogue_migration_downgrade_and_reapply(tmp_path: Path) -> None:
    db = tmp_path / "roundtrip.db"
    steps = (("upgrade", "head"), ("downgrade", "0001_initial"), ("upgrade", "head"))
    asyncio.run(asyncio.to_thread(_run_upgrade, f"sqlite+aiosqlite:///{db.as_posix()}", steps))
    engine = create_engine(f"sqlite:///{db.as_posix()}")
    with engine.connect() as conn:
        diff = compare_metadata(MigrationContext.configure(conn), Base.metadata)
        tables = {r[0] for r in conn.exec_driver_sql("SELECT name FROM sqlite_master")}
    engine.dispose()
    assert diff == [], diff
    catalogue = {"ingredients", "staples", "recipes", "recipe_ingredients", "app_config"}
    assert catalogue | {"substitution_rules"} <= tables


@pytest.mark.filterwarnings("ignore")
def test_chat_migration_downgrade_and_reapply(tmp_path: Path) -> None:
    db = tmp_path / "chat.db"
    steps = (("upgrade", "head"), ("downgrade", "0002_catalogue"), ("upgrade", "head"))
    asyncio.run(asyncio.to_thread(_run_upgrade, f"sqlite+aiosqlite:///{db.as_posix()}", steps))
    engine = create_engine(f"sqlite:///{db.as_posix()}")
    with engine.connect() as conn:
        diff = compare_metadata(MigrationContext.configure(conn), Base.metadata)
        tables = {r[0] for r in conn.exec_driver_sql("SELECT name FROM sqlite_master")}
        head = conn.exec_driver_sql("SELECT version_num FROM alembic_version").scalar_one()
    engine.dispose()
    assert diff == [], diff
    assert {"chat_sessions", "chat_messages"} <= tables
    assert head == HEAD


KITCHEN_TABLES = {
    "menus",
    "menu_dishes",
    "tickets",
    "ticket_events",
    "ticket_messages",
    "inbox_items",
    "cook_duty_log",
}


@pytest.mark.filterwarnings("ignore")
def test_kitchen_migration_downgrade_and_reapply(tmp_path: Path) -> None:
    db = tmp_path / "kitchen.db"
    url = f"sqlite+aiosqlite:///{db.as_posix()}"
    steps = (("upgrade", "head"), ("downgrade", "0003_chat"))
    asyncio.run(asyncio.to_thread(_run_upgrade, url, steps))
    # A household row from before 0004 must survive: eater_defaults has a server default.
    engine = create_engine(f"sqlite:///{db.as_posix()}")
    with engine.begin() as conn:
        tables = {r[0] for r in conn.exec_driver_sql("SELECT name FROM sqlite_master")}
        assert not (KITCHEN_TABLES & tables)
        conn.exec_driver_sql(
            "INSERT INTO households (id, name, timezone, default_servings, enabled_slots, "
            "slot_defaults, cook_can_approve_swaps, members_can_send_to_cook, "
            "show_names_to_cook, created_at, updated_at) VALUES "
            "('00000000000000000000000000000001', 'Old', 'Asia/Kolkata', 4, '[]', '{}', 1, 1, 0, "
            "CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)"
        )
    engine.dispose()
    asyncio.run(asyncio.to_thread(_run_upgrade, url, (("upgrade", "head"),)))
    engine = create_engine(f"sqlite:///{db.as_posix()}")
    with engine.connect() as conn:
        diff = compare_metadata(MigrationContext.configure(conn), Base.metadata)
        tables = {r[0] for r in conn.exec_driver_sql("SELECT name FROM sqlite_master")}
        defaults = conn.exec_driver_sql("SELECT eater_defaults FROM households").scalar_one()
    engine.dispose()
    assert diff == [], diff
    assert tables >= KITCHEN_TABLES
    assert defaults == "{}"


PANTRY_TABLES = {
    "stock_items",
    "ration_requests",
    "ration_items",
    "approvals",
    "ticket_stock_issues",
}
FEEDBACK_TABLES = {"ratings", "served_history", "consents", "export_jobs"}


def _tables_and_diff(db: Path) -> tuple[set[str], list[object]]:
    engine = create_engine(f"sqlite:///{db.as_posix()}")
    with engine.connect() as conn:
        diff = compare_metadata(MigrationContext.configure(conn), Base.metadata)
        tables = {r[0] for r in conn.exec_driver_sql("SELECT name FROM sqlite_master")}
    engine.dispose()
    return tables, list(diff)


@pytest.mark.filterwarnings("ignore")
def test_pantry_and_feedback_migrations_round_trip(tmp_path: Path) -> None:
    """0005 (pantry) and 0006 (feedback) downgrade cleanly and re-apply to the models."""
    db = tmp_path / "p67.db"
    url = f"sqlite+aiosqlite:///{db.as_posix()}"
    asyncio.run(asyncio.to_thread(_run_upgrade, url, (("upgrade", "head"),)))
    tables, diff = _tables_and_diff(db)
    assert diff == [], diff
    assert tables >= PANTRY_TABLES | FEEDBACK_TABLES

    asyncio.run(asyncio.to_thread(_run_upgrade, url, (("downgrade", "0005_pantry"),)))
    tables, _ = _tables_and_diff(db)
    assert not (FEEDBACK_TABLES & tables)
    assert tables >= PANTRY_TABLES

    # A household from before 0005 survives the new NOT NULL columns (server defaults).
    asyncio.run(asyncio.to_thread(_run_upgrade, url, (("downgrade", "0004_kitchen"),)))
    tables, _ = _tables_and_diff(db)
    assert not ((PANTRY_TABLES | FEEDBACK_TABLES) & tables)
    engine = create_engine(f"sqlite:///{db.as_posix()}")
    with engine.begin() as conn:
        conn.exec_driver_sql(
            "INSERT INTO households (id, name, timezone, default_servings, enabled_slots, "
            "slot_defaults, cook_can_approve_swaps, members_can_send_to_cook, "
            "show_names_to_cook, eater_defaults, created_at, updated_at) VALUES "
            "('00000000000000000000000000000002', 'Old', 'Asia/Kolkata', 4, '[]', '{}', 1, 1, "
            "0, '{}', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)"
        )
    engine.dispose()
    asyncio.run(asyncio.to_thread(_run_upgrade, url, (("upgrade", "head"),)))
    tables, diff = _tables_and_diff(db)
    assert diff == [], diff
    assert tables >= PANTRY_TABLES | FEEDBACK_TABLES
    engine = create_engine(f"sqlite:///{db.as_posix()}")
    with engine.connect() as conn:
        row = conn.exec_driver_sql("SELECT auto_decrement, ratings_enabled FROM households").one()
    engine.dispose()
    assert tuple(row) == (0, 1)

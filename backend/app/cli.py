"""Management commands.

python -m app.cli seed [--publish clean|all|none] [--no-demo] [--content-dir DIR]
python -m app.cli import-recipes PATH.csv [--publish none|clean|all] [--supersede-same-name]
python -m app.cli demo-day [--admin-phone +919999999999]
python -m app.cli openapi > docs/openapi.json
python -m app.cli staff-create --email ops@banega.app [--password ...]   (prints the TOTP URI)
python -m app.cli staff-reset-totp --email ops@banega.app
"""

from __future__ import annotations

import argparse
import asyncio
import getpass
import json
import os
import sys
from pathlib import Path

from app.services.importer import CONTENT_DIR, DEV_ADMIN_PHONE, PublishMode, seed_all


async def _seed(content_dir: Path, publish: PublishMode, demo: bool, admin_phone: str) -> int:
    from app.core.db import dispose_engine, get_sessionmaker

    async with get_sessionmaker()() as db:
        report = await seed_all(
            db,
            content_dir=content_dir,
            publish=publish,
            with_demo_household=demo,
            admin_phone=admin_phone,
        )
    await dispose_engine()
    print(f"ingredients: {report.ingredients.summary()}")
    print(f"recipes:     {report.recipes.summary()}")
    print(f"app config:  {report.config.summary()}")
    print(f"swap rules:  {report.substitutions.summary()}")
    if report.household is not None:
        print(f"household:   {report.household.summary()} (admin {admin_phone})")
    for slug, lines in sorted(report.recipes.unmatched.items()):
        print(f"  UNMATCHED {slug}: {lines}", file=sys.stderr)
    for slug, violations in sorted(report.recipes.violations.items()):
        codes = ", ".join(str(v.get("code")) for v in violations)
        print(f"  violations {slug}: {codes}")
    return 1 if report.recipes.unmatched else 0


async def _import_recipes(text: str, publish: PublishMode, supersede: bool) -> int:
    from app.core.db import dispose_engine, get_sessionmaker
    from app.services.csv_io import recipe_rows_from_csv
    from app.services.importer import load_recipes, retire_same_name

    rows = recipe_rows_from_csv(text)
    async with get_sessionmaker()() as db:
        report = await load_recipes(db, rows, publish=publish)
        retired = await retire_same_name(db, [r["slug"] for r in rows]) if supersede else []
        await db.commit()
    await dispose_engine()
    print(f"recipes: {report.summary()} (rows in file: {len(rows)})")
    for err in report.errors:
        print(f"  ERROR {err}", file=sys.stderr)
    for slug, lines in sorted(report.unmatched.items()):
        print(f"  UNMATCHED {slug}: {lines}", file=sys.stderr)
    if retired:
        print(
            f"  moved to draft (same name as a sheet recipe): {len(retired)}: {', '.join(retired)}"
        )
    held = sorted(set(report.violations) - set(report.unmatched))
    if held:
        print(f"  held back for review (policy check): {len(held)}: {', '.join(held[:20])}")
    return 1 if report.unmatched or report.errors else 0


async def _demo_day(admin_phone: str) -> int:
    from app.core.db import dispose_engine, get_sessionmaker
    from app.services.demo import create_demo_day

    async with get_sessionmaker()() as db:
        result = await create_demo_day(db, admin_phone=admin_phone)
    await dispose_engine()
    print(f"menu:   {result.menu_id}")
    print(f"ticket: {result.ticket_id} ({result.status})")
    if result.ladder_step:
        print(f"dahi:   out on the ticket -> ladder step {result.ladder_step}")
    sys.stdout.flush()
    sys.stdout.buffer.write((result.share_text + chr(10)).encode("utf-8"))
    return 0


def _openapi() -> int:
    from app.main import app

    # Bytes, so the output is UTF-8 whatever the console code page is (Windows).
    spec = json.dumps(app.openapi(), indent=2, ensure_ascii=False) + "\n"
    sys.stdout.buffer.write(spec.encode("utf-8"))
    sys.stdout.flush()
    return 0


async def _staff_create(email: str, password: str) -> int:
    from app.core.db import dispose_engine, get_sessionmaker
    from app.services import staff as staff_svc

    async with get_sessionmaker()() as db:
        try:
            staff = await staff_svc.create_staff(db, email, password)
        except ValueError as exc:
            print(f"error: {exc}", file=sys.stderr)
            await dispose_engine()
            return 2
        uri = staff_svc.reveal_enrolment_uri(staff)
        await db.commit()
    await dispose_engine()
    print(f"staff:    {staff.email} ({staff.id})")
    print("TOTP:     add this to an authenticator app now (shown once):")
    print(f"          {uri}")
    print("Log in at /admin with email + password + the 6-digit code.")
    return 0


async def _staff_reset_totp(email: str) -> int:
    from sqlalchemy import select

    from app.core.db import dispose_engine, get_sessionmaker
    from app.models import StaffUser
    from app.services import staff as staff_svc

    async with get_sessionmaker()() as db:
        staff = (
            await db.execute(
                select(StaffUser).where(StaffUser.email == staff_svc.normalize_email(email))
            )
        ).scalar_one_or_none()
        if staff is None:
            print(f"error: no staff {email}", file=sys.stderr)
            await dispose_engine()
            return 2
        staff_svc.reset_totp(staff)
        uri = staff_svc.reveal_enrolment_uri(staff)
        await db.commit()
    await dispose_engine()
    print(f"TOTP reset for {staff.email}; new URI (shown once):")
    print(f"          {uri}")
    return 0


def _password(arg: str | None) -> str:
    if arg:
        return arg
    env = os.environ.get("STAFF_PASSWORD")
    if env:
        return env
    return getpass.getpass("Password (12+ characters): ")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="python -m app.cli")
    sub = parser.add_subparsers(dest="cmd", required=True)
    seed = sub.add_parser("seed", help="load content/*.seed.json (idempotent)")
    seed.add_argument("--content-dir", type=Path, default=CONTENT_DIR)
    seed.add_argument(
        "--publish",
        choices=["none", "clean", "all"],
        default="clean",
        help="clean: publish recipes without policy violations (default); "
        "all: publish everything (dev demo)",
    )
    seed.add_argument("--no-demo", action="store_true", help="skip the demo household")
    seed.add_argument("--admin-phone", default=DEV_ADMIN_PHONE)
    imp = sub.add_parser(
        "import-recipes", help="import a recipe master CSV (same as the admin panel)"
    )
    imp.add_argument("path", type=Path)
    imp.add_argument(
        "--publish",
        choices=["none", "clean", "all"],
        default="none",
        help="none: keep each row's status (default); clean: publish rows that pass the "
        "diet/allergen policy check and match every ingredient",
    )
    imp.add_argument(
        "--supersede-same-name",
        action="store_true",
        help="move other published recipes with the same name as a sheet recipe to draft",
    )
    demo_day = sub.add_parser("demo-day", help="today's lunch menu + ticket for the demo family")
    demo_day.add_argument("--admin-phone", default=DEV_ADMIN_PHONE)
    sub.add_parser("openapi", help="print the OpenAPI spec as JSON")
    staff_create = sub.add_parser("staff-create", help="create an admin-panel staff account")
    staff_create.add_argument("--email", required=True)
    staff_create.add_argument(
        "--password", help="omit to read STAFF_PASSWORD or prompt (keeps it out of history)"
    )
    staff_reset = sub.add_parser("staff-reset-totp", help="new TOTP secret for a staff account")
    staff_reset.add_argument("--email", required=True)
    args = parser.parse_args(argv)

    if args.cmd == "staff-create":
        return asyncio.run(_staff_create(args.email, _password(args.password)))
    if args.cmd == "staff-reset-totp":
        return asyncio.run(_staff_reset_totp(args.email))

    if args.cmd == "seed":
        publish: PublishMode = args.publish
        return asyncio.run(_seed(args.content_dir, publish, not args.no_demo, args.admin_phone))
    if args.cmd == "import-recipes":
        mode: PublishMode = args.publish
        text = args.path.read_text(encoding="utf-8-sig")
        return asyncio.run(_import_recipes(text, mode, args.supersede_same_name))
    if args.cmd == "demo-day":
        return asyncio.run(_demo_day(args.admin_phone))
    return _openapi()


if __name__ == "__main__":
    raise SystemExit(main())

# Thin wrapper over scripts/dev.sh (which also works without make, e.g. in Git Bash on Windows).
DEV := bash scripts/dev.sh

.PHONY: setup test test-postgres lint fmt migrate revision compose-config compose-up compose-down logs staff

setup:          ## Create backend/.venv and install backend + admin + dev tools
	$(DEV) setup

test:           ## Run the backend test suite (SQLite in-memory, no Docker needed)
	$(DEV) test

test-postgres:  ## Alembic round trip + the suite on Postgres (TEST_DATABASE_URL, default banega_test)
	bash scripts/test-postgres.sh

lint:           ## ruff check + format check + mypy --strict
	$(DEV) lint

fmt:            ## ruff fix + format
	$(DEV) fmt

migrate:        ## alembic upgrade head via the compose migrate job
	$(DEV) migrate

revision:       ## make revision m="add tickets"
	$(DEV) revision "$(m)"

compose-config: ## Validate infra/docker-compose.yml
	$(DEV) compose-config

compose-up:     ## Build and start the dev stack (http://localhost:8080/v1/health)
	$(DEV) compose-up

compose-down:
	$(DEV) compose-down

logs:
	$(DEV) logs

staff:          ## make staff email=you@banega.app  (admin account; prints the TOTP URI)
	docker compose -f infra/docker-compose.yml exec api python -m app.cli staff-create --email "$(email)"

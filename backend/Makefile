.PHONY: install dev lint format test migrate migrate-status run

install:
	pip install -r requirements.txt -e ".[dev]"

lint:
	ruff check app tests

format:
	ruff format app tests

test:
	pytest -q

# Apply database migrations. Requires DATABASE_URL (Supabase connection string).
migrate:
	python scripts/migrate.py

migrate-status:
	python scripts/migrate.py --status

run:
	uvicorn app.main:app --reload --port 8000

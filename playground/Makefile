.PHONY: format

format: ## Format the code into unified format
	uv run black .
	uv run ruff check . --fix

play:
	make -C "../" play


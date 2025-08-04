# Makefile for assisted-chat project
# This Makefile provides convenient targets for managing the assisted-chat services

.PHONY: all \
	build-images \
	build-inspector build-assisted-mcp build-lightspeed-stack build-lightspeed-plus-llama-stack build-ui \
	generate run resume stop rm logs query query-interactive mcphost sqlite test-eval help psql

all: help ## Show help information

build-images: ## Build all container images
	@echo "Building container images..."
	./scripts/build-images.sh

build-inspector: ## Build inspector image
	@echo "Building inspector image..."
	./scripts/build-images.sh inspector

build-assisted-mcp: ## Build assisted service MCP image
	@echo "Building assisted service MCP image..."
	./scripts/build-images.sh assisted-mcp

build-lightspeed-stack: ## Build lightspeed stack image
	@echo "Building lightspeed stack image..."
	./scripts/build-images.sh lightspeed-stack

build-lightspeed-plus-llama-stack: ## Build lightspeed stack plus llama stack image
	@echo "Building lightspeed stack plus llama stack image..."
	./scripts/build-images.sh lightspeed-plus-llama-stack

build-ui: ## Build UI image
	@echo "Building UI image..."
	./scripts/build-images.sh ui

generate: ## Generate configuration files
	@echo "Generating configuration files..."
	./scripts/generate.sh

run: ## Start the assisted-chat services
	@echo "Starting assisted-chat services..."
	./scripts/run.sh

resume: ## Resume the assisted-chat services
	@echo "Resuming assisted-chat services..."
	./scripts/resume.sh

stop: ## Stop the assisted-chat services
	@echo "Stopping assisted-chat services..."
	./scripts/stop.sh

rm: ## Remove/cleanup the assisted-chat services
	@echo "Removing assisted-chat services..."
	./scripts/rm.sh

logs: ## Show logs for the assisted-chat services
	@echo "Showing logs for assisted-chat services..."
	./scripts/logs.sh

query: ## Query the assisted-chat services
	@echo "Querying assisted-chat services..."
	./scripts/query.sh

query-interactive: ## Query the assisted-chat services in interactive mode
	@echo "Querying assisted-chat services in interactive mode..."
	./scripts/query.sh --interactive

mcphost: ## Attach to mcphost
	@echo "Attaching to mcphost..."
	./scripts/mcphost.sh

psql: ## Connect to PostgreSQL database in the assisted-chat pod
	@echo "Connecting to PostgreSQL database..."
	@podman exec -it assisted-chat-pod-postgres env PGOPTIONS='-c search_path="lightspeed-stack",public' psql -U assisted-chat -d assisted-chat

sqlite: ## Copy SQLite database from pod and open in browser
	@echo "Copying SQLite database from pod..."
	@podman cp assisted-chat-pod-lightspeed-stack:/tmp/assisted-chat.db /tmp/assisted-chat.db
	@echo "Opening SQLite database in browser..."
	@sqlitebrowser /tmp/assisted-chat.db

test-eval: ## Run agent evaluation tests
	@echo "Refreshing OCM token..."
	@. utils/ocm-token.sh && get_ocm_token && echo "$$OCM_TOKEN" > test/evals/ocm_token.txt
	@echo "Running agent evaluation tests..."
	@cd test/evals && python eval.py

help: ## Show this help message
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-30s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Example usage:"
	@echo "  make build-images"
	@echo "  make run"
	@echo "  make logs"
	@echo "  make query"
	@echo "  make query-interactive"
	@echo "  make test-eval"

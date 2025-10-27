# Makefile for assisted-chat project
# This Makefile provides convenient targets for managing the assisted-chat services

# Default namespace for k8s operations
NAMESPACE ?= assisted-chat

.PHONY: all \
	build-images \
	build-inspector build-assisted-mcp build-lightspeed-stack build-lightspeed-plus-llama-stack build-ui \
	deploy-template ci-test deploy-template-local run-k8s stop-k8s rm-k8s logs-k8s load-images \
	generate run resume stop rm logs query query-int query-stage query-prod query-interactive query-k8s query-k8s-curl delete mcphost test-eval test-eval-k8s psql sqlite transcript-summaries-prod help

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

deploy-template: ## Used by the CI. Deploys the template on the temporary CI cluster
	scripts/deploy_template.sh

ci-test: ## Used by the CI to test the assisted-chat services
	./scripts/ci_test.sh

deploy-template-local: ## Used to test the CI flow locally. Deploys the template on whatever cluster `oc` is currently logged in to
	@set -euo pipefail; \
	SECRETS_BASE_PATH=$$(scripts/setup_secrets.sh); \
	oc create namespace $(NAMESPACE) || true; \
	NAMESPACE=$(NAMESPACE) SECRETS_BASE_PATH="$$SECRETS_BASE_PATH" ASSISTED_CHAT_IMG="$(ASSISTED_CHAT_IMG)" scripts/deploy_template.sh

# Kubernetes-native local dev helpers
run-k8s: ## Deploy and follow logs on current cluster (requires `oc login`)
	@$(MAKE) deploy-template-local
	NAMESPACE=$(NAMESPACE) ./scripts/deploy_local_components.sh

stop-k8s: ## Scale down the assisted-chat deployment to 0 replicas
	./scripts/stop_k8s.sh

rm-k8s: ## Remove all assisted-chat resources from the current cluster
	./scripts/rm_k8s.sh

logs-k8s: ## Follow logs of the assisted-chat deployment
	./scripts/logs_k8s.sh

load-images: ## Load local podman images into minikube
	./scripts/load_images.sh

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

query: ## Query the assisted-chat services (localhost)
	@echo "Querying assisted-chat services (localhost)..."
	./scripts/query.sh

query-int: ## Query the assisted-chat services (integration environment)
	@echo "Querying assisted-chat services (integration environment)..."
	QUERY_ENV=int ./scripts/query.sh

query-stage: ## Query the assisted-chat services (stage environment)
	@echo "Querying assisted-chat services (stage environment)..."
	QUERY_ENV=stage ./scripts/query.sh

query-prod: ## Query the assisted-chat services (production environment)
	@echo "Querying assisted-chat services (production environment)..."
	QUERY_ENV=prod ./scripts/query.sh

query-k8s: ## Query the assisted-chat services via k8s port-forward on localhost:8090
	@echo "Hint: ensure a port-forward is running: oc port-forward -n $(NAMESPACE) svc/assisted-chat 8090:8090" 
	QUERY_ENV=k8s ./scripts/query.sh

query-k8s-curl: ## Non-interactive k8s query via curl (default: "Show me all my clusters")
	NAMESPACE=$(NAMESPACE) ./scripts/query_k8s_curl.sh

query-interactive: query ## Query the assisted-chat services (deprecated, use 'query')
	@echo "WARNING: 'query-interactive' is deprecated. Use 'make query' instead."

delete: ## Delete a conversation from assisted-chat services
	@echo "Deleting conversation from assisted-chat services..."
	DELETE_MODE=true ./scripts/query.sh

mcphost: ## Attach to mcphost
	@echo "Attaching to mcphost..."
	./scripts/mcphost.sh

.ONESHELL:
test-eval: ## Run agent evaluation tests
	#!/bin/bash
	set -e
	set -o pipefail
	export TEMP_DIR=$(shell mktemp -d)
	trap 'rm -rf "$$TEMP_DIR"' EXIT
	export UNIQUE_ID=$(shell head /dev/urandom | tr -dc 0-9a-z | head -c 8)
	. utils/ocm-token.sh
	get_ocm_token
	echo "$$OCM_TOKEN" > test/evals/ocm_token.txt
	cp test/evals/eval_data.yaml $$TEMP_DIR/eval_data.yaml
	sed -i "s/uniq-cluster-name/$${UNIQUE_ID}/g" $$TEMP_DIR/eval_data.yaml
	cd test/evals && GOOGLE_APPLICATION_CREDENTIALS=config/vertex-credentials.json python eval.py --eval_data_yaml $$TEMP_DIR/eval_data.yaml --judge_provider="vertex"

.ONESHELL:
test-eval-k8s: ## Run evaluation tests against k8s-deployed service via port-forward
	set -euo pipefail
	echo "Refreshing OCM token..."
	mkdir -p test/evals
	if [ -n "$$OCM_TOKEN" ]; then
		umask 077
		printf '%s\n' "$$OCM_TOKEN" > test/evals/ocm_token.txt
	else
		. utils/ocm-token.sh && get_ocm_token
		umask 077
		printf '%s\n' "$$OCM_TOKEN" > test/evals/ocm_token.txt
	fi
	echo "Running agent evaluation tests (k8s)..."
	NAMESPACE=$(NAMESPACE) ./scripts/eval_k8s.sh

psql: ## Connect to PostgreSQL database in the assisted-chat pod
	@echo "Connecting to PostgreSQL database..."
	@podman exec -it assisted-chat-pod-postgres env PGOPTIONS='-c search_path="lightspeed-stack",public' psql -U assisted-chat -d assisted-chat

sqlite: ## Copy SQLite database from pod and open in browser
	@echo "Copying SQLite database from pod..."
	@podman cp assisted-chat-pod-lightspeed-stack:/tmp/assisted-chat.db /tmp/assisted-chat.db
	@echo "Opening SQLite database in browser..."
	@sqlitebrowser /tmp/assisted-chat.db

transcript-summaries-prod:
	./scripts/archives/download-and-extract prod
	./scripts/archives/summarize-transcripts

help: ## Show this help message
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-30s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Example usage:"
	@echo "  make build-images"
	@echo "  make load-images"
	@echo "  make run-k8s"
	@echo "  make logs-k8s"
	@echo "  make query-k8s"
	@echo "  make query-k8s-curl"
	@echo "  make test-eval-k8s"
	@echo "  make run"
	@echo "  make logs"
	@echo "  make query"
	@echo "  make query-int"
	@echo "  make query-stage"
	@echo "  make query-interactive"
	@echo "  make test-eval"

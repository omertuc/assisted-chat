#!/bin/bash

set -euxo pipefail

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

if [[ ! -d "${SCRIPT_DIR}/inspector" ||
    ! -d "${SCRIPT_DIR}/assisted-service-mcp" ||
    ! -d "${SCRIPT_DIR}/lightspeed-stack" ]]; then
    echo "Dependency directories do not exist. Load git submodules first."
    exit 1
fi

function check_redhat_subscription() {
    echo "Checking Red Hat subscription requirements..."

    # Check if subscription-manager is available
    if ! command -v subscription-manager &> /dev/null; then
        echo "ERROR: subscription-manager is not available. Please install subscription-manager package."
        exit 1
    fi

    # Check subscription status (ask for sudo password upfront)
    echo "This script requires sudo access to check Red Hat subscription status."
    echo "Please enter your sudo password when prompted:"
    sudo -v  # Ask for password and refresh sudo timestamp

    if ! sudo subscription-manager status >/dev/null 2>&1; then
        echo "ERROR: System is not registered with Red Hat subscription manager."
        echo "Please register your system:"
        echo "  sudo subscription-manager register --username <your-username>"
        echo "  sudo subscription-manager attach --auto"
        echo ""
        echo "Or get a free Red Hat Developer subscription at: https://developers.redhat.com/register"
        exit 1
    fi

    # Check if logged into Red Hat container registry
    if ! podman login --get-login registry.access.redhat.com &> /dev/null; then
        echo "ERROR: Not logged into Red Hat container registry."
        echo "Please login to the registry:"
        echo "  podman login registry.access.redhat.com"
        exit 1
    fi

    echo "✓ Red Hat subscription and registry access verified"
}

# Verify Red Hat subscription before building
check_redhat_subscription

function build_inspector() {
    pushd "${SCRIPT_DIR}/inspector"
    podman build -f Dockerfile . --tag localhost/local-ai-chat-inspector:latest
    popd
}

function build_assisted_mcp() {
    pushd "${SCRIPT_DIR}/assisted-service-mcp"
    make build IMAGE_NAME=localhost/local-ai-chat-assisted-service-mcp TAG=latest
    popd
}

function build_lightspeed_stack() {
    pushd "${SCRIPT_DIR}/lightspeed-stack"
    podman build -f Containerfile . --tag localhost/local-ai-chat-lightspeed-stack:latest
    popd
}

function build_lightspeed_stack_plus_llama_stack() {
    podman build -f Containerfile.add_llama_to_lightspeed . --tag localhost/local-ai-chat-lightspeed-stack-plus-llama-stack:latest
}

function build_ui() {
    pushd "${SCRIPT_DIR}/assisted-installer-ui/"
    git apply ../ui-patch.diff
    podman build -f apps/assisted-ui/Containerfile -t localhost/local-ai-chat-ui . --build-arg AIUI_APP_GIT_SHA="$(git rev-parse HEAD)" --build-arg AIUI_APP_VERSION=latest
    git apply -R ../ui-patch.diff
    popd
}

build_inspector
build_assisted_mcp
build_lightspeed_stack
build_lightspeed_stack_plus_llama_stack
build_ui

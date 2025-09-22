#!/bin/bash

set -euxo pipefail

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
PROJECT_ROOT=$(dirname "$SCRIPT_DIR")

if [[ ! -d "${PROJECT_ROOT}/inspector" ||
    ! -d "${PROJECT_ROOT}/assisted-service-mcp" ||
    ! -d "${PROJECT_ROOT}/assisted-installer-ui/" ||
    ! -d "${PROJECT_ROOT}/lightspeed-stack" ]]; then
    echo "Dependency directories do not exist. Load git submodules first."
    exit 1
fi

function show_usage() {
    cat <<EOF
Usage: $0 [OPTIONS] [IMAGES...]

Build container images for the assisted-chat project.

OPTIONS:
    -h, --help          Show this help message and exit

IMAGES:
    inspector                   Build the inspector image
    assisted-mcp                Build the assisted service MCP image
    lightspeed-stack            Build the lightspeed stack image
    lightspeed-plus-llama-stack Build the lightspeed stack plus llama stack image
    ui                          Build the UI image
    all                         Build all images (default)

Examples:
    $0                                   # Build all images
    $0 all                               # Build all images
    $0 inspector ui                      # Build only inspector and UI images
    $0 lightspeed-stack                  # Build only lightspeed stack image

EOF
}

function check_redhat_subscription() {
    echo "Checking Red Hat subscription requirements... You must be registered to complete the build successfully."

    # Check if subscription-manager is available
    if ! command -v subscription-manager &>/dev/null; then
        echo "ERROR: subscription-manager is not available. This machine is unlikely to be registered so the build will fail."
        exit 1
    fi

    # Check subscription status (ask for sudo password upfront)
    if [[ ! -f /etc/pki/consumer/cert.pem ]]; then
        echo "ERROR: Could not find /etc/pki/consumer/cert.pem so the system is unlikely to be registered with Red Hat subscription manager."
        echo "Please register your system:"
        echo "  sudo subscription-manager register --username <your-username>"
        echo "  sudo subscription-manager attach --auto"
        echo ""
        echo "Or get a free Red Hat Developer subscription at: https://developers.redhat.com/register"
        exit 1
    fi

    echo "✓ Red Hat subscription and registry access verified"
}

function build_inspector() {
    echo "Building inspector image..."
    pushd "${PROJECT_ROOT}/inspector"
    podman build -f Dockerfile . --tag localhost/local-ai-chat-inspector:latest
    popd
    echo "✓ Inspector image built successfully"
}

function build_assisted_mcp() {
    echo "Building assisted service MCP image..."
    pushd "${PROJECT_ROOT}/assisted-service-mcp"
    make build IMAGE_NAME=localhost/local-ai-chat-assisted-service-mcp TAG=latest
    popd
    echo "✓ Assisted service MCP image built successfully"
}

function build_lightspeed_stack() {
    echo "Building lightspeed stack image..."
    pushd "${PROJECT_ROOT}/lightspeed-stack"
    # Comment out the llama-stack dependency in pyproject.toml so it uses the locally installed version
    # instead
    sed -i '/^[^#].*llama-stack[[:space:]]*[>=|==]/ s/^/# /' pyproject.toml
    uv lock
    podman build -f Containerfile . --tag localhost/local-ai-chat-lightspeed-stack:latest
    # Undo it
    sed -i 's/^# \(.*llama-stack[[:space:]]*[>=|==].*\)$/\1/' pyproject.toml
    # uv.lock is guaranteed to change, and it's annoying to have it as a dirty file, so let's restore it
    git checkout uv.lock 2>/dev/null || true # Don't fail if uv.lock doesn't exist in git
    popd
    echo "✓ Lightspeed stack image built successfully"
}

function build_lightspeed_stack_plus_llama_stack() {
    echo "Building lightspeed stack plus llama stack image..."
    pushd "${PROJECT_ROOT}"
    podman build -f Containerfile.add_llama_to_lightspeed . --tag localhost/local-ai-chat-lightspeed-stack-plus-llama-stack:latest
    popd
    echo "✓ Lightspeed stack plus llama stack image built successfully"
}

function build_ui() {
    echo "Building UI image..."
    pushd "${PROJECT_ROOT}/assisted-installer-ui/"
    if git apply --reverse --check ../ui-patch.diff 2>/dev/null; then
        echo "Patch already applied"
    else
        git apply ../ui-patch.diff 2>/dev/null || echo "Warning: Could not apply UI patch, continuing without it"
    fi
    podman build -f apps/assisted-ui/Containerfile -t localhost/local-ai-chat-ui . --build-arg AIUI_APP_GIT_SHA="$(git rev-parse HEAD)" --build-arg AIUI_APP_VERSION=latest
    git apply -R ../ui-patch.diff 2>/dev/null || true # Don't fail if reverse patch doesn't apply
    popd
    echo "✓ UI image built successfully"
}

# Parse command line arguments
IMAGES_TO_BUILD=()
while [[ $# -gt 0 ]]; do
    case $1 in
    -h | --help)
        show_usage
        exit 0
        ;;
    inspector | assisted-mcp | lightspeed-stack | lightspeed-plus-llama-stack | ui | all)
        IMAGES_TO_BUILD+=("$1")
        shift
        ;;
    *)
        echo "Error: Unknown option or image '$1'"
        echo "Use '$0 --help' for usage information."
        exit 1
        ;;
    esac
done

# If no images specified, build all
if [[ ${#IMAGES_TO_BUILD[@]} -eq 0 ]]; then
    IMAGES_TO_BUILD=("all")
fi

# Verify Red Hat subscription before building
check_redhat_subscription

# Build requested images
for image in "${IMAGES_TO_BUILD[@]}"; do
    case $image in
    inspector)
        build_inspector
        ;;
    assisted-mcp)
        build_assisted_mcp
        ;;
    lightspeed-stack)
        build_lightspeed_stack
        ;;
    lightspeed-plus-llama-stack)
        build_lightspeed_stack_plus_llama_stack
        ;;
    ui)
        build_ui
        ;;
    all)
        build_inspector
        build_assisted_mcp
        build_lightspeed_stack
        build_lightspeed_stack_plus_llama_stack
        build_ui
        ;;
    esac
done

echo "✓ All requested images built successfully!"

#!/bin/bash

set -euo pipefail

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
PROJECT_ROOT=$(dirname "$SCRIPT_DIR")

OVERRIDE_FILE=$PROJECT_ROOT/.template-params.override.env

if [[ ! -f "$PROJECT_ROOT/.env" ]]; then
    echo "Missing the .env file that should contain your configuration."
    echo "Would you like help creating the .env file interactively? (y/n)"
    read -r answer
    if [[ "$answer" == "y" || "$answer" == "Y" ]]; then
        echo 'Would you like to use a Gemini API key or Vertex AI service account? (g/v)'
        read -r auth_type
        if [[ "$auth_type" == "g" || "$auth_type" == "G" ]]; then
            echo 'Visit https://console.cloud.google.com/apis/credentials?authuser=1&inv=1&invt=Ab1Pvg&project=assisted-installer and log-in if needed. Then press "use API tokens to authenticate" and paste your token here'
            read -sr GEMINI_API_KEY
            echo "GEMINI_API_KEY=$GEMINI_API_KEY" >"$PROJECT_ROOT/.env"
            chmod 600 "$PROJECT_ROOT/.env"

            echo 'Gemini key successfully configured.'

            # Create a dummy Vertex AI service account credentials file
            if [[ ! -f "$PROJECT_ROOT/config/vertex-credentials.json" ]]; then
                echo 'Also creating a dummy Vertex AI service account credentials file at config/vertex-credentials.json. If you want to use to be able to use both, modify config/vertex-credentials.json manually.'
                echo '{}' >"$PROJECT_ROOT/config/vertex-credentials.json"
                chmod 600 "$PROJECT_ROOT/config/vertex-credentials.json"
            fi

        elif [[ "$auth_type" == "v" || "$auth_type" == "V" ]]; then
            echo 'Please enter the path to your Vertex AI service account credentials file:'
            read -r VERTEX_AI_SERVICE_ACCOUNT_CREDENTIALS_PATH
            if [[ ! -f "$VERTEX_AI_SERVICE_ACCOUNT_CREDENTIALS_PATH" ]]; then
                echo "File not found: $VERTEX_AI_SERVICE_ACCOUNT_CREDENTIALS_PATH"
                exit 1
            fi

            if [[ -f "$PROJECT_ROOT/config/vertex-credentials.json" ]]; then
                echo "File $PROJECT_ROOT/config/vertex-credentials.json already exists. Do you want to overwrite it? (y/n)"
                read -r overwrite
                if [[ "$overwrite" != "y" && "$overwrite" != "Y" ]]; then
                    echo "Exiting without copying."
                    exit 1
                fi
            fi

            echo "$VERTEX_AI_SERVICE_ACCOUNT_CREDENTIALS_PATH will be copied to $PROJECT_ROOT/config/vertex-credentials.json, do you want to continue? (y/n)"
            read -r should_copy
            if [[ "$should_copy" != "y" && "$should_copy" != "Y" ]]; then
                echo "Exiting."
                exit 1
            fi

            cp "$VERTEX_AI_SERVICE_ACCOUNT_CREDENTIALS_PATH" "$PROJECT_ROOT/config/vertex-credentials.json"

            # We must set the GEMINI_API_KEY to a dummy value, as
            # lightspeed-stack wrongly expects it to be set for all Gemini
            # providers, even if we are using Vertex AI service account
            # authentication.
            echo GEMINI_API_KEY="dummy" >"$PROJECT_ROOT/.env"
            chmod 600 "$PROJECT_ROOT/.env"

            echo "Vertex credentials successfully configured."

            echo "Your Gemini API key will be set to a dummy value, as it is not needed for Vertex AI service account authentication, if you want to be able to use both, modify .env manually."
        else
            echo "Invalid choice. Exiting."
            exit 1
        fi
    else
        echo "Exiting. You can copy .env.template to .env and fill it in manually."
        exit 1
    fi
fi

source "$PROJECT_ROOT/.env"

mkdir -p "$PROJECT_ROOT/config"

if [[ -f $OVERRIDE_FILE ]]; then
    OVERRIDE_PARAMS="--param-file=$OVERRIDE_FILE"
fi

oc process --local \
    -f "$PROJECT_ROOT/template.yaml" \
    "${OVERRIDE_PARAMS-}" \
    --param-file="$PROJECT_ROOT/template-params.dev.env" |
    yq '.items[] | select(.kind == "ConfigMap" and .metadata.name == "lightspeed-stack-config").data."lightspeed-stack.yaml"' -r \
        >"$PROJECT_ROOT/config/lightspeed-stack.yaml"

yq -r '.objects[] | select(.metadata.name == "lightspeed-stack-config") | .data.system_prompt' "$PROJECT_ROOT/template.yaml" >"$PROJECT_ROOT/config/systemprompt.txt"

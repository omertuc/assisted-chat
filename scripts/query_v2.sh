#!/bin/bash

set -euo pipefail

# Response API v2 Query Script
# This script allows model/provider selection for each query, even in existing conversations.
# This provides flexibility to change models, tools, and context per query.

# Check if this is a delete operation
DELETE_MODE=${DELETE_MODE:-false}

# Color definitions
CYAN='\033[0;36m'
RESET='\033[0m'

# Get the script directory to locate utils
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
PROJECT_ROOT=$(dirname "$SCRIPT_DIR")

# Source the OCM token utility
source "$PROJECT_ROOT/utils/ocm-token.sh"

# Configure base URL based on QUERY_ENV environment variable
case "${QUERY_ENV:-}" in
    "int")
        BASE_URL="https://assisted-chat.api.integration.openshift.com"
        ;;
    "stage")
        BASE_URL="https://assisted-chat.api.stage.openshift.com"
        ;;
    "prod")
        BASE_URL="https://assisted-chat.api.openshift.com"
        ;;
    *)
        BASE_URL="http://localhost:8090"
        ;;
esac

get_available_models() {
    # Models endpoint is still v1 since models are shared between APIs
    curl --silent --show-error -X 'GET' "${BASE_URL}/v1/models" -H 'accept: application/json' -H "Authorization: Bearer ${OCM_TOKEN}"
}

select_model() {
    local models_json="$1"
    IFS=$'\t' < <(jq -r '
        # Get all models
        .models[] 

        # Ignore models that are not LLMs, like embeddings
        | select(.model_type == "llm") 

        # Extract relevant fields
        | . as $model
        | $model.provider_resource_id as $model_name
        | $model.provider_id as $provider

        # Determine type label based on model identifier
        | (if ($model_name | startswith("gemini/")) then "Gemini"
           elif ($model_name) then "Vertex Gemini"
           else ""
           end) as $type_label

        # Format with proper spacing for alignment
        | "\($model_name | . + (" " * (40 - length)))\($type_label)\t\($model_name)\t\($provider)"
        ' <<<"$models_json" | fzf --delimiter='\t' --with-nth=1 --accept-nth=2,3 --header="Model Name                               Type") read -r model_name model_provider
    echo "$model_name|$model_provider"
}

good_http_response() {
    local status_code="$1"
    [[ "$status_code" -ge 200 && "$status_code" -lt 300 ]]
}

get_conversation_history() {
    local conversation_id="$1"

    # Get fresh OCM token for conversation history
    if ! get_ocm_token; then
        echo "Failed to get OCM token for conversation history"
        return 1
    fi

    # Fetch conversation history using v2 endpoint
    tmpfile=$(mktemp)
    status=$(curl --silent --show-error --output "$tmpfile" --write-out "%{http_code}" \
        -H "Authorization: Bearer ${OCM_TOKEN}" \
        "${BASE_URL}/v2/conversations/${conversation_id}")
    body=$(cat "$tmpfile")
    rm "$tmpfile"

    if ! good_http_response "$status"; then
        echo "Error: Failed to fetch conversation history (HTTP $status)"
        echo "Response: $body"
        return 1
    fi

    echo "$body"
}

display_conversation_history() {
    local conversation_id="$1"

    echo -e "${CYAN}=== Conversation History (Response API v2) ===${RESET}"

    history_response=$(get_conversation_history "$conversation_id")
    if [[ $? -ne 0 ]]; then
        echo "Failed to fetch conversation history"
        return 1
    fi

    # Debug: Show the raw response
    # Extract chat history from the response
    chat_history=$(echo "$history_response" | jq -r '.chat_history // []')

    if [[ "$chat_history" == "[]" ]]; then
        echo "No previous messages in this conversation."
        return 0
    fi

    # Display each turn in the conversation
    echo "$chat_history" | jq -c '.[]' | while IFS= read -r turn; do
        messages=$(echo "$turn" | jq -r '.messages // []')
        started_at=$(echo "$turn" | jq -r '.started_at // "Unknown"')

        # Format timestamp
        if [[ "$started_at" != "Unknown" && "$started_at" != "null" ]]; then
            formatted_time=$(date -d "$started_at" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "$started_at")
        else
            formatted_time="Unknown time"
        fi

        echo -e "\n${CYAN}--- Turn ($formatted_time) ---${RESET}"

        # Display each message in the turn
        echo "$messages" | jq -c '.[]' | while IFS= read -r message; do
            content=$(echo "$message" | jq -r '.content // ""')
            msg_type=$(echo "$message" | jq -r '.type // "unknown"')

            if [[ "$msg_type" == "user" ]]; then
                echo -e "${CYAN}User:${RESET} $content"
            elif [[ "$msg_type" == "assistant" ]]; then
                echo -e "${CYAN}Assistant:${RESET} $content"
            else
                echo -e "${CYAN}${msg_type}:${RESET} $content"
            fi
        done
    done

    echo -e "\n${CYAN}=== End of History ===${RESET}\n"
}

select_conversation() {
    # Get fresh OCM token for conversation listing
    if ! get_ocm_token; then
        echo "Failed to get OCM token for listing conversations"
        return 1
    fi

    # Fetch conversations list using v2 endpoint
    tmpfile=$(mktemp)
    status=$(curl --silent --show-error --output "$tmpfile" --write-out "%{http_code}" \
        -H "Authorization: Bearer ${OCM_TOKEN}" \
        "${BASE_URL}/v2/conversations")
    body=$(cat "$tmpfile")
    rm "$tmpfile"

    if ! good_http_response "$status"; then
        echo "Error: Failed to fetch conversations (HTTP $status)"
        echo "Response: $body"
        exit 1
    fi

    # Parse conversations and create fzf options
    conversations_json=$(echo "$body" | jq -r '.conversations // []')

    if [[ "$conversations_json" == "[]" ]]; then
        if [[ "$DELETE_MODE" == "true" ]]; then
            echo "No conversations found"
            exit 0
        fi
        echo "No existing conversations found. Starting a new conversation."
        return 0
    fi

    fzf_options=()
    if [[ "$DELETE_MODE" != "true" ]]; then
        fzf_options+=("$(printf "%-41s | %-32s" "New conversation" "Start a fresh conversation")")
    fi

    while IFS= read -r conv; do
        if [[ -n "$conv" ]]; then
            conv_id=$(echo "$conv" | jq -r '.conversation_id')
            created_at=$(echo "$conv" | jq -r '.created_at // "Unknown"')
            message_count=$(echo "$conv" | jq -r '.message_count // "N/A"')
            model=$(echo "$conv" | jq -r '.last_used_model // "Unknown"')
            provider=$(echo "$conv" | jq -r '.last_used_provider // "Unknown"')

            # Format the created_at timestamp for display
            if [[ "$created_at" != "Unknown" && "$created_at" != "null" ]]; then
                formatted_date=$(date -d "$created_at" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "$created_at")
            else
                formatted_date="Unknown"
            fi

            # Create a formatted display line with model info
            display_line=$(printf "%-41s | Created: %-16s | Model: %-20s | Messages: %-3s" "$conv_id" "$formatted_date" "$model" "$message_count")
            fzf_options+=("$display_line")
        fi
    done < <(echo "$conversations_json" | jq -c '.[]')

    # Use fzf to let user select with a better prompt and preview
    if [[ "$DELETE_MODE" == "true" ]]; then
        prompt="Select conversation to delete (Response API v2): "
    else
        prompt="Select conversation (Response API v2): "
    fi
    selected=$(printf '%s\n' "${fzf_options[@]}" | fzf --prompt="$prompt" --height=15 --header="ID                                   | Created             | Model                | Messages")

    if [[ -z "$selected" ]]; then
        echo "No selection made. Exiting."
        exit 1
    fi

    if [[ "$DELETE_MODE" == "true" ]]; then
        CONVERSATION_ID=$(echo "$selected" | cut -c1-41 | xargs)
        read -p "Are you sure you want to delete conversation $CONVERSATION_ID? (y/N): " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            echo "Deletion cancelled."
            exit 0
        fi
        tmpfile=$(mktemp)
        status=$(curl --silent --show-error --output "$tmpfile" --write-out "%{http_code}" \
            -X DELETE -H "Authorization: Bearer ${OCM_TOKEN}" \
            "${BASE_URL}/v2/conversations/${CONVERSATION_ID}")
        body=$(cat "$tmpfile")
        rm "$tmpfile"
        if ! good_http_response "$status"; then
            echo "Error: Failed to delete conversation (HTTP $status)"
            echo "Response: $body"
            exit 1
        fi
        echo "Conversation $CONVERSATION_ID deleted successfully."
        exit 0
    elif [[ $(echo "$selected" | cut -d' ' -f1-2) == "New conversation" ]]; then
        CONVERSATION_ID=""
    else
        # Extract conversation ID from the selected line (first 41 characters)
        CONVERSATION_ID=$(echo "$selected" | cut -c1-41 | xargs)
    fi
}

CONVERSATION_ID=""
# select_conversation

# Display conversation history if an existing conversation was selected
if [[ -n "$CONVERSATION_ID" ]]; then
    echo "Selected existing conversation: $CONVERSATION_ID"
    display_conversation_history "$CONVERSATION_ID"
    echo "Response API v2 allows changing model/provider for each query in the conversation."
else
    echo "Starting new conversation (Response API v2)..."
fi

# Always select model for Response API v2 (both new and existing conversations)
echo "Selecting model for this query..."

if ! get_ocm_token; then
    echo "Failed to get OCM token for query"
    return 1
fi

MODELS=$(get_available_models)
model_selection=$(select_model "$MODELS")
MODEL_NAME=$(echo "$model_selection" | cut -d'|' -f1)
MODEL_PROVIDER=$(echo "$model_selection" | cut -d'|' -f2)

if [[ -z "$CONVERSATION_ID" ]]; then
    echo "Example: What is the OpenShift Assisted Installer? Can you list my clusters?"
fi

send_curl_query() {
    local query="$1"

    # Get fresh OCM token for this query
    if ! get_ocm_token; then
        echo "Failed to get OCM token for query"
        return 1
    fi

    # Make the curl request and capture the response using v2 endpoint
    tmpfile=$(mktemp)

    # Response API v2: Always include model/provider for flexibility
    json_payload='
    {
        "conversation_id": "'"$CONVERSATION_ID"'",
        "model": "'"$MODEL_NAME"'",
        "provider": "'"$MODEL_PROVIDER"'",
        "query": "'"${query}"'"
    }'

    status=$(curl --silent --show-error --output "$tmpfile" --write-out "%{http_code}" \
        -H "Authorization: Bearer ${OCM_TOKEN}" \
        "${BASE_URL}/v2/query" \
        --json "$json_payload")
    body=$(cat "$tmpfile")
    rm "$tmpfile"

    if ! good_http_response "$status"; then
        echo "Error: HTTP status $status"
        echo "Response body:"
        echo "$body"
        return 1
    fi

    # Extract and update conversation_id for next call
    new_conversation_id=$(echo "$body" | jq -r '.conversation_id // empty')
    if [[ -n "$new_conversation_id" ]]; then
        echo "Our conversation ID: $new_conversation_id"
        CONVERSATION_ID="$new_conversation_id"
    fi

    # Extract and display response_id for debugging conversation chaining
    response_id=$(echo "$body" | jq -r '.response_id // empty')
    if [[ -n "$response_id" ]]; then
        echo "Response ID (for chaining): $response_id"
    else
        echo "No response_id returned (conversation chaining may not work)"
    fi

    # Display the response in YAML format with cyan color
    echo -e "${CYAN}$(echo "$body" | python3 -m yq '.' -y)${RESET}"
}

echo -e "${CYAN}=== Using Response API v2 ===${RESET}"

while true; do
    # Prompt the user for input
    read -p "Enter your query (or type 'exit' to quit): " user_query

    # Check if the user wants to exit
    if [[ "$user_query" == "exit" ]]; then
        echo "Exiting script."
        break
    elif [[ "$user_query" == "" ]]; then
        continue
    fi

    send_curl_query "$user_query"
done

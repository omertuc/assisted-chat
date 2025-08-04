#!/bin/bash

set -euo pipefail

# Color definitions
CYAN='\033[0;36m'
RESET='\033[0m'

# Get the script directory to locate utils
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
PROJECT_ROOT=$(dirname "$SCRIPT_DIR")

# Source the OCM token utility
source "$PROJECT_ROOT/utils/ocm-token.sh"

INTERACTIVE_MODE=false
if [[ "${1:-}" == "--interactive" ]]; then
    INTERACTIVE_MODE=true
    echo "Interactive mode enabled."
fi

DEFAULT_QUERY="What is the OpenShift Assisted Installer? Can you list my clusters?"

get_available_models() {
    curl --silent --show-error -X 'GET' 'http://0.0.0.0:8090/v1/models' -H 'accept: application/json'
}

select_model() {
    local models_json="$1"
    local model_identifier
    model_identifier=$(echo "$models_json" | jq '.models[] | select(.model_type == "llm").identifier' -r | fzf | cut -d'/' -f2-)
    local provider
    provider=$(echo "$models_json" | jq '.models[] | select(.identifier == "'"$model_identifier"'") | .provider_id' -r)
    echo "$model_identifier|$provider"
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

    # Fetch conversation history
    tmpfile=$(mktemp)
    status=$(curl --silent --show-error --output "$tmpfile" --write-out "%{http_code}" \
        -H "Authorization: Bearer ${OCM_TOKEN}" \
        "http://localhost:8090/v1/conversations/${conversation_id}")
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
    
    echo -e "${CYAN}=== Conversation History ===${RESET}"
    
    history_response=$(get_conversation_history "$conversation_id")
    if [[ $? -ne 0 ]]; then
        echo "Failed to fetch conversation history"
        return 1
    fi
    
    # Debug: Show the raw response
    echo "DEBUG: Raw API response:"
    echo "$history_response" | jq '.'
    echo "---"
    
    # Extract chat history from the response
    chat_history=$(echo "$history_response" | jq -r '.chat_history // []')
    
    echo "DEBUG: Extracted chat_history:"
    echo "$chat_history"
    echo "---"
    
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

    # Fetch conversations list
    tmpfile=$(mktemp)
    status=$(curl --silent --show-error --output "$tmpfile" --write-out "%{http_code}" \
        -H "Authorization: Bearer ${OCM_TOKEN}" \
        'http://localhost:8090/v1/conversations')
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
        echo "No existing conversations found. Starting new conversation."
        return 0
    fi

    # Create formatted fzf options with conversation metadata
    options=()
    options+=("$(printf "%-36s | %-32s" "New conversation" "Start a fresh conversation")")
    
    while IFS= read -r conv; do
        if [[ -n "$conv" ]]; then
            conv_id=$(echo "$conv" | jq -r '.conversation_id')
            created_at=$(echo "$conv" | jq -r '.created_at // "Unknown"')
            message_count=$(echo "$conv" | jq -r '.message_count // "N/A"')
            model=$(echo "$conv" | jq -r '.model // "Unknown"')
            
            # Format the created_at timestamp for display
            if [[ "$created_at" != "Unknown" && "$created_at" != "null" ]]; then
                formatted_date=$(date -d "$created_at" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "$created_at")
            else
                formatted_date="Unknown"
            fi
            
            # Create a formatted display line with model info
            display_line=$(printf "%-36s | Created: %-16s | Model: %-20s | Messages: %-3s" "$conv_id" "$formatted_date" "$model" "$message_count")
            options+=("$display_line")
        fi
    done < <(echo "$conversations_json" | jq -c '.[]')

    # Use fzf to let user select with a better prompt and preview
    selected=$(printf '%s\n' "${options[@]}" | fzf --prompt="Select conversation: " --height=15 --header="ID                                   | Created             | Model                | Messages")
    
    if [[ -z "$selected" ]]; then
        echo "No selection made. Exiting."
        exit 1
    fi

    if [[ "$selected" =~ ^"New conversation" ]]; then
        CONVERSATION_ID=""
        CONVERSATION_MODEL=""
    else
        # Extract conversation ID from the selected line (first 36 characters)
        CONVERSATION_ID=$(echo "$selected" | cut -c1-36 | xargs)
        # Extract model from the conversation data
        CONVERSATION_MODEL=$(echo "$conversations_json" | jq -r '.[] | select(.conversation_id == "'"$CONVERSATION_ID"'") | .model // ""')
    fi
}

CONVERSATION_ID=""
CONVERSATION_MODEL=""
select_conversation

# Display conversation history if an existing conversation was selected
if [[ -n "$CONVERSATION_ID" ]]; then
    echo "Selected existing conversation: $CONVERSATION_ID"
    display_conversation_history "$CONVERSATION_ID"
fi

# Get available models
MODELS=$(get_available_models)

# Select model based on conversation choice
if [[ -n "$CONVERSATION_MODEL" && "$CONVERSATION_MODEL" != "null" ]]; then
    echo "Using model from existing conversation: $CONVERSATION_MODEL"
    MODEL_IDENTIFIER=$(echo "$CONVERSATION_MODEL" | cut -d'/' -f2-)
    PROVIDER=$(echo "$MODELS" | jq '.models[] | select(.identifier == "'"$MODEL_IDENTIFIER"'") | .provider_id' -r)
else
    echo "Selecting new model..."
    model_selection=$(select_model "$MODELS")
    MODEL_IDENTIFIER=$(echo "$model_selection" | cut -d'|' -f1)
    PROVIDER=$(echo "$model_selection" | cut -d'|' -f2)
fi

send_curl_query() {
    local query="$1"

    # Get fresh OCM token for this query
    if ! get_ocm_token; then
        echo "Failed to get OCM token for query"
        return 1
    fi

    # Make the curl request and capture the response
    tmpfile=$(mktemp)
    status=$(curl --silent --show-error --output "$tmpfile" --write-out "%{http_code}" \
        -H "Authorization: Bearer ${OCM_TOKEN}" \
        'http://localhost:8090/v1/query' \
        --json '{
    "conversation_id": "'"$CONVERSATION_ID"'",
    "model": "'"$MODEL_IDENTIFIER"'",
    "provider": "'"$PROVIDER"'",
    "query": "'"${query}"'"
  }')
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
        echo "Updated conversation ID: $new_conversation_id"
        CONVERSATION_ID="$new_conversation_id"
    fi

    # Display the response in YAML format with cyan color
    echo -e "${CYAN}$(echo "$body" | python3 -m yq '.' -y)${RESET}"
}

if "$INTERACTIVE_MODE"; then
    echo "Example: What is the OpenShift Assisted Installer? Can you list my clusters?"
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
else
    echo "Using default query: \"$DEFAULT_QUERY\""
    send_curl_query "$DEFAULT_QUERY"
fi

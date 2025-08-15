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

# Configure base URL based on QUERY_ENV environment variable
case "${QUERY_ENV:-}" in
    "int")
        BASE_URL="https://assisted-chat.api.integration.openshift.com"
        ;;
    "stage")
        BASE_URL="https://assisted-chat.api.stage.openshift.com"
        ;;
    *)
        BASE_URL="http://localhost:8090"
        ;;
esac

get_available_models() {
    curl --silent --show-error -X 'GET' "${BASE_URL}/v1/models" -H 'accept: application/json'
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

    # Fetch conversation history
    tmpfile=$(mktemp)
    status=$(curl --silent --show-error --output "$tmpfile" --write-out "%{http_code}" \
        -H "Authorization: Bearer ${OCM_TOKEN}" \
        "${BASE_URL}/v1/conversations/${conversation_id}")
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

    # Fetch conversations list
    tmpfile=$(mktemp)
    status=$(curl --silent --show-error --output "$tmpfile" --write-out "%{http_code}" \
        -H "Authorization: Bearer ${OCM_TOKEN}" \
        "${BASE_URL}/v1/conversations")
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
        echo "No existing conversations found. Starting a new conversation."
        return 0
    fi

    fzf_options=()
    fzf_options+=("$(printf "%-36s | %-32s" "New conversation" "Start a fresh conversation")")

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
            display_line=$(printf "%-36s | Created: %-16s | Model: %-20s | Messages: %-3s" "$conv_id" "$formatted_date" "$model" "$message_count")
            fzf_options+=("$display_line")
        fi
    done < <(echo "$conversations_json" | jq -c '.[]')

    # Use fzf to let user select with a better prompt and preview
    selected=$(printf '%s\n' "${fzf_options[@]}" | fzf --prompt="Select conversation: " --height=15 --header="ID                                   | Created             | Model                | Messages")

    if [[ -z "$selected" ]]; then
        echo "No selection made. Exiting."
        exit 1
    fi

    if [[ $(echo "$selected" | cut -d' ' -f1-2) == "New conversation" ]]; then
        CONVERSATION_ID=""
    else
        # Extract conversation ID from the selected line (first 36 characters)
        CONVERSATION_ID=$(echo "$selected" | cut -c1-36 | xargs)
    fi
}

CONVERSATION_ID=""
select_conversation

# Display conversation history if an existing conversation was selected
if [[ -n "$CONVERSATION_ID" ]]; then
    echo "Selected existing conversation: $CONVERSATION_ID"
    display_conversation_history "$CONVERSATION_ID"
else
    # Only select model for new conversations
    echo "Selecting model for new conversation..."
    MODELS=$(get_available_models)
    model_selection=$(select_model "$MODELS")
    MODEL_NAME=$(echo "$model_selection" | cut -d'|' -f1)
    MODEL_PROVIDER=$(echo "$model_selection" | cut -d'|' -f2)
    echo "Example: What is the OpenShift Assisted Installer? Can you list my clusters?"
fi

send_curl_query() {
    local query="$1"
    local start_time end_time duration

    # Record start time
    start_time=$(date +%s.%N)

    # Get fresh OCM token for this query
    if ! get_ocm_token; then
        echo "Failed to get OCM token for query"
        return 1
    fi

    # Make the curl request and capture the response
    tmpfile=$(mktemp)

    # For existing conversations, omit model/provider to let endpoint reuse from conversation
    if [[ -z "${MODEL_NAME-}" ]]; then
        json_payload='
        {
            "conversation_id": "'"$CONVERSATION_ID"'",
            "query": "'"${query}"'"
        }'
    else
        json_payload='
        {
            "conversation_id": "'"$CONVERSATION_ID"'",
            "model": "'"$MODEL_NAME"'",
            "provider": "'"$MODEL_PROVIDER"'",
            "query": "'"${query}"'"
        }'
    fi

    status=$(curl --silent --show-error --output "$tmpfile" --write-out "%{http_code}" \
        -H "Authorization: Bearer ${OCM_TOKEN}" \
        "${BASE_URL}/v1/query" \
        --json "$json_payload")
    body=$(cat "$tmpfile")
    rm "$tmpfile"

    # Record end time and calculate duration
    end_time=$(date +%s.%N)
    duration=$(echo "$end_time - $start_time" | bc)

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

    # Display the response in YAML format with cyan color
    echo -e "${CYAN}$(echo "$body" | python3 -m yq '.' -y)${RESET}"
    
    # Return the duration for the caller
    echo "$duration"
}

# Check if MEASURE_MODE is set to run multiple queries for performance measurement
if [[ "${MEASURE_MODE:-}" == "true" ]]; then
    # Prompt for the query to repeat
    read -p "Enter query to run 10 times: " user_query
    
    if [[ -z "$user_query" ]]; then
        echo "Error: No query provided"
        exit 1
    fi
    
    echo "Running query 10 times with fresh conversation IDs..."
    
    # Initialize results array
    results=()
    
    # Run the query 10 times
    for i in {1..10}; do
        echo "Run $i/10..."
        
        # Reset conversation ID for fresh conversation
        CONVERSATION_ID=""
        
        # Capture both output and timing (last line)
        output=$(send_curl_query "$user_query" 2>&1)
        duration=$(echo "$output" | tail -n1)
        
        # Add result to array
        results+=("{\"run\": $i, \"duration_seconds\": $duration, \"query\": \"$(echo "$user_query" | sed 's/"/\\"/g')\"}")
        
        echo "Duration: ${duration}s"
        echo ""
    done
    
    # Create JSON output
    json_output="["
    for i in "${!results[@]}"; do
        if [[ $i -gt 0 ]]; then
            json_output+=","
        fi
        json_output+="${results[$i]}"
    done
    json_output+="]"
    
    # Write to /tmp/measure.json
    echo "$json_output" | jq '.' > /tmp/measure.json
    echo "Results written to /tmp/measure.json"
    echo ""
    echo "To compare multiple measurements:"
    echo "1. Copy /tmp/measure.json to measure-<label>.json in your project directory"
    echo "2. Run multiple measurements with different labels"
    echo "3. Use 'make graph-measure' to visualize all results together"
    
else
    # Original interactive mode
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
fi

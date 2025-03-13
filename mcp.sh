#!/bin/zsh
# mcp.sh - MCP wrapper for speech.sh
# This script implements the Model Context Protocol (MCP) to make speech.sh accessible to MCP clients

# Exit on error, unset variable, and pipe failures
set -euo pipefail

# Path to the speech.sh script (assumes it's in the same directory)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SPEECH_SCRIPT="$SCRIPT_DIR/speech.sh"
LOG_FILE="$SCRIPT_DIR/logs.txt"

# Initialize or rotate log file if it gets too large (>1MB)
if [[ -f "$LOG_FILE" && $(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null) -gt 1048576 ]]; then
    mv "$LOG_FILE" "${LOG_FILE}.old"
    touch "$LOG_FILE"
    echo "[$(date "+%Y-%m-%d %H:%M:%S")] [MCP] Log file rotated due to size" >> "$LOG_FILE"
fi

# Create log file if it doesn't exist
touch "$LOG_FILE"

# Function to log messages to both stderr and log file with timestamp
function log_message() {
    local component="$1"
    local message="$2"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    local formatted_message="[$timestamp] [$component] $message"
    
    # Echo to stderr
    echo "$formatted_message" >&2
    
    # Append to log file
    echo "$formatted_message" >> "$LOG_FILE"
}

# Check if the speech.sh script exists and is executable
if [[ ! -x "$SPEECH_SCRIPT" ]]; then
    log_message "ERROR" "Cannot find or execute $SPEECH_SCRIPT"
    exit 1
fi

# API key handling - try to get from environment first
API_KEY="${OPENAI_API_KEY:-}"

# MCP server metadata
SERVER_NAME="speech"
SERVER_VERSION="1.0.0"
SERVER_DESCRIPTION="Text-to-speech conversion using OpenAI's API"
SERVER_AUTH_TYPE="none"

# Available methods in our MCP server
function get_server_capabilities() {
    jq -c -n \
        --arg name "$SERVER_NAME" \
        --arg version "$SERVER_VERSION" \
        --arg description "$SERVER_DESCRIPTION" \
        --arg auth_type "$SERVER_AUTH_TYPE" \
        '{
            "name": $name,
            "version": $version,
            "description": $description,
            "authType": $auth_type,
            "methods": {
                "speak": {
                    "description": "Say something out loud. Use it to attract the user's attention when you're done with a task, need help, or just want to say something.",
                    "parameters": {
                        "text": {
                            "type": "string",
                            "description": "The text to convert to speech",
                            "required": true
                        }
                    },
                    "notes": "Other settings (voice, speed, model) should be configured via environment variables: SPEECH_VOICE, SPEECH_SPEED, and SPEECH_MODEL"
                }
            }
        }'
}

# Function to generate a JSON-RPC response
function send_response() {
    local id="$1"
    local result="$2"
    
    # Create the JSON-RPC response without further processing
    echo "{\"jsonrpc\":\"2.0\",\"id\":$id,\"result\":$result}"
}

# Function to generate a JSON-RPC error response
function send_error() {
    local id="$1"
    local code="$2"
    local message="$3"
    
    log_message "ERROR" "JSON-RPC error: $message (code: $code)"
    
    # Use jq to ensure compact, single-line JSON output
    local error_json=$(jq -c -n \
        --arg code "$code" \
        --arg message "$message" \
        '{
            "jsonrpc": "2.0",
            "id": '"$id"',
            "error": {
                "code": ($code | tonumber),
                "message": $message
            }
        }')
    
    echo "$error_json"
}

# Function to handle the initialize method
function handle_initialize() {
    local id="$1"
    local params="$2"
    
    # Extract protocol version
    local protocol_version=$(echo "$params" | jq -r '.protocolVersion // ""')
    
    log_message "MCP" "Handling initialize with protocol version: $protocol_version"
    
    # Return server initialization response with proper format (as single-line JSON)
    local result=$(jq -c -n \
        --arg version "$protocol_version" \
        --arg name "$SERVER_NAME" \
        --arg server_version "$SERVER_VERSION" \
        '{
            "protocolVersion": $version,
            "capabilities": {
                "experimental": {},
                "prompts": {"listChanged": false},
                "tools": {"listChanged": false}
            },
            "serverInfo": {
                "name": $name,
                "version": $server_version
            }
        }')
    
    send_response "$id" "$result"
}

# Function to handle the speak method
function handle_speak() {
    local id="$1"
    local params="$2"
    
    # Get defaults from environment variables or use hardcoded defaults
    local default_voice="${SPEECH_VOICE:-onyx}"
    local default_speed="${SPEECH_SPEED:-1.0}"
    local default_model="${SPEECH_MODEL:-tts-1}"
    
    # Extract parameters using jq, with fallbacks to environment variables
    local text=$(echo "$params" | jq -r '.text // ""')
    local voice=$(echo "$params" | jq -r ".voice // \"$default_voice\"")
    local speed=$(echo "$params" | jq -r ".speed // \"$default_speed\"")
    local model=$(echo "$params" | jq -r ".model // \"$default_model\"")
    
    # Log the parameters being used
    log_message "SPEECH" "Using voice: $voice, speed: $speed, model: $model"
    log_message "SPEECH" "Text to speak: '$text'"
    
    # Validate required parameters
    if [[ -z "$text" ]]; then
        # For tool calls, we need to return error in the proper format
        local error_result=$(jq -c -n \
            '{
                "content": [{"type": "text", "text": "Missing required parameter: text"}],
                "isError": true
            }')
        send_response "$id" "$error_result"
        log_message "ERROR" "Missing required parameter: text"
        return
    fi
    
    # Prepare command arguments
    local cmd_args=()
    cmd_args+=("--text" "$text")
    cmd_args+=("--voice" "$voice")
    cmd_args+=("--speed" "$speed")
    cmd_args+=("--model" "$model")
    
    # Add API key if available
    if [[ -n "$API_KEY" ]]; then
        cmd_args+=("--api_key" "$API_KEY")
    fi
    
    # Generate a unique request ID using the time and some random data
    local request_id="req_${id}_$(date +%s%N)_${RANDOM}"
    log_message "SPEECH" "Generated request ID: $request_id"
    
    # Log the full command for debugging
    log_message "SPEECH" "Command: $SPEECH_SCRIPT ${cmd_args[*]}"
    
    # Run in background to not block the MCP server, capture output to log file
    "$SPEECH_SCRIPT" "${cmd_args[@]}" > "$SCRIPT_DIR/speech_${request_id}.log" 2>&1 &
    local speech_pid=$!
    log_message "SPEECH" "Started speech process with PID $speech_pid for request $request_id"
    
    # Start a background process to monitor the speech process
    (
        # Wait for the speech process to complete
        wait "$speech_pid" 2>/dev/null || true
        local exit_code=$?
        
        log_message "SPEECH" "Speech process ($speech_pid) has completed with exit code $exit_code"
        
        # If there was an error, log it
        if [[ $exit_code -ne 0 ]]; then
            log_message "ERROR" "Speech process failed with exit code $exit_code. Check speech_${request_id}.log for details"
        fi
    ) &
    
    # Return success immediately
    local success_json=$(jq -c -n \
        --arg text "$text" \
        --arg voice "$voice" \
        --arg speed "$speed" \
        --arg model "$model" \
        '{
            "content": [
                {
                    "type": "text", 
                    "text": "Done"
                }
            ],
            "isError": false
        }')
    send_response "$id" "$success_json"
}

# Function to handle the shutdown method
function handle_shutdown() {
    local id="$1"
    local params="$2"
    
    # Log shutdown to stderr
    log_message "MCP" "Received shutdown request. Terminating server..."
    
    # Send success response before exiting
    local result=$(jq -c -n '{"success":true}')
    send_response "$id" "$result"
    
    # Exit the script with success code
    exit 0
}

# Function to handle notifications/initialized method (no response needed)
function handle_notifications_initialized() {
    # This is just a notification, no response needed
    # But we can log it for debugging
    log_message "MCP" "Received notifications/initialized notification"
}

# Function to handle resources/list method
function handle_resources_list() {
    local id="$1"
    
    # Our simple speech server doesn't provide resources, so return empty list
    local result=$(jq -c -n '{"resources":[]}')
    send_response "$id" "$result"
}

# Function to handle tools/list method
function handle_tools_list() {
    local id="$1"
    
    log_message "MCP" "Handling tools/list request"
    
    # Define the JSON directly with simpler jq syntax to avoid quoting issues
    local result=$(cat <<'EOF' | jq -c
{
  "tools": [
    {
      "name": "speak",
      "description": "Say something out loud. Use it to attract the user's attention when you're done with a task, need help, or just want to say something.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "text": {
            "type": "string",
            "description": "The text to convert to speech"
          }
        },
        "required": ["text"]
      }
    }
  ]
}
EOF
)
    send_response "$id" "$result"
}

# Function to handle prompts/list method
function handle_prompts_list() {
    local id="$1"
    
    # Our simple speech server doesn't provide prompts, so return empty list
    local result=$(jq -c -n '{"prompts":[]}')
    send_response "$id" "$result"
}

# Function to handle tools/call method
function handle_tools_call() {
    local id="$1"
    local params="$2"
    
    # Extract tool name and arguments
    local tool_name=$(echo "$params" | jq -r '.name // ""')
    local arguments=$(echo "$params" | jq -c '.arguments // {}')
    
    log_message "MCP" "Calling tool: $tool_name with arguments: $arguments"
    
    # Route to the appropriate tool
    case "$tool_name" in
        "speak")
            # Call our speak method
            handle_speak "$id" "$arguments"
            ;;
        *)
            # Tool not found
            send_error "$id" -32601 "Tool not found: $tool_name"
            ;;
    esac
}

# Function to handle JSON-RPC requests
function handle_request() {
    local request="$1"
    
    # Parse the JSON-RPC request
    local jsonrpc=$(echo "$request" | jq -r '.jsonrpc // ""')
    local method=$(echo "$request" | jq -r '.method // ""')
    local id=$(echo "$request" | jq -r '.id // "null"')
    local params=$(echo "$request" | jq -r '.params // {}')
    
    log_message "MCP" "Received request method: $method, id: $id"
    
    # Validate JSON-RPC version
    if [[ "$jsonrpc" != "2.0" ]]; then
        send_error "$id" -32600 "Invalid JSON-RPC: version must be 2.0"
        return
    fi
    
    # Check if this is a notification (no id)
    local is_notification=false
    if [[ "$id" == "null" || "$method" == "notifications/initialized" ]]; then
        is_notification=true
    fi
    
    # Handle method calls
    case "$method" in
        "initialize")
            # Handle initialize method (required by MCP)
            handle_initialize "$id" "$params"
            ;;
        "shutdown")
            # Handle shutdown method
            handle_shutdown "$id" "$params"
            ;;
        "server.capabilities")
            # Return server capabilities
            send_response "$id" "$(get_server_capabilities)"
            ;;
        "speak")
            # Handle speak method directly (legacy support)
            handle_speak "$id" "$params"
            ;;
        "notifications/initialized")
            # Handle notifications/initialized method (no response needed)
            handle_notifications_initialized
            # Return empty string to indicate no response should be sent
            echo ""
            return
            ;;
        "resources/list")
            # Handle resources/list method
            handle_resources_list "$id"
            ;;
        "tools/list")
            # Handle tools/list method
            handle_tools_list "$id"
            ;;
        "tools/call")
            # Handle tools/call method
            handle_tools_call "$id" "$params"
            ;;
        "prompts/list")
            # Handle prompts/list method
            handle_prompts_list "$id"
            ;;
        *)
            # Method not found
            send_error "$id" -32601 "Method not found: $method"
            ;;
    esac
}

# Main loop to read from stdin and process JSON-RPC requests
function main() {
    # Print initialization message and log it
    log_message "MCP" "Speech server starting in stdio mode..."

    # Process input line by line
    while IFS= read -r line; do
        # Skip empty lines
        [[ -z "$line" ]] && continue
        
        # Log the received line for debugging (truncated if very long)
        if [[ ${#line} -gt 300 ]]; then
            log_message "MCP" "Received client message: ${line:0:300}... (truncated)"
        else
            log_message "MCP" "Received client message: $line"
        fi
        
        # Handle the JSON-RPC request
        response=$(handle_request "$line")
        
        # Skip empty responses (for notifications)
        if [[ -z "$response" ]]; then
            log_message "MCP" "No response required for notification"
            continue
        fi
        
        # Log the response for debugging (truncated if very long)
        if [[ ${#response} -gt 300 ]]; then
            log_message "MCP" "Sending server response: ${response:0:300}... (truncated)"
        else
            log_message "MCP" "Sending server response: $response"
        fi
        
        # Send the response
        echo "$response"

        # Flush stdout to ensure the response is sent immediately
        command -v flush >/dev/null 2>&1 && flush || command true
    done
}

# Execute the main function
main 
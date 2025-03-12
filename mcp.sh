#!/bin/zsh
# mcp.sh - MCP wrapper for speech.sh
# This script implements the Model Context Protocol (MCP) to make speech.sh accessible to MCP clients

# Exit on error, unset variable, and pipe failures
set -euo pipefail

# Path to the speech.sh script (assumes it's in the same directory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPEECH_SCRIPT="$SCRIPT_DIR/speech.sh"

# Check if the speech.sh script exists and is executable
if [[ ! -x "$SPEECH_SCRIPT" ]]; then
    echo "Error: Cannot find or execute $SPEECH_SCRIPT" >&2
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
    cat << EOF
{
  "name": "$SERVER_NAME",
  "version": "$SERVER_VERSION", 
  "description": "$SERVER_DESCRIPTION",
  "authType": "$SERVER_AUTH_TYPE",
  "methods": {
    "speak": {
      "description": "Convert text to speech using OpenAI's TTS API",
      "parameters": {
        "text": {
          "type": "string",
          "description": "The text to convert to speech",
          "required": true
        },
        "voice": {
          "type": "string",
          "description": "Voice model to use (default: onyx)",
          "enum": ["alloy", "echo", "fable", "onyx", "nova", "shimmer"],
          "required": false
        },
        "speed": {
          "type": "number",
          "description": "Speech speed (default: 1.0)",
          "required": false
        },
        "model": {
          "type": "string",
          "description": "TTS model to use (default: tts-1)",
          "enum": ["tts-1", "tts-1-hd"],
          "required": false
        }
      }
    }
  }
}
EOF
}

# Function to generate a JSON-RPC response
function send_response() {
    local id="$1"
    local result="$2"
    
    echo "{\"jsonrpc\":\"2.0\",\"id\":$id,\"result\":$result}"
}

# Function to generate a JSON-RPC error response
function send_error() {
    local id="$1"
    local code="$2"
    local message="$3"
    
    echo "{\"jsonrpc\":\"2.0\",\"id\":$id,\"error\":{\"code\":$code,\"message\":\"$message\"}}"
}

# Function to handle the speak method
function handle_speak() {
    local id="$1"
    local params="$2"
    
    # Extract parameters using jq
    local text=$(echo "$params" | jq -r '.text // ""')
    local voice=$(echo "$params" | jq -r '.voice // "onyx"')
    local speed=$(echo "$params" | jq -r '.speed // 1.0')
    local model=$(echo "$params" | jq -r '.model // "tts-1"')
    
    # Validate required parameters
    if [[ -z "$text" ]]; then
        send_error "$id" -32602 "Missing required parameter: text"
        return
    fi
    
    # Create a temporary file to capture output
    local output_file=$(mktemp)
    
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
    
    # Run the speech.sh script with the specified parameters
    # We set an output file so we don't need to play the audio
    "$SPEECH_SCRIPT" "${cmd_args[@]}" --output "$output_file" 2>/dev/null
    
    # Check if the command succeeded
    if [[ $? -eq 0 && -f "$output_file" ]]; then
        # Return success with file path
        send_response "$id" "{\"status\":\"success\",\"message\":\"Speech generated\",\"file_path\":\"$output_file\"}"
    else
        # Return error
        send_error "$id" -32000 "Failed to generate speech"
        # Clean up temporary file if it exists
        [[ -f "$output_file" ]] && rm "$output_file"
    fi
}

# Function to handle JSON-RPC requests
function handle_request() {
    local request="$1"
    
    # Parse the JSON-RPC request
    local jsonrpc=$(echo "$request" | jq -r '.jsonrpc // ""')
    local method=$(echo "$request" | jq -r '.method // ""')
    local id=$(echo "$request" | jq -r '.id // "null"')
    local params=$(echo "$request" | jq -r '.params // {}')
    
    # Validate JSON-RPC version
    if [[ "$jsonrpc" != "2.0" ]]; then
        send_error "$id" -32600 "Invalid JSON-RPC: version must be 2.0"
        return
    fi
    
    # Handle method calls
    case "$method" in
        "server.capabilities")
            # Return server capabilities
            send_response "$id" "$(get_server_capabilities)"
            ;;
        "speak")
            # Handle speak method
            handle_speak "$id" "$params"
            ;;
        *)
            # Method not found
            send_error "$id" -32601 "Method not found: $method"
            ;;
    esac
}

# Main loop to read from stdin and process JSON-RPC requests
function main() {
    # Print initialization message to stderr (not part of protocol)
    echo "MCP speech server starting in stdio mode..." >&2

    # Process input line by line
    while IFS= read -r line; do
        # Skip empty lines
        [[ -z "$line" ]] && continue
        
        # Handle the JSON-RPC request
        response=$(handle_request "$line")
        
        # Send the response
        echo "$response"
    done
}

# Execute the main function
main 
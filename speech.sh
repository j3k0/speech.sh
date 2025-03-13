#!/bin/zsh
# speech.sh - Text-to-speech utility using OpenAI's API
# Usage: ./speech.sh --text "Text to speak" [options]
# See --help for more information

# Exit on error, unset variable, and pipe failures
set -euo pipefail

# Script directory for log file path
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="$SCRIPT_DIR/speech_logs.txt"

# Default configuration
SPEED="1.0"
VOICE="onyx"
API_KEY="NONE"
FILE="AUTO"
VERBOSE="F"
MODEL="tts-1"  # Make model configurable
MAX_RETRIES="3"  # Maximum number of retry attempts for API calls
TIMEOUT="30"     # Timeout in seconds for API calls
PLAYER="auto"    # Audio player to use: auto, ffmpeg, or mplayer

# Initialize or rotate log file if it gets too large (>1MB)
if [[ -f "$LOG_FILE" && $(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null) -gt 1048576 ]]; then
    mv "$LOG_FILE" "${LOG_FILE}.old"
    touch "$LOG_FILE"
    echo "[$(date "+%Y-%m-%d %H:%M:%S")] [SYSTEM] Log file rotated due to size" >> "$LOG_FILE"
fi

# Create log file if it doesn't exist
touch "$LOG_FILE"

# Function to log messages to the log file with timestamp
function log_to_file() {
    local component="$1"
    local message="$2"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    local formatted_message="[$timestamp] [$component] $message"
    
    # Append to log file
    echo "$formatted_message" >> "$LOG_FILE"
}

# Function to log to stderr - always displayed regardless of verbose setting
log_err() {
    echo "$1" >&2
    log_to_file "ERROR" "$1"
    if command -v notify-send >/dev/null 2>&1; then
        notify-send "speech.sh: $1"
    fi
}

# Function to log to stdout - only when verbose is enabled
log() {
    if [[ "$VERBOSE" != "F" ]]; then
        echo "$1"
        if command -v notify-send >/dev/null 2>&1; then
            notify-send "speech.sh: $1"
        fi
    fi
    # Always log to file, regardless of verbose setting
    log_to_file "INFO" "$1"
}

# Function to handle errors
error_exit() {
    log_err "ERROR: $1"
    log_to_file "ERROR" "$1"
    exit "${2:-1}"  # Default exit code is 1
}

# Check if the command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Detect if being called by MCP and adjust settings if needed
if [[ -n "${MCP_CALLING:-}" ]] || [[ "$0" == *"mcp"* ]] || [[ "$(ps -p $PPID -o comm=)" == *"mcp"* ]]; then
    log_to_file "SYSTEM" "Detected running under MCP, adjusting settings"
    # Increase timeout and retries for better reliability when called by MCP
    TIMEOUT="60"
    MAX_RETRIES="3"
    # Use more reliable audio player under MCP
    PLAYER="ffmpeg"
    # Force output to a predictable location if not specified
    if [[ "$FILE" == "AUTO" ]]; then
        FILE="/tmp/openai_speech_mcp_output.mp3"
        log_to_file "FILE" "Force output file to $FILE for MCP"
    fi
fi

# Print usage information
show_help() {
    cat << EOF
Usage: $(basename $0) [options]

Convert text to speech using OpenAI's API.

Options:
  -h, --help          Show this help message and exit
  -t, --text TEXT     Text to convert to speech (required)
  -v, --voice VOICE   Voice model to use (default: onyx)
  -s, --speed SPEED   Speech speed (default: 1.0)
  -o, --output FILE   Output file path (default: auto-generated)
  -a, --api_key KEY   OpenAI API key
  -m, --model MODEL   TTS model to use (default: tts-1)
      --verbose       Enable verbose logging
  -V, --verbose       Same as --verbose
  -r, --retries N     Number of retry attempts for API calls (default: 3)
  -T, --timeout N     Timeout in seconds for API calls (default: 30)
  -p, --player PLAYER Audio player to use: auto, ffmpeg, or mplayer (default: auto)
                      'auto' will use ffmpeg if available, falling back to mplayer

The API key can be provided in three ways (in order of precedence):
1. Command-line argument (-a, --api_key)
2. OPENAI_API_KEY environment variable
3. A file named 'API_KEY' in the script's directory
EOF
    exit 0
}

# Check if required commands exist
check_dependencies() {
    log_to_file "SYSTEM" "Checking dependencies"
    local missing=0
    
    # Check required dependencies
    for cmd in curl jq; do
        if ! command_exists "$cmd"; then
            log_err "Required command not found: $cmd"
            log_to_file "ERROR" "Required dependency missing: $cmd"
            missing=1
        else
            log_to_file "SYSTEM" "Found required dependency: $cmd"
        fi
    done
    
    # Check audio players based on configuration
    if [[ "$PLAYER" == "auto" ]]; then
        log_to_file "SYSTEM" "Checking for available audio players (auto mode)"
        if command_exists "ffmpeg"; then
            log "ffmpeg found, using it for audio playback"
            log_to_file "SYSTEM" "Found ffmpeg, setting as audio player"
            PLAYER="ffmpeg"
        elif command_exists "mplayer"; then
            log "mplayer found, using it for audio playback"
            log_to_file "SYSTEM" "Found mplayer, setting as audio player"
            PLAYER="mplayer"
        else
            log_err "No audio player found. Please install ffmpeg or mplayer."
            log_to_file "ERROR" "No audio player found (tried ffmpeg and mplayer)"
            missing=1
        fi
    elif [[ "$PLAYER" == "ffmpeg" ]]; then
        log_to_file "SYSTEM" "Checking for ffmpeg (explicit configuration)"
        if ! command_exists "ffmpeg"; then
            log_err "ffmpeg was specified but not found"
            log_to_file "ERROR" "ffmpeg was explicitly requested but not found"
            missing=1
        else
            log_to_file "SYSTEM" "Found requested audio player: ffmpeg"
        fi
    elif [[ "$PLAYER" == "mplayer" ]]; then
        log_to_file "SYSTEM" "Checking for mplayer (explicit configuration)"
        if ! command_exists "mplayer"; then
            log_err "mplayer was specified but not found"
            log_to_file "ERROR" "mplayer was explicitly requested but not found"
            missing=1
        else
            log_to_file "SYSTEM" "Found requested audio player: mplayer"
        fi
    else
        log_err "Invalid player specified: $PLAYER. Valid options are: auto, ffmpeg, mplayer"
        log_to_file "ERROR" "Invalid player specified: $PLAYER"
        missing=1
    fi
    
    if [[ $missing -eq 1 ]]; then
        log_to_file "ERROR" "Dependency check failed, missing required components"
        error_exit "Missing dependencies. Please install the required packages." 2
    fi
    
    log_to_file "SYSTEM" "All dependencies checked successfully"
}

# Process command line arguments
parse_arguments() {
    # Initialize TEXT as empty to check if it's provided
    TEXT=""
    
    log_to_file "ARGS" "Starting to parse command line arguments"
    
    while (( $# > 0 )); do
        case "$1" in
            -h | --help)
                show_help
                ;;
            -v | --voice)
                if [[ -z "${2:-}" ]]; then
                    error_exit "Missing value for parameter: $1"
                fi
                VOICE="$2"
                log_to_file "ARGS" "Setting voice to: $VOICE"
                shift 2
                ;;
            -t | --text)
                if [[ -z "${2:-}" ]]; then
                    error_exit "Missing value for parameter: $1"
                fi
                TEXT="$2"
                log_to_file "ARGS" "Setting text to: $TEXT"
                shift 2
                ;;
            -s | --speed)
                if [[ -z "${2:-}" ]]; then
                    error_exit "Missing value for parameter: $1"
                fi
                SPEED="$2"
                log_to_file "ARGS" "Setting speed to: $SPEED"
                shift 2
                ;;
            -o | --output)
                if [[ -z "${2:-}" ]]; then
                    error_exit "Missing value for parameter: $1"
                fi
                FILE="$2"
                log_to_file "ARGS" "Setting output file to: $FILE"
                shift 2
                ;;
            -a | --api_key)
                if [[ -z "${2:-}" ]]; then
                    error_exit "Missing value for parameter: $1"
                fi
                API_KEY="$2"
                log_to_file "ARGS" "API key provided via command line"
                shift 2
                ;;
            -m | --model)
                if [[ -z "${2:-}" ]]; then
                    error_exit "Missing value for parameter: $1"
                fi
                MODEL="$2"
                log_to_file "ARGS" "Setting model to: $MODEL"
                shift 2
                ;;
            -p | --player)
                if [[ -z "${2:-}" ]]; then
                    error_exit "Missing value for parameter: $1"
                fi
                PLAYER="$2"
                log_to_file "ARGS" "Setting player to: $PLAYER"
                shift 2
                ;;
            -r | --retries)
                if [[ -z "${2:-}" ]]; then
                    error_exit "Missing value for parameter: $1"
                fi
                MAX_RETRIES="$2"
                log_to_file "ARGS" "Setting max retries to: $MAX_RETRIES"
                shift 2
                ;;
            -T | --timeout)
                if [[ -z "${2:-}" ]]; then
                    error_exit "Missing value for parameter: $1"
                fi
                TIMEOUT="$2"
                log_to_file "ARGS" "Setting timeout to: $TIMEOUT"
                shift 2
                ;;
            -V | --verbose)
                VERBOSE="T"
                log_to_file "ARGS" "Enabling verbose mode"
                shift 1
                ;;
            *)
                error_exit "Invalid option(s): $1. Use -h or --help for usage information."
                ;;
        esac
    done
    
    # Check if TEXT is provided
    if [[ -z "$TEXT" ]]; then
        log_err "No text to voice"
        log_to_file "ERROR" "No text to voice provided"
        echo "Use -h or --help for usage information" >&2
        exit 0
    fi
    
    # Validate PLAYER value
    if [[ ! "$PLAYER" =~ ^(auto|ffmpeg|mplayer)$ ]]; then
        error_exit "Invalid player: $PLAYER. Valid values are: auto, ffmpeg, mplayer"
    fi
    
    log_to_file "ARGS" "Argument parsing completed successfully"
}

# Get API key from available sources
get_api_key() {
    log_to_file "API" "Getting API key from available sources"
    if [[ "$API_KEY" == "NONE" ]]; then
        # First check for environment variable
        if [[ -n "${OPENAI_API_KEY:-}" ]]; then
            log "Using API key from OPENAI_API_KEY environment variable"
            log_to_file "API" "Using API key from OPENAI_API_KEY environment variable"
            API_KEY="$OPENAI_API_KEY"
            
            # Special handling for MCP environment
            if [[ -n "${MCP_CALLING:-}" ]] || [[ "$0" == *"mcp"* ]] || [[ "$(ps -p $PPID -o comm=)" == *"mcp"* ]]; then
                # Check if API key looks like a placeholder
                if [[ "$API_KEY" == *"your-api"* || "$API_KEY" == *"placeholder"* ]]; then
                    log_to_file "ERROR" "Detected placeholder API key when called by MCP"
                    log_err "MCP provided a placeholder API key. Please set a valid OpenAI API key."
                    # Look for API key in alternative locations for MCP
                    if [[ -e "$HOME/.openai_api_key" ]]; then
                        log_to_file "API" "Found alternative API key at $HOME/.openai_api_key"
                        API_KEY="$(cat "$HOME/.openai_api_key")"
                    fi
                fi
            fi
        # Then check for API_KEY file
        elif [[ ! -e "API_KEY" ]]; then
            log_to_file "API" "No API key available from any source"
            error_exit "No API key given as argument, no OPENAI_API_KEY environment variable, and no file called API_KEY"
        else
            log "Using API key from API_KEY file"
            log_to_file "API" "Using API key from API_KEY file"
            # Use cat with quotes to handle potential whitespace issues
            API_KEY="$(cat "API_KEY")"
        fi
    fi
    
    # Log if we have a valid-looking API key (just checking format, not validity)
    if [[ -n "$API_KEY" && "$API_KEY" != "NONE" ]]; then
        # Mask the key for privacy in logs - only show first 4 and last 4 chars
        local masked_key="${API_KEY:0:4}...${API_KEY: -4}"
        log_to_file "API" "API key obtained (masked: $masked_key)"
        
        # Additional validation - OpenAI API keys typically start with "sk-"
        if [[ ! "$API_KEY" =~ ^sk- ]]; then
            log_to_file "WARN" "API key doesn't match expected format (should start with 'sk-')"
            if [[ -n "${MCP_CALLING:-}" ]] || [[ "$0" == *"mcp"* ]] || [[ "$(ps -p $PPID -o comm=)" == *"mcp"* ]]; then
                log_to_file "WARN" "This may cause issues with MCP integration"
            fi
        fi
    else
        log_to_file "ERROR" "API key appears invalid or empty"
    fi
}

# Generate output filename if not provided
generate_filename() {
    log_to_file "FILE" "Generating output filename"
    if [[ "$FILE" == "AUTO" ]]; then
        local temp_dir
        temp_dir="$(dirname "$(mktemp -u)")"
        # Use more secure hash function if available
        if command_exists "sha256sum"; then
            FILE="${temp_dir}/OPENAI_SPEECH_$(echo -n "$TEXT $VOICE $SPEED" | sha256sum | cut -d" " -f1).mp3"
            log_to_file "FILE" "Using sha256sum for filename generation"
        else
            FILE="${temp_dir}/OPENAI_SPEECH_$(echo -n "$TEXT $VOICE $SPEED" | md5sum - | cut -d" " -f1).mp3"
            log_to_file "FILE" "Using md5sum for filename generation"
        fi
        log "Auto-generated filename: $FILE"
        log_to_file "FILE" "Auto-generated filename: $FILE"
    else
        log_to_file "FILE" "Using user-provided filename: $FILE"
    fi
    
    # Check if file already exists
    if [[ -e "$FILE" ]]; then
        log_to_file "FILE" "Output file already exists, will reuse cached audio"
    else
        log_to_file "FILE" "Output file does not exist, will generate new audio"
    fi
}

# Make API call to generate speech with retry logic
generate_speech() {
    if [[ ! -e "$FILE" ]]; then
        log "API call for \"$TEXT\""
        log_to_file "API" "Making API call for text: \"$TEXT\""
        
        # Create JSON payload once to avoid recreating it in each retry
        local json_payload
        json_payload=$(jq -n \
            --arg model "$MODEL" \
            --arg input "$TEXT" \
            --arg voice "$VOICE" \
            --arg speed "$SPEED" \
            '{model: $model, input: $input, voice: $voice, speed: $speed}')
        
        log_to_file "API" "Created JSON payload with model: $MODEL, voice: $VOICE, speed: $SPEED"
        
        local retry_count=0
        local success=false
        local error_message=""

        # Simple retry approach with basic curl options
        while [[ $retry_count -le $MAX_RETRIES && "$success" != "true" ]]; do
            if [[ $retry_count -gt 0 ]]; then
                log "Retry attempt $retry_count/$MAX_RETRIES..."
                log_to_file "API" "Retry attempt $retry_count/$MAX_RETRIES"
                # Add simple backoff
                local wait_time=3
                log_to_file "API" "Waiting $wait_time seconds before retry"
                sleep $wait_time
            fi
            
            # Simple curl command - no complex options
            log_to_file "API" "Making API request to OpenAI (attempt $retry_count)"
            local response
            response=$(curl --silent --show-error \
                --max-time "$TIMEOUT" \
                https://api.openai.com/v1/audio/speech \
                -H "Content-Type: application/json" \
                -H "Authorization: Bearer $API_KEY" \
                -d "$json_payload" \
                -o "$FILE" 2>&1) || {
                    local exit_code=$?
                    error_message="curl failed with exit code $exit_code: $response"
                    log_to_file "ERROR" "$error_message"
                    retry_count=$((retry_count + 1))
                    continue
                }
            
            # If we got here, it means curl succeeded
            success=true
            log_to_file "API" "API call successful on attempt $retry_count, response saved to $FILE"
        done
        
        if [[ "$success" != "true" ]]; then
            log_to_file "ERROR" "API call failed after $retry_count attempts: $error_message"
            error_exit "API call failed after $retry_count attempts: $error_message" 3
        fi
            
        if [[ ! -e "$FILE" ]]; then
            log_to_file "ERROR" "No output file created after API call"
            error_exit "No file created, something went wrong." 4
        fi

        # Check if the response is a JSON error instead of audio data
        if [[ "$(file --brief "$FILE" 2>/dev/null)" == "JSON data" ]]; then
            local error_message
            error_message="$(jq -r '.error.message // "Unknown error"' < "$FILE")"
            log_to_file "ERROR" "OpenAI API returned an error: $error_message"
            rm -f "$FILE"
            error_exit "OpenAI API error: $error_message" 5
        fi
        
        log_to_file "API" "API response successfully verified as audio data"
    else
        log "Skipping API call, using cached file"
        log_to_file "API" "Skipping API call, reusing cached file: $FILE"
    fi
}

# Play the audio file
play_audio() {
    log "Playing $FILE with $PLAYER"
    log_to_file "AUDIO" "Attempting to play $FILE with $PLAYER"
    
    # If running under MCP, just ensure file exists and is valid
    if [[ -n "${MCP_CALLING:-}" ]] || [[ "$0" == *"mcp"* ]] || [[ "$(ps -p $PPID -o comm=)" == *"mcp"* ]]; then
        if [[ -e "$FILE" && -s "$FILE" ]]; then
            log_to_file "AUDIO" "Running under MCP - file exists and is non-empty"
            log_to_file "AUDIO" "MCP will handle playback separately"
            return 0
        else
            log_to_file "ERROR" "Audio file does not exist or is empty"
            error_exit "No valid audio file found" 6
        fi
    fi
    
    if [[ "$PLAYER" == "ffmpeg" ]]; then
        # Use ffplay from the ffmpeg suite
        if command_exists "ffplay"; then
            log_to_file "AUDIO" "Using ffplay for audio playback"
            ffplay -autoexit -nodisp -loglevel quiet "$FILE" </dev/null >/dev/null 2>&1
            local exit_code=$?
            if [[ $exit_code -ne 0 ]]; then
                log_to_file "ERROR" "Failed to play audio with ffplay, exit code: $exit_code"
                error_exit "Failed to play audio file with ffplay" 6
            else
                log_to_file "AUDIO" "Audio playback completed successfully with ffplay"
            fi
        else
            # Fallback to ffmpeg if ffplay is not available
            log "ffplay not found, using ffmpeg directly"
            log_to_file "AUDIO" "ffplay not found, falling back to ffmpeg with aplay"
            # This only works with audio going to the default output
            ffmpeg -hide_banner -loglevel quiet -i "$FILE" -f wav - | aplay -q 2>/dev/null
            local exit_code=$?
            if [[ $exit_code -ne 0 ]]; then
                log_to_file "ERROR" "Failed to play audio with ffmpeg/aplay, exit code: $exit_code"
                error_exit "Failed to play audio file with ffmpeg" 6
            else
                log_to_file "AUDIO" "Audio playback completed successfully with ffmpeg/aplay"
            fi
        fi
    elif [[ "$PLAYER" == "mplayer" ]]; then
        log_to_file "AUDIO" "Using mplayer for audio playback"
        mplayer -quiet -really-quiet "$FILE" </dev/null >/dev/null 2>&1
        local exit_code=$?
        if [[ $exit_code -ne 0 ]]; then
            log_to_file "ERROR" "Failed to play audio with mplayer, exit code: $exit_code"
            error_exit "Failed to play audio file with mplayer" 6
        else
            log_to_file "AUDIO" "Audio playback completed successfully with mplayer"
        fi
    else
        log_to_file "ERROR" "Unknown player: $PLAYER"
        error_exit "Unknown player: $PLAYER"
    fi
}

# Main function
main() {
    log_to_file "SYSTEM" "Starting speech.sh execution"
    check_dependencies
    parse_arguments "$@"
    get_api_key
    generate_filename
    generate_speech
    play_audio
    log_to_file "SYSTEM" "Speech.sh execution completed successfully"
}

# Execute main function with all arguments
main "$@"


#!/bin/zsh
# speech.sh - Text-to-speech utility using OpenAI's API
# Usage: ./speech.sh --text "Text to speak" [options]
# See --help for more information

# Exit on error, unset variable, and pipe failures
set -euo pipefail

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

# Function to handle errors
error_exit() {
    log_err "ERROR: $1"
    exit "${2:-1}"  # Default exit code is 1
}

# Log to stderr - always displayed regardless of verbose setting
log_err() {
    echo "$1" >&2
    if command -v notify-send >/dev/null 2>&1; then
        notify-send "speech.sh: $1"
    fi
}

# Log to stdout - only when verbose is enabled
log() {
    if [[ "$VERBOSE" != "F" ]]; then
        echo "$1"
        if command -v notify-send >/dev/null 2>&1; then
            notify-send "speech.sh: $1"
        fi
    fi
}

# Check if the command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if required commands exist
check_dependencies() {
    local missing=0
    
    # Check required dependencies
    for cmd in curl jq; do
        if ! command_exists "$cmd"; then
            log_err "Required command not found: $cmd"
            missing=1
        fi
    done
    
    # Check audio players based on configuration
    if [[ "$PLAYER" == "auto" ]]; then
        if command_exists "ffmpeg"; then
            log "ffmpeg found, using it for audio playback"
            PLAYER="ffmpeg"
        elif command_exists "mplayer"; then
            log "mplayer found, using it for audio playback"
            PLAYER="mplayer"
        else
            log_err "No audio player found. Please install ffmpeg or mplayer."
            missing=1
        fi
    elif [[ "$PLAYER" == "ffmpeg" ]]; then
        if ! command_exists "ffmpeg"; then
            log_err "ffmpeg was specified but not found"
            missing=1
        fi
    elif [[ "$PLAYER" == "mplayer" ]]; then
        if ! command_exists "mplayer"; then
            log_err "mplayer was specified but not found"
            missing=1
        fi
    else
        log_err "Invalid player specified: $PLAYER. Valid options are: auto, ffmpeg, mplayer"
        missing=1
    fi
    
    if [[ $missing -eq 1 ]]; then
        error_exit "Missing dependencies. Please install the required packages." 2
    fi

    # Check curl version for retry support
    if curl --version | grep -q "curl 7."; then
        local curl_version
        curl_version=$(curl --version | head -n 1 | cut -d ' ' -f 2)
        local curl_major
        local curl_minor
        curl_major=$(echo "$curl_version" | cut -d. -f1)
        curl_minor=$(echo "$curl_version" | cut -d. -f2)
        
        # If curl version < 7.52.0, warn about lack of retry support
        if [[ $curl_major -lt 7 || ($curl_major -eq 7 && $curl_minor -lt 52) ]]; then
            log_err "Warning: Your curl version ($curl_version) doesn't support native retries. Falling back to script-based retries."
        fi
    fi
}

# Process command line arguments
parse_arguments() {
    # Initialize TEXT as empty to check if it's provided
    TEXT=""
    
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
                shift 2
                ;;
            -t | --text)
                if [[ -z "${2:-}" ]]; then
                    error_exit "Missing value for parameter: $1"
                fi
                TEXT="$2"
                shift 2
                ;;
            -s | --speed)
                if [[ -z "${2:-}" ]]; then
                    error_exit "Missing value for parameter: $1"
                fi
                SPEED="$2"
                shift 2
                ;;
            -o | --output)
                if [[ -z "${2:-}" ]]; then
                    error_exit "Missing value for parameter: $1"
                fi
                FILE="$2"
                shift 2
                ;;
            -a | --api_key)
                if [[ -z "${2:-}" ]]; then
                    error_exit "Missing value for parameter: $1"
                fi
                API_KEY="$2"
                shift 2
                ;;
            -m | --model)
                if [[ -z "${2:-}" ]]; then
                    error_exit "Missing value for parameter: $1"
                fi
                MODEL="$2"
                shift 2
                ;;
            -p | --player)
                if [[ -z "${2:-}" ]]; then
                    error_exit "Missing value for parameter: $1"
                fi
                PLAYER="$2"
                shift 2
                ;;
            -r | --retries)
                if [[ -z "${2:-}" ]]; then
                    error_exit "Missing value for parameter: $1"
                fi
                MAX_RETRIES="$2"
                shift 2
                ;;
            -T | --timeout)
                if [[ -z "${2:-}" ]]; then
                    error_exit "Missing value for parameter: $1"
                fi
                TIMEOUT="$2"
                shift 2
                ;;
            -V | --verbose)
                VERBOSE="T"
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
        echo "Use -h or --help for usage information" >&2
        exit 0
    fi
    
    # Validate PLAYER value
    if [[ ! "$PLAYER" =~ ^(auto|ffmpeg|mplayer)$ ]]; then
        error_exit "Invalid player: $PLAYER. Valid values are: auto, ffmpeg, mplayer"
    fi
}

# Get API key from available sources
get_api_key() {
    if [[ "$API_KEY" == "NONE" ]]; then
        # First check for environment variable
        if [[ -n "${OPENAI_API_KEY:-}" ]]; then
            log "Using API key from OPENAI_API_KEY environment variable"
            API_KEY="$OPENAI_API_KEY"
        # Then check for API_KEY file
        elif [[ ! -e "API_KEY" ]]; then
            error_exit "No API key given as argument, no OPENAI_API_KEY environment variable, and no file called API_KEY"
        else
            log "Using API key from API_KEY file"
            # Use cat with quotes to handle potential whitespace issues
            API_KEY="$(cat "API_KEY")"
        fi
    fi
}

# Generate output filename if not provided
generate_filename() {
    if [[ "$FILE" == "AUTO" ]]; then
        local temp_dir
        temp_dir="$(dirname "$(mktemp -u)")"
        # Use more secure hash function if available
        if command_exists "sha256sum"; then
            FILE="${temp_dir}/OPENAI_SPEECH_$(echo -n "$TEXT $VOICE $SPEED" | sha256sum | cut -d" " -f1).mp3"
        else
            FILE="${temp_dir}/OPENAI_SPEECH_$(echo -n "$TEXT $VOICE $SPEED" | md5sum - | cut -d" " -f1).mp3"
        fi
        log "Auto-generated filename: $FILE"
    fi
}

# Make API call to generate speech with retry logic
generate_speech() {
    if [[ ! -e "$FILE" ]]; then
        log "API call for \"$TEXT\""
        
        # Create JSON payload once to avoid recreating it in each retry
        local json_payload
        json_payload=$(jq -n \
            --arg model "$MODEL" \
            --arg input "$TEXT" \
            --arg voice "$VOICE" \
            --arg speed "$SPEED" \
            '{model: $model, input: $input, voice: $voice, speed: $speed}')
        
        local retry_count=0
        local success=false
        local error_message=""
        
        # Try to get curl version to determine if it supports native retries
        local supports_native_retry=false
        if curl --version | grep -q "curl 7."; then
            local curl_version
            curl_version=$(curl --version | head -n 1 | cut -d ' ' -f 2)
            local curl_major
            local curl_minor
            curl_major=$(echo "$curl_version" | cut -d. -f1)
            curl_minor=$(echo "$curl_version" | cut -d. -f2)
            
            # Retry option was added in curl 7.52.0
            if [[ $curl_major -gt 7 || ($curl_major -eq 7 && $curl_minor -ge 52) ]]; then
                supports_native_retry=true
            fi
        fi
        
        if [[ "$supports_native_retry" == "true" ]]; then
            # Use curl's built-in retry mechanism for newer curl versions
            log "Using curl's native retry mechanism"
            local response
            response=$(curl --fail --silent --show-error \
                --retry "$MAX_RETRIES" \
                --retry-delay 1 \
                --retry-max-time $(( TIMEOUT * 2 )) \
                --max-time "$TIMEOUT" \
                --connect-timeout 10 \
                https://api.openai.com/v1/audio/speech \
                -H "Content-Type: application/json" \
                -H "Authorization: Bearer $API_KEY" \
                -d "$json_payload" \
                -o "$FILE" || echo "CURL_ERROR:$?")
            
            if [[ "$response" =~ ^CURL_ERROR:([0-9]+)$ ]]; then
                error_message="curl failed with exit code ${BASH_REMATCH[1]}"
                success=false
            else
                success=true
            fi
        else
            # Manual retry logic for older curl versions
            while [[ $retry_count -lt $MAX_RETRIES && "$success" == "false" ]]; do
                if [[ $retry_count -gt 0 ]]; then
                    log "Retry attempt $retry_count/$MAX_RETRIES..."
                    # Add exponential backoff
                    sleep $(( 2 ** (retry_count - 1) ))
                fi
                
                local response
                response=$(curl --fail --silent --show-error \
                    --max-time "$TIMEOUT" \
                    --connect-timeout 10 \
                    https://api.openai.com/v1/audio/speech \
                    -H "Content-Type: application/json" \
                    -H "Authorization: Bearer $API_KEY" \
                    -d "$json_payload" \
                    -o "$FILE" || echo "CURL_ERROR:$?")
                
                if [[ "$response" =~ ^CURL_ERROR:([0-9]+)$ ]]; then
                    error_message="curl failed with exit code ${BASH_REMATCH[1]}"
                    retry_count=$((retry_count + 1))
                else
                    success=true
                    break
                fi
            done
        fi
        
        if [[ "$success" == "false" ]]; then
            error_exit "API call failed after $retry_count attempts: $error_message" 3
        fi
            
        if [[ ! -e "$FILE" ]]; then
            error_exit "No file created, something went wrong." 4
        fi

        if [[ "$(file --brief "$FILE" 2>/dev/null)" == "JSON data" ]]; then
            local error_message
            error_message="$(jq -r '.error.message // "Unknown error"' < "$FILE")"
            rm -f "$FILE"
            error_exit "OpenAI API error: $error_message" 5
        fi
    else
        log "Skipping API call, using cached file"
    fi
}

# Play the audio file
play_audio() {
    log "Playing $FILE with $PLAYER"
    
    if [[ "$PLAYER" == "ffmpeg" ]]; then
        # Use ffplay from the ffmpeg suite
        if command_exists "ffplay"; then
            ffplay -autoexit -nodisp -loglevel quiet "$FILE" </dev/null >/dev/null 2>&1 || error_exit "Failed to play audio file with ffplay" 6
        else
            # Fallback to ffmpeg if ffplay is not available
            log "ffplay not found, using ffmpeg directly"
            # This only works with audio going to the default output
            ffmpeg -hide_banner -loglevel quiet -i "$FILE" -f wav - | aplay -q 2>/dev/null || error_exit "Failed to play audio file with ffmpeg" 6
        fi
    elif [[ "$PLAYER" == "mplayer" ]]; then
        mplayer -quiet -really-quiet "$FILE" </dev/null >/dev/null 2>&1 || error_exit "Failed to play audio file with mplayer" 6
    else
        error_exit "Unknown player: $PLAYER"
    fi
}

# Main function
main() {
    check_dependencies
    parse_arguments "$@"
    get_api_key
    generate_filename
    generate_speech
    play_audio
}

# Execute main function with all arguments
main "$@"


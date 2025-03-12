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

# Check if required commands exist
check_dependencies() {
    local missing=0
    for cmd in curl jq mplayer; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log_err "Required command not found: $cmd"
            missing=1
        fi
    done
    
    if [[ $missing -eq 1 ]]; then
        error_exit "Missing dependencies. Please install the required packages." 2
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
        if command -v sha256sum >/dev/null 2>&1; then
            FILE="${temp_dir}/OPENAI_SPEECH_$(echo -n "$TEXT $VOICE $SPEED" | sha256sum | cut -d" " -f1).mp3"
        else
            FILE="${temp_dir}/OPENAI_SPEECH_$(echo -n "$TEXT $VOICE $SPEED" | md5sum - | cut -d" " -f1).mp3"
        fi
        log "Auto-generated filename: $FILE"
    fi
}

# Make API call to generate speech
generate_speech() {
    if [[ ! -e "$FILE" ]]; then
        log "API call for \"$TEXT\""

        local response
        response=$(curl --fail --silent --show-error https://api.openai.com/v1/audio/speech \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $API_KEY" \
            -d "$(jq -n \
                --arg model "$MODEL" \
                --arg input "$TEXT" \
                --arg voice "$VOICE" \
                --arg speed "$SPEED" \
                '{model: $model, input: $input, voice: $voice, speed: $speed}')" \
            -o "$FILE" || echo "CURL_ERROR")

        if [[ "$response" == "CURL_ERROR" ]]; then
            error_exit "API call failed" 3
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
    log "Playing $FILE"
    mplayer -quiet -really-quiet "$FILE" || error_exit "Failed to play audio file" 6
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


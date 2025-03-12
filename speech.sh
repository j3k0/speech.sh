#!/bin/zsh


SPEED="1.0"
VOICE="onyx"
API_KEY="NONE"
FILE="AUTO"
VERBOSE="F"

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
      --verbose       Enable verbose logging
  -V, --verbose       Same as --verbose

The API key can be provided in three ways (in order of precedence):
1. Command-line argument (-a, --api_key)
2. OPENAI_API_KEY environment variable
3. A file named 'API_KEY' in the script's directory
EOF
    exit 0
}

# echo and send a notification
log() {
    echo $1
    if [[ "$(command -v notify-send)" ]]
    then
        notify-send "Quick_speech.sh: $1"
    fi
}
log2() {
    if [[ "$VERBOSE" != "F" ]]
    then
        log $1
    fi
}

while (( $# > 0 )); do
    case "$1" in
        -h | --help)
            show_help
            ;;
        -v | --voice)
            VOICE="$2"
            shift 2
            ;;
        -t | --text)
            TEXT="$2"
            shift 2
            ;;
        -s | --speed)
            SPEED="$2"
            shift 2
            ;;
        -o | --output)
            FILE="$2"
            shift 2
            ;;
        -a | --api_key)
            API_KEY="$2"
            shift 2
            ;;
        -V | --verbose)
            VERBOSE="T"
            shift 1
            ;;
        *)
            echo "Invalid option(s): $@"
            echo "Use -h or --help for usage information"
            exit 1
            ;;

    esac
done

if [ -z "$TEXT" ]
then
    log "No text to voice"
    echo "Use -h or --help for usage information"
    exit 0
fi

if [[ "$API_KEY" == "NONE" ]]
then
    # First check for environment variable
    if [[ ! -z "$OPENAI_API_KEY" ]]
    then
        log2 "Using API key from OPENAI_API_KEY environment variable"
        API_KEY="$OPENAI_API_KEY"
    # Then check for API_KEY file
    elif [[ ! -e "API_KEY" ]]
    then
        log "No API key given as argument, no OPENAI_API_KEY environment variable, and no file called API_KEY"
        exit 1
    else
        log2 "Using API key from API_KEY file"
        API_KEY=$(cat "API_KEY")
    fi
fi

if [[ "$FILE" == "AUTO" ]]
then
    FILE="$(dirname $(mktemp))/OPENAI_SPEECH_$(echo -n "$TEXT $VOICE $SPEED" | md5sum - | cut -d" " -f1).mp3"
fi

if [[ ! -e "$FILE" ]]
then
    log "API call for \"$TEXT\""

    curl https://api.openai.com/v1/audio/speech \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $API_KEY" \
    -d "$(jq -n --arg model "tts-1" --arg input "$TEXT" --arg voice "$VOICE" --arg speed "$SPEED" '{model: $model, input: $input, voice: $voice, speed: $speed}')" \
    -o "$FILE"

    if [[ ! -e "$FILE" ]]
    then
        log "No file created, something went wrong."
        exit 1
    fi

    if [[ "$(file --brief $FILE)" == "JSON data" ]]
    then
        mess1="JSON data output, something went wrong"
        mess2="$(cat $FILE | jq '.error | .message')"
        log "$mess1\n$mess2"
        rm $FILE
        exit 1
    fi

else
    log "Skipping API call"

fi

log2 "Playing $FILE"
mplayer -quiet -really-quiet "$FILE"


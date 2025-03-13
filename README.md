# Speech.sh

A powerful command-line utility for text-to-speech conversion using OpenAI's API.

## Features

- Convert text to speech with a simple command
- Multiple voice options (onyx, alloy, echo, fable, nova, shimmer)
- Adjustable speech speed (0.25 to 4.0)
- Support for both tts-1 and tts-1-hd models
- Flexible API key management (command-line, environment variable, or file)
- Automatic caching to avoid duplicate API calls
- Robust retry mechanism for handling network issues
- Support for both ffmpeg and mplayer for audio playback
- MCP (Model Context Protocol) compatibility for integration with AI assistants

## Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/j3k0/speech.sh.git
   cd speech.sh
   ```

2. Make the scripts executable:
   ```bash
   chmod +x speech.sh mcp.sh launch
   ```

3. Ensure you have the required dependencies:
   - curl
   - jq
   - Either ffmpeg or mplayer (ffmpeg preferred)

## Usage

Basic usage:

```bash
./speech.sh --text "Hello, world!"
```

With more options:

```bash
./speech.sh --text "Hello, world!" --voice nova --speed 1.2 --model tts-1-hd
```

### Options

```
-h, --help          Show help message and exit
-t, --text TEXT     Text to convert to speech (required)
-v, --voice VOICE   Voice model to use (default: onyx)
-s, --speed SPEED   Speech speed (default: 1.0)
-o, --output FILE   Output file path (default: auto-generated)
-a, --api_key KEY   OpenAI API key
-m, --model MODEL   TTS model to use (default: tts-1)
-p, --player PLAYER Audio player to use: auto, ffmpeg, or mplayer (default: auto)
    --verbose       Enable verbose logging
-V, --verbose       Same as --verbose
-r, --retries N     Number of retry attempts for API calls (default: 3)
-T, --timeout N     Timeout in seconds for API calls (default: 30)
```

### API Key Configuration

The script accepts an OpenAI API key in three ways (in order of precedence):
1. Command-line argument: `--api_key "your-api-key"`
2. Environment variable: `export OPENAI_API_KEY="your-api-key"`
3. A file named `API_KEY` in the script's directory

## Advanced Features

### Auto-caching

The script caches audio files by default to avoid unnecessary API calls. 
If you request the same text with the same voice and speed, it will reuse 
the previously generated audio file.

### Retry Logic

The script includes sophisticated retry logic for API calls:
- Automatically retries failed API calls (default: 3 attempts)
- Implements exponential backoff for reliability
- Uses native curl retry mechanism when available
- Configurable timeout and retry values

### Audio Player Options

You can choose your preferred audio player:
- `--player auto`: Use ffmpeg if available, fall back to mplayer (default)
- `--player ffmpeg`: Force using ffmpeg
- `--player mplayer`: Force using mplayer

## MCP Integration

The `mcp.sh` script provides Model Context Protocol compatibility, allowing the 
text-to-speech functionality to be used by MCP-compatible AI assistants like Claude.

To use the MCP server:

```bash
# Start the MCP server using the launch script
./launch
```

For detailed instructions on using the MCP integration, see [MCP_README.md](MCP_README.md).

## Security Considerations

The script takes several steps to ensure security:
- Uses proper JSON handling with `jq` for parameter processing
- Implements proper array-based parameter passing to prevent shell injection
- Validates needed dependencies before execution
- Uses error handling throughout the execution process

## Examples

Convert text to speech with default settings:
```bash
./speech.sh --text "Hello, world!"
```

Use a different voice:
```bash
./speech.sh --text "Hello, world!" --voice nova
```

Adjust the speech speed:
```bash
./speech.sh --text "Hello, world!" --speed 1.5
```

Save to a specific file:
```bash
./speech.sh --text "Hello, world!" --output hello.mp3
```

Use environment variable for API key:
```bash
export OPENAI_API_KEY="your-api-key"
./speech.sh --text "Hello, world!"
```

## Troubleshooting

If you encounter issues:

1. Enable verbose logging with the `--verbose` flag
2. Check that your OpenAI API key is valid
3. Verify that all dependencies are installed
4. Ensure you have internet connectivity
5. Check the permissions of the output directory

## Contributors

- Jean-Christophe Hoelt
- Claude AI (Anthropic)

## License

GPL

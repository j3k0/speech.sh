# Speech.sh

A text-to-speech CLI and MCP server using the Groq TTS API (OpenAI-compatible).

## Features

- Convert text to speech with a simple command
- Multiple voice options (troy, austin, hannah, autumn)
- Adjustable speech speed
- Hash-based caching to avoid duplicate API calls (24h auto-cleanup)
- Retry with exponential backoff
- Audio playback via ffplay, mplayer, or VLC
- MCP server for integration with AI assistants (Claude Desktop, Claude Code)

## Hosted deployment

A hosted deployment is available on [Fronteir AI](https://fronteir.ai/mcp/j3k0-speech-sh).

## Quick Start

```bash
git clone https://github.com/j3k0/speech.sh.git
cd speech.sh
export OPENAI_API_KEY="your-groq-api-key"
./speech.sh --text "Hello, world!"
```

### Dependencies

- `curl`, `jq` (for the shell version)
- One audio player: `ffplay` (from ffmpeg), `mplayer`, or `vlc`

## CLI Usage

```bash
# Basic
./speech.sh --text "Hello, world!"

# With options
./speech.sh --text "Hello!" --voice austin --speed 1.2 --verbose
```

### Options

```
-t, --text TEXT       Text to convert to speech (required)
-v, --voice VOICE     Voice to use (default: troy)
-s, --speed SPEED     Speech speed (default: 1.0)
-o, --output FILE     Output file path (default: auto-generated)
-a, --api_key KEY     API key
-m, --model MODEL     TTS model (default: canopylabs/orpheus-v1-english)
-p, --player PLAYER   Audio player: auto, ffmpeg, mplayer, vlc (default: auto)
-r, --retries N       Retry attempts (default: 3)
-T, --timeout N       Timeout in seconds (default: 30)
    --verbose         Enable verbose logging
```

### API Key

Provide your Groq API key in one of three ways (in order of precedence):
1. `--api_key "your-key"`
2. `export OPENAI_API_KEY="your-key"`
3. A file named `API_KEY` in the script's directory

## MCP Server

Two implementations are available:

### Python (recommended)

Uses the [FastMCP](https://github.com/modelcontextprotocol/python-sdk) SDK. Requires Python 3.10+ and `uv`.

```bash
# Setup
uv venv --python python3 .venv
uv pip install --python .venv/bin/python "mcp[cli]" httpx

# Run
OPENAI_API_KEY="your-key" .venv/bin/python server.py
```

#### Claude Desktop / Claude Code configuration

```json
{
  "mcpServers": {
    "speak": {
      "command": "/path/to/speech.sh/.venv/bin/python",
      "args": ["/path/to/speech.sh/server.py"],
      "env": {
        "OPENAI_API_KEY": "your-groq-api-key",
        "SPEECH_VOICE": "troy",
        "SPEECH_SPEED": "1.0",
        "SPEECH_MODEL": "canopylabs/orpheus-v1-english"
      }
    }
  }
}
```

### Shell (legacy)

The original shell-based MCP server (`mcp.sh`). Works in environments without Python but may hit macOS sandboxing issues with Claude Desktop.

```bash
./mcp.sh
```

### MCP Tool

The server exposes a single `speak` tool:

| Parameter | Type   | Required | Default | Description              |
|-----------|--------|----------|---------|--------------------------|
| text      | string | yes      |         | The text to speak        |
| voice     | string | no       | troy    | Voice to use             |
| speed     | number | no       | 1.0     | Speech speed             |

### Environment Variables

| Variable         | Description            | Default                          |
|------------------|------------------------|----------------------------------|
| OPENAI_API_KEY   | Groq API key           | (required)                       |
| SPEECH_VOICE     | Default voice          | troy                             |
| SPEECH_SPEED     | Default speed          | 1.0                              |
| SPEECH_MODEL     | TTS model              | canopylabs/orpheus-v1-english    |
| SPEECH_API_URL   | API endpoint (Python)  | https://api.groq.com/openai/v1/audio/speech |

## Architecture

- **speech.sh** - Shell-based TTS engine (API calls, caching, playback)
- **mcp.sh** - Shell-based MCP wrapper over speech.sh (JSON-RPC 2.0 over stdio)
- **server.py** - Python MCP server, self-contained replacement for both scripts above

## License

GPL

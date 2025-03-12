# Speech.sh MCP Integration

This document explains how to use `speech.sh` with the Model Context Protocol (MCP).

## What is MCP?

The Model Context Protocol (MCP) is an open protocol that enables seamless integration between LLM applications (like Claude) and external tools. It allows AI models to access external functionality in a standardized way.

## How to Use

The `mcp.sh` script in this repository provides MCP compatibility for the text-to-speech functionality of `speech.sh`. It implements the `stdio` transport layer of MCP, which allows communication through standard input and output streams.

### Configuration in Claude Desktop

To use this MCP server with Claude Desktop, add the following to your configuration:

```json
{
  "mcpServers": {
    "speech": {
      "command": "/path/to/speech.sh/mcp.sh",
      "env": {
        "OPENAI_API_KEY": "your-openai-api-key"
      }
    }
  }
}
```

Replace `/path/to/speech.sh/mcp.sh` with the actual path to the script on your system and `your-openai-api-key` with your OpenAI API key.

### Available Methods

The MCP server exposes the following methods:

#### speak

Converts text to speech using OpenAI's TTS API.

Parameters:
- `text` (string, required): The text to convert to speech
- `voice` (string, optional): Voice model to use (default: "onyx")
  - Options: "alloy", "echo", "fable", "onyx", "nova", "shimmer"
- `speed` (number, optional): Speech speed (default: 1.0)
- `model` (string, optional): TTS model to use (default: "tts-1")
  - Options: "tts-1", "tts-1-hd"

Example request:
```json
{
  "jsonrpc": "2.0",
  "method": "speak",
  "params": {
    "text": "Hello, world!",
    "voice": "nova",
    "speed": 1.2
  },
  "id": 1
}
```

Response:
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "status": "success",
    "message": "Speech generated",
    "file_path": "/tmp/tmpfile123.mp3"
  }
}
```

## Testing

You can test the MCP server manually by starting it and sending JSON-RPC requests via stdin:

```bash
./mcp.sh
```

Then input a JSON-RPC request:
```json
{"jsonrpc":"2.0","method":"server.capabilities","id":1}
```

You should receive a response with the server's capabilities.

## Troubleshooting

- Make sure both `speech.sh` and `mcp.sh` are executable (`chmod +x speech.sh mcp.sh`)
- Verify that you have all the required dependencies for `speech.sh` (curl, jq, and either ffmpeg or mplayer)
- Check that your OpenAI API key is valid and has access to the TTS API 
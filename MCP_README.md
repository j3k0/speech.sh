# Speech MCP Server

This MCP (Model Context Protocol) server provides text-to-speech capabilities through OpenAI's API. It allows client applications to convert text into spoken audio.

## Installation

1. Ensure you have the following dependencies installed:
   - `zsh` shell
   - `jq` for JSON parsing
   - `speech.sh` (included in the same directory)

2. Make sure both scripts are executable:
   ```bash
   chmod +x mcp.sh speech.sh
   ```

3. Set up your OpenAI API key (required for the TTS service):
   ```bash
   export OPENAI_API_KEY="your-api-key-here"
   ```

## Configuration

The speech server can be configured using the following environment variables:

| Environment Variable | Description | Default Value | Allowed Values |
|---------------------|-------------|---------------|----------------|
| OPENAI_API_KEY      | OpenAI API key for authentication | (required) | Valid OpenAI API key |
| SPEECH_VOICE        | Voice to use for the speech | "onyx" | "alloy", "echo", "fable", "onyx", "nova", "shimmer" |
| SPEECH_SPEED        | Speed of the speech | 1.0 | 0.25 to 4.0 |
| SPEECH_MODEL        | TTS model to use | "tts-1" | "tts-1", "tts-1-hd" |

Example configuration:
```bash
export SPEECH_VOICE="nova"
export SPEECH_SPEED="1.2"
export SPEECH_MODEL="tts-1-hd"
```

## API Methods

### speak

Converts text to speech and returns the path to the generated audio file.

**Parameters:**
- `text` (string, required): The text to convert to speech

**Example Request:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "speak",
  "params": {
    "text": "Hello, I'm using the speech MCP server!"
  }
}
```

**Example Response:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "status": "success",
    "message": "Speech generated",
    "file_path": "/tmp/tmp.XXXXXXXXXX"
  }
}
```

## Usage Examples

### From a terminal

```bash
# Start the MCP server
./mcp.sh

# In another terminal, use it with a JSON-RPC request
echo '{"jsonrpc":"2.0","id":1,"method":"speak","params":{"text":"Hello world"}}' | ./mcp.sh
```

### From a client application

```python
import json
import subprocess

def speak(text):
    request = {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "speak",
        "params": {
            "text": text
        }
    }
    
    process = subprocess.Popen(
        ["./mcp.sh"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True
    )
    
    stdout, stderr = process.communicate(json.dumps(request))
    
    if process.returncode == 0:
        response = json.loads(stdout)
        if "result" in response:
            return response["result"]
    
    return None

# Example usage
result = speak("Hello, this is a test of the speech MCP server")
print(f"Speech file created at: {result['file_path']}")
```

## Notes

- The speech audio is saved to a temporary file. You are responsible for managing these files (playing and/or deleting them).
- The server does not stream the audio directly - it returns the file path for you to handle.
- The default configuration uses the "onyx" voice at normal speed with the standard TTS model, which is suitable for most purposes. 
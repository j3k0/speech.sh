# Speech MCP Server

This MCP (Model Context Protocol) server provides text-to-speech capabilities through OpenAI's API. It allows AI assistants and other applications to convert text into spoken audio.

## Installation

1. Ensure you have the following dependencies installed:
   - `zsh` shell
   - `jq` for JSON parsing
   - `curl` for API communication
   - `ffmpeg` or `mplayer` for audio playback (ffmpeg preferred)
   - `speech.sh` (included in the same directory)

2. Make sure all scripts are executable:
   ```bash
   chmod +x mcp.sh speech.sh launch
   ```

3. Set up your OpenAI API key (required for the TTS service):
   ```bash
   export OPENAI_API_KEY="your-api-key-here"
   ```

## Starting the Server

The simplest way to start the MCP server is by using the included launch script:

```bash
./launch
```

Or you can run the MCP script directly:

```bash
./mcp.sh
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

## MCP Tools API

### speak

Converts text to speech and plays it through your device's speakers.

**Parameters:**
- `text` (string, required): The text to convert to speech

**Example Request:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "speak",
    "arguments": {
      "text": "Hello, I'm using the speech MCP server!"
    }
  }
}
```

**Example Response:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "content": [
      {
        "type": "text",
        "text": "Done"
      }
    ],
    "isError": false
  }
}
```

## Security Considerations

The MCP server implements several security measures:
- Uses proper JSON handling with `jq` to avoid injection vulnerabilities
- Implements parameter passing using arrays rather than string concatenation
- Validates required parameters before processing
- Runs the speech generation in a background process to avoid blocking the server

## Logging and Troubleshooting

The server includes a comprehensive logging system to help diagnose issues:

- The MCP server logs to `logs.txt` in the script directory
- The speech.sh script logs to `speech_logs.txt` in the same directory
- Individual speech request outputs are captured in `speech_[request_id].log` files
- All logs include timestamps and component identifiers for easy tracking
- Log files are automatically rotated when they exceed 1MB in size

This dual-layer logging system provides detailed information about:
- MCP server interactions and requests
- Speech generation process and parameters
- API calls to OpenAI with success/failure status
- Audio playback attempts and outcomes

If audio is not playing correctly:
1. Check the main `logs.txt` file for errors in the MCP layer
2. Check `speech_logs.txt` for errors in the speech generation process
3. Look for the specific request ID in the logs 
4. Examine the corresponding `speech_[request_id].log` file for detailed output
5. Verify that your audio system is working correctly

Common issues:
- API key problems: Check if there are authentication errors in the logs
- Audio device issues: Ensure your system's audio is properly configured
- Network problems: Look for timeout errors or connection issues
- Multiple simultaneous requests: Be aware that if multiple speech requests are made at once, they will all play potentially overlapping each other

## Usage Examples

### From a terminal

```bash
# Start the MCP server
./mcp.sh

# In another terminal, use it with a JSON-RPC request
echo '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"speak","arguments":{"text":"Hello world"}}}' | nc localhost 8123
```

### From a client application

```python
import json
import subprocess

def speak(text):
    request = {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "tools/call",
        "params": {
            "name": "speak",
            "arguments": {
                "text": text
            }
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
        return response
    
    return None

# Example usage
result = speak("Hello, this is a test of the speech MCP server")
print(result)
```

## Notes

- The speech is played immediately through your system's speakers
- The server handles the API communication, caching, and audio playback
- Default configuration uses the "onyx" voice at normal speed with the standard TTS model
- The speech generation runs in the background, so the API response returns immediately
- For AI assistants like Claude, this integration allows them to speak to users directly 
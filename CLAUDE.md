# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

speech.sh is a text-to-speech CLI utility and MCP server written in zsh. It calls the OpenAI TTS API (`/v1/audio/speech`) to convert text to speech, caches results locally, and plays audio.

## Running

```bash
# Direct CLI usage
./speech.sh --text "Hello" --voice nova --speed 1.2 --verbose

# MCP server mode (JSON-RPC 2.0 over stdio)
./mcp.sh
```

There are no build steps, tests, or linters. The scripts are run directly.

## Architecture

Two main scripts with a clear separation:

- **speech.sh** — Core TTS engine. Handles argument parsing, API key resolution (CLI arg → `OPENAI_API_KEY` env → `API_KEY` file), hash-based caching in `temp_audio/`, OpenAI API calls with retry/backoff, and audio playback via ffmpeg/mplayer/vlc.

- **mcp.sh** — MCP protocol wrapper. Implements JSON-RPC 2.0 over stdio (`initialize`, `tools/list`, `tools/call`, `shutdown`). Exposes a single `speak` tool. Spawns `speech.sh` as a background process for non-blocking responses. Reads defaults from env vars: `SPEECH_VOICE`, `SPEECH_SPEED`, `SPEECH_MODEL`, `OPENAI_API_KEY`.

- **launch** — Quick-start script that sets env vars and runs `mcp.sh`. Gitignored because it contains an API key.

## Key Design Patterns

- Both scripts use `set -euo pipefail` for strict error handling
- Three-layer logging: MCP logs (`logs.txt`), speech logs (`speech_logs.txt`), per-request logs (`logs/speech_req_*.log`), all with 1MB auto-rotation
- Audio file caching uses SHA256/MD5 hashing of text+voice+speed+model for dedup, with 24-hour auto-cleanup
- API calls use curl with configurable retries (default 3) and exponential backoff
- JSON handling always uses `jq` (no string manipulation)
- MCP responses must be single-line JSON on stdout

## Dependencies

Requires: `curl`, `jq`, and one audio player (`ffmpeg`, `mplayer`, or `vlc`)

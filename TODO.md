# Completed Items
- [x] OPENAI_API_KEY from environment variable
- [x] Add --help and --verbose (-h and -v)
- [x] Use best practices for shell scripting
- [x] If --verbose isn't set, the script should output no text at all (or only on stderr)
- [x] Evaluate and improve external tool usage (curl with retry logic)
- [x] Evaluate use of ffmpeg instead of mplayer
- [x] Evaluate option to make it MCP compatible (add an mcp.sh script, using mcp in stdio mode)
- [x] Create launch script for easier MCP server startup
- [x] Add comprehensive logging to diagnose issues when audio doesn't play
- [x] Add detailed logging to speech.sh with separate log file

# Future Enhancements
- [ ] Add input validation for text parameter (length limits, prohibited characters)
- [ ] Add validation for voice, speed, and model parameters
- [ ] Improve process isolation for background processes
- [ ] Add support for additional TTS engines or providers
- [ ] Add support for streaming audio output
- [ ] Create installation script for easier deployment
- [ ] Add unit tests for critical functionality
- [ ] Implement sequential speech processing to prevent overlapping audio
- [ ] Add a proper speech queue with FIFO ordering
- [ ] Implement timeout for individual speech requests
- [ ] Add option to cancel pending speech requests
- [ ] Add queue status reporting (position in queue, estimated wait time)
- [ ] Implement priority levels for speech requests
- [ ] Add web interface for monitoring speech server status
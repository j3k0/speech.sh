# Completed Items
- [x] OPENAI_API_KEY from environment variable
- [x] Add --help and --verbose (-h and -v)
- [x] Use best practices for shell scripting
- [x] If --verbose isn't set, the script should output no text at all (or only on stderr)
- [x] Evaluate and improve external tool usage (curl with retry logic)
- [x] Evaluate use of ffmpeg instead of mplayer
- [x] Evaluate option to make it MCP compatible (add an mcp.sh script, using mcp in stdio mode)
- [x] Create launch script for easier MCP server startup

# Future Enhancements
- [ ] Add input validation for text parameter (length limits, prohibited characters)
- [ ] Add validation for voice, speed, and model parameters
- [ ] Add option to log speech.sh errors to a file instead of discarding them
- [ ] Improve process isolation for background processes
- [ ] Add support for additional TTS engines or providers
- [ ] Add support for streaming audio output
- [ ] Create installation script for easier deployment
- [ ] Add unit tests for critical functionality
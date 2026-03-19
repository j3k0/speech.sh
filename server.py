# /// script
# requires-python = ">=3.10"
# dependencies = ["mcp[cli]", "httpx"]
# ///
"""Speech MCP server — TTS via Groq (OpenAI-compatible) API with caching and playback."""

import hashlib
import logging
import os
import subprocess
import time
from pathlib import Path

import httpx
from mcp.server.fastmcp import FastMCP

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SCRIPT_DIR = Path(__file__).resolve().parent
TEMP_DIR = SCRIPT_DIR / "temp_audio"
TEMP_DIR.mkdir(exist_ok=True)

API_BASE_URL = os.environ.get(
    "SPEECH_API_URL", "https://api.groq.com/openai/v1/audio/speech"
)
DEFAULT_VOICE = os.environ.get("SPEECH_VOICE", "troy")
DEFAULT_SPEED = float(os.environ.get("SPEECH_SPEED", "1.0"))
DEFAULT_MODEL = os.environ.get("SPEECH_MODEL", "canopylabs/orpheus-v1-english")
API_KEY = os.environ.get("OPENAI_API_KEY", "")
MAX_RETRIES = int(os.environ.get("SPEECH_MAX_RETRIES", "3"))
TIMEOUT = int(os.environ.get("SPEECH_TIMEOUT", "30"))
CACHE_MAX_AGE = 24 * 3600  # seconds

log = logging.getLogger("speech")
logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(name)s] %(message)s")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _cleanup_old_files() -> int:
    """Remove cached audio files older than CACHE_MAX_AGE. Returns count removed."""
    count = 0
    cutoff = time.time() - CACHE_MAX_AGE
    for f in TEMP_DIR.glob("speech_*.wav"):
        if f.stat().st_mtime < cutoff:
            f.unlink(missing_ok=True)
            count += 1
    if count:
        log.info("Cleaned up %d old audio files", count)
    return count


def _cache_path(text: str, voice: str, speed: float, model: str) -> Path:
    """Return a deterministic cache path based on input parameters."""
    key = f"{text} {voice} {speed} {model}"
    h = hashlib.sha256(key.encode()).hexdigest()[:12]
    return TEMP_DIR / f"speech_{h}.wav"


def _generate_speech(text: str, voice: str, speed: float, model: str) -> Path:
    """Call the TTS API (with retries) and return path to the audio file."""
    path = _cache_path(text, voice, speed, model)
    if path.exists():
        log.info("Cache hit: %s", path.name)
        return path

    payload = {
        "model": model,
        "input": text,
        "voice": voice,
        "speed": speed,
        "response_format": "wav",
    }
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {API_KEY}",
    }

    last_error = None
    for attempt in range(MAX_RETRIES + 1):
        if attempt > 0:
            wait = min(2 ** attempt, 8)
            log.info("Retry %d/%d in %ds…", attempt, MAX_RETRIES, wait)
            time.sleep(wait)
        try:
            log.info("API request attempt %d for: %s", attempt, text[:60])
            with httpx.Client(timeout=TIMEOUT) as client:
                resp = client.post(API_BASE_URL, json=payload, headers=headers)

            if resp.headers.get("content-type", "").startswith("application/json"):
                error_msg = resp.json().get("error", {}).get("message", resp.text)
                raise RuntimeError(f"API error: {error_msg}")

            resp.raise_for_status()
            path.write_bytes(resp.content)
            log.info("Audio saved: %s (%d bytes)", path.name, len(resp.content))
            return path

        except Exception as exc:
            last_error = exc
            log.warning("Attempt %d failed: %s", attempt, exc)

    raise RuntimeError(f"API call failed after {MAX_RETRIES + 1} attempts: {last_error}")


def _find_player() -> str:
    """Find an available audio player."""
    for player in ("ffplay", "mplayer", "vlc"):
        if subprocess.run(["which", player], capture_output=True).returncode == 0:
            return player
    raise RuntimeError("No audio player found (tried ffplay, mplayer, vlc)")


def _play_audio(path: Path) -> None:
    """Play an audio file using the best available player."""
    player = _find_player()
    log.info("Playing %s with %s", path.name, player)

    if player == "ffplay":
        subprocess.run(
            ["ffplay", "-autoexit", "-nodisp", "-loglevel", "quiet", str(path)],
            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
    elif player == "mplayer":
        subprocess.run(
            ["mplayer", "-quiet", "-really-quiet", str(path)],
            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
    elif player == "vlc":
        subprocess.run(["open", str(path), "-a", "/Applications/VLC.app"])


# ---------------------------------------------------------------------------
# MCP Server
# ---------------------------------------------------------------------------

mcp = FastMCP("speak")


@mcp.tool()
def speak(text: str, voice: str = DEFAULT_VOICE, speed: float = DEFAULT_SPEED) -> str:
    """Say something out loud. Use it to attract the user's attention when you're done with a task, need help, or just want to say something."""
    _cleanup_old_files()
    path = _generate_speech(text, voice, speed, DEFAULT_MODEL)
    _play_audio(path)
    return "Done"


if __name__ == "__main__":
    mcp.run()

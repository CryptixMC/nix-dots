"""Every host-specific location the engine touches, resolved in one place.

Precedence for each: the environment variable, then the matching key in
~/.config/qubi/config.json (where one exists), then a default that works on
a machine with nothing but goose and Ollama installed. Nothing in this
package may hardcode a user name, a home directory or a repo checkout.
"""
import os

RUNTIME_DIR = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
CONFIG_HOME = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
DATA_HOME = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")

CONFIG_PATH = os.environ.get("QUBI_CONFIG") or os.path.join(CONFIG_HOME, "qubi", "config.json")
TIERCONF_DIR = os.path.join(RUNTIME_DIR, "qubi", "tierconf")
BASE_GOOSE_CONFIG = os.environ.get("QUBI_GOOSE_CONFIG") or os.path.join(CONFIG_HOME, "goose", "config.yaml")
GOOSE_SESSIONS_DB = os.environ.get("QUBI_GOOSE_SESSIONS_DB") or os.path.join(DATA_HOME, "goose", "sessions", "sessions.db")

DEFAULT_SOCKET_PATH = "$XDG_RUNTIME_DIR/qubi/engine.sock"
DEFAULT_OLLAMA_URL = "http://127.0.0.1:11434"
# Optional. A JSON file `{"state": "docked" | "undocked" | "gaming"}` written
# by whatever manages the machine's GPU; see docs/hw-state.md. Absent file
# means "docked", i.e. a GPU is available.
DEFAULT_HW_STATE_FILE = "/run/qubi/hw-state.json"


def _expand(p):
    return os.path.expanduser(os.path.expandvars(p.replace("$XDG_RUNTIME_DIR", RUNTIME_DIR)))


def _engine(cfg):
    return (cfg or {}).get("engine") or {}


def socket_path(cfg=None):
    return _expand(os.environ.get("QUBI_SOCKET") or _engine(cfg).get("socket_path") or DEFAULT_SOCKET_PATH)


def default_cwd(cfg=None):
    """Working directory new goose sessions are created in."""
    return _expand(os.environ.get("QUBI_DEFAULT_CWD") or _engine(cfg).get("default_cwd") or "~")


def themes_dir(cfg=None):
    """Directory of `<name>/base16.yaml` (+ optional theme.json) themes that
    `qubi/theme` serves to clients with no filesystem access."""
    return _expand(os.environ.get("QUBI_THEMES_DIR") or _engine(cfg).get("themes_dir")
                   or os.path.join(CONFIG_HOME, "qubi", "themes"))


def ollama_url(cfg=None):
    return (os.environ.get("QUBI_OLLAMA_URL") or _engine(cfg).get("ollama_url") or DEFAULT_OLLAMA_URL).rstrip("/")


def hw_state_file(cfg=None):
    return _expand(os.environ.get("QUBI_HW_STATE_FILE") or _engine(cfg).get("hw_state_file") or DEFAULT_HW_STATE_FILE)


def ws_bind(cfg=None):
    """(enabled, host, port) for the websocket transport."""
    e = _engine(cfg)
    enabled = os.environ.get("QUBI_WS_ENABLE", str(e.get("ws_enable", True))).lower() not in ("0", "false", "no")
    host = os.environ.get("QUBI_WS_HOST") or e.get("ws_host") or "127.0.0.1"
    port = int(os.environ.get("QUBI_WS_PORT") or e.get("ws_port") or 8765)
    return enabled, host, port

# Qubi

A local-first AI assistant: one persistent engine that routes each turn to
the right model tier in front of [goose](https://github.com/block/goose),
with a Quickshell desktop frontend and a mobile PWA speaking the same
protocol.

This tree is being extracted from a personal dotfiles repo. Layout:

| Path      | What                                                            |
|-----------|-----------------------------------------------------------------|
| `python/` | The `qubi` package: engine, config/bench/models CLIs, MCP servers |
| `nix/`    | Nix package (and, later, the home-manager module)               |

## Running from a checkout

```sh
pip install -e '.[dev]'      # or: nix build -f nix/package.nix
qubi-config init             # writes ~/.config/qubi/config.json if missing
qubi-engine
```

Requires `goose` and `sqlite3` on `PATH` and an Ollama server.

## Host-specific settings

Nothing is hardcoded to a user or checkout. Each of these resolves from the
environment variable, then the `engine.*` key in `config.json`, then the
default (see `python/src/qubi/paths.py`):

| Env                   | Config key             | Default                              |
|-----------------------|------------------------|--------------------------------------|
| `QUBI_CONFIG`         | –                      | `~/.config/qubi/config.json`         |
| `QUBI_SOCKET`         | `engine.socket_path`   | `$XDG_RUNTIME_DIR/qubi/engine.sock`  |
| `QUBI_DEFAULT_CWD`    | `engine.default_cwd`   | `~`                                  |
| `QUBI_THEMES_DIR`     | `engine.themes_dir`    | `~/.config/qubi/themes`              |
| `QUBI_OLLAMA_URL`     | `engine.ollama_url`    | `http://127.0.0.1:11434`             |
| `QUBI_HW_STATE_FILE`  | `engine.hw_state_file` | `/run/qubi/hw-state.json` (optional) |
| `QUBI_SHELL_PATH`     | –                      | default Quickshell config            |

## Tests

```sh
pytest && ruff check .
```

import importlib


def _paths(monkeypatch, **env):
    for k in ("QUBI_SOCKET", "QUBI_DEFAULT_CWD", "QUBI_THEMES_DIR", "QUBI_OLLAMA_URL", "QUBI_HW_STATE_FILE"):
        monkeypatch.delenv(k, raising=False)
    monkeypatch.setenv("XDG_RUNTIME_DIR", "/run/user/4242")
    for k, v in env.items():
        monkeypatch.setenv(k, v)
    import qubi.paths
    return importlib.reload(qubi.paths)


def test_defaults_name_no_user_or_checkout(monkeypatch):
    p = _paths(monkeypatch)
    assert p.socket_path() == "/run/user/4242/qubi/engine.sock"
    assert p.ollama_url() == "http://127.0.0.1:11434"
    assert p.hw_state_file() == "/run/qubi/hw-state.json"
    for value in (p.socket_path(), p.themes_dir(), p.hw_state_file()):
        assert "nix-dots" not in value


def test_config_socket_path_expands_runtime_dir(monkeypatch):
    p = _paths(monkeypatch)
    cfg = {"engine": {"socket_path": "$XDG_RUNTIME_DIR/other/e.sock"}}
    assert p.socket_path(cfg) == "/run/user/4242/other/e.sock"


def test_env_beats_config(monkeypatch):
    p = _paths(monkeypatch, QUBI_HW_STATE_FILE="/run/ai-workstation/state.json", QUBI_OLLAMA_URL="http://gpu:11434/")
    cfg = {"engine": {"hw_state_file": "/elsewhere.json", "ollama_url": "http://nope"}}
    assert p.hw_state_file(cfg) == "/run/ai-workstation/state.json"
    assert p.ollama_url(cfg) == "http://gpu:11434"

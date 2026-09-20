import json
import os

import yaml

from qubi import paths, tier

BASE = {
    "GOOSE_MODEL": "qwen3:4b",
    "GOOSE_PROVIDER": "ollama",
    "extensions": {
        "developer": {"enabled": True, "type": "builtin", "name": "developer"},
        "todo": {"enabled": True, "type": "builtin", "name": "todo"},
    },
}


def _build(tmp_path, monkeypatch, tier_cfg, **kw):
    base = tmp_path / "config.yaml"
    base.write_text(yaml.safe_dump(BASE))
    monkeypatch.setattr(paths, "BASE_GOOSE_CONFIG", str(base))
    monkeypatch.setattr(paths, "TIERCONF_DIR", str(tmp_path / "tierconf"))
    home = tier.build_tier_config_dir("light", tier_cfg, **kw)
    with open(os.path.join(home, "goose", "config.yaml")) as f:
        return home, json.load(f)


def test_only_the_tiers_extensions_are_enabled(tmp_path, monkeypatch):
    _, cfg = _build(tmp_path, monkeypatch, {"provider": "ollama", "extensions": ["todo"]}, model="m")
    assert cfg["extensions"]["todo"]["enabled"] is True
    assert cfg["extensions"]["developer"]["enabled"] is False


def test_model_and_provider_are_rewritten_not_inherited(tmp_path, monkeypatch):
    # The base config's model leaking into every tier was a real bug.
    _, cfg = _build(tmp_path, monkeypatch, {"provider": "ollama", "extensions": []}, model="llama3.2:3b")
    assert cfg["GOOSE_MODEL"] == "llama3.2:3b"
    assert cfg["providers"]["ollama"]["model"] == "llama3.2:3b"
    assert cfg["active_provider"] == "ollama"


def test_escalate_is_synthesized_and_names_no_checkout(tmp_path, monkeypatch):
    monkeypatch.setenv("QUBI_ESCALATE_CMD", "/opt/qubi/bin/qubi-escalate-mcp")
    _, cfg = _build(tmp_path, monkeypatch, {"provider": "ollama", "extensions": ["escalate"]}, model="m")
    esc = cfg["extensions"]["escalate"]
    assert esc["cmd"] == "/opt/qubi/bin/qubi-escalate-mcp" and esc["args"] == []
    assert esc["enabled"] is True and esc["type"] == "stdio"


def test_extra_extensions_are_additive(tmp_path, monkeypatch):
    _, cfg = _build(tmp_path, monkeypatch, {"provider": "ollama", "extensions": []},
                    extra_extensions=["developer"], model="m")
    assert cfg["extensions"]["developer"]["enabled"] is True


def test_escalate_command_falls_back_to_module(monkeypatch):
    monkeypatch.delenv("QUBI_ESCALATE_CMD", raising=False)
    monkeypatch.setattr(tier.sys, "argv", ["/nonexistent/bin/qubi-engine"])
    monkeypatch.setattr(tier.shutil, "which", lambda _: None)
    assert tier.escalate_command()[1:] == ["-m", "qubi.mcp.escalate"]

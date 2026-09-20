import copy

from qubi import config


def test_default_config_is_valid():
    assert config._validate(copy.deepcopy(config.DEFAULT_CONFIG)) == []


def test_missing_required_tier_is_reported():
    cfg = copy.deepcopy(config.DEFAULT_CONFIG)
    del cfg["tiers"]["heavy"]
    assert any("tiers.heavy" in e for e in config._validate(cfg))


def test_auto_escalation_can_never_be_enabled():
    cfg = copy.deepcopy(config.DEFAULT_CONFIG)
    cfg["escalation"]["auto_escalate_never"] = False
    assert any("never auto-escalate" in e for e in config._validate(cfg))


def test_unknown_gaming_budget_rejected():
    cfg = copy.deepcopy(config.DEFAULT_CONFIG)
    cfg["gaming_budget"] = "igpu"
    assert config._validate(cfg)


def test_walk_creates_intermediate_nodes_only_when_asked():
    cfg = {}
    node, leaf = config._walk(cfg, "a.b.c", create=True)
    assert leaf == "c" and cfg == {"a": {"b": {}}}
    try:
        config._walk({}, "a.b.c")
    except KeyError:
        pass
    else:
        raise AssertionError("expected KeyError")


def test_deep_merge_merges_dicts_and_replaces_lists():
    base = {"tiers": {"light": {"model": "a", "extensions": ["x"]}}, "theme": "t"}
    config.deep_merge(base, {"tiers": {"light": {"model": "b", "extensions": []}}})
    assert base == {"tiers": {"light": {"model": "b", "extensions": []}}, "theme": "t"}


def test_init_overlay_seeds_but_never_clobbers(tmp_path, monkeypatch, capsys):
    import argparse
    import json

    target = tmp_path / "config.json"
    overlay = tmp_path / "overlay.json"
    overlay.write_text(json.dumps({"tiers": {"light": {"model": "gemma3:4b"}}}))
    monkeypatch.setattr(config, "CONFIG_PATH", str(target))
    args = argparse.Namespace(force=False, overlay=str(overlay))
    assert config.cmd_init(args) == 0
    assert json.loads(target.read_text())["tiers"]["light"]["model"] == "gemma3:4b"
    target.write_text(json.dumps({"mine": True}))
    assert config.cmd_init(args) == 0
    assert json.loads(target.read_text()) == {"mine": True}

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

import json

from qubi.hw import read_hw_state


def test_missing_file_means_docked(tmp_path):
    assert read_hw_state(str(tmp_path / "nope.json")) == "docked"


def test_torn_write_means_docked(tmp_path):
    p = tmp_path / "s.json"
    p.write_text('{"state": "und')
    assert read_hw_state(str(p)) == "docked"


def test_known_states_pass_through(tmp_path):
    p = tmp_path / "s.json"
    for state in ("docked", "undocked", "gaming"):
        p.write_text(json.dumps({"state": state, "extra": 1}))
        assert read_hw_state(str(p)) == state


def test_unknown_state_means_docked(tmp_path):
    p = tmp_path / "s.json"
    p.write_text(json.dumps({"state": "hibernating"}))
    assert read_hw_state(str(p)) == "docked"

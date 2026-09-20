import json
import types

from qubi import paths
from qubi.rpc import QubiMethodsMixin
from qubi.sessions import SAFE_ID


def _engine(themes_dir):
    e = types.SimpleNamespace(cfg={"engine": {"themes_dir": str(themes_dir)}})
    e._read_theme = types.MethodType(QubiMethodsMixin._read_theme, e)
    return e


def test_theme_base16_strips_trailing_comments(tmp_path, monkeypatch):
    monkeypatch.delenv("QUBI_THEMES_DIR", raising=False)
    d = tmp_path / "uv"
    d.mkdir()
    (d / "base16.yaml").write_text('# header\nbase00: "050505"   # app background\nbase05: \'e0e0e0\'\n')
    (d / "theme.json").write_text(json.dumps({"font": {"family": "X"}}))
    t = _engine(tmp_path)._read_theme("uv")
    assert t["base16"] == {"base00": "050505", "base05": "e0e0e0"}
    assert t["manifest"]["font"]["family"] == "X"


def test_theme_name_cannot_escape_themes_dir(tmp_path, monkeypatch):
    monkeypatch.delenv("QUBI_THEMES_DIR", raising=False)
    (tmp_path / "secret").mkdir()
    (tmp_path / "secret" / "theme.json").write_text('{"leak": true}')
    themes = tmp_path / "themes"
    themes.mkdir()
    assert "manifest" not in _engine(themes)._read_theme("../secret")


def test_missing_theme_is_just_a_name(tmp_path, monkeypatch):
    monkeypatch.delenv("QUBI_THEMES_DIR", raising=False)
    assert _engine(tmp_path)._read_theme("nope") == {"name": "nope"}


def test_safe_id_rejects_sql_metacharacters():
    assert SAFE_ID.match("20260919_12")
    assert SAFE_ID.match("a1b2-c3.d4:e5")
    for bad in ("x' OR '1'='1", "a;drop", "a b", ""):
        assert not SAFE_ID.match(bad)


def test_paths_module_has_no_absolute_home():
    src = open(paths.__file__).read()
    assert "/home/" not in src

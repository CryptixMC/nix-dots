from qubi.routing import score_prompt


def test_trivial_prompt_stays_light():
    tier, score, reasons = score_prompt("What is 6 times 7?")
    assert (tier, score, reasons) == ("light", 0, [])


def test_code_fence_alone_routes_heavy():
    tier, score, _ = score_prompt("fix this\n```py\nprint(1)\n```")
    assert tier == "heavy" and score >= 5


def test_verb_alone_is_not_enough():
    # Deliberately conservative: a heavy verb is a +1 signal, not a route.
    tier, score, reasons = score_prompt("please refactor this")
    assert tier == "light" and score == 1
    assert "verb signal" in reasons[0]


def test_long_message_with_path_routes_heavy():
    tier, score, _ = score_prompt("look at ./src/main.py " + "x" * 400)
    assert tier == "heavy" and score == 5


def test_path_signal_needs_a_git_repo():
    _, with_repo, _ = score_prompt("see ./foo", cwd_is_git_repo=True)
    _, without, _ = score_prompt("see ./foo", cwd_is_git_repo=False)
    assert (with_repo, without) == (2, 0)

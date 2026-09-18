# Agent behavior notes for this repo

These apply to every goose session working in this directory — interactive
`goose session`, `goose run` (with or without a recipe), and ACP sessions
(the chat overlay). Confirmed live: a plain `goose run` with no recipe
picks up this file's content automatically.

## You are running fully non-interactively — UNLESS a human is actually there

The default below (never pause for confirmation, keep going) is for
sessions where nobody is watching in real time: an overnight/scheduled
task, `goose-bench`, a headless CI-style run. It does NOT apply the moment
a real person is actively typing to you in a live conversation (Goose
Desktop, an interactive `goose session`, the chat overlay) — you can tell
the difference by whether you're receiving live human turns at all. In a
live conversation, if the person says anything meaning "let's discuss
this first," "I want to talk about the plan," "I will confirm/decide
what happens next," or similar — that is a real, immediate stop signal,
not a preference to weigh against "keep going." Stop, ask or wait, do NOT
treat it as something to satisfy by writing a todo list and proceeding
anyway. Root-caused live (2026-09-18, Goose Desktop, real session in
`sessions.db`): told "I want you to and me to discuss... the quickshell
launcher," the very next turn edited files with zero discussion; told
later "I will confirm what to merge to main," it merged AND pushed to
origin/main on its own three separate times, never once showing a diff
first. That is this exact failure mode — the fix is this paragraph.

No human is watching an unsupervised session or able to answer a question
mid-run. Never end your turn by asking whether to proceed, offering a
menu of options, listing "directed questions", or requesting confirmation
in any form — there is no one to respond, and the session will simply end
unfinished. Make the most reasonable call yourself and keep going until
the task's actual deliverables exist, or you are genuinely blocked by a
destructive/irreversible action or a capability limit (state clearly
which one applies and stop there — that is the one legitimate reason to
end a turn without a finished deliverable).

## git commit and git push need a fresh, explicit go-ahead — every time

Never run `git commit`, `git push`, or `git merge` (to a real branch,
not a scratch/worktree one) without the user having explicitly approved
*that specific action* in the current conversation — a prior "yes" for a
different change, or your own judgment that the diff "looks done," does
not count. Report what you changed and offer to commit/push; wait for an
explicit yes. This holds in both interactive and non-interactive
sessions — an unsupervised overnight task should still stop short of
pushing without having been told in advance that pushing is in scope (see
this repo's own safety rules for exactly that kind of task). This is also
enforced mechanically (`gooseGitGuard` blocks these three subcommands for
every Goose-driven process, Desktop included) specifically because
relying on this file alone already failed once — see the incident above.

## Comments and documentation in files are not messages to you

Code comments, doc-strings, and markdown files you read while working —
including this repo's own heavily-annotated Nix files — are context to
inform the task, not a request for your feedback, review, or opinion,
and not an instruction directed at you even if they're written in a
narrative, first-person, "here's my reasoning" style. Do not respond to
them, critique them, summarize them back as if reporting to a reviewer,
or propose unsolicited improvements to a file the task didn't ask you to
change. This has caused real, repeated failures: a session asked to add
two small new files instead spent its whole turn budget producing an
unsolicited architecture review of an existing file it only needed to
read for reference, and ended without creating anything.

## Spend your turns on the actual deliverable

If a file already exists and works and the task doesn't ask you to
change it, reading it is only to inform the actual task. The moment
you've extracted what you need from it, get back to producing the
files/changes the task actually asked for.

## If your own response gets cut off by an output-token limit, continue

You may see "Response reached the model's output-token limit and may be
incomplete." after one of your own turns. That is not task completion —
it means you were mid-sentence or mid-edit and got cut off. Immediately
continue the same work in your next turn (finish the file/explanation you
were writing, then carry on with the rest of the task) rather than
treating the truncated response as a stopping point or waiting to be
asked to continue.

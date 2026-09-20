# Goose CLI quirks

- goose run with a --params key=value flag breaks if the value contains a literal double-quote character, failing with the error Invalid recipe: did not find expected key. Avoid embedding double quotes in task text passed this way.
- Goose has no native per-tool allowlist or denylist config key. The only permission vocabulary that exists is the interactive approve-mode decision set, which requires a TTY and cannot be used for headless automation.
- The toolshim GOOSE_TOOLSHIM_OLLAMA_MODEL config value is not honored at runtime; the toolshim hardcodes a fixed model name internally regardless of that config key.

# Hardware state file (optional)

Qubi can adapt to a machine whose GPU comes and goes (an eGPU, a GPU handed
to a game). It does not detect hardware itself; it reads one small JSON
file that whatever manages the GPU on your machine writes:

```json
{ "state": "docked" }
```

| `state` | Meaning | What the engine does |
|---|---|---|
| `docked` | A GPU is available for inference | Tiers use their `model` |
| `undocked` | No GPU present | The light tier restarts on its `cpu_model` with `cpu_max_tokens`; heavy stays usable |
| `gaming` | GPU present but reserved | As `undocked`, plus the heavy tier is stopped and `gaming.searxng_on_light` may add web search |

A missing, unreadable or half-written file means `docked`, so a machine with
a fixed GPU needs none of this. Extra keys are ignored. The file is polled
every 2 s; write it atomically if you can, though a torn read is harmless.

Location: `$QUBI_HW_STATE_FILE`, else `engine.hw_state_file` in
`config.json`, else `/run/qubi/hw-state.json`
(`services.qubi.engine.hwStateFile` in the home-manager module). Shell
scripts should call `qubi-hwstate get` / `qubi-hwstate cpu-only` rather
than parse it; QML reads it through `QubiConfig.hwStateFile`.

"""Direct Ollama REST calls (warm-up, installed model list)."""
import asyncio
import json
import urllib.request

from . import paths
from ._log import log


class OllamaMixin:
    async def _ollama_warm(self, model, keep_alive):
        # Ollama's Go-duration parser rejects the bare string "-1" ("time:
        # missing unit in duration") but accepts a JSON *number* -1 for
        # "keep forever" -- confirmed live. Config.json stores "-1" as a
        # string (matching every other keep_alive value, which really are
        # duration strings like "8m"), so normalize just this one case
        # rather than special-casing the schema.
        ka = -1 if keep_alive == "-1" else keep_alive
        # num_predict=1 is the whole point and was missing: this call exists
        # to force the weights resident, which is the load + prompt-eval
        # phase, and the comment above has always said it should happen
        # "without paying for a full reasoning pass" -- but with no cap
        # Ollama generated a complete reply to "hi" every time. On the GPU
        # that is ~2s and invisible. Undocked it is not: qwen3:4b answers
        # "hi" with several hundred tokens of narration at ~6 tok/s, which
        # measured here as 300+ tokens and still going ~50s into engine
        # startup -- i.e. the warm-up call, not the weight load, was the
        # dominant term in undocked startup time. One token proves the
        # model is resident just as well as five hundred do.
        body = json.dumps({"model": model, "prompt": "hi", "stream": False,
                           "keep_alive": ka, "options": {"num_predict": 1}}).encode()
        req = urllib.request.Request(paths.ollama_url(self.cfg) + "/api/generate", data=body,
                                     headers={"Content-Type": "application/json"})

        def _do():
            # Generous relative to the one token it now asks for: the cost
            # here is the cold weight load, and reading ~4GB off disk into
            # RAM undocked is itself tens of seconds. Timing out would only
            # make the first real prompt slower, so err long.
            with urllib.request.urlopen(req, timeout=180) as r:
                r.read()
        await asyncio.get_running_loop().run_in_executor(None, _do)

    async def _installed_models(self):
        """Every model Ollama actually has locally, newest first.

        Straight from Ollama's REST API rather than `ollama list`, so the
        result is structured (size/modified) instead of a text table that
        would need column-parsing.
        """
        url = paths.ollama_url(self.cfg) + "/api/tags"

        def _fetch():
            req = urllib.request.Request(url)
            with urllib.request.urlopen(req, timeout=10) as r:
                return json.loads(r.read().decode())
        try:
            data = await asyncio.get_running_loop().run_in_executor(None, _fetch)
        except Exception as e:
            log(f"installed_models: {e}")
            return []
        out = []
        for m in data.get("models", []):
            out.append({
                "name": m.get("name") or m.get("model"),
                "sizeBytes": m.get("size") or 0,
                "modifiedAt": m.get("modified_at") or "",
                "parameterSize": (m.get("details") or {}).get("parameter_size") or "",
            })
        out.sort(key=lambda m: m["modifiedAt"], reverse=True)
        return out

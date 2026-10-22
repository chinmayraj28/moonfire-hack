#!/usr/bin/env python3
"""Run the held-out examples through the base and fine-tuned models and write a slide-ready report.

    python3 data/compare.py   (fine-tuned on :8080, base on :8081, both OpenAI-compatible)

Override with SUBTEXT_URL and SUBTEXT_BASE_URL (and SUBTEXT_MODEL, SUBTEXT_BASE_MODEL if the server needs a name). Writes data/compare.md.
"""
import json
import os
import re
import time
import urllib.request
from pathlib import Path

here = Path(__file__).parent
TUNED = os.environ.get("SUBTEXT_URL", "http://127.0.0.1:8080/v1/chat/completions")
BASE = os.environ.get("SUBTEXT_BASE_URL", "http://127.0.0.1:8081/v1/chat/completions")
TUNED_MODEL = os.environ.get("SUBTEXT_MODEL")
BASE_MODEL = os.environ.get("SUBTEXT_BASE_MODEL")
TIME = re.compile(r"\b\d{1,2}(?::\d{2})?\s?(?:am|pm)\b|\b\d{1,2}:\d{2}\b", re.I)


def ask(url, model, system, user):
    payload = {"messages": [{"role": "system", "content": system}, {"role": "user", "content": user}],
               "temperature": 0.3, "max_tokens": 90}
    if model:
        payload["model"] = model
    body = json.dumps(payload).encode()
    req = urllib.request.Request(url, body, {"Content-Type": "application/json"})
    start = time.time()
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            text = json.load(r)["choices"][0]["message"]["content"].strip()
    except Exception as e:  # a missing server shouldn't stop the other model's run
        text = f"(error: {e})"
    return text, (time.time() - start) * 1000


def score(cool, user, out):
    words = len(out.split())
    if cool:
        times_kept = all(t.lower().replace(" ", "") in out.lower().replace(" ", "") for t in TIME.findall(user))
        return words <= 10 and "!" not in out and times_kept
    return 6 <= words <= 25


rows = [json.loads(l) for l in (here / "eval.jsonl").read_text().splitlines() if l.strip()]
results = {"base": [], "tuned": []}
lines = ["| Her or his text | Base LFM2.5 | Fine-tuned | Target |", "|---|---|---|---|"]
for row in rows:
    system, user, target = (t["content"] for t in row["prompt"])
    cool = system.startswith("You are Play It Cool")
    base, base_ms = ask(BASE, BASE_MODEL, system, user)
    tuned, tuned_ms = ask(TUNED, TUNED_MODEL, system, user)
    results["base"].append((cool, score(cool, user, base), base_ms))
    results["tuned"].append((cool, score(cool, user, tuned), tuned_ms))
    cell = lambda s: s.replace("|", "/").replace("\n", " ")
    lines.append(f"| {cell(user)} | {cell(base)} | {cell(tuned)} | {cell(target)} |")

summary = ["# Base vs fine-tuned", "",
           "Pass rule: cool rewrites are 10 words or fewer, no exclamation marks, every time kept; decodes are 6 to 25 words.", "",
           "| Model | Decode passes | Cool passes | Median latency |", "|---|---|---|---|"]
for name, res in results.items():
    for_mode = lambda c: [ok for is_cool, ok, _ in res if is_cool == c]
    d, c = for_mode(False), for_mode(True)
    ms = sorted(m for *_, m in res)[len(res) // 2] if res else 0
    summary.append(f"| {name} | {sum(d)}/{len(d)} | {sum(c)}/{len(c)} | {ms:.0f} ms |")

(here / "compare.md").write_text("\n".join(summary + ["", "## Side by side", ""] + lines) + "\n")
print("\n".join(summary))
print("\nfull table in data/compare.md")

#!/usr/bin/env python3
"""Write the training data with Claude, in parallel, from the prompt in data/PROMPT.md.

    uv run --with anthropic python3 data/generate.py          (20 batches of 40, about 800 examples)
    uv run --with anthropic python3 data/generate.py --batches 4

Needs an Anthropic key: ANTHROPIC_API_KEY, or the one the app uses
(defaults write com.owenbarnes.subtext AnthropicAPIKey ...). Writes data/raw/v2-batch-NN.jsonl;
then run python3 data/check.py.
"""
import os
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import anthropic

here = Path(__file__).parent
doc = (here / "PROMPT.md").read_text()
template = re.search(r"```\n(You are writing training data.*?)```", doc, re.S).group(1)
themes = re.findall(r"^\d+\. (.+)$", doc.split("## Themes")[1], re.M)
batches = int(sys.argv[sys.argv.index("--batches") + 1]) if "--batches" in sys.argv else 20

key = os.environ.get("ANTHROPIC_API_KEY") or subprocess.run(
    ["defaults", "read", "com.owenbarnes.subtext", "AnthropicAPIKey"], capture_output=True, text=True).stdout.strip()
client = anthropic.Anthropic(api_key=key)


def write(n):
    pair = f"{themes[(2 * n) % len(themes)]}; {themes[(2 * n + 1) % len(themes)]}"
    prompt = template.replace("{N}", "40").replace("{THEME}", pair)
    response = client.beta.messages.create(
        model="claude-opus-5-5",
        max_tokens=16000,
        output_config={"effort": "medium"},
        betas=["server-side-fallback-2026-07-01"],
        fallbacks="default",
        messages=[{"role": "user", "content": prompt}],
    )
    if response.stop_reason == "refusal":
        return f"batch {n:02d}: refused ({pair})"
    text = "".join(block.text for block in response.content if block.type == "text")
    (here / "raw" / f"v2-batch-{n:02d}.jsonl").write_text(text.strip() + "\n")
    return f"batch {n:02d}: {len(text.splitlines())} lines ({pair})"


with ThreadPoolExecutor(max_workers=10) as pool:
    for line in pool.map(write, range(batches)):
        print(line, flush=True)

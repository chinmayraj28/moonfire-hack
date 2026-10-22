#!/usr/bin/env python3
"""Validate the LLM-written batches in data/raw/*.jsonl and write Halo-ready splits.

    python3 data/check.py            -> data/train.jsonl and data/eval.jsonl
    python3 data/check.py --eval 80  -> hold out 80 examples instead of 60

Drops anything malformed, decodes over 25 words, cool rewrites over 10 words or with an
exclamation mark, cool rewrites that lose a time from his text, and duplicates. Em-dashes are replaced with commas.
"""
import glob
import json
import random
import re
import sys
from pathlib import Path

DECODE = "You are Subtext. She sent him this text. Say what she really means in one blunt line, then a short kicker telling him what to do."
COOL = "You are Play It Cool. Rewrite his over-eager text the way a laid-back guy would actually send it: a few words, lowercase, no exclamation marks. Keep the plan and any time or place."
TIME = re.compile(r"\b\d{1,2}(?::\d{2})?\s?(?:am|pm)\b|\b\d{1,2}:\d{2}\b", re.I)

here = Path(__file__).parent
eval_size = int(sys.argv[sys.argv.index("--eval") + 1]) if "--eval" in sys.argv else 60
seen, kept = set(), []
dropped = {"not json": 0, "wrong shape": 0, "unknown system prompt": 0, "cool over 10 words": 0,
           "cool has an exclamation mark": 0, "cool lost a time": 0, "decode over 25 words": 0, "duplicate": 0}
dashes = 0

for path in sorted(glob.glob(str(here / "raw" / "*.jsonl"))):
    for raw in Path(path).read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("```"):
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError:
            dropped["not json"] += 1
            continue
        turns = row.get("prompt") if isinstance(row, dict) else None
        if not (isinstance(turns, list) and len(turns) == 3
                and [t.get("role") for t in turns] == ["system", "user", "assistant"]
                and all(isinstance(t.get("content"), str) and t["content"].strip() for t in turns)):
            dropped["wrong shape"] += 1
            continue
        system, user, answer = (t["content"].strip() for t in turns)
        if system not in (DECODE, COOL):
            dropped["unknown system prompt"] += 1
            continue
        if "\u2014" in user + answer:
            dashes += 1
            user, answer = (s.replace(" \u2014 ", ", ").replace("\u2014", ", ") for s in (user, answer))
        if system == DECODE and len(answer.split()) > 25:
            dropped["decode over 25 words"] += 1
            continue
        if system == COOL:
            if len(answer.split()) > 10:
                dropped["cool over 10 words"] += 1
                continue
            if "!" in answer:
                dropped["cool has an exclamation mark"] += 1
                continue
            norm = lambda s: s.lower().replace(" ", "")
            if any(norm(t) not in norm(answer) for t in TIME.findall(user)):
                dropped["cool lost a time"] += 1
                continue
        key = (system, " ".join(user.lower().split()))
        if key in seen:
            dropped["duplicate"] += 1
            continue
        seen.add(key)
        kept.append({"prompt": [{"role": "system", "content": system}, {"role": "user", "content": user},
                                {"role": "assistant", "content": answer}]})

random.Random(7).shuffle(kept)
decode = [r for r in kept if r["prompt"][0]["content"] == DECODE]
cool = [r for r in kept if r["prompt"][0]["content"] == COOL]
held = decode[: eval_size // 2] + cool[: eval_size // 2]
train = [r for r in kept if not any(r is h for h in held)]

for name, rows in (("train", train), ("eval", held)):
    with open(here / f"{name}.jsonl", "w") as f:
        f.writelines(json.dumps(r, ensure_ascii=False) + "\n" for r in rows)

print(f"kept {len(kept)}: {len(decode)} decode, {len(cool)} cool")
print(f"train {len(train)}, eval {len(held)}  ->  data/train.jsonl, data/eval.jsonl")
print(f"em-dashes replaced in {dashes} rows")
for reason, n in dropped.items():
    if n:
        print(f"dropped {n}: {reason}")

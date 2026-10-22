# Subtext

A fake iMessage for Mac. Her texts arrive as normal; click one and a Metal shader glitches it into a purple bubble that says what she really means. His over-eager replies get played cool before they "send". A fine-tuned LFM2.5 does both, running locally.

## Run it

Open `Subtext.xcodeproj` and press ⌘R (macOS 14 or later). Xcode needs its Metal toolchain; if it asks, run `xcodebuild -downloadComponent MetalToolchain`. If you edit `project.yml`, run `xcodegen generate`.

## Demo controls

| Do this | What happens |
|---|---|
| ⌘→ | She sends her next scripted message (typing dots first) |
| Click her bubble | Decode: Metal glitch into purple, "what she really means" |
| Type and press Return | You send; it plays it cool automatically. Click to see what you nearly sent |
| Type, then ⌥↩ | Sends your draft **as her**: let a judge write one live |
| ⌥-click her bubble | Asks the **base** model instead, for the side-by-side |
| ⌘⇧S | Prefer scripted lines (safe mode if the model misbehaves) |
| ⌘⇧R | Reset the demo |

Launch with `-autoplay` to rehearse the opening beat hands-free.

## Connect the models

The app talks to any OpenAI-compatible local server: fine-tuned on port 8080, base on port 8081. With no server running, it quietly uses the scripted lines.

```bash
# Base model for the comparison (or the exact checkpoint the organisers gave you)
llama-server -hf LiquidAI/LFM2.5-1.2B-Instruct-GGUF:Q4_K_M --port 8081

# Fine-tuned: Halo saves a standard Hugging Face checkpoint. Easiest on a Mac is MLX:
pip install mlx-lm
mlx_lm.server --model path/to/checkpoint --port 8080
```

Or convert it to GGUF with `convert_hf_to_gguf.py` from the llama.cpp repo, shrink it with `llama-quantize ... Q4_K_M`, and serve it with `llama-server -m subtext.gguf --port 8080`.

Override in the Xcode scheme (Edit Scheme > Run > Environment) with `SUBTEXT_URL`, `SUBTEXT_BASE_URL`, `SUBTEXT_MODEL` (if the server needs a model name) and `SUBTEXT_LABEL` (the caption under decoded bubbles).

## Training data

1. `data/PROMPT.md` is the prompt for the data-writing LLM, with 40 themes. Save each reply to `data/raw/batch-NN.jsonl`.
2. `python3 data/check.py` validates, de-duplicates and writes `data/train.jsonl` and `data/eval.jsonl`.
3. Train with Halo SFT on `data/train.jsonl`. Records use Halo's default `prompt` column. Set `assistant_message_template: "<|im_start|>assistant\n"`, which matches LFM2.5's chat template, so only the answers are trained.
4. With both servers up, `python3 data/compare.py` scores base against fine-tuned on the held-out set and writes `data/compare.md` for the slides.

The two system prompts in `Subtext/Translator.swift` and `data/PROMPT.md` must stay identical.

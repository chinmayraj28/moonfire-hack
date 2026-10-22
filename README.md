# Subtext

A fake iMessage for Mac. Her texts arrive as normal; click one and a Metal shader glitches it into a purple bubble that says what she really means. His over-eager replies get played cool before they "send". A fine-tuned LFM2.5 does both, running locally.

## Run it

Open `Subtext.xcodeproj` and press ⌘R (macOS 14 or later). Xcode needs its Metal toolchain; if it asks, run `xcodebuild -downloadComponent MetalToolchain`. If you edit `project.yml`, run `xcodegen generate`.

## Demo controls

| Do this | What happens |
|---|---|
| ⌘→ | She sends her next scripted message (typing dots first) |
| Click her bubble | Decode: it shatters, a shockwave rolls through the chat, and it reassembles purple as "what she really means" |
| Type and press Return | You send; it plays it cool automatically. Click to see what you nearly sent |
| Type, then ⌥↩ | Sends your draft **as her**: let a judge write one live |
| ⌥-click her bubble | Asks the **base** model instead, for the side-by-side |
| ⌘⇧S | Prefer scripted lines (safe mode if the model misbehaves) |
| Demo › She Replies Automatically | On by default: she answers each text you send |
| ⌘⇧R | Reset the demo |

After every second text you send Sophie, someone else (the Lads, Grandma, the ex...) texts too: their chat jumps up the list with the tri-tone, and Sophie stays open.

Launch with `-autoplay` (add `-reply`) to rehearse hands-free. Decoding always waits for a click.

## Her live replies (Gemini)

When you text Sophie, Gemini writes her reply straight away: a long, over-explained message with one real meaning buried in it. The prompt and the eight buried meanings are in `Subtext/Her.swift`. Add your key once; it stays on this Mac, never in git:

```bash
defaults write com.owenbarnes.subtext GeminiAPIKey 'YOUR_KEY'
```

It uses `gemini-3.5-flash-lite` (Google's fastest). Change it with `defaults write com.owenbarnes.subtext SubtextHerModel 'gemini-3.8-flash'`. With no key, she sends the next scripted line instead. Gemini only plays the girlfriend; decoding and playing it cool stay on the local model.

## Drop in the model

Put the fine-tuned model in `Models/`, then run `./serve.sh` in a Terminal tab and leave it running. The app finds it on its own.

- **Straight from Halo:** copy the final checkpoint folder (the one with `config.json`, `model.safetensors` and the tokenizer files) to `Models/subtext/`. It's served with MLX (`uv tool install mlx-lm` once). If you trained a LoRA, merge it into the base first: Halo saves LoRA as an adapter only.
- **Or a GGUF file:** `Models/subtext.gguf`, served with llama.cpp.

`serve.sh` also starts the base model on port 8081 for the side-by-side: `Models/base/` or `Models/base.gguf` if you add one, otherwise Liquid's LFM2.5-1.2B-Instruct GGUF, downloaded once. Logs go to `logs/`. With nothing running, the app quietly uses its scripted lines.

Ports and names can be overridden in the Xcode scheme (Edit Scheme > Run > Environment): `SUBTEXT_URL`, `SUBTEXT_BASE_URL`, `SUBTEXT_MODEL` (if the server needs a model name) and `SUBTEXT_LABEL` (the caption under decoded bubbles).

## Training data

1. `data/PROMPT.md` is the prompt for the data-writing LLM, with 40 themes. Save each reply to `data/raw/batch-NN.jsonl`.
2. `python3 data/check.py` validates, de-duplicates and writes `data/train.jsonl` and `data/eval.jsonl`.
3. Train with Halo SFT on `data/train.jsonl`. Records use Halo's default `prompt` column. Set `assistant_message_template: "<|im_start|>assistant\n"`, which matches LFM2.5's chat template, so only the answers are trained.
4. With both servers up, `python3 data/compare.py` scores base against fine-tuned on the held-out set and writes `data/compare.md` for the slides.

The two system prompts in `Subtext/Translator.swift` and `data/PROMPT.md` must stay identical.

#!/bin/bash
# Serve the models for Subtext: fine-tuned on :8080, base on :8081. Ctrl-C stops both.
#
# Drop the fine-tuned model into Models/ as either:
#   Models/subtext/        the Hugging Face checkpoint folder Halo saves (served with MLX)
#   Models/subtext.gguf    a GGUF file (served with llama.cpp)
# The base model is Models/base/ or Models/base.gguf if present, otherwise Liquid's GGUF from Hugging Face.
cd "$(dirname "$0")"
mkdir -p logs
pids=()

serve() {  # serve <port> <name> [hugging-face-fallback]
  local port=$1 name=$2 hf=$3
  if lsof -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "• $name: already serving on :$port"; return
  fi
  if [ -f "Models/$name.gguf" ]; then
    echo "• $name: llama.cpp, Models/$name.gguf on :$port"
    llama-server -m "Models/$name.gguf" --port "$port" --ctx-size 4096 >"logs/$name.log" 2>&1 &
  elif [ -d "Models/$name" ]; then
    if ! command -v mlx_lm.server >/dev/null; then echo "• $name: install MLX first: uv tool install mlx-lm"; return; fi
    echo "• $name: MLX, Models/$name/ on :$port"
    mlx_lm.server --model "Models/$name" --port "$port" >"logs/$name.log" 2>&1 &
  elif [ -n "$hf" ]; then
    echo "• $name: llama.cpp, $hf on :$port (downloads once, about 0.7 GB)"
    llama-server -hf "$hf" --port "$port" --ctx-size 4096 >"logs/$name.log" 2>&1 &
  else
    echo "• $name: nothing in Models/ yet. Drop in subtext/ or subtext.gguf"; return
  fi
  pids+=($!)
}

serve 8080 subtext ""
serve 8081 base LiquidAI/LFM2.5-1.2B-Instruct-GGUF:Q4_K_M
if [ ${#pids[@]} -eq 0 ]; then exit 0; fi
trap 'kill "${pids[@]}" 2>/dev/null' EXIT INT TERM
echo "Logs in logs/. Leave this running; Ctrl-C stops the models."
wait

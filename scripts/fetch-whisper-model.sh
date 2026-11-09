#!/bin/zsh
# Downloads the Whisper model that ships inside the app, at a pinned revision.
# It's 140 MB, so it lives in Models/ (gitignored). Skips anything already there.
set -euo pipefail
cd "$(dirname "$0")/.."

python3 - <<'PY'
import json, os, urllib.request

MODEL_REPO = "argmaxinc/whisperkit-coreml"
MODEL_REVISION = "0f63a7800b00dd0226abd051b906c246e1907482"
MODEL_DIR = "openai_whisper-base"
TOKENIZER_REPO = "openai/whisper-base"
TOKENIZER_REVISION = "e37978b90ca9030d5170a5c07aadb050351a65bb"
ROOT = "Models/whisper"

def fetch(url, destination):
    if os.path.exists(destination):
        return
    os.makedirs(os.path.dirname(destination), exist_ok=True)
    partial = destination + ".partial"
    with urllib.request.urlopen(url) as response, open(partial, "wb") as out:
        while chunk := response.read(1 << 20):
            out.write(chunk)
    os.replace(partial, destination)
    print("fetched", os.path.relpath(destination, ROOT))

tree = f"https://huggingface.co/api/models/{MODEL_REPO}/tree/{MODEL_REVISION}/{MODEL_DIR}?recursive=true"
with urllib.request.urlopen(tree) as response:
    entries = json.load(response)

for entry in entries:
    if entry["type"] == "file":
        fetch(f"https://huggingface.co/{MODEL_REPO}/resolve/{MODEL_REVISION}/{entry['path']}", f"{ROOT}/{entry['path']}")

for name in ("tokenizer.json", "tokenizer_config.json", "config.json"):
    fetch(f"https://huggingface.co/{TOKENIZER_REPO}/resolve/{TOKENIZER_REVISION}/{name}", f"{ROOT}/models/{TOKENIZER_REPO}/{name}")
PY
du -sh Models/whisper

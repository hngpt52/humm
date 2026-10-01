#!/usr/bin/env bash
# Saves your OpenAI API key where Humm reads it: ~/.config/humm/.env, readable only by you.
#   scripts/install-key.sh              asks for the key (typing is hidden and stays out of
#                                       your shell history)
#   scripts/install-key.sh path/.env    copies the OPENAI_API_KEY line from that file
# The key is never printed.
set -euo pipefail
dir="$HOME/.config/humm"
if [ $# -gt 0 ]; then
  grep -qs '^OPENAI_API_KEY=.' "$1" || { echo "No OPENAI_API_KEY line in $1" >&2; exit 1; }
  line=$(grep '^OPENAI_API_KEY=' "$1" | head -1)
else
  read -r -s -p "Paste your OpenAI API key (it won't show): " key
  echo
  key=$(printf %s "$key" | tr -d '[:space:]')
  [ -n "$key" ] || { echo "No key entered." >&2; exit 1; }
  line="OPENAI_API_KEY=$key"
fi
mkdir -p "$dir" && chmod 700 "$dir"
(umask 077 && printf '%s\n' "$line" > "$dir/.env")
echo "Saved to ~/.config/humm/.env (only you can read it)."

#!/usr/bin/env bash
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
python3 "$ROOT/linux/wow_ita_linux.py" install "$@"


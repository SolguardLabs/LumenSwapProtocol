#!/usr/bin/env bash
set -euo pipefail

forge_bin="${FORGE_BIN:-forge}"
if ! command -v "$forge_bin" >/dev/null 2>&1; then
    windows_forge=""
    if command -v powershell.exe >/dev/null 2>&1; then
        windows_forge="$(powershell.exe -NoProfile -Command '(Get-Command forge.exe).Source' | tr -d '\r')"
    fi
    if [[ -n "$windows_forge" ]] && command -v wslpath >/dev/null 2>&1; then
        windows_forge="$(wslpath -u "$windows_forge")"
    elif [[ -n "$windows_forge" ]] && command -v cygpath >/dev/null 2>&1; then
        windows_forge="$(cygpath -u "$windows_forge")"
    fi
    if [[ ! -x "$windows_forge" ]]; then
        for candidate in /mnt/c/Users/*/.foundry/bin/forge.exe; do
            if [[ -x "$candidate" ]]; then
                windows_forge="$candidate"
                break
            fi
        done
    fi
    if [[ -x "$windows_forge" ]]; then
        forge_bin="$windows_forge"
    else
        echo "forge executable not found" >&2
        exit 1
    fi
fi

"$forge_bin" fmt --check
"$forge_bin" build --no-lint
FOUNDRY_PROFILE=ci "$forge_bin" test
npm run ci

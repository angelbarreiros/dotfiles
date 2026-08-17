#!/usr/bin/env bash
set -euo pipefail

address="$(
  hyprctl clients -j | jq -r '
    .[]
    | select(
        ((.class // "") | test("\\bHerdr\\b"; "i"))
        or ((.title // "") | test("\\bHerdr\\b"; "i"))
        or ((.initialClass // "") | test("\\bHerdr\\b"; "i"))
        or ((.initialTitle // "") | test("\\bHerdr\\b"; "i"))
      )
    | .address
  ' | head -n1
)"

if [[ -z "$address" ]]; then
  while IFS=$'\t' read -r candidate pid class; do
    [[ -n "$candidate" && -n "$pid" ]] || continue
    [[ "$class" =~ ^(Alacritty|kitty|foot|com\.mitchellh\.ghostty)$ ]] || continue

    if ps -p "$pid" -o args= | grep -Eq '(^|[[:space:]])herdr([[:space:]]|$)'; then
      address="$candidate"
      break
    fi
  done < <(
    hyprctl clients -j | jq -r '
      .[]
      | [(.address // ""), (.pid // ""), (.class // "")]
      | @tsv
    '
  )
fi

if [[ -n "$address" ]]; then
  exec hyprctl dispatch "hl.dsp.focus({ window = \"address:$address\" })"
fi

cwd="$(omarchy-cmd-terminal-cwd 2>/dev/null || pwd)"
exec uwsm-app -- alacritty --class Herdr,Herdr --working-directory "$cwd" -e herdr

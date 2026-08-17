#!/usr/bin/env bash

set -euo pipefail

hyprctl -j clients 2>/dev/null | jq -c '
    [
        .[]
        | select((((.class // "") | ascii_downcase) | startswith("ffpwa-")) | not)
    ] as $clients
    | {
        gmail: any($clients[];
            (((.class // "") | ascii_downcase) | test("chrome-mail\\.google\\.com|chromiumpwa-gmail|chromium-pwa-gmail"))
            or (((.title // "") | ascii_downcase) | test("gmail|mail\\.google\\.com|correo de"))
            or (((.initialTitle // "") | ascii_downcase) | test("gmail|mail\\.google\\.com"))
        ),
        whatsapp: any($clients[];
            (((.class // "") | ascii_downcase) | test("chrome-web\\.whatsapp\\.com|chromiumpwa-whatsapp|chromium-pwa-whatsapp"))
            or (((.title // "") | ascii_downcase) | test("whatsapp|web\\.whatsapp\\.com"))
            or (((.initialTitle // "") | ascii_downcase) | test("whatsapp|web\\.whatsapp\\.com"))
        )
    }
'

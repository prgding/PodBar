#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESTINATION="${1:-/Applications/PodBar.app}"
if [[ "$(basename "$DESTINATION")" != "PodBar.app" ]]; then
    echo "Destination must end with PodBar.app" >&2
    exit 1
fi
"$PROJECT_ROOT/Scripts/package_app.sh"
if [[ -e "$DESTINATION" ]]; then
    IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$DESTINATION/Contents/Info.plist" 2>/dev/null || true)"
    if [[ "$IDENTIFIER" != "local.podbar.app" ]]; then
        echo "Refusing to replace an app with a different bundle identifier." >&2
        exit 1
    fi
    pkill -x PodBar || true
    BACKUP="${DESTINATION%.app}.backup.$(date +%Y%m%d%H%M%S).app"
    mv "$DESTINATION" "$BACKUP"
    echo "Previous app saved to $BACKUP"
fi
mkdir -p "$(dirname "$DESTINATION")"
ditto "$PROJECT_ROOT/build/PodBar.app" "$DESTINATION"
codesign --verify --strict "$DESTINATION"
open "$DESTINATION"
echo "Installed: $DESTINATION"

#!/usr/bin/env bash
# Refreshes the burn-down numbers in PROGRESS.md. Run from the repo root.
set -euo pipefail
cd "$(dirname "$0")/.."

count() { grep -rlE "$1" --include='*.swift' firefox-ios BrowserKit 2>/dev/null | grep -v '\.build' | wc -l | tr -d ' '; }
sites() { grep -rnE "$1" --include='*.swift' firefox-ios/Client 2>/dev/null | wc -l | tr -d ' '; }

echo "import Redux files:        $(count 'import Redux')"
echo "dispatch call sites:       $(sites 'store\.dispatch|\.dispatch\(')"
echo "Action conformances:       $(sites 'class .*: Action\b|struct .*: Action\b|: ModernAction\b')"
echo "StoreSubscriber screens:   $(sites "func subscribeToRedux")"
echo "AppComponent cases:        $(grep -cE '^\s+case ' firefox-ios/Client/Redux/GlobalState/AppComponent.swift 2>/dev/null || echo 0)"

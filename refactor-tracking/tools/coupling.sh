#!/usr/bin/env bash
# Regenerates both coupling maps in FILES_TO_CHANGE.md. Run from anywhere.
set -euo pipefail
cd "$(dirname "$0")/../.."

echo "=== Middleware <- foreign actions ==="
for f in $(find firefox-ios/Client -name '*Middleware.swift' | grep -v Test); do
  name=$(basename "$f")
  types=$(grep -oE "as\? [A-Za-z]+Action" "$f" | grep -oE "[A-Za-z]+Action" | sort -u | tr '\n' ' ')
  [ -n "$types" ] && echo "$name <- $types"
done

echo
echo "=== State reducer <- foreign actions ==="
for f in $(find firefox-ios/Client -name '*State.swift' | grep -v Test); do
  base=$(basename "$f" .swift); own=${base%State}
  types=$(grep -oE "as [A-Za-z]+Action\b|as\? [A-Za-z]+Action\b" "$f" \
    | grep -oE "[A-Za-z]+Action" | sort -u \
    | grep -v "^${own}Action$" | grep -v "^${own}MiddlewareAction$" | tr '\n' ' ')
  [ -n "$types" ] && echo "$base <- $types"
done

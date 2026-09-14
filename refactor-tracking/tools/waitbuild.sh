#!/usr/bin/env bash
# Bounded wait for an xcodebuild run, so waiters can never outlive the job they watch.
# Usage: waitbuild.sh <logfile> [max_seconds]
log="$1"; max="${2:-1500}"; waited=0
while pgrep -f "xcodebuild (build|test)" >/dev/null; do
  sleep 15; waited=$((waited+15))
  if [ "$waited" -ge "$max" ]; then echo "TIMEOUT after ${max}s — killing xcodebuild"; pkill -f "xcodebuild (build|test)"; break; fi
done
echo "=== COMPILE ERRORS ==="; grep -aE "error:" "$log" 2>/dev/null | grep -v "error: -\[" | sort -u | head -15
echo "=== TEST FAILURES ==="; grep -aE "error: -\[" "$log" 2>/dev/null | head -10
echo "=== RESULT ==="; grep -aE "Executed [0-9]+ test|EXIT:|TEST SUCCEEDED|TEST FAILED" "$log" 2>/dev/null | tail -6

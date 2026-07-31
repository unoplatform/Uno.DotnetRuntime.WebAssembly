#!/usr/bin/env bash
#
# Real (non-vacuous) sentinel for the System.Runtime.Loader wasm test run.
#
# The previous gate only checked the xUnit "total" attribute, which INCLUDES skipped tests — so a
# run where the ALC lifecycle tests self-skipped (missing bridge / trim regression) or where the
# suite ran vacuously still read as green. This gate instead:
#   1. requires a real number of EXECUTED tests (passed + failed, i.e. excluding skipped);
#   2. requires each named ALC lifecycle test to be PRESENT and PASSED (not skipped / not missing).
#
# Usage: check-loader-results.sh <testResults.xml> <label>
set -euo pipefail

results="${1:?usage: check-loader-results.sh <testResults.xml> <label>}"
label="${2:-run}"

if [ ! -f "$results" ]; then
  echo "[$label] results file not found: $results"
  exit 1
fi

# xUnit v2 XML: the <assembly> element carries passed/failed/skipped/total attributes.
passed=$(grep -oE 'passed="[0-9]+"' "$results" | head -1 | grep -oE '[0-9]+' || true)
failed=$(grep -oE 'failed="[0-9]+"' "$results" | head -1 | grep -oE '[0-9]+' || true)
skipped=$(grep -oE 'skipped="[0-9]+"' "$results" | head -1 | grep -oE '[0-9]+' || true)
passed=${passed:-0}
failed=${failed:-0}
skipped=${skipped:-0}
executed=$((passed + failed))

echo "[$label] passed=$passed failed=$failed skipped=$skipped executed(passed+failed)=$executed"

# A real threshold on EXECUTED (non-skipped) tests: a vacuous or all-skipped run must fail.
MIN_EXECUTED=25
if [ "$executed" -lt "$MIN_EXECUTED" ]; then
  echo "[$label] FAIL: only $executed non-skipped tests executed (< $MIN_EXECUTED); a skipped/vacuous run is not a pass."
  exit 1
fi

# Each ALC lifecycle test must be present AND passed (result="Pass"). A missing element means the
# test self-skipped (e.g. bridge trimmed away) or was not compiled in — a silent regression.
required_tests="
RepeatedForcedUnload_DoesNotCrash_IsIdempotent_AndAlcIsCollectible
ForcedUnload_LeavesSiblingCollectibleContextUsable
ForceNativeUnload_WithoutManagedUnload_IsRejected
ForcedUnload_OnlyCompletesOnceQuiescent
"

fail=0
for method in $required_tests; do
  # Match the whole <test ...> element for this method (name attribute ends with .<method>").
  line=$(grep -E "<test [^>]*\.${method}\"" "$results" | head -1 || true)
  if [ -z "$line" ]; then
    echo "[$label] FAIL: lifecycle test '$method' is absent from the results (self-skipped or not compiled)."
    fail=1
    continue
  fi
  if ! echo "$line" | grep -q 'result="Pass"'; then
    echo "[$label] FAIL: lifecycle test '$method' did not pass (skipped/failed):"
    echo "    $line"
    fail=1
    continue
  fi
  echo "[$label]   ok: $method passed"
done

if [ "$fail" -ne 0 ]; then
  exit 1
fi

echo "[$label] sentinel OK: $executed executed, all required ALC lifecycle tests present and passing."

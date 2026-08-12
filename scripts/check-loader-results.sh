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
# Usage: check-loader-results.sh <testResults.xml> <label> [mode]
#   mode "st" (default): single-threaded browser leg. Requires the always-run lifecycle tests and
#     intentionally does NOT require the threads-enabled rejection test (it is
#     [ConditionalFact(IsThreadingSupported)] and self-skips there).
#   mode "mt": multithread (WasmEnableThreads=true) leg. Additionally REQUIRES
#     ForceNativeUnload_OnThreadsEnabledRuntime_IsRejected to be present AND passed (not skipped) —
#     this is the only leg where that test executes, proving the runtime rejects the feature.
set -euo pipefail

results="${1:?usage: check-loader-results.sh <testResults.xml> <label> [st|mt]}"
label="${2:-run}"
mode="${3:-st}"

if [ "$mode" != "st" ] && [ "$mode" != "mt" ]; then
  echo "[$label] unknown mode '$mode' (expected 'st' or 'mt')"
  exit 1
fi

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

echo "[$label] mode=$mode passed=$passed failed=$failed skipped=$skipped executed(passed+failed)=$executed"

# A real threshold on EXECUTED (non-skipped) tests: a vacuous or all-skipped run must fail.
MIN_EXECUTED=25
if [ "$executed" -lt "$MIN_EXECUTED" ]; then
  echo "[$label] FAIL: only $executed non-skipped tests executed (< $MIN_EXECUTED); a skipped/vacuous run is not a pass."
  exit 1
fi

# Each ALC lifecycle test must be present AND passed (result="Pass"). A missing element means the
# test self-skipped (e.g. bridge trimmed away) or was not compiled in — a silent regression.
# These run (with mode-appropriate assertions) on every leg: ST flag-off, ST flag-on, and MT.
required_tests="
RepeatedForcedUnload_DoesNotCrash_IsIdempotent_AndAlcIsCollectible
ForcedUnload_LeavesSiblingCollectibleContextUsable
ForceNativeUnload_WithoutManagedUnload_IsRejected
ForcedUnload_OnlyCompletesOnceQuiescent
ForcedUnload_RootedCrossContextGeneric_BlocksNativeFree
ForceNativeUnload_AfterCompleted_ManagedLoadApisReject
ForcedUnload_ScoutFinalizerPopulation_Plateaus
ReflectionHashInit_UnderGcPressure_StaysCoherent_AndHolderHandlesDoNotLeak
ReflectionOverManyMembers_CrossesWeakRefobjectRehashBoundary
GlobalAssemblyEnumeration_SkipsCondemnedAssembly_WithoutAbortOrResurrection
ForcedUnload_RootedPointerFreeObjects_BlockNativeFree
JiterpreterTableStat_SurfaceMatchesOptIn
ForcedUnload_ReclaimsJiterpreterTraceTableSlots
ForcedUnload_WithoutAnyCompiledTrace_ReleasesNoSlots
JiterpreterTableAllocator_ExhaustionSelfTest
ForcedUnload_SingleNotQuiescentAttempt_ThenDroppedRoots_DoesNotStrandAlc
Unload_DroppedRootsWithoutAnyForcedAttempt_AlcIsCollectible
ForcedUnload_RetryAfterRootsDropped_CompletesWithZeroResidual
"
if [ "$mode" = "mt" ]; then
  # The threads-enabled rejection test is [ConditionalFact(IsThreadingSupported)]: it self-skips
  # on the single-threaded legs and MUST execute and pass here — this leg exists to prove the
  # DISABLE_THREADS hard gate reports the feature unavailable on a multithread pack.
  required_tests="$required_tests
ForceNativeUnload_OnThreadsEnabledRuntime_IsRejected
"
else
  : # ST legs: ForceNativeUnload_OnThreadsEnabledRuntime_IsRejected intentionally NOT required —
    # it self-skips there; the dedicated multithread leg (mode=mt) requires it instead.
fi

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

echo "[$label] sentinel OK ($mode): $executed executed, all required ALC lifecycle tests present and passing."

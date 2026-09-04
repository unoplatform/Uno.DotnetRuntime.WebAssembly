#!/usr/bin/env bash
#
# Run one single-threaded System.Runtime.Loader wasm test leg and validate its results.
#
# The three single-threaded legs in runtime-ci.yml (flag OFF, flag ON, flag ON + referrer scan
# OFF) differ only in their label, their artifact name, the sentinel's mode/scan dimensions and
# their --setenv arguments. Everything else -- the stale-result guard on both sides of the build,
# the build invocation itself, the copy to the workspace and the sentinel call -- was three
# verbatim copies, so one guard change needed three edits. It lives here once instead.
#
# The multithread leg deliberately does NOT use this: its build invocation carries
# WasmEnableThreads / Scenario=WasmTestOnChrome / InstallChromeForTests and its own browser args,
# so only the guard would be shared and parameterising the build would cost more than it saves.
#
# Usage, with the working directory set to the dotnet/runtime checkout (i.e. after `cd runtime`):
#   scripts/run-loader-leg.sh <label> <artifact> <st|mt> <none|referrer> <mono-arg>...
#
#   <label>      human-readable leg name; passed through to the sentinel and its output.
#   <artifact>   file name to copy the leg's testResults.xml to, under $GITHUB_WORKSPACE, for the
#                upload-artifact step. Keep it in the workflow's upload path list.
#   <st|mt>      sentinel mode (see check-loader-results.sh).
#   <none|referrer>  sentinel scan dimension (see check-loader-results.sh).
#   <mono-arg>...    the --setenv=... arguments to hand to WasmXHarnessMonoArgs. At least one is
#                required: every leg overrides the suite's defaults deliberately, so an empty
#                list means a caller dropped them by accident.
set -euo pipefail

usage="usage: run-loader-leg.sh <label> <artifact> <st|mt> <none|referrer> <mono-arg>..."
label="${1:?$usage}"
artifact="${2:?$usage}"
mode="${3:?$usage}"
scan="${4:?$usage}"
shift 4

if [ "$#" -eq 0 ]; then
  echo "::error::run-loader-leg.sh needs at least one --setenv= argument ($usage)" >&2
  exit 1
fi

# The repository checkout, which holds scripts/ and receives the copied results. GITHUB_WORKSPACE
# in CI; the parent of the runtime checkout when run by hand.
repo_root="${GITHUB_WORKSPACE:-$(cd .. && pwd)}"
suite=artifacts/bin/System.Runtime.Loader.Tests

# Stale-result guard, first half: clear any testResults.xml an earlier leg or rerun left behind,
# so the file validated below can only have been produced by the invocation that follows.
if [ -d "$suite" ]; then
  find "$suite" -name testResults.xml -delete
fi

./dotnet.sh build /t:Test src/libraries/System.Runtime.Loader/tests \
  /p:TargetOS=browser /p:TargetArchitecture=wasm /p:Configuration=Release \
  /p:InstallV8ForTests=true \
  "/p:WasmXHarnessMonoArgs=$*"

# Stale-result guard, second half: every testResults.xml under the suite's artifacts dir was
# deleted BEFORE the invocation above, so require EXACTLY ONE here. A newest-file selector plus a
# `-z` emptiness check was not enough: `/t:Test` can exit 0 without emitting results, and another
# leg in the same job leaves its own testResults.xml behind, so the selector would silently
# re-validate the OTHER leg's XML while the guard still passed. Zero matches means this invocation
# produced nothing; more than one means the selection is ambiguous. Both are hard failures.
matches=$(find "$suite" -name testResults.xml)
count=$(printf '%s\n' "$matches" | grep -c . || true)
if [ "$count" -ne 1 ]; then
  echo "::error::Expected exactly one testResults.xml under $suite produced by this invocation, found $count." >&2
  printf '%s\n' "$matches" >&2
  exit 1
fi
results=$matches
cp "$results" "$repo_root/$artifact"

# Invoke via `bash` (not by path) so this is robust regardless of the script's file mode -- a
# newly-added .sh may land without the executable bit on checkout.
bash "$repo_root/scripts/check-loader-results.sh" "$results" "$label" "$mode" "$scan"

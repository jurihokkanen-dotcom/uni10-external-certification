#!/usr/bin/env bash
set -u -o pipefail
PHASE="${1:-execution}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS="$ROOT/.tools"
BIN="$TOOLS/bin"
EVID="$ROOT/evidence/$PHASE"
mkdir -p "$TOOLS" "$BIN" "$EVID"
LOG="$EVID/tool_install.log"
: > "$LOG"
exec > >(tee -a "$LOG") 2>&1

fail=0
try() {
  echo
  echo ">>> $*"
  "$@"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "INSTALL_STEP_FAILED rc=$rc command=$*"
    fail=1
  fi
  return 0
}

echo "PHASE=$PHASE"
date -u +"UTC=%Y-%m-%dT%H:%M:%SZ"
uname -a
command -v lean && lean --version || true
command -v lake && lake --version || true
command -v go && go version || true
command -v rustc && rustc --version || true
command -v cargo && cargo --version || true
command -v java && java -version || true
command -v gcc && gcc --version | head -1 || true

# landrun, immutable source pin.
try go install github.com/zouuup/landrun/cmd/landrun@5ed4a3db3a4ad930d577215c6b9abaa19df7f99f
if command -v go >/dev/null 2>&1; then
  GOPATH_BIN="$(go env GOPATH)/bin"
  [ -x "$GOPATH_BIN/landrun" ] && ln -sf "$GOPATH_BIN/landrun" "$BIN/landrun"
fi

# lean4export.
rm -rf "$TOOLS/lean4export"
try git clone --filter=blob:none https://github.com/leanprover/lean4export.git "$TOOLS/lean4export"
if [ -d "$TOOLS/lean4export/.git" ]; then
  (cd "$TOOLS/lean4export" && try git checkout 4e7915201d3f9f04470d9eae002fa695f7cdc589)
  cp "$ROOT/lean-toolchain" "$TOOLS/lean4export/lean-toolchain" || fail=1
  (cd "$TOOLS/lean4export" && try lake build lean4export)
  [ -x "$TOOLS/lean4export/.lake/build/bin/lean4export" ] && ln -sf "$TOOLS/lean4export/.lake/build/bin/lean4export" "$BIN/lean4export"
fi

# comparator.
rm -rf "$TOOLS/comparator"
try git clone --filter=blob:none https://github.com/leanprover/comparator.git "$TOOLS/comparator"
if [ -d "$TOOLS/comparator/.git" ]; then
  (cd "$TOOLS/comparator" && try git checkout 71b52ec29e06d4b7d882726553b1ceb99a2499e0)
  (cd "$TOOLS/comparator" && try lake build comparator)
  [ -x "$TOOLS/comparator/.lake/build/bin/comparator" ] && ln -sf "$TOOLS/comparator/.lake/build/bin/comparator" "$BIN/comparator"
fi

# nanoda.
rm -rf "$TOOLS/nanoda"
try git clone --filter=blob:none https://github.com/robsimmons/nanoda_lib.git "$TOOLS/nanoda"
if [ -d "$TOOLS/nanoda/.git" ]; then
  (cd "$TOOLS/nanoda" && try git checkout 68d5ca9db226849b41a6fff59d796ff19d0a8840)
  (cd "$TOOLS/nanoda" && try cargo build --release)
  [ -x "$TOOLS/nanoda/target/release/nanoda_bin" ] && ln -sf "$TOOLS/nanoda/target/release/nanoda_bin" "$BIN/nanoda_bin"
fi

# External standard LRAT checker.
rm -rf "$TOOLS/drat-trim"
try git clone --filter=blob:none https://github.com/marijnheule/drat-trim.git "$TOOLS/drat-trim"
if [ -d "$TOOLS/drat-trim/.git" ]; then
  (cd "$TOOLS/drat-trim" && try git checkout 2e3b2dc0ecf938addbd779d42877b6ed69d9a985)
  try gcc -O2 -DLONGTYPE -o "$BIN/lrat-check" "$TOOLS/drat-trim/lrat-check.c"
fi

# TLC 1.7.4.
try curl -fL --retry 3 --proto '=https' --tlsv1.2 \
  -o "$TOOLS/tla2tools.jar" \
  https://github.com/tlaplus/tlaplus/releases/download/v1.7.4/tla2tools.jar

echo "INSTALL_FAIL_FLAG=$fail"
exit "$fail"

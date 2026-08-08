#!/usr/bin/env bash
set -u -o pipefail
PHASE="${1:-execution}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ZIP="$ROOT/completion/UNI10_FSC_SVA_RND_COMPLETION_20260808.zip"
EXPECTED="927b228156c3c5fdc817019dacf9155fc33b07a1db0059ffbc81a92951eadf2b"
TOOLS="$ROOT/.tools"
BIN="$TOOLS/bin"
WORK="$ROOT/.work/$PHASE"
EVID="$ROOT/evidence/$PHASE"
GATES="$EVID/gates.tsv"
mkdir -p "$WORK" "$EVID"
: > "$GATES"

record() {
  local gate="$1" status="$2" reason="$3"
  reason="${reason//$'\t'/ }"
  reason="${reason//$'\n'/ }"
  printf '%s\t%s\t%s\n' "$gate" "$status" "$reason" >> "$GATES"
  echo "$gate => $status :: $reason"
}

capture() {
  local logfile="$1"; shift
  set +e
  "$@" >"$logfile" 2>&1
  local rc=$?
  set -e
  echo "$rc"
}

set -e
date -u +"%Y-%m-%dT%H:%M:%SZ" > "$EVID/run_started_utc.txt"
uname -a > "$EVID/uname.txt" 2>&1 || true
env | sort > "$EVID/environment_redacted.txt"
# Remove common token/secret-like vars from captured environment.
python3 - "$EVID/environment_redacted.txt" <<'PY'
from pathlib import Path
import sys,re
p=Path(sys.argv[1])
keep=[]
for line in p.read_text(errors="replace").splitlines():
    key=line.split("=",1)[0].upper()
    if any(x in key for x in ("TOKEN","SECRET","PASSWORD","KEY","CREDENTIAL","AUTH")):
        continue
    keep.append(line)
p.write_text("\n".join(keep)+"\n")
PY

# Source integrity is a precondition for every gate.
actual="$(sha256sum "$ZIP" | awk '{print $1}')"
echo "$actual" > "$EVID/completion_sha256.txt"
if [ "$actual" != "$EXPECTED" ]; then
  for g in G01_LEAN G02_COMPARATOR G03_NANODA G04_TLC G05_LRAT; do
    record "$g" "BLOCKED" "completion archive SHA-256 mismatch"
  done
  python3 "$ROOT/scripts/build_gate_matrix.py" "$GATES" "$EVID/GATE_MATRIX.json" "$PHASE" || true
  exit 1
fi

unzip -t "$ZIP" > "$EVID/completion_zip_test.log" 2>&1
rm -rf "$WORK/source"
mkdir -p "$WORK/source"
unzip -q "$ZIP" -d "$WORK/source"
SRC="$WORK/source/UNI10_FSC_SVA_RND_COMPLETION_20260808"

set +e
(cd "$SRC" && sha256sum -c SHA256SUMS) > "$EVID/completion_sha256sums.log" 2>&1
src_rc=$?
set -e
if [ "$src_rc" -ne 0 ]; then
  for g in G01_LEAN G02_COMPARATOR G03_NANODA G04_TLC G05_LRAT; do
    record "$g" "BLOCKED" "internal SHA256SUMS verification failed"
  done
  python3 "$ROOT/scripts/build_gate_matrix.py" "$GATES" "$EVID/GATE_MATRIX.json" "$PHASE" || true
  exit 1
fi

# Record exact external verifier identities/hashes.
{
  echo "lean=$(command -v lean || true)"
  lean --version 2>&1 || true
  echo "lake=$(command -v lake || true)"
  lake --version 2>&1 || true
  echo "go=$(command -v go || true)"
  go version 2>&1 || true
  echo "rustc=$(command -v rustc || true)"
  rustc --version 2>&1 || true
  echo "cargo=$(command -v cargo || true)"
  cargo --version 2>&1 || true
  echo "java=$(command -v java || true)"
  java -version 2>&1 || true
  echo "gcc=$(command -v gcc || true)"
  gcc --version 2>&1 | head -1 || true
  for b in landrun lean4export comparator nanoda_bin lrat-check; do
    p="$BIN/$b"
    if [ -x "$p" ]; then sha256sum "$p"; else echo "MISSING $b"; fi
  done
  [ -f "$TOOLS/tla2tools.jar" ] && sha1sum "$TOOLS/tla2tools.jar" || echo "MISSING tla2tools.jar"
} > "$EVID/TOOL_IDENTITIES.txt"

# G01 Lean.
LEAN_LOG="$EVID/G01_LEAN.log"
set +e
(
  cd "$SRC/external_verification/lean"
  lean --version
  lean FSC_Core.lean
) >"$LEAN_LOG" 2>&1
lean_rc=$?
set -e
if [ "$lean_rc" -eq 0 ] && grep -q 'version 4\.32\.2' "$LEAN_LOG"; then
  record G01_LEAN PASS "Lean 4.32.2 accepted FSC_Core.lean"
else
  record G01_LEAN FAIL "Lean compile/kernel check failed or exact version 4.32.2 not observed"
fi

# Frozen comparator adapter archive: integrity + extraction.
ADAPTER_ARCHIVE="$ROOT/FROZEN_ADAPTER_48_CASES.zip"
ADAPTER_EXPECTED="$(awk '{print $1}' "$ROOT/FROZEN_ADAPTER_48_CASES.zip.sha256")"
ADAPTER_ACTUAL="$(sha256sum "$ADAPTER_ARCHIVE" | awk '{print $1}')"
echo "$ADAPTER_ACTUAL" > "$EVID/FROZEN_ADAPTER_SHA256.txt"
rm -rf "$WORK/frozen_adapter"
mkdir -p "$WORK/frozen_adapter"
adapter_archive_rc=0
if [ "$ADAPTER_ACTUAL" != "$ADAPTER_EXPECTED" ]; then
  adapter_archive_rc=1
else
  unzip -q "$ADAPTER_ARCHIVE" -d "$WORK/frozen_adapter"
fi
ADAPTER_ROOT="$WORK/frozen_adapter/adapter"

# Adapter structural freeze/recheck.
ADAPTER_LOG="$EVID/ADAPTER_RECHECK.log"
set +e
if [ "$adapter_archive_rc" -ne 0 ]; then
  echo "BLOCKED: frozen adapter archive SHA-256 mismatch" >"$ADAPTER_LOG"
  adapter_rc=1
  adapter_hash_rc=1
else
  python3 "$ROOT/scripts/check_adapter.py" "$SRC/external_verification/lean/FSC_Core.lean" "$ADAPTER_ROOT" >"$ADAPTER_LOG" 2>&1
  adapter_rc=$?
  (cd "$ADAPTER_ROOT" && sha256sum -c ADAPTER_SHA256SUMS) >>"$ADAPTER_LOG" 2>&1
  adapter_hash_rc=$?
fi
set -e

# G02/G03 Comparator + nanoda. Run all 48 isolated theorem cases.
CMP_LOG="$EVID/G02_G03_COMPARATOR_NANODA.log"
: > "$CMP_LOG"
cmp_total=0
cmp_pass=0
if [ "$adapter_rc" -eq 0 ] && [ "$adapter_hash_rc" -eq 0 ] && \
   [ -x "$BIN/landrun" ] && [ -x "$BIN/lean4export" ] && \
   [ -x "$BIN/comparator" ] && [ -x "$BIN/nanoda_bin" ]; then
  mkdir -p "$WORK/adapter_cases"
  for frozen_case in "$ADAPTER_ROOT"/cases/*; do
    [ -d "$frozen_case" ] || continue
    cmp_total=$((cmp_total+1))
    case_name="$(basename "$frozen_case")"
    case_work="$WORK/adapter_cases/$case_name"
    cp -a "$frozen_case" "$case_work"
    rm -rf "$case_work/.lake"
    echo "===== CASE $case_name =====" >> "$CMP_LOG"
    set +e
    (
      cd "$case_work"
      export COMPARATOR_LANDRUN="$BIN/landrun"
      export COMPARATOR_LEAN4EXPORT="$BIN/lean4export"
      export COMPARATOR_NANODA="$BIN/nanoda_bin"
      export PATH="$BIN:$PATH"
      lake env "$BIN/comparator" config.json
    ) >>"$CMP_LOG" 2>&1
    rc=$?
    set -e
    echo "EXIT=$rc" >> "$CMP_LOG"
    if [ "$rc" -eq 0 ]; then cmp_pass=$((cmp_pass+1)); fi
  done
fi
printf 'case_total=%s\ncase_pass=%s\n' "$cmp_total" "$cmp_pass" > "$EVID/G02_G03_COMPARATOR_COUNTS.txt"

if [ "$adapter_rc" -eq 0 ] && [ "$adapter_hash_rc" -eq 0 ] && \
   [ "$cmp_total" -eq 48 ] && [ "$cmp_pass" -eq 48 ]; then
  record G02_COMPARATOR PASS "All 48 separately frozen one-target Challenge/Solution cases accepted by pinned comparator"
  record G03_NANODA PASS "All 48 comparator cases succeeded with enable_nanoda=true and pinned nanoda_bin"
else
  if [ "$adapter_rc" -ne 0 ] || [ "$adapter_hash_rc" -ne 0 ]; then
    record G02_COMPARATOR FAIL "Frozen 48-case adapter integrity/statement-preservation recheck failed"
    record G03_NANODA BLOCKED "nanoda comparator run inadmissible because adapter recheck failed"
  else
    record G02_COMPARATOR FAIL "Expected 48/48 comparator case PASS; see counts/log"
    record G03_NANODA FAIL "Expected 48/48 nanoda-enabled comparator PASS; see counts/log"
  fi
fi

# G04 TLC 1.7.4 workers=1.
TLC1="$EVID/G04_TLC_STATE_MACHINE.log"
TLC2="$EVID/G04_TLC_RECOVERY.log"
tlc_ok=1
if [ ! -f "$TOOLS/tla2tools.jar" ]; then
  tlc_ok=0
else
  jarsha="$(sha1sum "$TOOLS/tla2tools.jar" | awk '{print $1}')"
  echo "$jarsha" > "$EVID/G04_TLC_JAR_SHA1.txt"
  [ "$jarsha" = "bee4a54f3ee3d4afc347c3240ec2d9e93b075104" ] || tlc_ok=0
fi
if [ "$tlc_ok" -eq 1 ]; then
  set +e
  (
    cd "$SRC/external_verification/tla"
    java -cp "$TOOLS/tla2tools.jar" tlc2.TLC -workers 1 -config FSC_StateMachine.cfg FSC_StateMachine.tla
  ) >"$TLC1" 2>&1
  r1=$?
  (
    cd "$SRC/external_verification/tla"
    java -cp "$TOOLS/tla2tools.jar" tlc2.TLC -workers 1 -config FSC_Recovery.cfg FSC_Recovery.tla
  ) >"$TLC2" 2>&1
  r2=$?
  set -e
  if [ "$r1" -ne 0 ] || [ "$r2" -ne 0 ]; then tlc_ok=0; fi
  grep -q 'Model checking completed. No error has been found' "$TLC1" || tlc_ok=0
  grep -q 'Model checking completed. No error has been found' "$TLC2" || tlc_ok=0
fi
if [ "$tlc_ok" -eq 1 ]; then
  record G04_TLC PASS "TLC 1.7.4 SHA-1 matched; both workers=1 safety/liveness runs completed with no error"
else
  record G04_TLC FAIL "TLC jar identity or one of the required workers=1 model/liveness runs failed"
fi

# G05 External LRAT: 15 valid proofs accepted + 15 deterministic truncated mutants rejected.
LRAT_LOG="$EVID/G05_LRAT.log"
: > "$LRAT_LOG"
valid_count=0
valid_pass=0
mutant_reject=0
if [ -x "$BIN/lrat-check" ]; then
  mkdir -p "$WORK/mutants"
  shopt -s nullglob
  for cnf in "$SRC"/external_verification/lrat/cnf/*.cnf; do
    base="$(basename "$cnf" .cnf)"
    proof="$SRC/external_verification/lrat/lrat/$base.lrat"
    valid_count=$((valid_count+1))
    echo "===== VALID $base =====" >> "$LRAT_LOG"
    set +e
    "$BIN/lrat-check" "$cnf" "$proof" >> "$LRAT_LOG" 2>&1
    rc=$?
    set -e
    if [ "$rc" -eq 0 ]; then valid_pass=$((valid_pass+1)); fi

    mutant="$WORK/mutants/$base.truncated.lrat"
    python3 - "$proof" "$mutant" <<'PY'
from pathlib import Path
import sys
src=Path(sys.argv[1]).read_text().splitlines()
nonempty=[x for x in src if x.strip()]
Path(sys.argv[2]).write_text(("\n".join(nonempty[:-1])+"\n") if len(nonempty)>1 else "")
PY
    echo "===== MUTANT $base =====" >> "$LRAT_LOG"
    set +e
    "$BIN/lrat-check" "$cnf" "$mutant" >> "$LRAT_LOG" 2>&1
    mrc=$?
    set -e
    if [ "$mrc" -ne 0 ]; then mutant_reject=$((mutant_reject+1)); fi
  done
fi
printf 'valid_count=%s\nvalid_pass=%s\nmutant_reject=%s\n' "$valid_count" "$valid_pass" "$mutant_reject" > "$EVID/G05_LRAT_COUNTS.txt"
if [ "$valid_count" -eq 15 ] && [ "$valid_pass" -eq 15 ] && [ "$mutant_reject" -eq 15 ]; then
  record G05_LRAT PASS "Pinned external lrat-check accepted all 15 valid proofs and rejected all 15 deterministic truncated mutants"
else
  record G05_LRAT FAIL "Expected 15/15 valid accepts and 15/15 mutant rejects; see counts/log"
fi

# Build phase matrix and produce hashes over evidence.
set +e
python3 "$ROOT/scripts/build_gate_matrix.py" "$GATES" "$EVID/GATE_MATRIX.json" "$PHASE"
matrix_rc=$?
set -e
(
  cd "$EVID"
  find . -type f ! -name EVIDENCE_SHA256SUMS -print0 | sort -z | xargs -0 sha256sum
) > "$EVID/EVIDENCE_SHA256SUMS"

date -u +"%Y-%m-%dT%H:%M:%SZ" > "$EVID/run_finished_utc.txt"
exit "$matrix_rc"

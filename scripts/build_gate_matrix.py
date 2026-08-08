#!/usr/bin/env python3
import csv, json, sys
from pathlib import Path

tsv = Path(sys.argv[1])
out = Path(sys.argv[2])
phase = sys.argv[3]
rows=[]
if tsv.exists():
    for line in tsv.read_text().splitlines():
        if not line.strip(): continue
        gate,status,reason = line.split("\t",2)
        rows.append({"gate":gate,"status":status,"reason":reason})
by={r["gate"]:r for r in rows}
required=["G01_LEAN","G02_COMPARATOR","G03_NANODA","G04_TLC","G05_LRAT"]
complete=all(g in by for g in required)
all_pass=complete and all(by[g]["status"]=="PASS" for g in required)
doc={
  "record_type":"UNI10_EXTERNAL_CERTIFICATION_GATES_1_5_RUN",
  "phase":phase,
  "required_gates":required,
  "gates":rows,
  "all_gates_1_5_pass":all_pass,
  "gate_6_external_trust_anchor":"OPEN_NOT_EXECUTED_BY_GITHUB_RUNNER",
  "formal_external_certification":"NOT_CLAIMED",
  "promotion":"FORBIDDEN_UNTIL_GATE_6_AND_FINAL_INDEPENDENT_CERTIFICATION_CLOSE"
}
out.write_text(json.dumps(doc,indent=2)+"\n")
print(json.dumps(doc,indent=2))
sys.exit(0 if all_pass else 1)

#!/usr/bin/env python3
import json, hashlib, sys, zipfile
from pathlib import Path

root=Path(sys.argv[1])
outdir=Path(sys.argv[2])
outdir.mkdir(parents=True,exist_ok=True)
phases={}
for phase in ("execution","recheck"):
    candidates=list(root.rglob(f"{phase}/GATE_MATRIX.json"))
    if not candidates:
        candidates=list(root.rglob("GATE_MATRIX.json"))
        candidates=[p for p in candidates if phase in str(p)]
    if not candidates:
        raise SystemExit(f"Missing {phase} GATE_MATRIX.json")
    phases[phase]=json.loads(candidates[0].read_text())

gates=["G01_LEAN","G02_COMPARATOR","G03_NANODA","G04_TLC","G05_LRAT"]
def idx(doc): return {x["gate"]:x for x in doc["gates"]}
a,b=idx(phases["execution"]),idx(phases["recheck"])
combined=[]
for g in gates:
    s1=a.get(g,{}).get("status","MISSING")
    s2=b.get(g,{}).get("status","MISSING")
    combined.append({
      "gate":g,
      "execution_status":s1,
      "independent_recheck_status":s2,
      "combined_status":"PASS" if s1=="PASS" and s2=="PASS" else "NOT_PASS"
    })
all15=all(x["combined_status"]=="PASS" for x in combined)
summary={
 "record_type":"UNI10_EXTERNAL_CERTIFICATION_GITHUB_TECHNICAL_EVIDENCE_SUMMARY",
 "completion_sha256":"927b228156c3c5fdc817019dacf9155fc33b07a1db0059ffbc81a92951eadf2b",
 "gates_1_5":combined,
 "all_gates_1_5_execution_and_recheck_pass":all15,
 "gate_6_external_signer_trust_anchor":{
   "status":"OPEN",
   "reason":"GitHub technical runner intentionally does not authenticate the pre-existing embedded Ed25519 signer identity."
 },
 "external_certification_final_package_created":False,
 "formal_promotion_candidate_allowed":False,
 "next_step":"Close Gate 6 with an independently authenticated trust anchor, then perform final certification-package verification."
}
sp=outdir/"TECHNICAL_CERTIFICATION_SUMMARY.json"
sp.write_text(json.dumps(summary,indent=2)+"\n")

# Package all downloaded evidence + summary.
zpath=outdir/"UNI10_EXTERNAL_CERTIFICATION_GATES_1_5_EVIDENCE.zip"
with zipfile.ZipFile(zpath,"w",zipfile.ZIP_DEFLATED) as z:
    z.write(sp, sp.name)
    for p in sorted(root.rglob("*")):
        if p.is_file():
            z.write(p, str(Path("raw_evidence")/p.relative_to(root)))
h=hashlib.sha256(zpath.read_bytes()).hexdigest()
(outdir/(zpath.name+".sha256")).write_text(f"{h}  {zpath.name}\n")
print(json.dumps(summary,indent=2))

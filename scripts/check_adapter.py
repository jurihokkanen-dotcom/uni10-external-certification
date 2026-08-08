#!/usr/bin/env python3
import hashlib,json,re,sys
from pathlib import Path

repo=Path(__file__).resolve().parents[1]
source=Path(sys.argv[1])
adapter=Path(sys.argv[2]) if len(sys.argv) > 2 else repo/"adapter"
src=source.read_text()
manifest=json.loads((adapter/"ADAPTER_MANIFEST.json").read_text())

def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()

decl_re=re.compile(r'^\s*(?:theorem|lemma|def|abbrev|structure|inductive|axiom|opaque|namespace|end|open)\b')
thm_re=re.compile(r'^\s*theorem\s+([A-Za-z0-9_]+)\b')

def blocks(text):
    ls=text.splitlines(keepends=True)
    starts=[i for i,l in enumerate(ls) if decl_re.match(l)]+[len(ls)]
    stack=[]; out=[]
    for i in range(len(starts)-1):
        a,b=starts[i],starts[i+1]; first=ls[a]
        m=re.match(r'^\s*namespace\s+([A-Za-z0-9_.]+)\b', first)
        if m: stack.append(m.group(1)); out.append(("other",None,"".join(ls[a:b]))); continue
        if re.match(r'^\s*end\b',first):
            if stack: stack.pop()
            out.append(("other",None,"".join(ls[a:b]))); continue
        tm=thm_re.match(first)
        block="".join(ls[a:b])
        if tm:
            pos=block.find(":=")
            if pos<0: raise SystemExit("BLOCKED theorem without :=")
            q=".".join(stack+[tm.group(1)])
            out.append(("theorem",q,block))
        else:
            out.append(("other",None,block))
    return out

source_blocks=blocks(src)
source_thms={q:b for typ,q,b in source_blocks if typ=="theorem"}
errors=[]
if sha(source)!=manifest["source_sha256"]:
    errors.append("source SHA differs from frozen adapter manifest")
if len(manifest["cases"])!=48:
    errors.append("adapter case count != 48")
for c in manifest["cases"]:
    cdir=adapter/"cases"/c["case"]
    sol=cdir/"Solution.lean"; cha=cdir/"Challenge.lean"; cfgp=cdir/"config.json"
    if not sol.exists() or sha(sol)!=sha(source):
        errors.append(f"{c['case']}: Solution not byte-identical source")
        continue
    cfg=json.loads(cfgp.read_text())
    if cfg.get("theorem_names")!=[c["theorem"]] or cfg.get("enable_nanoda") is not True:
        errors.append(f"{c['case']}: config drift")
    sb=source_blocks; cb=blocks(cha.read_text())
    if len(sb)!=len(cb):
        errors.append(f"{c['case']}: declaration block count drift")
        continue
    changed=0
    for (st,sq,sblock),(ct,cq,cblock) in zip(sb,cb):
        if (st,sq)!=(ct,cq):
            errors.append(f"{c['case']}: declaration identity drift"); break
        if sblock==cblock:
            continue
        if st!="theorem" or sq!=c["theorem"]:
            errors.append(f"{c['case']}: non-target declaration changed: {sq}")
            break
        sp=sblock.find(":="); cp=cblock.find(":=")
        if sp<0 or cp<0 or sblock[:sp].rstrip()!=cblock[:cp].rstrip():
            errors.append(f"{c['case']}: target theorem statement changed")
            break
        rhs=cblock[cp:].strip()
        if rhs!=":= by\n  sorry":
            errors.append(f"{c['case']}: Challenge target replacement is not exact `:= by sorry`")
            break
        changed+=1
    if changed!=1:
        errors.append(f"{c['case']}: expected exactly one changed theorem block, got {changed}")
if errors:
    print(json.dumps({"status":"BLOCKED","errors":errors},indent=2))
    sys.exit(1)
print(json.dumps({"status":"PASS","case_count":48,"source_sha256":sha(source)},indent=2))

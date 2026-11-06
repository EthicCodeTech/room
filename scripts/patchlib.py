"""Tiny helper: apply independent text replacements, report any that did not match, never drop the ones that did."""
import sys
def patch(path, pairs):
    s = open(path).read(); missed = []
    for a, b in pairs:
        if a in s: s = s.replace(a, b, 1)
        else: missed.append(a.strip().splitlines()[0][:90])
    open(path, 'w').write(s)
    print(f"{path.split('/')[-1]}: {len(pairs)-len(missed)}/{len(pairs)} applied" + ("" if not missed else "  MISSED: " + " | ".join(missed)))

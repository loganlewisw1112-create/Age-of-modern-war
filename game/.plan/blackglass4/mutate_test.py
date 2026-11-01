"""Fault injection: each mutation plants one known fault; the auditor must flag it in the named check."""
import json, os, subprocess, sys, copy, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
BASE = json.load(open(os.path.join(HERE, "site.json")))
def F(s, i): return next(f for f in s["footprints"] if f["id"] == i)
def T(s, i): return next(t for t in s["turrets"] if t["id"] == i)
def Rd(s, i): return next(r for r in s["roads"] if r["id"] == i)
M = [
 ("A1", "barracks moved onto the depot", lambda s: F(s, "barracks_a").update(rect=[40, 150, 60, 170])),
 ("A2", "floodmast planted on the main road", lambda s: F(s, "flood_0").update(rect=[60, 130, 63, 133])),
 ("A3", "containers stacked in front of the intake door", lambda s: F(s, "containers").update(rect=[70, 34, 80, 46])),
 ("A4", "hazard lane narrowed to 5 m", lambda s: Rd(s, "h_in").update(w=5.0)),
 ("A5", "hazard post pushed into the loop corner", lambda s: F(s, "hzpost").update(rect=[150, 46, 158, 54])),
 ("A6", "footpath laid across the rail", lambda s: s["roads"].append({"id": "f_x", "cls": "foot", "w": 2.0, "oneway": False, "zone": "hazard", "pts": [[60, -4], [60, 18]]})),
 ("A7", "laser moved over the main road", lambda s: T(s, "pdl_hq").update(pos=[118, 130])),
 ("A8", "floodmast 20 m tall under the medevac approach", lambda s: s["footprints"].append({"id": "mast_x", "kind": "mast", "zone": "clean", "rect": [74, 205, 76, 207], "h": 20.0, "cls": "ops", "level": "ground"})),
 ("A8", "fuel farm moved under the cargo approach path", lambda s: F(s, "fuel").update(rect=[118, 214, 138, 234])),
 ("A9", "fuel farm moved next to the barracks", lambda s: F(s, "fuel").update(rect=[160, 98, 170, 110])),
 ("A10", "fuel rack lowered to 4 m over the roads", lambda s: next(u for u in s["utilities"] if u["id"] == "rack_fuel").update(h=4.0)),
 ("A11", "a tower removed from the east wall", lambda s: s["footprints"].remove(F(s, "t_e3"))),
 ("A12", "capture loop made a dead end", lambda s: Rd(s, "h_loop").update(pts=Rd(s, "h_loop")["pts"][:-8])),
 ("A14", "aid station pushed into the mountain", lambda s: F(s, "aid").update(rect=[-8, 104, 12, 124])),
 ("A15", "dropship sunk 1.9 m into the cargo pad", lambda s: next(pr for pr in s["props"] if pr["id"] == "p_crane").update(z=-1.85)),
 ("A16", "one corner tower swapped to a flak gun", lambda s: T(s, "t_ne.t").update(kind="flak")),
 ("A13", "dissection opened straight onto the prototype works", lambda s: s["interior"]["corridors"].append({"a": "dissect", "b": "proto", "x0": -56.0, "x1": -45.0, "z": 0.0, "h": 4.0, "cp": False, "kind": "corridor"})),
]
ok = 0
tmp = tempfile.mkdtemp()
for cid, what, fn in M:
    s = copy.deepcopy(BASE)
    fn(s)
    if cid == "A11":
        s["turrets"] = [t for t in s["turrets"] if t["on"] != "t_e3"]
    p = os.path.join(tmp, "s.json"); json.dump(s, open(p, "w"))
    env = dict(os.environ, SITE_JSON=p, AUDIT_OUT=tmp)
    subprocess.run([sys.executable, os.path.join(HERE, "audit.py")], env=env, capture_output=True)
    rep = json.load(open(os.path.join(tmp, "audit_report.json")))
    hit = next(c for c in rep["checks"] if c["id"] == cid)
    caught = len(hit["issues"]) > 0
    ok += caught
    print("%-4s %-7s %-52s -> %s" % (cid, "CAUGHT" if caught else "MISSED", what, (hit["issues"] or ["(no issue)"])[0][:90]))
print("fault injection: %d / %d caught" % (ok, len(M)))
sys.exit(0 if ok == len(M) else 1)

# G7-CNSIM7: counter-nanite strike team, operators, APCs, packages (MAX_TOKENS 750000, MAX_TOOL_CALLS 140)
Read G7_COMMON.md first. Flow name: cnsim7. Spec: G7_REFERENCE master scope sections 0, 6.1 and 6.3–6.8 (all of
them, exactly: roles, counts, one leader, 7 security gunners, APC kit, "no main weapon", side panels, remote twin .50,
caps), plus the brainstorm record B1, B8, B9, B16–B20 entries that concern the strike group. Quality bar (6.7): the most
advanced human tactical force in the game; if it moves or fights like ordinary units, that's a bug.

Pre-registered stubs (ORCH): `sim/systems/counter_nanite.gd` (after Strikes/Creep/Cores), `sim/systems/apc7.gd` (after
Counterdrone, before Combat). CNFAC7 builds the facility (training, garages, decon, dropships) in parallel: agree the
spawn and loading interface with it on the board early.

## Deliver
1. **Content** (`content/g7/defs_g7_cn.json`, all numbers PROVISIONAL): Human A and Human B only. The 20-soldier strike
   team (7 role defs: leader, second-in-command/radio, deployment specialist, scanner technician, EW specialist,
   security gunner, medic/engineer), the 8-operator tactical squad (7 role defs, two hunter-killers), the strike APC and
   the tactical APC, the 4 package kinds, weapons and kits. The unlock: a late, very expensive research item (send ORCH a
   change_request with the exact research.json entry and prerequisites: Stage 10 + an EMP/EW line). Art: use ARTCN7's
   sample sheets (assets/art/g7_cn, frame names in its manifest; art_catalog registration by change_request); the full
   art roll-out comes later, after the owner approves the look.
2. **Strike team rules:** two squads of 10 in 2 APCs, operates only as the full pair; one team leader (if the leader
   falls, squad A's second-in-command takes over); spawns inside its APCs; dismount/remount any time; tactical squads
   max 3 deployed in normal matches (a cap hook so Last Protocol can lift it).
3. **APC systems** (`apc7.gd`): unhackable flag (CREEP7's `can_hack` must refuse it); strike APC: two manned .50 cal
   mounts front and rear with shielded gunners (security gunners man them while moving; a hit gunner is replaced from
   inside), no main weapon; tactical APC: one remote twin .50; both: shield dome during deployment (recharge), active
   protection vs missiles/shells/drones, anti-drone emitter, short-range EMP pulse (also knocks off leeches), side pop-out
   panels firing interceptors, smoke and interceptor drones (limited stock, refilled at the facility), top-tier armour,
   chaff, sealed cabin, low heat signature.
4. **Packages and deployment** (`counter_nanite.gd`): loadout chosen before a mission (no field swaps); deployment
   sequence (scanner technicians find creep/seeds via CREEP7's reveal, EW specialists jam the local hive link,
   deployment specialists arm under the dome, then `Creep.purge`); deaths or the dome failing stall it; the engineers
   decide by themselves where portable barriers and unhackable sentry turrets go during the hold and pack them up after;
   **hero detonation** (one operator stays and detonates by hand: instant arming, certain death, short withdrawal window,
   call sign read out, logged for the end screen "Remembered" list). Commands: ask ORCH by change_request for the names
   you need (e.g. cn_set_loadout, cn_deploy, cn_hero_detonate, cn_dome, cn_panels).
5. **Suits and exposure:** sealed suits for strike team and operators: no exposure unless punctured (WOUND7's
   `Wounds.puncture` and bullet/close-up hits); ordinary soldiers build exposure on foot in creep; exposure hurts and slows
   until decontaminated (CNFAC7's decon zone clears it). Render fields for LOOK7 via change_request.
6. **Group movement:** use SQUAD7's `Convoy` API (fact convoy.api; SQUAD7-2 owns convoy.gd) for the motorcade (strike
   APCs in the centre, tactical APCs lead/rear/threatened flank, shielding, never stopping in a kill zone, perimeter before
   dismount, moving cover for soldiers on foot). Anything missing from the API: change_request to SQUAD7-2.

## Tests (tests/test_cnsim7.gd)
team composition and the one-leader succession; pair-only operation; spawn inside APCs, dismount/remount; tactical cap;
unhackable vs Machine hacking; dome, APS, EMP, panels and stock; no main weapon on the strike APC; loadout locked in the
field; deployment sequence and stalls; hero detonation; suit puncture and exposure; same seed twice = same hash; a match
without the unlock is hash-identical to before; sim cost with a full group reported.
Playtest flow tools/pt7_cnsim7.gd: research the unlock (debug), the full group in convoy taking contact, a deployment
with the dome up purging creep, a hero detonation; shots of each plus a 10-shot strip of the convoy.

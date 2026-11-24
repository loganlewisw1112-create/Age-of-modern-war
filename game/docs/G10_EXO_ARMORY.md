# G10 Exo Armory — owner-frozen design

**Owner freeze (2026-11-23 Q&A).** Subordinate to `G10_SCOPE.md`. Art: `G10_GHOST_LOOK.md`. Implementation only after G10 APPROVE.

## Purpose

Ghost Wing outfits exo units and squads with specialized weapons, armor, gear, attachments and armor upgrades through an **Exo Armory** building. Catalog items are unlockables: some pre-unlocked, some earned. The Armory is a Coalition-only strategic bottleneck—not a Human A CN facility and never a counter-nanite path.

## Owner Q&A locks

| Topic | Decision |
|-------|----------|
| Refit location | **Heavy refits only at Armory.** Field kits from mule/APC are **light only**. |
| Pay / unlock | **Mixed.** Starters free/cheap. Elite = contracts **and** steal/unseal/reliquary. |
| UX depth | **Presets first** → later **mix-and-match** → later **per-squad / per-operator** kits. |
| Field kits | Ammo / battery / one attachment-class swap; strength scales with **tactical mission importance**; never a full Armory refit. |
| Bay capacity | Start **2–3** bays; each bay outfits a full **4**-op squad; upgrade up to **+3** → **6 bays max** per Armory. |
| Armory destroyed | **Harsh:** suits **in-bay** destroyed/captured; Ghosts already in the field keep current kit; no new heavy refits until rebuilt. |
| Who builds | **Coalition only.** Enemies may **raid for unlock intel / parts**; they **never** outfit Ghosts. |
| Stage bands | **1–6** scavenged locker (**1 bay**) → **7–10** full Armory (**2–3 bays**) → **11–13** black Armory (up to **6**). |

## Building stages

### Stages 1–6 — Scavenged locker
- One bay; limited preset catalog (Mk I / scavenged kits only).
- Looks field-jury-rigged under Ghost clean rules (patched charcoal, exposed debt stripe).
- No mix-and-match; presets only.

### Stages 7–10 — Full Exo Armory
- Starts with **2–3** bays (owner may choose 2 or 3 at build; default **3** if unspecified).
- Each bay = one **4-op** squad parallel outfit.
- Bay upgrades purchaseable up toward stage cap; full **6** reserved for late black Armory unless an interim upgrade path is unlocked via contracts.
- Presets + gated mix-and-match unlock.

### Stages 11–13 — Black Armory
- Up to **6** bays; Mk III / ace catalogs; full per-operator kit editing when unlocked.
- Highest raid value; heat and false-flag interactions apply if Atrocity doctrine is active.

## Placement and look

- Sits on the Ghost wing / vault campus (capability **24**): surface hatch + underground outfit floor.
- Visual: void charcoal, cold-bone trim, patron-gold debt stripe; sealed bay doors; suit racks as glass coffins adjacent to Reliquary (**27**).
- Readable tells: bay occupancy lights, shimmer when a suit swaps battery (**53**), alarm when raided.

## Outfit categories

1. **Primary weapons** — suppressed smart-rifle families; Judge-only backdoor arms (**56**); Shade marksman; Warden support.
2. **Secondary / tools** — breach kits (**20** soft/hard/collapse); EMP scalpel (**21**); backdoor spikes (**22**).
3. **Armor / plates** — hardened joints (**52**); Warden petals; Shade cloak panels; role-locked incompatibilities.
4. **Attachments** — optics, suppressors, underbarrel; battery taps for dual-cell (**53**).
5. **Gear** — spider deploy (**37**); Reaper link / magazine (**38/40**); mule call; execution kit (**60**).
6. **Suit firmware** — pack hierarchy radio (**59**); Conductor mesh privileges (**7**); contract-gated ROE chips (**28/47**).

### Compatibility (hard rules)
- Shade cannot take Warden heavy plates or heavy primary.
- Judge cannot take Warden corridor kit.
- Backdoor ammo only validates against Syndicate-sold compromised hardware (**22**).
- Hardpoint conflicts from black-budget modular suits (**3**) remain; Armory cannot stack incompatible ports.
- No Counter-Nanite, Human A CN suits, or Machine hive firmware.

## Unlock model

### Pre-unlocked
- Role starter presets: Strike / Assault / Recon (+ Judge / Warden / Shade when those roles exist).
- Basic ammo, battery, one common optic.

### Earned / unlock paths (may combine)
- **Contracts (**28/47**):** Surgical unlocks mid catalogs; Atrocity unlocks cruel kits and False Flag chain items.
- **Steal / unseal:** vault and raid loot opens elite attachment rows.
- **Reliquary (**27**):** consume tagged recovered tech for one allow-listed non-stacking upgrade.
- **Blood debt (**5**):** recovering suits can refund or unlock refit efficiency; abandoning suits raises Armory costs.
- **Aces (**64**):** named operators unlock unique preset rows (3 early → +6 → final campaign unlock via G15 mapping).

PROVISIONAL costs/times live in `rules_g10_exo_armory.json` at implementation.

## Orders / UX

- Commands (proposed): `exo_armory_outfit`, `exo_armory_preset`, `exo_armory_bay_upgrade`, `exo_field_kit` (mule/APC only).
- Early UI: pick a **preset** for the squad assigned to a bay.
- Mid unlock: **mix-and-match** slots with compatibility matrix warnings.
- Late unlock: **per-operator** kits within a squad (Sergeant may queue juniors into bays — **59**).
- Field kit UI: one light action; magnitude from Conductor/mission-importance score (intel card priority, HVT tier, heat).

## Combat / strategic consequences

- Armory is a high-value raid target; losing it mid-match is catastrophic for suits in-bay (**harsh rule**).
- Field Ghosts retain kits → survivors can still fight, but cannot re-role until rebuilt.
- Enemy raid yields **intel fragments / parts** toward Counter-Ghost understanding—not Ghost outfit rights.
- Heat (**29**) can slow bay times or lock Atrocity presets when map alert is high (PROVISIONAL).

## Acceptance (draft Done-when fragments)

1. Coalition-only build; Human A/B/Machine cannot construct or use outfit commands.
2. Stage locker vs full vs black Armory bay caps enforced (1 → 2–3 → ≤6).
3. Each bay outfits exactly one 4-op squad in parallel; upgrade path reaches 6 only when rules allow.
4. Heavy refit requires Armory bay; field kit path limited to ammo/battery/one attachment-class and mission-scaled.
5. Destroyed Armory: in-bay suits removed/captured; field kits persist; outfit commands fail until rebuild.
6. Unlock gates: preset → mix-match → per-op; contract/reliquary/steal paths tested; CN denial holds.
7. Look checkpoint includes Armory hatch, bay lights, and occupied-suit racks per `G10_GHOST_LOOK.md`.

## Plan hook

Implementation tasks live in `docs/superpowers/plans/2026-11-23-g10-shadow-coalition.md` (Exo Armory task under Ghost / buildings pillars).

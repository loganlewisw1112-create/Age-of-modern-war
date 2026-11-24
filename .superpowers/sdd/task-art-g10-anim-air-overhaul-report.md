# ART10 — G10 anim + air overhaul (post-`g10.lock`)

**Agent:** ART10 · **Branch:** g71 · **Date:** 2026-11-24  
**Kind:** Post-lock art amendment (owner demand after `g10.lock` CLOSED)

## Inventory (pre-overhaul)

| Air id | Prior art approach | Problem |
|--------|--------------------|---------|
| `x_patron_cas` | Unique fixed-wing CAS drawer | OK role; needed anim frames |
| `x_silent_rotor` | **CAS clone** + teal band mark + idle/gunship polish | Shared silhouette |
| `x_stealth_transport` | **CAS clone** + band + open-door polish | Shared silhouette |
| `x_stealth_drone` | **CAS clone** + tip polish | Shared silhouette |
| `x_shock_drone` | **CAS clone** + tip polish | Shared silhouette |
| `x_recon_drone` | **CAS clone** + tip polish | Shared silhouette |

Infantry/Ghost movement: **camo-token strips** (`rest/walk/sprint/fire/hit/battery/shield` oil-slick overlays) — not Human A pose boards.

Deferred (unchanged): TECHNICAL / SAFEHOUSE / HATCH.

## Done

### 1. Real animation boards (Human A quality)

- CELL / DEATH / WALKER / Ghost Wing sheets now use **real FIG poses**:  
  `idle · walk_a · walk_b · run_0 · fire · hit(=wounded) · die_0`
- Ghost legacy `states` keys remapped to **pose crops** from the anim board (`camo_is_anim_crop`), not token slick overlays.
- Air sheets: `idle · flight · fire · hit`

### 2. Unique air redesigns (black / gunmetal)

| Id | Identity |
|----|----------|
| `x_patron_cas` | Fixed-wing swept-delta **attack CAS** — no rotors; chin EO + wing guns (role kept) |
| `x_silent_rotor` | Slender **quiet-insert helo** — main rotor disc + fenestron, stub gun pods |
| `x_stealth_transport` | **Large** angular flying-wing cargo VTOL — twin tip ducts, rear ramp |
| `x_stealth_drone` | Flat **diamond flying-wing UCAV** — serrated TE, no rotors |
| `x_shock_drone` | Compact **X-frame multi-rotor** striker — chin gun + rotor arms |
| `x_recon_drone` | **Tiny** high-wing spyglass — boom EO pod, twin-boom H-tail, no rotors |

Sizes deliberately stratified: transport > CAS ≈ silent > shock > stealth drone > recon.

### 3. Boards / strips (`game/.plan/shots/G71_LOOK/`)

- `board_g10_anim_cell.png` (+`_2x`)
- `board_g10_anim_death.png` (+`_2x`)
- `board_g10_anim_walker.png` (+`_2x`)
- `board_g10_anim_infantry.png` (+`_2x`)
- `board_g10_anim_air_fleet.png` (+`_2x`)
- `strip_g10_air_unique.png` (+`_2x`) — idle vs fire silhouette proof
- `strip_g10_air_facings.png` (+`_2x`)
- `strip_g10_air_states.png` (+`_2x`) — per-id anim columns
- `strip_g10_ghost_anim.png` (+`_2x`) — pose crops (also refreshes legacy camo strip path)

### 4. Wiring / tests

- Generators: `game/tools/art/g10_coalition_air.gd` (new), `g10_coalition_samples.gd`, `g10_coalition.gd` (`bulk_wave: 4`)
- Catalog: `game/assets/art/g10_coalition/` regenerated (unique air + multi-frame sheets)
- `test_g10_content` **15/0** (anim frame coverage + MD5 silhouette uniqueness across all 6 air ids)

## Lock note

**`g10.lock` may need an amend FACT.** This ship is a post-lock owner art amendment: approved-core kit grammar kept (CELL/DEATH/WALKER black Human A; CLOSE AIR remains attack-CAS), but air silhouettes and movement boards supersede wave3 camo/CAS-clone polish recorded at lock time.

## Commit / remote

- **Commit:** `5354846f` — *Overhaul G10 anim boards and unique Coalition air silhouettes.*
- Board FACT `ship.art.g10.anim_air_overhaul` seq **294**
- Remote: `github/g71`

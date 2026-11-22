//! rts_core: deterministic native helpers for the RTS sim (CONTRACTS_G3b section 5).
//!
//! Hard rules (CONTRACTS_G3b section 0): every loop runs in ascending input-index order (callers
//! pass entities in ascending id order), no hash-map iteration order is ever observable, no
//! threads inside a call (built with gdext experimental-threads so a SimWorld may step on a worker,
//! CONTRACTS_G4 s3), no wall-clock time, no RNG. Floats are plain IEEE f32/f64 (no fast-math).
//!
//! Classes (all RefCounted, Packed-array API only):
//!   RtsGrid  - uniform spatial hash: rebuild / query_radius / nearest_enemy_batch
//!   RtsNav   - per-move-class (+ per-team gate) passability + weights, A*, components, flow fields
//!   RtsSteer - batch movement tick (path advance + separation) against an RtsNav grid
//!   RtsFog   - stateless fog circle stamping (fog.gd, PERF4-2 CR 890)
//!   RtsCombat - stateless line-of-fire (damage.gd line_clear) + batch helpers for combat.gd
//!   RtsFormation - exact formations7.gd big-group assignment polish (G7 PERF7K, 0.5.4)
//!   RtsSpot - exact senses7.gd spot pass ring search + _sees without smoke (G7 PERF7L, 0.5.5)
//!   RtsSwarmDraw - entity_layer.gd unit kernel for plain units on motion-layer frames (G7.1 SWARMNAT71, 0.6.4; display only)

use godot::prelude::*;

mod advance;
mod combat;
mod combat_prep;
mod fastdict;
mod find;
mod fog;
mod fog_gather;
mod formation;
mod gather;
mod mirror;
mod grid;
mod spot;
mod morale_scan;
mod nav;
mod steer;
mod swarm_draw;

struct RtsCore;

#[gdextension]
unsafe impl ExtensionLibrary for RtsCore {}

/// Small info object so GDScript can print what was loaded.
#[derive(GodotClass)]
#[class(base = RefCounted, init)]
pub struct RtsCoreInfo {}

#[godot_api]
impl RtsCoreInfo {
    /// Crate version string, e.g. "rts_core 0.1.0".
    #[func]
    fn version() -> GString {
        GString::from(concat!("rts_core ", env!("CARGO_PKG_VERSION")).to_string().as_str())
    }
}

//! rts_core: deterministic native helpers for the RTS sim (CONTRACTS_G3b section 5).
//!
//! Hard rules (CONTRACTS_G3b section 0): every loop runs in ascending input-index order (callers
//! pass entities in ascending id order), no hash-map iteration order is ever observable, no
//! threads, no wall-clock time, no RNG. Floats are plain IEEE f32/f64 (no fast-math).
//!
//! Classes (all RefCounted, Packed-array API only):
//!   RtsGrid  - uniform spatial hash: rebuild / query_radius / nearest_enemy_batch
//!   RtsNav   - per-move-class passability + weights, A*, connected components, flow fields
//!   RtsSteer - batch movement tick (path advance + separation) against an RtsNav grid

use godot::prelude::*;

mod advance;
mod grid;
mod nav;
mod steer;

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

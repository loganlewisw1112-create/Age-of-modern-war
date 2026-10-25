//! G5 CORE10K: pointer-level reads of entity Dictionaries for the hot loops (no Variant clones).
//! A Godot 4 Variant is 24 bytes: i32 type at offset 0, payload at offset 8 (int64 / double / two
//! f32 for Vector2 / the Dictionary or Array object, whose only member is its private pointer).
//! Only keys that every unit dict always holds (id, pos, path) are read through
//! dictionary_operator_index_const (it must not be used for a missing key); optional keys keep the
//! Variant::get_named path. Read-only: nothing here writes Godot memory.

use godot::prelude::*;
use godot::sys::{self, GodotFfi};

#[derive(Clone, Copy)]
pub struct VP(pub *const u8);

impl VP {
    #[inline]
    pub fn is_null(&self) -> bool {
        self.0.is_null()
    }
    #[inline]
    pub unsafe fn ty(&self) -> i32 {
        *(self.0 as *const i32)
    }
    #[inline]
    unsafe fn data(&self) -> *const u8 {
        self.0.add(8)
    }
    /// GDScript int(v) for int / float / bool (else 0).
    #[inline]
    pub unsafe fn int(&self) -> i64 {
        let t = self.ty();
        if t == VariantType::INT.ord() {
            *(self.data() as *const i64)
        } else if t == VariantType::FLOAT.ord() {
            *(self.data() as *const f64) as i64
        } else if t == VariantType::BOOL.ord() {
            (*self.data() != 0) as i64
        } else {
            0
        }
    }
    #[inline]
    pub unsafe fn v2(&self) -> Option<Vector2> {
        if self.ty() == VariantType::VECTOR2.ord() {
            let d = self.data() as *const f32;
            Some(Vector2::new(*d, *d.add(1)))
        } else {
            None
        }
    }
    /// Identity of a reference payload (Array / Dictionary private pointer), as is_same() compares.
    #[inline]
    pub unsafe fn ref_id(&self) -> usize {
        *(self.data() as *const usize)
    }
    /// The Dictionary type pointer inside this Variant (None if it is not a Dictionary).
    #[inline]
    pub unsafe fn dict(&self) -> Option<sys::GDExtensionConstTypePtr> {
        if self.ty() == VariantType::DICTIONARY.ord() { Some(self.data() as sys::GDExtensionConstTypePtr) } else { None }
    }
}

/// &arr[i] (no clone). i must be in range.
#[inline]
pub unsafe fn arr_at(arr: &VarArray, i: usize) -> VP {
    VP(sys::interface_fn!(array_operator_index_const)(arr.sys() as sys::GDExtensionConstTypePtr, i as sys::GDExtensionInt) as *const u8)
}

/// &dict[key] for a key the dict is known to hold (no clone).
#[inline]
pub unsafe fn dget(d: sys::GDExtensionConstTypePtr, key: &Variant) -> VP {
    VP(sys::interface_fn!(dictionary_operator_index_const)(d, key.var_sys()) as *const u8)
}

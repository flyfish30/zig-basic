const std = @import("std");
const simd = @import("simd_core.zig");

const target = @import("builtin").target;
const arch = target.cpu.arch;

const VecLen = simd.VecLen;
const VecType = simd.VecType;

const c = @cImport(
    @cInclude("wasm_simd128.h"),
);

pub const SimdSamples = struct {
    pub fn binOpI16x8(vec1: simd.I16x8, vec2: simd.I16x8) simd.I16x8 {
        const acc = c.wasm_i16x8_mul(vec1, vec2);
        return acc;
    }
};

pub fn tableLookupBytes(tbl: @Vector(VecLen(u8), u8), idx: @Vector(VecLen(i8), i8)) @Vector(VecLen(u8), u8) {
    return c.wasm_i8x16_swizzle(tbl, idx);
}

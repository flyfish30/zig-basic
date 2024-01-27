const std = @import("std");
const simd = @import("simd_sample.zig");

const target = @import("builtin").target;
const arch = target.cpu.arch;

const c = @cImport(
    @cInclude("immintrin.h"),
);

pub const SimdSamples = struct {
    pub fn binOpI16x8(vec1: simd.I16x8, vec2: simd.I16x8) simd.I16x8 {
        const acc = c._mm_mullo_epi16(@bitCast(vec1), @bitCast(vec2));
        return @bitCast(acc);
    }
};

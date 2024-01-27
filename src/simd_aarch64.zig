const std = @import("std");
const simd = @import("simd_sample.zig");

const target = @import("builtin").target;
const arch = target.cpu.arch;

const c = @cImport(
    @cInclude("arm_neon.h"),
);

pub const SimdSamples = struct {
    pub fn binOpI16x8(vec1: simd.I16x8, vec2: simd.I16x8) simd.I16x8 {
        const acc = c.vmulq_s16(vec1, vec2);
        return acc;
    }
};

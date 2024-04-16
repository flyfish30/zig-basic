const std = @import("std");
const simd = @import("simd_core.zig");

const VecLen = simd.VecLen;
const VecType = simd.VecType;

const target = @import("builtin").target;
const arch = target.cpu.arch;

const c = @cImport(
    @cInclude("arm_neon.h"),
);

pub const SimdSamples = struct {
    pub fn binOpI16x8(vec1: simd.I16x8, vec2: simd.I16x8) simd.I16x8 {
        const acc = vec1 * vec2;
        return acc;
    }
};

pub fn tableLookupBytes(tbl: @Vector(VecLen(u8), u8), idx: @Vector(VecLen(i8), i8)) @Vector(VecLen(u8), u8) {
    comptime var i = 0;
    var out_vec: @Vector(VecLen(u8), u8) = undefined;

    inline while (i < comptime VecLen(i8)) : (i += 1) {
        out_vec[i] = if (idx[i] < 0) 0 else tbl[@intCast(idx[i])];
    }

    return out_vec;
}

pub fn tableLookup128Bytes(tbl: @Vector(16, u8), idx: @Vector(16, i8)) @TypeOf(tbl) {
    comptime var i = 0;
    var out_vec: @Vector(16, u8) = undefined;

    inline while (i < 16) : (i += 1) {
        out_vec[i] = if (idx[i] < 0) 0 else tbl[@intCast(idx[i])];
    }

    return out_vec;
}

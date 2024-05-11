const std = @import("std");
const simd = @import("simd_core.zig");
const simdg = @import("simd_generic.zig");

const target = @import("builtin").target;
const arch = target.cpu.arch;

const VEC_BITS_LEN = simd.VEC_BITS_LEN;
const VecLen = simd.VecLen;
const VecType = simd.VecType;

const VectorIndex = std.simd.VectorIndex;
const VecU8Index = VectorIndex(@Vector(VecLen(u8), u8));

const c = @cImport({
    @cDefine("IN_ZIG_INCLUDE", "");
    @cInclude("wasm_simd128_intrins.h");
});

pub const SimdSamples = struct {
    pub fn binOpI16x8(vec1: simd.I16x8, vec2: simd.I16x8) simd.I16x8 {
        // const acc = c.wasm_i16x8_mul(vec1, vec2);

        const acc = vec1;
        _ = vec2;
        return acc;
    }
};

/// Get the mask of @Vector(VecLen(T), bool) that have consecutive n bits is 1
/// from lsb.
pub fn maskFirstN(comptime T: type, n: usize) @Vector(VecLen(T), bool) {
    return simdg.maskFirstN(T, n);
}

pub fn maskedLoadVecOr(comptime T: type, val_vec: @Vector(VecLen(T), T), mask: @Vector(VecLen(T), bool), buf: []T) @Vector(VecLen(T), T) {
    return simdg.maskedLoadVecOr(T, val_vec, mask, buf);
}

pub fn maskedLoadVec(comptime T: type, mask: @Vector(VecLen(T), bool), buf: []T) @Vector(VecLen(T), T) {
    return simdg.maskedLoadVec(T, mask, buf);
}

pub fn maskedStoreVec(comptime T: type, mask: @Vector(VecLen(T), bool), buf: []T, vec: @Vector(VecLen(T), T)) void {
    simdg.maskedStoreVec(T, mask, buf, vec);
}

pub fn blendedLoadVecOr(comptime T: type, val_vec: @Vector(VecLen(T), T), mask: @Vector(VecLen(T), bool), buf: []T) @Vector(VecLen(T), T) {
    return simdg.blendedLoadVecOr(T, val_vec, mask, buf);
}

pub fn blendedLoadVec(comptime T: type, mask: @Vector(VecLen(T), bool), buf: []T) @Vector(VecLen(T), T) {
    return simdg.blendedLoadVec(T, mask, buf);
}

pub fn blendedStoreVec(comptime T: type, mask: @Vector(VecLen(T), bool), buf: []T, vec: @Vector(VecLen(T), T)) void {
    simdg.blendedStoreVec(T, mask, buf, vec);
}

inline fn wasm_shuffle_u8(vec: @Vector(VecLen(u8), u8), idx: @Vector(VecLen(i8), i8)) @TypeOf(vec) {
    return @bitCast(c.wasm128_shuffle_u8(@bitCast(vec), @bitCast(idx)));
}

pub fn tableLookupBytes(tbl: @Vector(VecLen(u8), u8), idx: @Vector(VecLen(i8), i8)) @Vector(VecLen(u8), u8) {
    return wasm_shuffle_u8(tbl, idx);
}

pub fn tableLookup16Bytes(tbl: @Vector(16, u8), idx: @Vector(16, i8)) @TypeOf(tbl) {
    // wasm32 has 128 bits vector
    return wasm_shuffle_u8(tbl, idx);
}

/// Elements are shifted rightwards (towards higher indices). The shifted most
/// lowest elements will filled zero.
pub fn shiftRightVec(comptime T: type, vec: @Vector(VecLen(T), T), count: VectorIndex(@TypeOf(vec))) @TypeOf(vec) {
    comptime var bit_count: usize = undefined;

    bit_count = switch (@typeInfo(T)) {
        .Int => |info| info.bits,
        .Float => |info| info.bits,
        else => @compileError("shiftRightVec not support type: " ++ @typeName(T)),
    };

    switch (bit_count) {
        8 => {
            const vec_u8: @Vector(VecLen(u8), u8) = @bitCast(vec);
            return @bitCast(shiftRightVecU8(vec_u8, count));
        },
        16 => {
            const vec_u8: @Vector(VecLen(u8), u8) = @bitCast(vec);
            return @bitCast(shiftRightVecU8(vec_u8, @as(VecU8Index, count) * 2));
        },
        32 => {
            const vec_u8: @Vector(VecLen(u8), u8) = @bitCast(vec);
            return @bitCast(shiftRightVecU8(vec_u8, @as(VecU8Index, count) * 4));
        },
        64 => {
            const vec_u8: @Vector(VecLen(u8), u8) = @bitCast(vec);
            return @bitCast(shiftRightVecU8(vec_u8, @as(VecU8Index, count) * 8));
        },
        else => @compileError("shiftRightVec not support type: " ++ @typeName(T)),
    }
}

/// Elements are shifted leftwards (towards lower indices). The shifted most
/// highest elements will filled zero.
pub fn shiftLeftVec(comptime T: type, vec: @Vector(VecLen(T), T), count: VectorIndex(@TypeOf(vec))) @TypeOf(vec) {
    comptime var bit_count: usize = undefined;

    bit_count = switch (@typeInfo(T)) {
        .Int => |info| info.bits,
        .Float => |info| info.bits,
        else => @compileError("shiftLeftVec not support type: " ++ @typeName(T)),
    };

    switch (bit_count) {
        8 => {
            const vec_u8: @Vector(VecLen(u8), u8) = @bitCast(vec);
            return @bitCast(shiftLeftVecU8(vec_u8, count));
        },
        16 => {
            const vec_u8: @Vector(VecLen(u8), u8) = @bitCast(vec);
            return @bitCast(shiftLeftVecU8(vec_u8, @as(VecU8Index, count) * 2));
        },
        32 => {
            const vec_u8: @Vector(VecLen(u8), u8) = @bitCast(vec);
            return @bitCast(shiftLeftVecU8(vec_u8, @as(VecU8Index, count) * 4));
        },
        64 => {
            const vec_u8: @Vector(VecLen(u8), u8) = @bitCast(vec);
            return @bitCast(shiftLeftVecU8(vec_u8, @as(VecU8Index, count) * 8));
        },
        else => @compileError("shiftLeftVec not support type: " ++ @typeName(T)),
    }
}

fn shiftRightVecU8(vec: @Vector(VecLen(u8), u8), count: VectorIndex(@TypeOf(vec))) @TypeOf(vec) {
    const asc_idx = std.simd.iota(i8, 16);
    // if index < 0, then result byte is 0
    const idx0: @Vector(16, i8) = asc_idx - @as(@Vector(16, i8), @splat(@intCast(count)));
    return wasm_shuffle_u8(vec, idx0);
}

fn shiftLeftVecU8(vec: @Vector(VecLen(u8), u8), count: VectorIndex(@TypeOf(vec))) @TypeOf(vec) {
    const count_n = 16 - @as(u8, count);

    const asc_idx = std.simd.iota(i8, 16);
    const asc_idx_u: @Vector(16, u8) = @bitCast(asc_idx);
    // when index >= 16, the result byte is 0,
    // idx1_u is [16-n, 16-n+1, .. 16 - 1, 16, 17, ..]
    const idx0_u: @Vector(16, u8) = asc_idx_u +% @as(@Vector(16, u8), @splat(count_n));
    const idx0: @Vector(16, i8) = @bitCast(idx0_u);
    return wasm_shuffle_u8(vec, idx0);
}

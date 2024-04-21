const std = @import("std");
const simd = @import("simd_core.zig");

const builtin = @import("builtin");
const target = builtin.target;
const arch = target.cpu.arch;

const assert = std.debug.assert;

const VEC_BITS_LEN = simd.VEC_BITS_LEN;
const VecLen = simd.VecLen;
const VecType = simd.VecType;
const vectorLength = simd.vectorLength;
const VecChild = simd.VecChild;

fn Pair(comptime VType: type) type {
    return struct { VType, VType };
}

pub fn packSelectLeft(vec: anytype, mask: @Vector(vectorLength(@TypeOf(vec)), bool)) @TypeOf(vec) {
    return packSelect(vec, mask)[0];
}

pub fn packSelect(vec: anytype, mask: @Vector(vectorLength(@TypeOf(vec)), bool)) Pair(@TypeOf(vec)) {
    return packSelectGeneric(vec, mask);
}

fn packSelectGeneric(vec: anytype, mask: @Vector(vectorLength(@TypeOf(vec)), bool)) Pair(@TypeOf(vec)) {
    const Child = VecChild(@TypeOf(vec));
    const vecLen = comptime vectorLength(@TypeOf(vec));
    // var int_mask = @as(std.meta.Int(.unsigned, vecLen), @bitCast(mask));
    // std.debug.print("packSelect int_mask is: 0b{b:0>32}\n", .{int_mask});

    switch (VEC_BITS_LEN) {
        128 => {
            return packSelectVec128(vec, mask);
        },
        256 => {
            const mask0: @Vector(vecLen / 2, bool) = std.simd.extract(mask, 0, vecLen / 2);
            const mask1: @Vector(vecLen / 2, bool) = std.simd.extract(mask, vecLen / 2, vecLen / 2);
            const mask0_u: u32 = @as(std.meta.Int(.unsigned, vecLen / 2), @bitCast(mask0));
            const mask1_u: u32 = @as(std.meta.Int(.unsigned, vecLen / 2), @bitCast(mask1));
            const count0 = @popCount(mask0_u);
            const count1 = @popCount(mask1_u);

            const vec0_pair = packSelectVec128(std.simd.extract(vec, 0, vecLen / 2), mask0);
            const vec1_pair = packSelectVec128(std.simd.extract(vec, vecLen / 2, vecLen / 2), mask1);

            var vec_lane: [vecLen * 2]Child align(64) = undefined;
            vec_lane[0 .. vecLen / 2].* = vec0_pair[0];
            vec_lane[count0..][0 .. vecLen / 2].* = vec1_pair[0];
            vec_lane[vecLen * 3 / 2 .. vecLen * 2].* = vec1_pair[1];
            vec_lane[vecLen + count1 ..][0 .. vecLen / 2].* = vec0_pair[1];
            return .{ @bitCast(std.simd.extract(vec_lane, 0, vecLen)), @bitCast(std.simd.extract(vec_lane, vecLen, vecLen)) };
        },
        else => @compileError(std.fmt.comptimePrint("packSelectLeftGeneric can not support {d} bits vector", .{VEC_BITS_LEN})),
    }
}

fn packSelectVec128(vec: anytype, mask: @Vector(vectorLength(@TypeOf(vec)), bool)) Pair(@TypeOf(vec)) {
    const Child = VecChild(@TypeOf(vec));
    const vecLen = comptime vectorLength(@TypeOf(vec));

    switch (@bitSizeOf(Child)) {
        8 => {
            const mask_u: u32 = @as(std.meta.Int(.unsigned, vecLen), @bitCast(mask));
            const mask0_u: u32 = mask_u & 0xff;
            const mask1_u: u32 = (mask_u >> 8) & 0xff;
            const count0 = @popCount(mask0_u);
            const count1 = @popCount(mask1_u);

            const idx: @Vector(16, i8) = @bitCast(idxFromBits128(u8, mask_u));
            const pack_2vec = simd.tableLookup128Bytes(vec, idx);
            const vec0: @Vector(8, u8) = @bitCast(std.simd.extract(pack_2vec, 0, 8));
            const vec1: @Vector(8, u8) = @bitCast(std.simd.extract(pack_2vec, 8, 8));

            // vec0 and vec1 layout is bellow
            // packSelect left   <-- | -->      packSelect right
            // [ 0, 1, .. count0 - 1,  count0, count0 + 1, .., 7 ]
            var vec_lane: [vecLen * 2]Child align(64) = undefined;
            vec_lane[0 .. vecLen / 2].* = vec0;
            vec_lane[count0..][0 .. vecLen / 2].* = vec1;
            vec_lane[vecLen * 3 / 2 .. vecLen * 2].* = vec1;
            vec_lane[vecLen + count1 ..][0 .. vecLen / 2].* = vec0;
            return .{ @bitCast(std.simd.extract(vec_lane, 0, vecLen)), @bitCast(std.simd.extract(vec_lane, vecLen, vecLen)) };
        },
        16, 32, 64 => {
            const mask_u: u64 = @as(std.meta.Int(.unsigned, vecLen), @bitCast(mask));
            const idx: @Vector(16, i8) = @bitCast(idxFromBits128(Child, mask_u));
            const packed_vec = simd.tableLookup128Bytes(@as(@Vector(16, u8), @bitCast(vec)), idx);
            // packed_vec layout is bellow
            // count = @popCount(mask_u)
            // packSelect left  <-- | -->             packSelect right
            // [ 0, 1, .. count - 1,  count, count + 1, .., vecLen - 1 ]
            return .{ @bitCast(packed_vec), @bitCast(packed_vec) };
        },
        else => @compileError("packSelectVec128 can not support element type: " ++ @typeName(Child)),
    }

    return vec;
}

const table8x16: [256 * 8]u8 align(16) = table_indices: {
    comptime var indices: @Vector(256 * 8, u8) = table16x8[0 .. 256 * 8].*;
    indices /= @splat(2);
    break :table_indices @bitCast(indices);
};

// Some cpu simd extention(Neon, SSE4, AVX, .etc) not provide an equivalent
// of AVX512 permutex2var, so we need byte indices for lookup table instruction
// (one vector's worth for each of 256 combinations of 8 mask bits).
// Loading them directly would require 4 KiB. We can instead store lane indices
// and convert to byte indices (2*lane + 0..1), with the doubling baked into
// the table. AVX2 Compress32 stores eight 4-bit lane indices (total 1 KiB),
// broadcasts them into each 32-bit lane and shifts. Here, 16-bit lanes are too
// narrow to hold all bits, and unpacking nibbles is likely more costly than
// the higher cache footprint from storing bytes.
const table16x8: [256 * 8]u8 align(16) = .{
    // PrintCompress16x8Tables
    0, 2, 4, 6, 8, 10, 12, 14, 0, 2, 4, 6, 8, 10, 12, 14, //
    2, 0, 4, 6, 8, 10, 12, 14, 0, 2, 4, 6, 8, 10, 12, 14, //
    4, 0, 2, 6, 8, 10, 12, 14, 0, 4, 2, 6, 8, 10, 12, 14, //
    2, 4, 0, 6, 8, 10, 12, 14, 0, 2, 4, 6, 8, 10, 12, 14, //
    6, 0, 2, 4, 8, 10, 12, 14, 0, 6, 2, 4, 8, 10, 12, 14, //
    2, 6, 0, 4, 8, 10, 12, 14, 0, 2, 6, 4, 8, 10, 12, 14, //
    4, 6, 0, 2, 8, 10, 12, 14, 0, 4, 6, 2, 8, 10, 12, 14, //
    2, 4, 6, 0, 8, 10, 12, 14, 0, 2, 4, 6, 8, 10, 12, 14, //
    8, 0, 2, 4, 6, 10, 12, 14, 0, 8, 2, 4, 6, 10, 12, 14, //
    2, 8, 0, 4, 6, 10, 12, 14, 0, 2, 8, 4, 6, 10, 12, 14, //
    4, 8, 0, 2, 6, 10, 12, 14, 0, 4, 8, 2, 6, 10, 12, 14, //
    2, 4, 8, 0, 6, 10, 12, 14, 0, 2, 4, 8, 6, 10, 12, 14, //
    6, 8, 0, 2, 4, 10, 12, 14, 0, 6, 8, 2, 4, 10, 12, 14, //
    2, 6, 8, 0, 4, 10, 12, 14, 0, 2, 6, 8, 4, 10, 12, 14, //
    4, 6, 8, 0, 2, 10, 12, 14, 0, 4, 6, 8, 2, 10, 12, 14, //
    2, 4, 6, 8, 0, 10, 12, 14, 0, 2, 4, 6, 8, 10, 12, 14, //
    10, 0, 2, 4, 6, 8, 12, 14, 0, 10, 2, 4, 6, 8, 12, 14, //
    2, 10, 0, 4, 6, 8, 12, 14, 0, 2, 10, 4, 6, 8, 12, 14, //
    4, 10, 0, 2, 6, 8, 12, 14, 0, 4, 10, 2, 6, 8, 12, 14, //
    2, 4, 10, 0, 6, 8, 12, 14, 0, 2, 4, 10, 6, 8, 12, 14, //
    6, 10, 0, 2, 4, 8, 12, 14, 0, 6, 10, 2, 4, 8, 12, 14, //
    2, 6, 10, 0, 4, 8, 12, 14, 0, 2, 6, 10, 4, 8, 12, 14, //
    4, 6, 10, 0, 2, 8, 12, 14, 0, 4, 6, 10, 2, 8, 12, 14, //
    2, 4, 6, 10, 0, 8, 12, 14, 0, 2, 4, 6, 10, 8, 12, 14, //
    8, 10, 0, 2, 4, 6, 12, 14, 0, 8, 10, 2, 4, 6, 12, 14, //
    2, 8, 10, 0, 4, 6, 12, 14, 0, 2, 8, 10, 4, 6, 12, 14, //
    4, 8, 10, 0, 2, 6, 12, 14, 0, 4, 8, 10, 2, 6, 12, 14, //
    2, 4, 8, 10, 0, 6, 12, 14, 0, 2, 4, 8, 10, 6, 12, 14, //
    6, 8, 10, 0, 2, 4, 12, 14, 0, 6, 8, 10, 2, 4, 12, 14, //
    2, 6, 8, 10, 0, 4, 12, 14, 0, 2, 6, 8, 10, 4, 12, 14, //
    4, 6, 8, 10, 0, 2, 12, 14, 0, 4, 6, 8, 10, 2, 12, 14, //
    2, 4, 6, 8, 10, 0, 12, 14, 0, 2, 4, 6, 8, 10, 12, 14, //
    12, 0, 2, 4, 6, 8, 10, 14, 0, 12, 2, 4, 6, 8, 10, 14, //
    2, 12, 0, 4, 6, 8, 10, 14, 0, 2, 12, 4, 6, 8, 10, 14, //
    4, 12, 0, 2, 6, 8, 10, 14, 0, 4, 12, 2, 6, 8, 10, 14, //
    2, 4, 12, 0, 6, 8, 10, 14, 0, 2, 4, 12, 6, 8, 10, 14, //
    6, 12, 0, 2, 4, 8, 10, 14, 0, 6, 12, 2, 4, 8, 10, 14, //
    2, 6, 12, 0, 4, 8, 10, 14, 0, 2, 6, 12, 4, 8, 10, 14, //
    4, 6, 12, 0, 2, 8, 10, 14, 0, 4, 6, 12, 2, 8, 10, 14, //
    2, 4, 6, 12, 0, 8, 10, 14, 0, 2, 4, 6, 12, 8, 10, 14, //
    8, 12, 0, 2, 4, 6, 10, 14, 0, 8, 12, 2, 4, 6, 10, 14, //
    2, 8, 12, 0, 4, 6, 10, 14, 0, 2, 8, 12, 4, 6, 10, 14, //
    4, 8, 12, 0, 2, 6, 10, 14, 0, 4, 8, 12, 2, 6, 10, 14, //
    2, 4, 8, 12, 0, 6, 10, 14, 0, 2, 4, 8, 12, 6, 10, 14, //
    6, 8, 12, 0, 2, 4, 10, 14, 0, 6, 8, 12, 2, 4, 10, 14, //
    2, 6, 8, 12, 0, 4, 10, 14, 0, 2, 6, 8, 12, 4, 10, 14, //
    4, 6, 8, 12, 0, 2, 10, 14, 0, 4, 6, 8, 12, 2, 10, 14, //
    2, 4, 6, 8, 12, 0, 10, 14, 0, 2, 4, 6, 8, 12, 10, 14, //
    10, 12, 0, 2, 4, 6, 8, 14, 0, 10, 12, 2, 4, 6, 8, 14, //
    2, 10, 12, 0, 4, 6, 8, 14, 0, 2, 10, 12, 4, 6, 8, 14, //
    4, 10, 12, 0, 2, 6, 8, 14, 0, 4, 10, 12, 2, 6, 8, 14, //
    2, 4, 10, 12, 0, 6, 8, 14, 0, 2, 4, 10, 12, 6, 8, 14, //
    6, 10, 12, 0, 2, 4, 8, 14, 0, 6, 10, 12, 2, 4, 8, 14, //
    2, 6, 10, 12, 0, 4, 8, 14, 0, 2, 6, 10, 12, 4, 8, 14, //
    4, 6, 10, 12, 0, 2, 8, 14, 0, 4, 6, 10, 12, 2, 8, 14, //
    2, 4, 6, 10, 12, 0, 8, 14, 0, 2, 4, 6, 10, 12, 8, 14, //
    8, 10, 12, 0, 2, 4, 6, 14, 0, 8, 10, 12, 2, 4, 6, 14, //
    2, 8, 10, 12, 0, 4, 6, 14, 0, 2, 8, 10, 12, 4, 6, 14, //
    4, 8, 10, 12, 0, 2, 6, 14, 0, 4, 8, 10, 12, 2, 6, 14, //
    2, 4, 8, 10, 12, 0, 6, 14, 0, 2, 4, 8, 10, 12, 6, 14, //
    6, 8, 10, 12, 0, 2, 4, 14, 0, 6, 8, 10, 12, 2, 4, 14, //
    2, 6, 8, 10, 12, 0, 4, 14, 0, 2, 6, 8, 10, 12, 4, 14, //
    4, 6, 8, 10, 12, 0, 2, 14, 0, 4, 6, 8, 10, 12, 2, 14, //
    2, 4, 6, 8, 10, 12, 0, 14, 0, 2, 4, 6, 8, 10, 12, 14, //
    14, 0, 2, 4, 6, 8, 10, 12, 0, 14, 2, 4, 6, 8, 10, 12, //
    2, 14, 0, 4, 6, 8, 10, 12, 0, 2, 14, 4, 6, 8, 10, 12, //
    4, 14, 0, 2, 6, 8, 10, 12, 0, 4, 14, 2, 6, 8, 10, 12, //
    2, 4, 14, 0, 6, 8, 10, 12, 0, 2, 4, 14, 6, 8, 10, 12, //
    6, 14, 0, 2, 4, 8, 10, 12, 0, 6, 14, 2, 4, 8, 10, 12, //
    2, 6, 14, 0, 4, 8, 10, 12, 0, 2, 6, 14, 4, 8, 10, 12, //
    4, 6, 14, 0, 2, 8, 10, 12, 0, 4, 6, 14, 2, 8, 10, 12, //
    2, 4, 6, 14, 0, 8, 10, 12, 0, 2, 4, 6, 14, 8, 10, 12, //
    8, 14, 0, 2, 4, 6, 10, 12, 0, 8, 14, 2, 4, 6, 10, 12, //
    2, 8, 14, 0, 4, 6, 10, 12, 0, 2, 8, 14, 4, 6, 10, 12, //
    4, 8, 14, 0, 2, 6, 10, 12, 0, 4, 8, 14, 2, 6, 10, 12, //
    2, 4, 8, 14, 0, 6, 10, 12, 0, 2, 4, 8, 14, 6, 10, 12, //
    6, 8, 14, 0, 2, 4, 10, 12, 0, 6, 8, 14, 2, 4, 10, 12, //
    2, 6, 8, 14, 0, 4, 10, 12, 0, 2, 6, 8, 14, 4, 10, 12, //
    4, 6, 8, 14, 0, 2, 10, 12, 0, 4, 6, 8, 14, 2, 10, 12, //
    2, 4, 6, 8, 14, 0, 10, 12, 0, 2, 4, 6, 8, 14, 10, 12, //
    10, 14, 0, 2, 4, 6, 8, 12, 0, 10, 14, 2, 4, 6, 8, 12, //
    2, 10, 14, 0, 4, 6, 8, 12, 0, 2, 10, 14, 4, 6, 8, 12, //
    4, 10, 14, 0, 2, 6, 8, 12, 0, 4, 10, 14, 2, 6, 8, 12, //
    2, 4, 10, 14, 0, 6, 8, 12, 0, 2, 4, 10, 14, 6, 8, 12, //
    6, 10, 14, 0, 2, 4, 8, 12, 0, 6, 10, 14, 2, 4, 8, 12, //
    2, 6, 10, 14, 0, 4, 8, 12, 0, 2, 6, 10, 14, 4, 8, 12, //
    4, 6, 10, 14, 0, 2, 8, 12, 0, 4, 6, 10, 14, 2, 8, 12, //
    2, 4, 6, 10, 14, 0, 8, 12, 0, 2, 4, 6, 10, 14, 8, 12, //
    8, 10, 14, 0, 2, 4, 6, 12, 0, 8, 10, 14, 2, 4, 6, 12, //
    2, 8, 10, 14, 0, 4, 6, 12, 0, 2, 8, 10, 14, 4, 6, 12, //
    4, 8, 10, 14, 0, 2, 6, 12, 0, 4, 8, 10, 14, 2, 6, 12, //
    2, 4, 8, 10, 14, 0, 6, 12, 0, 2, 4, 8, 10, 14, 6, 12, //
    6, 8, 10, 14, 0, 2, 4, 12, 0, 6, 8, 10, 14, 2, 4, 12, //
    2, 6, 8, 10, 14, 0, 4, 12, 0, 2, 6, 8, 10, 14, 4, 12, //
    4, 6, 8, 10, 14, 0, 2, 12, 0, 4, 6, 8, 10, 14, 2, 12, //
    2, 4, 6, 8, 10, 14, 0, 12, 0, 2, 4, 6, 8, 10, 14, 12, //
    12, 14, 0, 2, 4, 6, 8, 10, 0, 12, 14, 2, 4, 6, 8, 10, //
    2, 12, 14, 0, 4, 6, 8, 10, 0, 2, 12, 14, 4, 6, 8, 10, //
    4, 12, 14, 0, 2, 6, 8, 10, 0, 4, 12, 14, 2, 6, 8, 10, //
    2, 4, 12, 14, 0, 6, 8, 10, 0, 2, 4, 12, 14, 6, 8, 10, //
    6, 12, 14, 0, 2, 4, 8, 10, 0, 6, 12, 14, 2, 4, 8, 10, //
    2, 6, 12, 14, 0, 4, 8, 10, 0, 2, 6, 12, 14, 4, 8, 10, //
    4, 6, 12, 14, 0, 2, 8, 10, 0, 4, 6, 12, 14, 2, 8, 10, //
    2, 4, 6, 12, 14, 0, 8, 10, 0, 2, 4, 6, 12, 14, 8, 10, //
    8, 12, 14, 0, 2, 4, 6, 10, 0, 8, 12, 14, 2, 4, 6, 10, //
    2, 8, 12, 14, 0, 4, 6, 10, 0, 2, 8, 12, 14, 4, 6, 10, //
    4, 8, 12, 14, 0, 2, 6, 10, 0, 4, 8, 12, 14, 2, 6, 10, //
    2, 4, 8, 12, 14, 0, 6, 10, 0, 2, 4, 8, 12, 14, 6, 10, //
    6, 8, 12, 14, 0, 2, 4, 10, 0, 6, 8, 12, 14, 2, 4, 10, //
    2, 6, 8, 12, 14, 0, 4, 10, 0, 2, 6, 8, 12, 14, 4, 10, //
    4, 6, 8, 12, 14, 0, 2, 10, 0, 4, 6, 8, 12, 14, 2, 10, //
    2, 4, 6, 8, 12, 14, 0, 10, 0, 2, 4, 6, 8, 12, 14, 10, //
    10, 12, 14, 0, 2, 4, 6, 8, 0, 10, 12, 14, 2, 4, 6, 8, //
    2, 10, 12, 14, 0, 4, 6, 8, 0, 2, 10, 12, 14, 4, 6, 8, //
    4, 10, 12, 14, 0, 2, 6, 8, 0, 4, 10, 12, 14, 2, 6, 8, //
    2, 4, 10, 12, 14, 0, 6, 8, 0, 2, 4, 10, 12, 14, 6, 8, //
    6, 10, 12, 14, 0, 2, 4, 8, 0, 6, 10, 12, 14, 2, 4, 8, //
    2, 6, 10, 12, 14, 0, 4, 8, 0, 2, 6, 10, 12, 14, 4, 8, //
    4, 6, 10, 12, 14, 0, 2, 8, 0, 4, 6, 10, 12, 14, 2, 8, //
    2, 4, 6, 10, 12, 14, 0, 8, 0, 2, 4, 6, 10, 12, 14, 8, //
    8, 10, 12, 14, 0, 2, 4, 6, 0, 8, 10, 12, 14, 2, 4, 6, //
    2, 8, 10, 12, 14, 0, 4, 6, 0, 2, 8, 10, 12, 14, 4, 6, //
    4, 8, 10, 12, 14, 0, 2, 6, 0, 4, 8, 10, 12, 14, 2, 6, //
    2, 4, 8, 10, 12, 14, 0, 6, 0, 2, 4, 8, 10, 12, 14, 6, //
    6, 8, 10, 12, 14, 0, 2, 4, 0, 6, 8, 10, 12, 14, 2, 4, //
    2, 6, 8, 10, 12, 14, 0, 4, 0, 2, 6, 8, 10, 12, 14, 4, //
    4, 6, 8, 10, 12, 14, 0,  2, 0, 4, 6, 8, 10, 12, 14, 2, //
    2, 4, 6, 8,  10, 12, 14, 0, 0, 2, 4, 6, 8,  10, 12, 14,
};

// There are only 4 lanes, so we can afford to load the index vector directly.
const indices32x4: [16 * 16]u8 align(16) = .{
    // PrintCompress32x4Tables
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, //
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, //
    4, 5, 6, 7, 0, 1, 2, 3, 8, 9, 10, 11, 12, 13, 14, 15, //
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, //
    8, 9, 10, 11, 0, 1, 2, 3, 4, 5, 6, 7, 12, 13, 14, 15, //
    0, 1, 2, 3, 8, 9, 10, 11, 4, 5, 6, 7, 12, 13, 14, 15, //
    4, 5, 6, 7, 8, 9, 10, 11, 0, 1, 2, 3, 12, 13, 14, 15, //
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, //
    12, 13, 14, 15, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, //
    0, 1, 2, 3, 12, 13, 14, 15, 4, 5, 6, 7, 8, 9, 10, 11, //
    4, 5, 6, 7, 12, 13, 14, 15, 0, 1, 2, 3, 8, 9, 10, 11, //
    0, 1, 2, 3, 4, 5, 6, 7, 12, 13, 14, 15, 8, 9, 10, 11, //
    8, 9, 10, 11, 12, 13, 14, 15, 0, 1, 2, 3, 4, 5, 6, 7, //
    0, 1, 2, 3, 8, 9, 10, 11, 12, 13, 14, 15, 4, 5, 6, 7, //
    4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 0,  1,  2,  3, //
    0, 1, 2, 3, 4, 5, 6,  7,  8,  9,  10, 11, 12, 13, 14, 15,
};

// There are only 2 lanes, so we can afford to load the index vector directly.
const indices64x2: [4 * 16]u8 align(16) = .{
    // PrintCompress64x2Tables
    0, 1, 2,  3,  4,  5,  6,  7,  8, 9, 10, 11, 12, 13, 14, 15,
    0, 1, 2,  3,  4,  5,  6,  7,  8, 9, 10, 11, 12, 13, 14, 15,
    8, 9, 10, 11, 12, 13, 14, 15, 0, 1, 2,  3,  4,  5,  6,  7,
    0, 1, 2,  3,  4,  5,  6,  7,  8, 9, 10, 11, 12, 13, 14, 15,
};

fn idxFromBits128(comptime T: type, mask_bits: u64) @Vector(16, u8) {
    switch (@sizeOf(T)) {
        1 => {
            const mask0_bits = mask_bits & 0xff;
            const mask1_bits = (mask_bits >> 8) & 0xff;
            const idx0: @Vector(8, u8) = table8x16[mask0_bits * 8 ..][0..8].*;
            var idx1: @Vector(8, u8) = table8x16[mask1_bits * 8 ..][0..8].*;
            idx1 += @splat(8);
            return std.simd.join(idx0, idx1);
        },
        2 => {
            // TODO: It is only for little-endian, it should to implement
            // it for big-endian
            const byte_idx: @Vector(8, u8) = table16x8[mask_bits * 8 ..][0..8].*;
            const pairs: @Vector(8, u16) = @bitCast(std.simd.interlace([_]@Vector(8, u8){ byte_idx, byte_idx }));
            return @bitCast(pairs + @as(@Vector(8, u16), @splat(0x100)));
        },
        4 => {
            return indices32x4[mask_bits * 16 ..][0..16].*;
        },
        8 => {
            return indices64x2[mask_bits * 16 ..][0..16].*;
        },
        else => @compileError("Invalid type for idxFromBits" ++ @typeName(T)),
    }
}

//	uint64_t index_masks[6] = {
//		0xaaaaaaaaaaaaaaaa,
//		0xcccccccccccccccc,
//		0xf0f0f0f0f0f0f0f0,
//		0xff00ff00ff00ff00,
//		0xffff0000ffff0000,
//		0xffffffff00000000,
//	};
//
//	const __m512i index_bits[6] = {
//		_mm512_set1_epi8(1),
//		_mm512_set1_epi8(2),
//		_mm512_set1_epi8(4),
//		_mm512_set1_epi8(8),
//		_mm512_set1_epi8(16),
//		_mm512_set1_epi8(32),
//	};
//		if (mask) {
//			//len = 64 - __builtin_popcountll(mask);
//			len = 64 - _mm_popcnt_u64(mask);
//			mask = ~mask;
//			__m512i indices = _mm512_set1_epi8(0);
//			for (size_t index = 0; index < 6; index++) {
//				uint64_t m = _pext_u64(index_masks[index], mask);
//				indices = _mm512_mask_add_epi8(indices, m, indices, index_bits[index]);
//			}
//
//			output = _mm512_permutexvar_epi8(indices, input);
//		}

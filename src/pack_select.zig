const std = @import("std");
const simd = @import("simd_core.zig");

const builtin = @import("builtin");
const target = builtin.target;
const arch = target.cpu.arch;

const assert = std.debug.assert;

const VEC_BITS_LEN = simd.VEC_BITS_LEN;
const VecLen = simd.VecLen;
const VecType = simd.VecType;

fn vectorLength(comptime VectorType: type) comptime_int {
    return switch (@typeInfo(VectorType)) {
        .Vector => |info| info.len,
        .Array => |info| info.len,
        else => @compileError("Invalid type " ++ @typeName(VectorType)),
    };
}

fn VecChild(comptime T: type) type {
    return std.meta.Child(T);
}

pub fn packSelectLeft(vec: anytype, mask: @Vector(vectorLength(@TypeOf(vec)), bool)) @TypeOf(vec) {
    return packSelectLeftGeneric(vec, mask);
}

fn packSelectLeftGeneric(vec: anytype, mask: @Vector(vectorLength(@TypeOf(vec)), bool)) @TypeOf(vec) {
    const Child = VecChild(@TypeOf(vec));
    const vecLen = comptime vectorLength(@TypeOf(vec));
    var int_mask = @as(std.meta.Int(.unsigned, vecLen), @bitCast(mask));
    std.debug.print("packSelect int_mask is: 0b{b:0>32}\n", .{int_mask});

    const num_groups = @popCount(int_mask & ~(int_mask << 1));
    _ = num_groups;

    //        var result: @TypeOf(vec) = 0;
    //        var cur_pos = 0;
    //        while (int_mask != 0) {
    //            const mask_ctz = @ctz(int_mask);
    //            const num_ones = @ctz(~(int_mask >> mask_ctz));
    //
    //            result =
    //            comptime var ones = 1;
    //            inline for (0..num_ones) |_| ones <<= 1;
    //            ones -%= 1;
    //            // @compileLog(std.fmt.comptimePrint("ans |= (src >> {}) & 0b{b}", .{ mask_ctz - cur_pos, (ones << cur_pos) }));
    //            ans |= (src >> (mask_ctz - cur_pos)) & (ones << cur_pos);
    //            cur_pos += num_ones;
    //            for (0..num_ones) |_| int_mask &= int_mask - 1;
    //        }
    //        return ans;
    const select_mask = std.simd.iota(u8, vecLen) >= @as(@Vector(vecLen, u8), @splat(@as(u8, @popCount(int_mask))));
    return @select(Child, select_mask, vec, @as(@Vector(vecLen, Child), @splat(0)));
}

// pub fn packSelectLeft(vec: anytype, mask: @Vector(vectorLength(@TypeOf(vec)), bool)) @Vector(vectorLength(@TypeOf(vec)), VecChild(@TypeOf(vec))) {
//     const Child = VecChild(@TypeOf(vec));
//     // const vecLen = comptime vectorLength(@TypeOf(vec));
//
//     const MaskUint = std.meta.Int(.unsigned, VEC_BITS_LEN / 4);
//     const ChildVecLen = VEC_BITS_LEN / @bitSizeOf(Child);
//     const ChildAsUint = std.meta.Int(.unsigned, @bitSizeOf(Child));
//     const max_child_uint = std.math.maxInt(ChildAsUint);
//     const max_masks: @Vector(ChildVecLen, ChildAsUint) = @splat(max_child_uint);
//     const zero_masks: @Vector(ChildVecLen, ChildAsUint) = @splat(0);
//
//     const dummy_mask: @Vector(4, MaskUint) = undefined;
//     const vec_mask: @Vector(4, MaskUint) = @bitCast(@select(Child, mask, max_masks, zero_masks));
//     std.debug.print("packSelect mask: {any}\n", .{mask});
//     std.debug.print("packSelect max_masks: {any}\n", .{max_masks});
//     std.debug.print("packSelect vec_mask: {any}\n", .{vec_mask});
//     const shiftMask0 = @shuffle(MaskUint, vec_mask, dummy_mask, @Vector(4, i32){ 0, 1, 2, 2 });
//     const shiftMask1 = @shuffle(MaskUint, vec_mask, dummy_mask, @Vector(4, i32){ 0, 1, 1, 1 });
//     const shiftMask2 = @shuffle(MaskUint, vec_mask, dummy_mask, @Vector(4, i32){ 0, 0, 0, 0 });
//     const shiftMask0b = shiftMask0 > @as(@Vector(4, MaskUint), @splat(0));
//     const shiftMask1b = shiftMask1 > @as(@Vector(4, MaskUint), @splat(0));
//     const shiftMask2b = shiftMask2 > @as(@Vector(4, MaskUint), @splat(0));
//     std.debug.print("packSelect shiftMask0b: {any}\n", .{shiftMask0b});
//     std.debug.print("packSelect shiftMask1b: {any}\n", .{shiftMask1b});
//     std.debug.print("packSelect shiftMask2b: {any}\n", .{shiftMask2b});
//
//     var vec_as_masku: @Vector(4, MaskUint) = @bitCast(vec);
//     const perm_vec0 = @shuffle(MaskUint, vec_as_masku, dummy_mask, @Vector(4, i32){ 1, 2, 3, 3 });
//     std.debug.print("packSelect perm_vec0: {any}\n", .{perm_vec0});
//     vec_as_masku = @select(MaskUint, shiftMask0b, vec_as_masku, perm_vec0);
//     const perm_vec1 = @shuffle(MaskUint, vec_as_masku, dummy_mask, @Vector(4, i32){ 1, 2, 3, 3 });
//     std.debug.print("packSelect perm_vec1: {any}\n", .{perm_vec1});
//     vec_as_masku = @select(MaskUint, shiftMask1b, vec_as_masku, perm_vec1);
//     const perm_vec2 = @shuffle(MaskUint, vec_as_masku, dummy_mask, @Vector(4, i32){ 1, 2, 3, 3 });
//     std.debug.print("packSelect perm_vec2: {any}\n", .{perm_vec2});
//     vec_as_masku = @select(MaskUint, shiftMask2b, vec_as_masku, perm_vec2);
//     return @bitCast(vec_as_masku);
// }

// inline __m128 left_pack(__m128 val, __m128i mask) noexcept
// {
//     const __m128i shiftMask0 = _mm_shuffle_epi32(mask, 0xA4);
//     const __m128i shiftMask1 = _mm_shuffle_epi32(mask, 0x54);
//     const __m128i shiftMask2 = _mm_shuffle_epi32(mask, 0x00);
//
//     __m128 v = val;
//     v = _mm_blendv_ps(_mm_permute_ps(v, 0xF9), v, shiftMask0);
//     v = _mm_blendv_ps(_mm_permute_ps(v, 0xF9), v, shiftMask1);
//     v = _mm_blendv_ps(_mm_permute_ps(v, 0xF9), v, shiftMask2);
//     return v;
// }
//
// inline __m256 left_pack(__m256d val, __m256i mask) noexcept
// {
//     const __m256i shiftMask0 = _mm256_permute4x64_epi64(mask, 0xA4);
//     const __m256i shiftMask1 = _mm256_permute4x64_epi64(mask, 0x54);
//     const __m256i shiftMask2 = _mm256_permute4x64_epi64(mask, 0x00);
//
//     __m256d v = val;
//     v = _mm256_blendv_pd(_mm256_permute4x64_pd(v, 0xF9), v, shiftMask0);
//     v = _mm256_blendv_pd(_mm256_permute4x64_pd(v, 0xF9), v, shiftMask1);
//     v = _mm256_blendv_pd(_mm256_permute4x64_pd(v, 0xF9), v, shiftMask2);
//
//     return v;
// }

// NEON does not provide an equivalent of AVX2 permutevar, so we need byte
// indices for VTBL (one vector's worth for each of 256 combinations of
// 8 mask bits). Loading them directly would require 4 KiB. We can instead
// store lane indices and convert to byte indices (2*lane + 0..1), with the
// doubling baked into the table. AVX2 Compress32 stores eight 4-bit lane
// indices (total 1 KiB), broadcasts them into each 32-bit lane and shifts.
// Here, 16-bit lanes are too narrow to hold all bits, and unpacking nibbles
// is likely more costly than the higher cache footprint from storing bytes.
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

// NEON does not provide an equivalent of AVX2 permutevar, so we need byte
// indices for VTBL (one vector's worth for each of 256 combinations of
// 8 mask bits). Loading them directly would require 4 KiB. We can instead
// store lane indices and convert to byte indices (2*lane + 0..1), with the
// doubling baked into the table. AVX2 Compress32 stores eight 4-bit lane
// indices (total 1 KiB), broadcasts them into each 32-bit lane and shifts.
// Here, 16-bit lanes are too narrow to hold all bits, and unpacking nibbles
// is likely more costly than the higher cache footprint from storing bytes.
const not_table16x8: [256 * 8]u8 align(16) = .{
    // PrintCompressNot16x8Tables
    0, 2, 4, 6, 8, 10, 12, 14, 2, 4, 6, 8, 10, 12, 14, 0, //
    0, 4, 6, 8, 10, 12, 14, 2, 4, 6, 8, 10, 12, 14, 0, 2, //
    0, 2, 6, 8, 10, 12, 14, 4, 2, 6, 8, 10, 12, 14, 0, 4, //
    0, 6, 8, 10, 12, 14, 2, 4, 6, 8, 10, 12, 14, 0, 2, 4, //
    0, 2, 4, 8, 10, 12, 14, 6, 2, 4, 8, 10, 12, 14, 0, 6, //
    0, 4, 8, 10, 12, 14, 2, 6, 4, 8, 10, 12, 14, 0, 2, 6, //
    0, 2, 8, 10, 12, 14, 4, 6, 2, 8, 10, 12, 14, 0, 4, 6, //
    0, 8, 10, 12, 14, 2, 4, 6, 8, 10, 12, 14, 0, 2, 4, 6, //
    0, 2, 4, 6, 10, 12, 14, 8, 2, 4, 6, 10, 12, 14, 0, 8, //
    0, 4, 6, 10, 12, 14, 2, 8, 4, 6, 10, 12, 14, 0, 2, 8, //
    0, 2, 6, 10, 12, 14, 4, 8, 2, 6, 10, 12, 14, 0, 4, 8, //
    0, 6, 10, 12, 14, 2, 4, 8, 6, 10, 12, 14, 0, 2, 4, 8, //
    0, 2, 4, 10, 12, 14, 6, 8, 2, 4, 10, 12, 14, 0, 6, 8, //
    0, 4, 10, 12, 14, 2, 6, 8, 4, 10, 12, 14, 0, 2, 6, 8, //
    0, 2, 10, 12, 14, 4, 6, 8, 2, 10, 12, 14, 0, 4, 6, 8, //
    0, 10, 12, 14, 2, 4, 6, 8, 10, 12, 14, 0, 2, 4, 6, 8, //
    0, 2, 4, 6, 8, 12, 14, 10, 2, 4, 6, 8, 12, 14, 0, 10, //
    0, 4, 6, 8, 12, 14, 2, 10, 4, 6, 8, 12, 14, 0, 2, 10, //
    0, 2, 6, 8, 12, 14, 4, 10, 2, 6, 8, 12, 14, 0, 4, 10, //
    0, 6, 8, 12, 14, 2, 4, 10, 6, 8, 12, 14, 0, 2, 4, 10, //
    0, 2, 4, 8, 12, 14, 6, 10, 2, 4, 8, 12, 14, 0, 6, 10, //
    0, 4, 8, 12, 14, 2, 6, 10, 4, 8, 12, 14, 0, 2, 6, 10, //
    0, 2, 8, 12, 14, 4, 6, 10, 2, 8, 12, 14, 0, 4, 6, 10, //
    0, 8, 12, 14, 2, 4, 6, 10, 8, 12, 14, 0, 2, 4, 6, 10, //
    0, 2, 4, 6, 12, 14, 8, 10, 2, 4, 6, 12, 14, 0, 8, 10, //
    0, 4, 6, 12, 14, 2, 8, 10, 4, 6, 12, 14, 0, 2, 8, 10, //
    0, 2, 6, 12, 14, 4, 8, 10, 2, 6, 12, 14, 0, 4, 8, 10, //
    0, 6, 12, 14, 2, 4, 8, 10, 6, 12, 14, 0, 2, 4, 8, 10, //
    0, 2, 4, 12, 14, 6, 8, 10, 2, 4, 12, 14, 0, 6, 8, 10, //
    0, 4, 12, 14, 2, 6, 8, 10, 4, 12, 14, 0, 2, 6, 8, 10, //
    0, 2, 12, 14, 4, 6, 8, 10, 2, 12, 14, 0, 4, 6, 8, 10, //
    0, 12, 14, 2, 4, 6, 8, 10, 12, 14, 0, 2, 4, 6, 8, 10, //
    0, 2, 4, 6, 8, 10, 14, 12, 2, 4, 6, 8, 10, 14, 0, 12, //
    0, 4, 6, 8, 10, 14, 2, 12, 4, 6, 8, 10, 14, 0, 2, 12, //
    0, 2, 6, 8, 10, 14, 4, 12, 2, 6, 8, 10, 14, 0, 4, 12, //
    0, 6, 8, 10, 14, 2, 4, 12, 6, 8, 10, 14, 0, 2, 4, 12, //
    0, 2, 4, 8, 10, 14, 6, 12, 2, 4, 8, 10, 14, 0, 6, 12, //
    0, 4, 8, 10, 14, 2, 6, 12, 4, 8, 10, 14, 0, 2, 6, 12, //
    0, 2, 8, 10, 14, 4, 6, 12, 2, 8, 10, 14, 0, 4, 6, 12, //
    0, 8, 10, 14, 2, 4, 6, 12, 8, 10, 14, 0, 2, 4, 6, 12, //
    0, 2, 4, 6, 10, 14, 8, 12, 2, 4, 6, 10, 14, 0, 8, 12, //
    0, 4, 6, 10, 14, 2, 8, 12, 4, 6, 10, 14, 0, 2, 8, 12, //
    0, 2, 6, 10, 14, 4, 8, 12, 2, 6, 10, 14, 0, 4, 8, 12, //
    0, 6, 10, 14, 2, 4, 8, 12, 6, 10, 14, 0, 2, 4, 8, 12, //
    0, 2, 4, 10, 14, 6, 8, 12, 2, 4, 10, 14, 0, 6, 8, 12, //
    0, 4, 10, 14, 2, 6, 8, 12, 4, 10, 14, 0, 2, 6, 8, 12, //
    0, 2, 10, 14, 4, 6, 8, 12, 2, 10, 14, 0, 4, 6, 8, 12, //
    0, 10, 14, 2, 4, 6, 8, 12, 10, 14, 0, 2, 4, 6, 8, 12, //
    0, 2, 4, 6, 8, 14, 10, 12, 2, 4, 6, 8, 14, 0, 10, 12, //
    0, 4, 6, 8, 14, 2, 10, 12, 4, 6, 8, 14, 0, 2, 10, 12, //
    0, 2, 6, 8, 14, 4, 10, 12, 2, 6, 8, 14, 0, 4, 10, 12, //
    0, 6, 8, 14, 2, 4, 10, 12, 6, 8, 14, 0, 2, 4, 10, 12, //
    0, 2, 4, 8, 14, 6, 10, 12, 2, 4, 8, 14, 0, 6, 10, 12, //
    0, 4, 8, 14, 2, 6, 10, 12, 4, 8, 14, 0, 2, 6, 10, 12, //
    0, 2, 8, 14, 4, 6, 10, 12, 2, 8, 14, 0, 4, 6, 10, 12, //
    0, 8, 14, 2, 4, 6, 10, 12, 8, 14, 0, 2, 4, 6, 10, 12, //
    0, 2, 4, 6, 14, 8, 10, 12, 2, 4, 6, 14, 0, 8, 10, 12, //
    0, 4, 6, 14, 2, 8, 10, 12, 4, 6, 14, 0, 2, 8, 10, 12, //
    0, 2, 6, 14, 4, 8, 10, 12, 2, 6, 14, 0, 4, 8, 10, 12, //
    0, 6, 14, 2, 4, 8, 10, 12, 6, 14, 0, 2, 4, 8, 10, 12, //
    0, 2, 4, 14, 6, 8, 10, 12, 2, 4, 14, 0, 6, 8, 10, 12, //
    0, 4, 14, 2, 6, 8, 10, 12, 4, 14, 0, 2, 6, 8, 10, 12, //
    0, 2, 14, 4, 6, 8, 10, 12, 2, 14, 0, 4, 6, 8, 10, 12, //
    0, 14, 2, 4, 6, 8, 10, 12, 14, 0, 2, 4, 6, 8, 10, 12, //
    0, 2, 4, 6, 8, 10, 12, 14, 2, 4, 6, 8, 10, 12, 0, 14, //
    0, 4, 6, 8, 10, 12, 2, 14, 4, 6, 8, 10, 12, 0, 2, 14, //
    0, 2, 6, 8, 10, 12, 4, 14, 2, 6, 8, 10, 12, 0, 4, 14, //
    0, 6, 8, 10, 12, 2, 4, 14, 6, 8, 10, 12, 0, 2, 4, 14, //
    0, 2, 4, 8, 10, 12, 6, 14, 2, 4, 8, 10, 12, 0, 6, 14, //
    0, 4, 8, 10, 12, 2, 6, 14, 4, 8, 10, 12, 0, 2, 6, 14, //
    0, 2, 8, 10, 12, 4, 6, 14, 2, 8, 10, 12, 0, 4, 6, 14, //
    0, 8, 10, 12, 2, 4, 6, 14, 8, 10, 12, 0, 2, 4, 6, 14, //
    0, 2, 4, 6, 10, 12, 8, 14, 2, 4, 6, 10, 12, 0, 8, 14, //
    0, 4, 6, 10, 12, 2, 8, 14, 4, 6, 10, 12, 0, 2, 8, 14, //
    0, 2, 6, 10, 12, 4, 8, 14, 2, 6, 10, 12, 0, 4, 8, 14, //
    0, 6, 10, 12, 2, 4, 8, 14, 6, 10, 12, 0, 2, 4, 8, 14, //
    0, 2, 4, 10, 12, 6, 8, 14, 2, 4, 10, 12, 0, 6, 8, 14, //
    0, 4, 10, 12, 2, 6, 8, 14, 4, 10, 12, 0, 2, 6, 8, 14, //
    0, 2, 10, 12, 4, 6, 8, 14, 2, 10, 12, 0, 4, 6, 8, 14, //
    0, 10, 12, 2, 4, 6, 8, 14, 10, 12, 0, 2, 4, 6, 8, 14, //
    0, 2, 4, 6, 8, 12, 10, 14, 2, 4, 6, 8, 12, 0, 10, 14, //
    0, 4, 6, 8, 12, 2, 10, 14, 4, 6, 8, 12, 0, 2, 10, 14, //
    0, 2, 6, 8, 12, 4, 10, 14, 2, 6, 8, 12, 0, 4, 10, 14, //
    0, 6, 8, 12, 2, 4, 10, 14, 6, 8, 12, 0, 2, 4, 10, 14, //
    0, 2, 4, 8, 12, 6, 10, 14, 2, 4, 8, 12, 0, 6, 10, 14, //
    0, 4, 8, 12, 2, 6, 10, 14, 4, 8, 12, 0, 2, 6, 10, 14, //
    0, 2, 8, 12, 4, 6, 10, 14, 2, 8, 12, 0, 4, 6, 10, 14, //
    0, 8, 12, 2, 4, 6, 10, 14, 8, 12, 0, 2, 4, 6, 10, 14, //
    0, 2, 4, 6, 12, 8, 10, 14, 2, 4, 6, 12, 0, 8, 10, 14, //
    0, 4, 6, 12, 2, 8, 10, 14, 4, 6, 12, 0, 2, 8, 10, 14, //
    0, 2, 6, 12, 4, 8, 10, 14, 2, 6, 12, 0, 4, 8, 10, 14, //
    0, 6, 12, 2, 4, 8, 10, 14, 6, 12, 0, 2, 4, 8, 10, 14, //
    0, 2, 4, 12, 6, 8, 10, 14, 2, 4, 12, 0, 6, 8, 10, 14, //
    0, 4, 12, 2, 6, 8, 10, 14, 4, 12, 0, 2, 6, 8, 10, 14, //
    0, 2, 12, 4, 6, 8, 10, 14, 2, 12, 0, 4, 6, 8, 10, 14, //
    0, 12, 2, 4, 6, 8, 10, 14, 12, 0, 2, 4, 6, 8, 10, 14, //
    0, 2, 4, 6, 8, 10, 12, 14, 2, 4, 6, 8, 10, 0, 12, 14, //
    0, 4, 6, 8, 10, 2, 12, 14, 4, 6, 8, 10, 0, 2, 12, 14, //
    0, 2, 6, 8, 10, 4, 12, 14, 2, 6, 8, 10, 0, 4, 12, 14, //
    0, 6, 8, 10, 2, 4, 12, 14, 6, 8, 10, 0, 2, 4, 12, 14, //
    0, 2, 4, 8, 10, 6, 12, 14, 2, 4, 8, 10, 0, 6, 12, 14, //
    0, 4, 8, 10, 2, 6, 12, 14, 4, 8, 10, 0, 2, 6, 12, 14, //
    0, 2, 8, 10, 4, 6, 12, 14, 2, 8, 10, 0, 4, 6, 12, 14, //
    0, 8, 10, 2, 4, 6, 12, 14, 8, 10, 0, 2, 4, 6, 12, 14, //
    0, 2, 4, 6, 10, 8, 12, 14, 2, 4, 6, 10, 0, 8, 12, 14, //
    0, 4, 6, 10, 2, 8, 12, 14, 4, 6, 10, 0, 2, 8, 12, 14, //
    0, 2, 6, 10, 4, 8, 12, 14, 2, 6, 10, 0, 4, 8, 12, 14, //
    0, 6, 10, 2, 4, 8, 12, 14, 6, 10, 0, 2, 4, 8, 12, 14, //
    0, 2, 4, 10, 6, 8, 12, 14, 2, 4, 10, 0, 6, 8, 12, 14, //
    0, 4, 10, 2, 6, 8, 12, 14, 4, 10, 0, 2, 6, 8, 12, 14, //
    0, 2, 10, 4, 6, 8, 12, 14, 2, 10, 0, 4, 6, 8, 12, 14, //
    0, 10, 2, 4, 6, 8, 12, 14, 10, 0, 2, 4, 6, 8, 12, 14, //
    0, 2, 4, 6, 8, 10, 12, 14, 2, 4, 6, 8, 0, 10, 12, 14, //
    0, 4, 6, 8, 2, 10, 12, 14, 4, 6, 8, 0, 2, 10, 12, 14, //
    0, 2, 6, 8, 4, 10, 12, 14, 2, 6, 8, 0, 4, 10, 12, 14, //
    0, 6, 8, 2, 4, 10, 12, 14, 6, 8, 0, 2, 4, 10, 12, 14, //
    0, 2, 4, 8, 6, 10, 12, 14, 2, 4, 8, 0, 6, 10, 12, 14, //
    0, 4, 8, 2, 6, 10, 12, 14, 4, 8, 0, 2, 6, 10, 12, 14, //
    0, 2, 8, 4, 6, 10, 12, 14, 2, 8, 0, 4, 6, 10, 12, 14, //
    0, 8, 2, 4, 6, 10, 12, 14, 8, 0, 2, 4, 6, 10, 12, 14, //
    0, 2, 4, 6, 8, 10, 12, 14, 2, 4, 6, 0, 8, 10, 12, 14, //
    0, 4, 6, 2, 8, 10, 12, 14, 4, 6, 0, 2, 8, 10, 12, 14, //
    0, 2, 6, 4, 8, 10, 12, 14, 2, 6, 0, 4, 8, 10, 12, 14, //
    0, 6, 2, 4, 8, 10, 12, 14, 6, 0, 2, 4, 8, 10, 12, 14, //
    0, 2, 4, 6, 8, 10, 12, 14, 2, 4, 0, 6, 8, 10, 12, 14, //
    0, 4, 2, 6, 8, 10, 12, 14, 4, 0, 2, 6, 8, 10, 12, 14, //
    0, 2, 4, 6, 8, 10, 12, 14, 2, 0, 4, 6, 8, 10, 12, 14, //
    0, 2, 4, 6, 8, 10, 12, 14, 0, 2, 4, 6, 8, 10, 12, 14,
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

// There are only 4 lanes, so we can afford to load the index vector directly.
const not_indices32x4: [16 * 16]u8 align(16) = .{
    // PrintCompressNot32x4Tables
    0,  1,  2,  3,  4,  5,  6,  7,  8,  9,  10, 11, 12, 13, 14, 15,
    4,  5,  6,  7,  8,  9,  10, 11, 12, 13, 14, 15, 0,  1,  2,  3,
    0,  1,  2,  3,  8,  9,  10, 11, 12, 13, 14, 15, 4,  5,  6,  7,
    8,  9,  10, 11, 12, 13, 14, 15, 0,  1,  2,  3,  4,  5,  6,  7,
    0,  1,  2,  3,  4,  5,  6,  7,  12, 13, 14, 15, 8,  9,  10, 11,
    4,  5,  6,  7,  12, 13, 14, 15, 0,  1,  2,  3,  8,  9,  10, 11,
    0,  1,  2,  3,  12, 13, 14, 15, 4,  5,  6,  7,  8,  9,  10, 11,
    12, 13, 14, 15, 0,  1,  2,  3,  4,  5,  6,  7,  8,  9,  10, 11,
    0,  1,  2,  3,  4,  5,  6,  7,  8,  9,  10, 11, 12, 13, 14, 15,
    4,  5,  6,  7,  8,  9,  10, 11, 0,  1,  2,  3,  12, 13, 14, 15,
    0,  1,  2,  3,  8,  9,  10, 11, 4,  5,  6,  7,  12, 13, 14, 15,
    8,  9,  10, 11, 0,  1,  2,  3,  4,  5,  6,  7,  12, 13, 14, 15,
    0,  1,  2,  3,  4,  5,  6,  7,  8,  9,  10, 11, 12, 13, 14, 15,
    4,  5,  6,  7,  0,  1,  2,  3,  8,  9,  10, 11, 12, 13, 14, 15,
    0,  1,  2,  3,  4,  5,  6,  7,  8,  9,  10, 11, 12, 13, 14, 15,
    0,  1,  2,  3,  4,  5,  6,  7,  8,  9,  10, 11, 12, 13, 14, 15,
};

// There are only 2 lanes, so we can afford to load the index vector directly.
const indices64x2: [4 * 16]u8 align(16) = .{
    // PrintCompress64x2Tables
    0, 1, 2,  3,  4,  5,  6,  7,  8, 9, 10, 11, 12, 13, 14, 15,
    0, 1, 2,  3,  4,  5,  6,  7,  8, 9, 10, 11, 12, 13, 14, 15,
    8, 9, 10, 11, 12, 13, 14, 15, 0, 1, 2,  3,  4,  5,  6,  7,
    0, 1, 2,  3,  4,  5,  6,  7,  8, 9, 10, 11, 12, 13, 14, 15,
};

// There are only 2 lanes, so we can afford to load the index vector directly.
const not_indices64x2: [4 * 16]u8 align(16) = .{
    // PrintCompressNot64x2Tables
    0, 1, 2,  3,  4,  5,  6,  7,  8, 9, 10, 11, 12, 13, 14, 15,
    8, 9, 10, 11, 12, 13, 14, 15, 0, 1, 2,  3,  4,  5,  6,  7,
    0, 1, 2,  3,  4,  5,  6,  7,  8, 9, 10, 11, 12, 13, 14, 15,
    0, 1, 2,  3,  4,  5,  6,  7,  8, 9, 10, 11, 12, 13, 14, 15,
};

fn IdxFromBits(comptime T: type, mask_bits: u64) @Vector(VecLen(T), T) {
    switch (@sizeOf(T)) {
        2 => {
            assert(mask_bits < 256);
            const byte_idx: @Vector(u8, 8) = table16x8[mask_bits * 8][0..8];
            const pairs: @Vector(u16, 8) = @bitCast(std.simd.interlace([_]@Vector(u8, 8){ byte_idx, byte_idx }));
            return @bitCast(pairs + @as(@Vector(u16, 8), @splat(0x100)));
        },
        4 => {
            assert(mask_bits < 16);
            const index: @Vector(u8, 16) = indices32x4[mask_bits * 16][0..16];
            return @bitCast(index);
        },
        8 => {
            assert(mask_bits < 4);
            const index: @Vector(u8, 16) = indices64x2[mask_bits * 16][0..16];
            return @bitCast(index);
        },
        else => @compileError("Invalid type for IdxFromBits" ++ @typeName(T)),
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

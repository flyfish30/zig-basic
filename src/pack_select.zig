const std = @import("std");
const simd = @import("simd_core.zig");

const builtin = @import("builtin");
const target = builtin.target;
const arch = target.cpu.arch;
const native_endian = builtin.cpu.arch.endian();

const assert = std.debug.assert;

const VEC_BITS_LEN = simd.VEC_BITS_LEN;
const VecLen = simd.VecLen;
const VecType = simd.VecType;
const vectorLength = simd.vectorLength;
const VecChild = simd.VecChild;

fn Pair(comptime T: type) type {
    return struct { T, T };
}

pub fn packSelectLeft(vec: anytype, mask: @Vector(vectorLength(@TypeOf(vec)), bool)) @TypeOf(vec) {
    return packSelect(vec, mask)[0];
}

pub fn packSelectRight(vec: anytype, mask: @Vector(vectorLength(@TypeOf(vec)), bool)) @TypeOf(vec) {
    return packSelect(vec, mask)[1];
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

            var vec_lane: [vecLen * 2]Child align(32) = undefined;
            vec_lane[0 .. vecLen / 2].* = vec0_pair[0];
            vec_lane[count0..][0 .. vecLen / 2].* = vec1_pair[0];
            vec_lane[vecLen * 3 / 2 .. vecLen * 2].* = vec1_pair[1];
            vec_lane[vecLen + count1 ..][0 .. vecLen / 2].* = vec0_pair[1];
            return .{ @bitCast(std.simd.extract(vec_lane, 0, vecLen)),
                      @bitCast(std.simd.extract(vec_lane, vecLen, vecLen)) };
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
            const pack_2vec = simd.tableLookup16Bytes(vec, idx);
            const vec0: @Vector(8, u8) = @bitCast(std.simd.extract(pack_2vec, 0, 8));
            const vec1: @Vector(8, u8) = @bitCast(std.simd.extract(pack_2vec, 8, 8));

            // vec0 and vec1 layout is bellow
            // packSelect left   <-- | -->   packSelect right
            // [ 0, 1, .. count - 1,  count, count + 1, .., 7 ]
            var vec_lane: [vecLen * 2]Child align(32) = undefined;
            vec_lane[0 .. vecLen / 2].* = vec0;
            vec_lane[count0..][0 .. vecLen / 2].* = vec1;
            vec_lane[vecLen * 3 / 2 .. vecLen * 2].* = vec1;
            vec_lane[vecLen + count1 ..][0 .. vecLen / 2].* = vec0;
            return .{ @bitCast(std.simd.extract(vec_lane, 0, vecLen)),
                      @bitCast(std.simd.extract(vec_lane, vecLen, vecLen)) };
        },
        16, 32, 64 => {
            const mask_u: u64 = @as(std.meta.Int(.unsigned, vecLen), @bitCast(mask));
            const idx: @Vector(16, i8) = @bitCast(idxFromBits128(Child, mask_u));
            const packed_vec = simd.tableLookup16Bytes(@as(@Vector(16, u8), @bitCast(vec)), idx);
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

fn lenLookupTable(comptime num: u16) usize {
    const IntType = std.meta.Int(.unsigned, num);
    const max_int: u16 = std.math.maxInt(IntType);
    return (max_int + 1) * num;
}

// The num parameter is number of lanes in SIMD vector
fn getLaneIndicesTable(comptime num: u16) [lenLookupTable(num)]u8 {
    comptime var indices: [lenLookupTable(num)]u8 = undefined;
    const asc_idx: [num]u8 = @bitCast(std.simd.iota(u8, num));
    comptime var i = 0;
    inline while (i < (1 << num)) : (i += 1) {
        comptime var bit_idx = 0;
        comptime var bit_idx_rev = num;
        comptime var j_rev = bit_idx_rev;
        comptime var j = 0;
        // generate lane indices for bit compress table
        inline while (bit_idx < num) : (bit_idx += 1) {
            if (i & (1 << bit_idx) != 0) {
                indices[i * num + j] = asc_idx[bit_idx];
                j += 1;
            }
            bit_idx_rev -= 1;
            if (i & (1 << bit_idx_rev) == 0) {
                j_rev -= 1;
                indices[i * num + j_rev] = asc_idx[bit_idx_rev];
            }
        }
    }

    return indices;
}

// lookup table of byte indices for 256 combinations of 8 mask bits
const table8x8: [256 * 8]u8 align(16) = table8x8_indices: {
    @setEvalBranchQuota(2500);
    break :table8x8_indices getLaneIndicesTable(8);
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
const table16x8: [256 * 8]u8 align(16) = table16x8_indices: {
    var indices: @Vector(256 * 8, u8) = table8x8[0.. 256 * 8].*;
    indices *= @splat(2);
    break :table16x8_indices indices;
};

// There are only 4 lanes, so we can afford to load the index vector directly.
const indices32x4: [16 * 16]u8 align(16) = table32x4_indices: {
    var indices = @as(@Vector(16 * 4, u32), getLaneIndicesTable(4));
    indices *= @splat(@as(u32, 0x04040404));
    indices += @splat(@as(u32, 0x03020100));
    break :table32x4_indices @bitCast(indices);
};

// There are only 2 lanes, so we can afford to load the index vector directly.
const indices64x2: [4 * 16]u8 align(16) = table32x4_indices: {
    var indices = @as(@Vector(4 * 2, u64), getLaneIndicesTable(2));
    indices *= @splat(@as(u64, 0x08080808_08080808));
    indices += @splat(@as(u64, 0x07060504_03020100));
    break :table32x4_indices @bitCast(indices);
};

fn idxFromBits128(comptime T: type, mask_bits: u64) @Vector(16, u8) {
    switch (@sizeOf(T)) {
        1 => {
            const mask0_bits = @as(usize, @intCast(mask_bits & 0xff));
            const mask1_bits = @as(usize, @intCast((mask_bits >> 8) & 0xff));
            const idx0: @Vector(8, u8) = table8x8[mask0_bits * 8 ..][0..8].*;
            var idx1: @Vector(8, u8) = table8x8[mask1_bits * 8 ..][0..8].*;
            idx1 += @splat(8);
            return std.simd.join(idx0, idx1);
        },
        2 => {
            // TODO: It is only tested in little-endian, it should to verify it
            // in big-endian
            const byte_idx: @Vector(8, u8) = table16x8[@intCast(mask_bits * 8) ..][0..8].*;
            switch (native_endian) {
                .little => return @bitCast(std.simd.interlace(.{ byte_idx, byte_idx + @as(@Vector(8, u8), @splat(1)) })),
                .big => return @bitCast(std.simd.interlace(.{ byte_idx + @as(@Vector(8, u8), @splat(1)), byte_idx })),
            }
        },
        4 => {
            return indices32x4[@intCast(mask_bits * 16) ..][0..16].*;
        },
        8 => {
            return indices64x2[@intCast(mask_bits * 16) ..][0..16].*;
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

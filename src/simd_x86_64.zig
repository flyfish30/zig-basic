const std = @import("std");

const target = @import("builtin").target;
const arch = target.cpu.arch;

const simd = @import("simd_core.zig");

const VEC_BITS_LEN = simd.VEC_BITS_LEN;
const VecLen = simd.VecLen;
const VecType = simd.VecType;

const VectorIndex = std.simd.VectorIndex;
const VecU8Index = VectorIndex(@Vector(VecLen(u8), u8));

const c = @cImport({
    @cInclude("immintrin.h");
    @cInclude("x86_64_intrins.h");
});

pub const SimdSamples = struct {
    pub fn binOpI16x8(vec1: simd.I16x8, vec2: simd.I16x8) simd.I16x8 {
        const acc = c._mm_mullo_epi16(@bitCast(vec1), @bitCast(vec2));
        return @bitCast(acc);
    }
};

inline fn mm_shuffle_u8(vec: @Vector(VecLen(u8), u8), idx: @Vector(VecLen(i8), i8)) @TypeOf(vec) {
    const mm_vec: @Vector(VecLen(i64), i64) = @bitCast(vec);
    const mm_idx: @Vector(VecLen(i64), i64) = @bitCast(idx);
    return asm ("vpshufb %[indices], %[tbl], %[result]"
        : [result] "=x" (-> @Vector(VecLen(u8), u8)),
        : [tbl] "x" (mm_vec),
          [indices] "x" (mm_idx),
    );
}

pub fn tableLookupBytes(tbl: @Vector(VecLen(u8), u8), idx: @Vector(VecLen(i8), i8)) @TypeOf(tbl) {
    switch (VEC_BITS_LEN) {
        128 => return mm_shuffle_u8(tbl, idx),
        256 => {
            const idx_u: @Vector(VecLen(u8), u8) = @bitCast(idx);
            // if index >= 128, then result byte is 0, lookup all lower 128 bits lanes
            const idx0_u = idx_u + @as(@Vector(VecLen(u8), u8), @splat(@intCast(128 - 16)));
            const idx0: @Vector(VecLen(i8), i8) = @bitCast(idx0_u);
            // if index < 0, then result byte is 0, lookup all upper 128 bits lanes
            const idx1 = idx - @as(@Vector(VecLen(i8), i8), @splat(@intCast(16)));
            const half_len = comptime VecLen(u8) / 2;
            const tbl_lo = std.simd.extract(tbl, 0, half_len);
            const dbl_tbl_lo = std.simd.join(tbl_lo, tbl_lo);
            const tbl_hi = std.simd.extract(tbl, half_len, half_len);
            const dbl_tbl_hi = std.simd.join(tbl_hi, tbl_hi);

            const result0 = mm_shuffle_u8(dbl_tbl_lo, idx0);
            const result1 = mm_shuffle_u8(dbl_tbl_hi, idx1);
            return result0 + result1;
        },
        // 512 => ,
        else => @compileError("tableLookupBytes: not support more than 512 bits or above"),
    }
}

inline fn mm128_shuffle_u8(vec: @Vector(16, u8), idx: @Vector(16, i8)) @TypeOf(vec) {
    const mm_vec: @Vector(2, i64) = @bitCast(vec);
    const mm_idx: @Vector(2, i64) = @bitCast(idx);
    return asm ("vpshufb %[indices], %[tbl], %[result]"
        : [result] "=x" (-> @Vector(16, u8)),
        : [tbl] "x" (mm_vec),
          [indices] "x" (mm_idx),
    );
}

pub fn tableLookup128Bytes(tbl: @Vector(16, u8), idx: @Vector(16, i8)) @TypeOf(tbl) {
    return mm128_shuffle_u8(tbl, idx);
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
    switch (VEC_BITS_LEN) {
        128 => {
            const asc_idx = std.simd.iota(i8, 16);
            // if index < 0, then result byte is 0
            const idx0: @Vector(16, i8) = asc_idx - @as(@Vector(16, i8), @splat(@intCast(count)));
            return mm_shuffle_u8(vec, idx0);
        },
        256 => {
            if (count == 0) {
                return vec;
            }

            // VEC_BITS_LEN == 256

            // ensure the count is u5 type, so it less than 32
            const count_u5 = @as(u5, count);
            var base_n: u8 = @bitCast(16 - @as(i8, count_u5));

            // if (count <= 16) then base_n += 128 - 16 else base_n
            const offset: u8 = ((base_n >> 7) ^ 0x1) * (128 - 16);
            base_n += offset;

            const asc_idx = std.simd.iota(i8, 16);
            const asc_idx_u: @Vector(16, u8) = @bitCast(asc_idx);
            // when index < 0, the result byte is 0
            // idx0 is [0-n, 0-n+1, .. -1, 0, 1, ..]
            const idx0: @Vector(16, i8) = asc_idx - @as(@Vector(16, i8), @splat(@intCast(count)));

            // if count <= 16, then
            //   when index >= 128, the result byte is 0,
            //   idx1_u is [128-n, 128-n+1, .. 128 - 1, 128, 129, ..]
            // else count > 16
            //   when index < 0, the result byte is 0,
            //   idx1 is [16-n, 16-n+1, .. -1, 0, 1, ..]
            const idx1_u: @Vector(16, u8) = asc_idx_u +% @as(@Vector(16, u8), @splat(base_n));
            const idx1: @Vector(16, i8) = @bitCast(idx1_u);
            // all indices in idx_lt0 is less than 0
            const idx_lt0: @Vector(16, i8) = @splat(-1);

            const result0 = mm_shuffle_u8(vec, std.simd.join(idx0, idx0));
            // shift left the vec by count
            const result1 = mm_shuffle_u8(vec, std.simd.join(idx1, idx_lt0));
            return result0 + std.simd.shiftElementsRight(result1, 16, 0);
        },
        // 512 => ,
        else => @compileError("shiftRightVecU8 not support 512 or above bits vector"),
    }
}

fn shiftLeftVecU8(vec: @Vector(VecLen(u8), u8), count: VectorIndex(@TypeOf(vec))) @TypeOf(vec) {
    switch (VEC_BITS_LEN) {
        128 => {
            const count_n = 128 - 16 + @as(u8, count);

            const asc_idx = std.simd.iota(i8, 16);
            const asc_idx_u: @Vector(16, u8) = @bitCast(asc_idx);
            // when index >= 128, the result byte is 0,
            // idx1_u is [112+n, 112+n+1, .. 128 - 1, 128, 129, ..]
            const idx0_u: @Vector(16, u8) = asc_idx_u +% @as(@Vector(16, u8), @splat(count_n));
            const idx0: @Vector(16, i8) = @bitCast(idx0_u);
            return mm_shuffle_u8(vec, idx0);
        },
        256 => {
            if (count == 0) {
                return vec;
            }

            // VEC_BITS_LEN == 256

            const count_n = 128 - 16 + @as(u8, count);

            // ensure the count is u5 type, so it less than 32
            const count_u5 = @as(u5, count);
            var base_n: u8 = @bitCast(@as(i8, count_u5) - 16);

            // if (count >= 16) then base_n += 128 - 16 else base_n
            const offset: u8 = ((base_n >> 7) ^ 0x1) * (128 - 16);
            base_n += offset;

            const asc_idx = std.simd.iota(i8, 16);
            const asc_idx_u: @Vector(16, u8) = @bitCast(asc_idx);
            // when index >= 128, the result byte is 0,
            // idx0_u is [112+n, 112+n+1, .. 128 - 1, 128, 129, ..]
            const idx0_u: @Vector(16, u8) = asc_idx_u +% @as(@Vector(16, u8), @splat(count_n));
            const idx0: @Vector(16, i8) = @bitCast(idx0_u);

            // if count >= 16, then
            //   when index >= 128, the result byte is 0,
            //   96 = 128 - 16 - 16
            //   idx1_u is [96+n, 96+n+1, .. 128 - 1, 128, 129, ..]
            // else count < 16
            //   when index < 0, the result byte is 0
            //   idx1_u is [n-16, n-16+1, .. -1, 0, 1, ..]
            const idx1_u: @Vector(16, u8) = asc_idx_u +% @as(@Vector(16, u8), @splat(base_n));
            const idx1: @Vector(16, i8) = @bitCast(idx1_u);
            // all indices in idx_lt0 is less than 0
            const idx_lt0: @Vector(16, i8) = @splat(-1);

            const result0 = mm_shuffle_u8(vec, std.simd.join(idx0, idx0));
            // shift left the vec by count
            const result1 = mm_shuffle_u8(vec, std.simd.join(idx_lt0, idx1));
            return result0 + std.simd.shiftElementsLeft(result1, 16, 0);
        },
        // 512 => ,
        else => @compileError("shiftLeftVecU8 not support VEC_BITS_LEN is " ++ VEC_BITS_LEN),
    }
}

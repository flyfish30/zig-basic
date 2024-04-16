const std = @import("std");
const simd = @import("simd_core.zig");

const target = @import("builtin").target;
const arch = target.cpu.arch;

const VEC_BITS_LEN = simd.VEC_BITS_LEN;
const VecLen = simd.VecLen;
const VecType = simd.VecType;

const VectorIndex = std.simd.VectorIndex;
const VecU8Index = VectorIndex(@Vector(VecLen(u8), u8));

const c = @cImport(
    @cInclude("arm_neon.h"),
);

pub const SimdSamples = struct {
    pub fn binOpI16x8(vec1: simd.I16x8, vec2: simd.I16x8) simd.I16x8 {
        const acc = c.vmulq_s16(vec1, vec2);
        return acc;
    }

    pub fn transpose4x4U32(vecs: [4]@Vector(4, u32)) @TypeOf(vecs) {
        const vec_t0: @Vector(4, u32) = c.vzip1q_u32(vecs[0], vecs[2]);
        const vec_t1: @Vector(4, u32) = c.vzip2q_u32(vecs[0], vecs[2]);
        const vec_t2: @Vector(4, u32) = c.vzip1q_u32(vecs[1], vecs[3]);
        const vec_t3: @Vector(4, u32) = c.vzip2q_u32(vecs[1], vecs[3]);
        const vec_out0: @Vector(4, u32) = c.vzip1q_u32(vec_t0, vec_t2);
        const vec_out1: @Vector(4, u32) = c.vzip2q_u32(vec_t0, vec_t2);
        const vec_out2: @Vector(4, u32) = c.vzip1q_u32(vec_t1, vec_t3);
        const vec_out3: @Vector(4, u32) = c.vzip2q_u32(vec_t1, vec_t3);
        std.debug.print("vec_ts: {any}, {any}, {any}, {any}\n", .{ vec_t0, vec_t1, vec_t2, vec_t3 });
        return .{ vec_out0, vec_out1, vec_out2, vec_out3 };
    }
};

inline fn neon_shuffle_u8(vec: @Vector(VecLen(u8), u8), idx: @Vector(VecLen(i8), i8)) @TypeOf(vec) {
    const neon_idx: @Vector(VecLen(u8), u8) = @bitCast(idx);
    return asm ("tbl.16b %[ret], { %[v0] }, %[v1]"
        : [ret] "=w" (-> @Vector(VecLen(u8), u8)),
        : [v0] "w" (vec),
          [v1] "w" (neon_idx),
    );
}

pub fn tableLookupBytes(tbl: @Vector(VecLen(u8), u8), idx: @Vector(VecLen(i8), i8)) @Vector(VecLen(u8), u8) {
    return neon_shuffle_u8(tbl, idx);
}

pub fn tableLookup128Bytes(tbl: @Vector(16, u8), idx: @Vector(16, i8)) @TypeOf(tbl) {
    // neon has 128 bits vector
    return neon_shuffle_u8(tbl, idx);
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
    return neon_shuffle_u8(vec, idx0);
}

fn shiftLeftVecU8(vec: @Vector(VecLen(u8), u8), count: VectorIndex(@TypeOf(vec))) @TypeOf(vec) {
    const count_n = 16 - @as(u8, count);

    const asc_idx = std.simd.iota(i8, 16);
    const asc_idx_u: @Vector(16, u8) = @bitCast(asc_idx);
    // when index >= 16, the result byte is 0,
    // idx1_u is [16-n, 16-n+1, .. 16 - 1, 16, 17, ..]
    const idx0_u: @Vector(16, u8) = asc_idx_u +% @as(@Vector(16, u8), @splat(count_n));
    const idx0: @Vector(16, i8) = @bitCast(idx0_u);
    return neon_shuffle_u8(vec, idx0);
}

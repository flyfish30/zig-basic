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

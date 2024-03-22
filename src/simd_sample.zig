const std = @import("std");
const target = @import("builtin").target;
const arch = target.cpu.arch;

pub const I64x2 = @Vector(2, i64);
pub const U64x2 = @Vector(2, u64);
pub const I32x4 = @Vector(4, i32);
pub const U32x4 = @Vector(4, u32);
pub const I16x8 = @Vector(8, i16);
pub const U16x8 = @Vector(8, u16);

pub const I32x4x4 = @Vector(16, u32);
pub const U32x4x4 = @Vector(16, u32);

const LINE_END_DELIM = switch (target.os.tag) {
    .windows => '\r',
    else => '\n',
};

const SimdSamples = switch (arch) {
    .x86_64 => @import("simd_x86_64.zig").SimdSamples,
    .aarch64 => @import("simd_aarch64.zig").SimdSamples,
    else => @import("simd_generic.zig").SimdSamples,
};

pub fn simdSample() !void {
    std.debug.print("target: {any}\n", .{target});
    std.debug.print("cpu arch: {any}\n", .{arch});

    switch (arch) {
        .x86_64 => {
            const hasFeature = std.Target.x86.featureSetHas;
            std.debug.print("cpu has avx2 feature: {any}\n", .{hasFeature(target.cpu.features, .avx2)});
        },
        .aarch64 => {
            const hasFeature = std.Target.aarch64.featureSetHas;
            std.debug.print("cpu has neon feature: {any}\n", .{hasFeature(target.cpu.features, .neon)});
        },

        .hexagon => {
            const hasFeature = std.Target.hexagon.featureSetHas;
            std.debug.print("cpu has hvxv68 feature: {any}\n", .{hasFeature(target.cpu.features, .hvxv68)});
        },
        else => {
            std.debug.print("the arch of cpu has generic simd supported!\n", .{});
        },
    }

    var vacc: @Vector(32, u32) = @splat(22);
    const v55: @Vector(32, u32) = @splat(55);
    const vb: @Vector(32, u32) = [_]u32{
        13, 46, 85, 36, 72, 82, 97, 23,
        82, 87, 12, 34, 28, 94, 62, 88,
        76, 98, 16, 39, 71, 83, 78, 46,
        86, 15, 92, 46, 38, 63, 26, 19,
    };

    const mask: @Vector(32, bool) = [_]bool{
        true, false, true,  true,  false, false, true,  true,
        true, false, false, true,  true,  false, true,  true,
        true, false, true,  false, false, true,  false, true,
        true, true,  false, true,  false, true,  true,  false,
    };

    var vcat: @Vector(64, u32) = @splat(95);
    vcat = std.simd.join(vacc, v55);
    std.debug.print("combine(vacc, v55) = {any}\n", .{vcat});

    const vbu64: @Vector(32, u64) = @as(@Vector(32, u64), vb);
    std.debug.print("extend vb is {any}\n", .{vbu64});

    vacc += vb;
    std.debug.print("type of vacc: {any}\n", .{@TypeOf(vacc)});
    std.debug.print("vacc + vb = {any}\n", .{vacc});

    vacc = @select(u32, mask, vacc, v55);
    std.debug.print("select vacc = {any}\n", .{vacc});

    var fa: I16x8 = @splat(25);
    const fb: I16x8 = @splat(32);
    fa = SimdSamples.binOpI16x8(fa, fb);
    std.debug.print("fa = {d}\n", .{fa});

    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();
    var bias_str: [8]u8 = undefined;
    try stdout.print("Please input a bias string:\n", .{});
    const readed_str = try stdin.readUntilDelimiter(&bias_str, LINE_END_DELIM);
    const bias = try std.fmt.parseInt(u32, readed_str, 10);
    std.debug.print("User input: {d}\n", .{bias});
    const vecs = [4]@Vector(4, u32){
        std.simd.iota(u32, 4) + @as(@Vector(4, u32), @splat(bias)),
        std.simd.iota(u32, 4) + @as(@Vector(4, u32), @splat(bias + 4)),
        std.simd.iota(u32, 4) + @as(@Vector(4, u32), @splat(bias + 8)),
        std.simd.iota(u32, 4) + @as(@Vector(4, u32), @splat(bias + 12)),
    };
    if (arch == .aarch64) {
        const vec4x4 = SimdSamples.transpose4x4U32(vecs);
        std.debug.print("transposed vec4x4: {any}\n", .{vec4x4});
    } else {
        const vec_zipped = transposeVec4x4_zip(@bitCast(vecs));

        // const vec_zipped = std.simd.interlace(vecs);
        const trn_vec1 = std.simd.extract(vec_zipped, 0, 4);
        const trn_vec2 = std.simd.extract(vec_zipped, 4, 4);
        const trn_vec3 = std.simd.extract(vec_zipped, 8, 4);
        const trn_vec4 = std.simd.extract(vec_zipped, 12, 4);
        std.debug.print("transposed vec4x4: {any}\n", .{[_]@Vector(4, u32){ trn_vec1, trn_vec2, trn_vec3, trn_vec4 }});
    }

    // transpose 8x8 matrix
    const vec64u32 = std.simd.iota(u32, 64) + @as(@Vector(64, u32), @splat(bias));
    {
        const z3_vecs = transposeVec8x8_zip(vec64u32);

        const vec_t0 = std.simd.extract(z3_vecs, 0, 8);
        const vec_t1 = std.simd.extract(z3_vecs, 8, 8);
        const vec_t2 = std.simd.extract(z3_vecs, 16, 8);
        const vec_t3 = std.simd.extract(z3_vecs, 24, 8);
        const vec_t4 = std.simd.extract(z3_vecs, 32, 8);
        const vec_t5 = std.simd.extract(z3_vecs, 40, 8);
        const vec_t6 = std.simd.extract(z3_vecs, 48, 8);
        const vec_t7 = std.simd.extract(z3_vecs, 56, 8);
        std.debug.print("transposed vec8x8: {any}\n", .{[_]@Vector(8, u32){ vec_t0, vec_t1, vec_t2, vec_t3, vec_t4, vec_t5, vec_t6, vec_t7 }});
    }

    const v16h: @Vector(16, i16) = [_]i16{
        13, 46,  85, 13688, 72, 82,  -11321, 23,
        82, -21, 12, 34,    28, -45, 62,     88,
    };
    const rt_i16: u32 = (@as(u32, 0xfffd) << 16) | @as(u32, 0xfffa); // (-3, -6) in u32
    const vmul_i16 = regVecMulS2wI16Even(v16h, rt_i16);
    std.debug.print("vmul_i16: {any}\n", .{vmul_i16});

    const rt_u16: u32 = (3 << 16) | 8;
    const vmul_u16 = regVecMulS2wU16Even(v16h, rt_u16);
    std.debug.print("vmul_u16: {any}\n", .{vmul_u16});
}

pub inline fn combine(vec1: @Vector(32, u32), vec2: @TypeOf(vec1)) @Vector(64, u32) {
    const T = u32;
    const N = 32;
    var pair_arr: [2 * N]T = undefined;
    var vec_slice: []T = &pair_arr;
    const vec1_slice: []T = @constCast(@ptrCast(&@as([N]T, @bitCast(vec1))));
    std.debug.print("vec1_slice: {any}\n", .{vec1_slice});
    const vec2_slice: []T = @constCast(@ptrCast(&@as([N]T, @bitCast(vec2))));
    std.debug.print("vec2_slice: {any}\n", .{vec2_slice});
    @memcpy(vec_slice[0..N], vec1_slice);
    std.debug.print("vec_slice[0..N]: {any}\n", .{vec_slice});
    @memcpy(vec_slice[N .. 2 * N], vec2_slice);
    std.debug.print("vec_slice[N..2*N]: {any}\n", .{vec_slice});
    var vec_pair: @Vector(64, u32) = pair_arr;
    return vec_pair;
}

inline fn transposeVec4x4_zip(vecs: @Vector(16, u32)) @Vector(16, u32) {
    const z0_vec0 = std.simd.extract(vecs, 0, 8);
    const z0_vec1 = std.simd.extract(vecs, 8, 8);
    const z1_vecs = std.simd.interlace([_]@Vector(8, u32){ z0_vec0, z0_vec1 });

    const z1_vec0 = std.simd.extract(z1_vecs, 0, 8);
    const z1_vec1 = std.simd.extract(z1_vecs, 8, 8);
    const z2_vecs = std.simd.interlace([_]@Vector(8, u32){ z1_vec0, z1_vec1 });

    return z2_vecs;
}

inline fn transposeVec16x4_zip(vecs: @Vector(64, u32)) @Vector(64, u32) {
    const z0_vec0 = std.simd.extract(vecs, 0, 32);
    const z0_vec1 = std.simd.extract(vecs, 32, 32);
    const z1_vecs = std.simd.interlace([_]@Vector(32, u32){ z0_vec0, z0_vec1 });

    const z1_vec0 = std.simd.extract(z1_vecs, 0, 32);
    const z1_vec1 = std.simd.extract(z1_vecs, 32, 32);
    const z2_vecs = std.simd.interlace([_]@Vector(32, u32){ z1_vec0, z1_vec1 });

    return z2_vecs;
}

inline fn transposeVec8x8_zip(vecs: @Vector(64, u32)) @Vector(64, u32) {
    const z0_vec0 = std.simd.extract(vecs, 0, 32);
    const z0_vec1 = std.simd.extract(vecs, 32, 32);
    const z1_vecs = std.simd.interlace([_]@Vector(32, u32){ z0_vec0, z0_vec1 });

    const z1_vec0 = std.simd.extract(z1_vecs, 0, 32);
    const z1_vec1 = std.simd.extract(z1_vecs, 32, 32);
    const z2_vecs = std.simd.interlace([_]@Vector(32, u32){ z1_vec0, z1_vec1 });

    const z2_vec0 = std.simd.extract(z2_vecs, 0, 32);
    const z2_vec1 = std.simd.extract(z2_vecs, 32, 32);
    const z3_vecs = std.simd.interlace([_]@Vector(32, u32){ z2_vec0, z2_vec1 });

    return z3_vecs;
}

fn regVecMulS2wI16Even(vec: @Vector(16, i16), rt: u32) @Vector(8, i32) {
    const v0v1 = std.simd.deinterlace(2, vec);
    const rh0: i16 = @bitCast(@as(u16, @truncate(rt)));
    const rh1: i16 = @bitCast(@as(u16, @truncate(rt >> 16)));
    const vrh0: @Vector(8, i32) = @splat(@intCast(rh0));
    const vrh1: @Vector(8, i32) = @splat(@intCast(rh1));
    std.debug.print("regVecMulS2wI16Even vrh0: {any}\n", .{vrh0});
    std.debug.print("regVecMulS2wI16Even vrh1: {any}\n", .{vrh1});

    const halfv0 = v0v1[0] * vrh0;
    const halfv1 = v0v1[1] * vrh1;
    std.debug.print("regVecMulS2wI16Even halfv0: {any}\n", .{halfv0});
    std.debug.print("regVecMulS2wI16Even halfv1: {any}\n", .{halfv1});
    std.debug.print("halfv0 type is {any}\n", .{@TypeOf(halfv0)});

    return halfv0 + halfv1;
}

fn regVecMulS2wU16Even(vec: @Vector(16, i16), rt: u32) @Vector(8, i32) {
    const v0v1 = std.simd.deinterlace(2, vec);
    const rh0: u16 = @as(u16, @truncate(rt));
    const rh1: u16 = @as(u16, @truncate(rt >> 16));
    const vrh0: @Vector(8, i32) = @splat(@intCast(rh0));
    const vrh1: @Vector(8, i32) = @splat(@intCast(rh1));
    std.debug.print("regVecMulS2wU16Even vrh0: {any}\n", .{vrh0});
    std.debug.print("regVecMulS2wU16Even vrh1: {any}\n", .{vrh1});

    const halfv0 = v0v1[0] * vrh0;
    const halfv1 = v0v1[1] * vrh1;
    std.debug.print("regVecMulS2wU16Even halfv0: {any}\n", .{halfv0});
    std.debug.print("regVecMulS2wU16Even halfv1: {any}\n", .{halfv1});
    std.debug.print("halfv0 type is {any}\n", .{@TypeOf(halfv0)});

    return halfv0 + halfv1;
}

// vec_pair is merged with a vec and itself shift right by 2
fn regVecMulS2wI16Odd(vec_pair: @Vector(32, i16), rt: u32) @Vector(8, i32) {
    const vec = std.simd.join(std.simd.extract(vec_pair, 1, 15), std.simd.extract(vec_pair, 30, 1));
    return regVecMulS2wI16Even(vec, rt);
}

// vec_pair is merged with a vec and itself shift right by 2
fn regVecMulS2wU16Odd(vec_pair: @Vector(32, i16), rt: u32) @Vector(8, i32) {
    const vec = std.simd.join(std.simd.extract(vec_pair, 1, 15), std.simd.extract(vec_pair, 30, 1));
    return regVecMulS2wU16Even(vec, rt);
}

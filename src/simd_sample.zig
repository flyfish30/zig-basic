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

    vacc += vb;
    std.debug.print("type of vacc: {any}\n", .{@TypeOf(vacc)});
    std.debug.print("vacc + vb = {any}\n", .{vacc});

    vacc = @select(u32, mask, vacc, v55);
    std.debug.print("select vacc = {any}\n", .{vacc});

    var fa: I16x8 = @splat(25);
    const fb: I16x8 = @splat(32);
    fa = SimdSamples.binOpI16x8(fa, fb);
    std.debug.print("fa = {d}\n", .{fa});

    var arr1: [4]u32 = undefined;
    var arr2: [4]u32 = undefined;
    var arr3: [4]u32 = undefined;
    var arr4: [4]u32 = undefined;
    var i: usize = 0;

    const stdin = std.io.getStdIn().reader();
    const stdout = std.io.getStdOut().writer();
    var bias_str: [8]u8 = undefined;
    try stdout.print("Please input a bias string:\n", .{});
    const readed_str = try stdin.readUntilDelimiter(&bias_str, LINE_END_DELIM);
    const bias = try std.fmt.parseInt(u32, readed_str, 10);
    std.debug.print("User input: {any}\n", .{bias});
    while (i < arr1.len) : (i += 1) {
        const a: u32 = @as(u32, @intCast(i)) + bias;
        arr1[i] = a;
        arr2[i] = a + 4;
        arr3[i] = a + 8;
        arr4[i] = a + 12;
    }
    const vecs = [4]@Vector(4, u32){
        arr1,
        arr2,
        arr3,
        arr4,
    };
    if (arch == .aarch64) {
        const vec4x4 = SimdSamples.transpose4x4U32(vecs);
        std.debug.print("transposed vec4x4: {any}\n", .{vec4x4});
    }
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

const std = @import("std");
const target = @import("builtin").target;
const arch = target.cpu.arch;

pub const I64x2 = @Vector(2, i64);
pub const U64x2 = @Vector(2, u64);
pub const I32x4 = @Vector(4, i32);
pub const U32x4 = @Vector(4, u32);
pub const I16x8 = @Vector(8, i16);
pub const U16x8 = @Vector(8, u16);

const SimdSamples = GetSimdSamples();

fn GetSimdSamples() type {
    comptime var T: type = undefined;

    if (arch == .x86_64) {
        T = @import("simd_x86_64.zig");
    } else if (arch == .aarch64) {
        T = @import("simd_aarch64.zig");
    } else {
        T = @import("simd_generic.zig");
    }

    return T.SimdSamples;
}

pub fn simdSample() void {
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

    vacc += vb;
    std.debug.print("vacc + vb = {any}\n", .{vacc});

    vacc = @select(u32, mask, vacc, v55);
    std.debug.print("select vacc = {any}\n", .{vacc});

    var fa: I16x8 = @splat(25);
    const fb: I16x8 = @splat(32);
    fa = SimdSamples.binOpI16x8(fa, fb);
    std.debug.print("fa = {d}\n", .{fa});
}

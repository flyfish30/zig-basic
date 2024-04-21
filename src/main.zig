const std = @import("std");
const misc = @import("base_examples.zig");
const img = @import("image_processing.zig");
const sd = @import("simd_sample.zig");
const simd = @import("simd_core.zig");
const bisort = @import("bitonic_sort.zig");
const vqsort = @import("vec_qsort.zig");

const Allocator = std.mem.Allocator;

const VecLen = simd.VecLen;
const VecType = simd.VecType;

// export fn _start() callconv(.C) noreturn {
//     try @call(.auto, main, .{});
// }

pub fn main() !void {
    // for (std.os.argv) |arg| {
    //     std.debug.print("arg: {s}\n", .{arg});
    // }

    try misc.stdoutExample();
    try misc.baseExample();
    try sd.simdSample();

    bitonicSortSample();
    vqsortSample();

    if (std.os.argv.len > 1) {
        try img.readAndProcessImage(std.mem.span(std.os.argv[1]));
    }
}

fn bitonicSortSample() void {
    const IntType = u8;
    var prnd = std.rand.DefaultPrng.init(83751737);
    var array_int: [simd.VecLen(IntType)]IntType = undefined;
    for (&array_int) |*a| {
        a.* = prnd.random().int(IntType);
    }
    var vec_int: simd.VecType(IntType) = array_int;
    std.debug.print("original vec_int is: {any}\n", .{vec_int});

    vec_int = bisort.bitonicSort1V(IntType, vec_int);
    std.debug.print("sorted vec_int is: {any}\n", .{vec_int});
    return;
}

fn vqsortSample() void {
    const IntType = u32;
    var prnd = std.rand.DefaultPrng.init(83751737);
    var array_int: [VecLen(IntType)]IntType = undefined;
    for (&array_int) |*a| {
        a.* = prnd.random().int(IntType);
    }
    array_int[VecLen(IntType) - 1] = 5;
    std.debug.print("original array_int is: {any}\n", .{array_int});

    vqsort.vqsort(IntType, array_int[0 .. VecLen(IntType) - 1]);
    std.debug.print("vqsort array_int is: {any}\n", .{array_int});
    return;
}

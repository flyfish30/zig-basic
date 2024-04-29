const std = @import("std");
const misc = @import("base_examples.zig");
const img = @import("image_processing.zig");
const sd = @import("simd_sample.zig");
const simd = @import("simd_core.zig");
const sortv = @import("sort_vectors.zig");
const vqsort = @import("vqsort.zig");

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
    try vqsortSample();

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

    var vecn_tuple: simd.VecNTuple(1, IntType) = undefined;
    vecn_tuple[0] = vec_int;
    vecn_tuple = sortv.sortNVecs(1, IntType, vecn_tuple);
    vec_int = vecn_tuple[0];
    std.debug.print("sorted vec_int is: {any}\n", .{vec_int});
    return;
}

fn vqsortSample() !void {
    const IntType = u16;
    var prnd = std.rand.DefaultPrng.init(83751737);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var array_int = try allocator.alloc(IntType, 3749);
    defer allocator.free(array_int);
    for (array_int) |*a| {
        a.* = prnd.random().int(IntType);
    }
    array_int[VecLen(IntType) - 1] = 5;
    std.debug.print("original array_int is: {any}\n", .{array_int});

    vqsort.vqsort(IntType, array_int);
    const is_sorted = vqsort.isSorted(IntType, array_int);
    std.debug.print("vqsort array_int is: {any}\n", .{array_int});
    std.debug.print("vqsort array_int is_sorted={any}\n", .{is_sorted});
    return;
}

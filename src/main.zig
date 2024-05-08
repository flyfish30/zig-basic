const std = @import("std");
const misc = @import("base_examples.zig");
const img = @import("image_processing.zig");
const sd = @import("simd_sample.zig");
const simd = @import("simd_core.zig");
const sortv = @import("sort_vectors.zig");
const sortn = @import("sorting_networks.zig");
const vqsort = @import("vqsort.zig");

const Allocator = std.mem.Allocator;

const VecLen = simd.VecLen;
const VecType = simd.VecType;

test {
    std.testing.refAllDecls(@This());
}

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

    vecSortSample();
    try vqsortSample();

    if (std.os.argv.len > 1) {
        try img.readAndProcessImage(std.mem.span(std.os.argv[1]));
    }
}

fn vecSortSample() void {
    const IntType = u8;
    const N = comptime VecLen(IntType);
    const N_VECS = 16;
    var prnd = std.rand.DefaultPrng.init(83751737);
    var array_int: [N*N_VECS]IntType = undefined;
    for (&array_int) |*a| {
        a.* = prnd.random().int(IntType);
    }

    comptime var i = 0;
    var vecn_tuple: [N_VECS]VecType(IntType) = undefined;
    inline while (i < N_VECS) : (i += 1) {
        vecn_tuple[i] = array_int[i * N ..][0 .. N].*;
        // std.debug.print("original vec_int[{d}] is: {any}\n", .{i, vecn_tuple[i]});
    }

    sortv.sortNVecs(N_VECS, IntType, &vecn_tuple);

    i = 0;
    inline while (i < N_VECS) : (i += 1) {
        array_int[i * N ..][0 .. N].* = vecn_tuple[i];
        // std.debug.print("sorted vec_int[{d}] is: {any}\n", .{i, vecn_tuple[i]});
    }
    const is_sorted = vqsort.isSorted(IntType, simd.asSlice(IntType, &array_int));
    std.debug.print("vecSort array_int is_sorted={any}\n", .{is_sorted});
    return;
}

fn vqsortSample() !void {
    const IntType = u8;
    var prnd = std.rand.DefaultPrng.init(83751737);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var array_int = try allocator.alloc(IntType, 23749);
    defer allocator.free(array_int);
    for (array_int) |*a| {
        a.* = prnd.random().int(IntType);
    }
    array_int[VecLen(IntType) - 1] = 5;
    // std.debug.print("original array_int is: {any}\n", .{array_int});

    vqsort.vqsort(IntType, array_int);
    const is_sorted = vqsort.isSorted(IntType, array_int);
    // std.debug.print("vqsort array_int is: {any}\n", .{array_int});
    std.debug.print("vqsort array_int is_sorted={any}\n", .{is_sorted});
    return;
}

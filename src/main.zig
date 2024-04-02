const std = @import("std");
const misc = @import("base_examples.zig");
const img = @import("image_processing.zig");
const sd = @import("simd_sample.zig");
const bisort = @import("bitonic_sort.zig");

const Allocator = std.mem.Allocator;

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

    if (std.os.argv.len > 1) {
        try img.readAndProcessImage(std.mem.span(std.os.argv[1]));
    }
}

fn bitonicSortSample() void {
    const IntType = u8;
    var prnd = std.rand.DefaultPrng.init(83751737);
    var array_int: [bisort.VecLen(IntType)]IntType = undefined;
    for (&array_int) |*a| {
        a.* = prnd.random().int(IntType);
    }
    var vec_int: bisort.VecType(IntType) = array_int;
    std.debug.print("original vec_int is: {any}\n", .{vec_int});

    vec_int = bisort.bitonicSort1V(IntType, vec_int);
    std.debug.print("sorted vec_int is: {any}\n", .{vec_int});
    return;
}

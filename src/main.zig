const std = @import("std");
const misc = @import("base_examples.zig");
const img = @import("image_processing.zig");
const sd = @import("simd_sample.zig");
const simd = @import("simd_core.zig");
const sortv = @import("sort_vectors.zig");
const sortn = @import("sorting_networks.zig");
const vqsort = @import("vqsort.zig");
const funalg = @import("functor_alg.zig");
const pfunalg = @import("pure_functor_alg.zig");
const default = @import("default.zig");

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
    try funalg.algSample();
    pfunalg.pureAlgSample();

    vecSortSample();
    try vqsortSample();

    if (std.os.argv.len > 1) {
        try img.readAndProcessImage(std.mem.span(std.os.argv[1]));
    }

    try defaultSample();
    try errorSample();
}

fn vecSortSample() void {
    const IntType = u8;
    const N = comptime VecLen(IntType);
    const N_VECS = 16;
    var prnd = std.rand.DefaultPrng.init(83754737);
    var array_int: [N * N_VECS]IntType = undefined;
    for (&array_int) |*a| {
        a.* = prnd.random().int(IntType);
    }

    comptime var i = 0;
    var vecn_tuple: [N_VECS]VecType(IntType) = undefined;
    inline while (i < N_VECS) : (i += 1) {
        vecn_tuple[i] = array_int[i * N ..][0..N].*;
        // std.debug.print("original vec_int[{d}] is: {any}\n", .{i, vecn_tuple[i]});
    }

    sortv.sortNVecs(N_VECS, IntType, &vecn_tuple);

    i = 0;
    inline while (i < N_VECS) : (i += 1) {
        array_int[i * N ..][0..N].* = vecn_tuple[i];
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
    var array_int = try allocator.alloc(IntType, 3749);
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

const Default = default.Default;
const BaseNoneDefaultInst = default.BaseNoneDefaultInst;
const VectorDefaultInst = default.VectorDefaultInst;
const DeriveNoneDefaultInst = default.DeriveNoneDefaultInst;

fn defaultSample() !void {
    const i32_def = Default(BaseNoneDefaultInst(i32), i32).init(.{ .none = {} });
    std.debug.print("i32 default is {d}\n", .{i32_def.default()});

    const Vec1 = @Vector(8, i32);
    const vec_def = Default(VectorDefaultInst(Vec1), Vec1).init(.{ .none = {} });
    std.debug.print("Vec(8, i32) default is {any}\n", .{vec_def.default()});

    const Gender = enum {
        Male,
        Female,
    };

    const Person = struct {
        age: u8,
        name: [:0]u8,
        address: [:0]u8,
        postcode: ?[*:0]u8,
        gender: Gender,
        score: u32,
    };
    const person_def = Default(DeriveNoneDefaultInst(Person), Person).init(.{ .none = {} });
    const def_val = person_def.default();
    std.debug.print("Person default is {any}\n", .{def_val});
    std.debug.print("person name: {s}", .{def_val.name});
    return;
}

fn errorSample() Allocator.Error!void {
    var a: u32 = 0;
    _ = &a;
    if (a == 42) {
        // If return error.BadNumber, it will cause a
        // error: expected type 'error{OutOfMemory}', found type 'error{BadNumber}'
        // return error.BadNumber;
        return error.OutOfMemory;
    }

    // If call function checkBadNumber, it will cause a
    // error: expected type 'error{OutOfMemory}', found 'error{BadNumber}'.
    // Because the 'error.BadNumber' not a member of error set Allocator.Error.
    // _ = try checkBadNumber(a);
    return;
}

fn checkBadNumber(n: u32) error{BadNumber}!u32 {
    if (n == 42) return error.BadNumber;
    return n + 40;
}

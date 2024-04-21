const std = @import("std");
const builtin = @import("builtin");
const bisort = @import("bitonic_sort.zig");
const simd = @import("simd_core.zig");

const VEC_BITS_LEN = simd.VEC_BITS_LEN;
const VecLen = simd.VecLen;
const VecType = simd.VecType;
const vectorLength = simd.vectorLength;
const VecChild = simd.VecChild;

pub fn vqsort(comptime T: type, buf: []T) void {
    const maxLevels: usize = 60;
    doVecQSort(T, buf, maxLevels);
}

fn doVecQSort(comptime T: type, buf: []T, remLevels: usize) void {
    if (buf.len <= VecLen(T)) {
        const asc_idx = std.simd.iota(usize, VecLen(T));
        const mask = asc_idx < @as(@Vector(VecLen(T), usize), @splat(buf.len));
        const pad = switch (@typeInfo(T)) {
            .Int, .ComptimeInt => std.math.maxInt(T),
            .Float, .ComptimeFloat => std.math.floatMax,
            else => @compileError("bad type"),
        };
        const pad_vec: @Vector(VecLen(T), T) = @splat(pad);
        var vec: @Vector(VecLen(T), T) = simd.maskedLoadVecOr(T, pad_vec, mask, buf);
        vec = bisort.bitonicSort1V(T, vec);
        simd.maskedStoreVec(T, mask, buf, vec);
        return;
    }

    const pivot = getPivot(T, buf);
    const mid = partition(T, buf, pivot);
    doVecQSort(T, buf[0..mid], remLevels - 1);
    doVecQSort(T, buf[mid + 1 .. buf.len], remLevels - 1);
}

fn partition(comptime T: type, buf: []T, pivot: T) usize {
    _ = pivot;
    return (buf.len / 2);
}

fn getPivot(comptime T: type, buf: []T) T {
    return buf[0];
}

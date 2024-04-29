const std = @import("std");
const builtin = @import("builtin");
const simd = @import("simd_core.zig");
const psel = @import("pack_select.zig");
const sortv = @import("sort_vectors.zig");

const assert = std.debug.assert;

const VEC_BITS_LEN = simd.VEC_BITS_LEN;
const VecLen = simd.VecLen;
const VecType = simd.VecType;
const vectorLength = simd.vectorLength;
const VecChild = simd.VecChild;
const VecNTuple = simd.VecNTuple;

const BorderSafe = enum {
    unsafed,
    safed,
};

// SortConstants
const MAX_ROWS: usize = 16;
const MAX_COLS: usize = 16;
//   the partition unroll number must be power of 2
const N_UNROLL: usize = 1 << 2; // 4

// maximum count for vectorize sort
fn lenVSort(comptime T: type, comptime N: usize) usize {
    const rows_num = if ((N / VecLen(T)) >= 4) MAX_ROWS else 8;
    return rows_num * @min(N, MAX_COLS);
}

pub fn vqsort(comptime T: type, buf: []T) void {
    const maxLevels: usize = 60;

    if (buf.len <= VecLen(T)) {
        sortSmallBuf(T, buf, buf.len, .unsafed);
        return;
    }

    // Guanteed to have at least one vector length space
    vqsortRec(T, buf, 0, buf.len, maxLevels);
}

pub fn isSorted(comptime T: type, buf: []T) bool {
    var i: usize = 0;
    while (i + 1 < buf.len) : (i += 1) {
        if (buf[i] > buf[i + 1]) {
            break;
        }
    } else {
        return true;
    }

    return false;
}

// recusive function for vqsort
fn vqsortRec(comptime T: type, buf: []T, start: usize, num: usize, remLevels: usize) void {
    if (num <= VecLen(T)) {
        sortSmallBuf(T, buf[start..], num, .unsafed);
        return;
    }

    const pivot = getPivotNSamples(T, buf[start .. start + num]);
    const mid = partition(T, buf, start, num, pivot);
    if (mid + VecLen(T) <= buf.len) {
        vqsortRecSafe(T, buf, start, mid - start, remLevels - 1);
    } else {
        vqsortRec(T, buf, start, mid - start, remLevels - 1);
    }
    if (start + num + VecLen(T) <= buf.len) {
        vqsortRecSafe(T, buf, mid, start + num - mid, remLevels - 1);
    } else {
        vqsortRec(T, buf, mid, start + num - mid, remLevels - 1);
    }
}

// recusive function for vqsort that has enough space to load/store vector
// in right most element
fn vqsortRecSafe(comptime T: type, buf: []T, start: usize, num: usize, remLevels: usize) void {
    if (num <= VecLen(T)) {
        sortSmallBuf(T, buf[start..], num, .safed);
        return;
    }

    const pivot = getPivotNSamples(T, buf[start .. start + num]);
    const mid = partition(T, buf, start, num, pivot);
    vqsortRecSafe(T, buf, start, mid - start, remLevels - 1);
    vqsortRecSafe(T, buf, mid, start + num - mid, remLevels - 1);
}

fn sortSmallBuf(comptime T: type, buf: []T, num: usize, comptime border: BorderSafe) void {
    var vecn_tuple: VecNTuple(1, T) = undefined;
    const asc_idx = std.simd.iota(usize, VecLen(T));
    const mask = asc_idx < @as(@Vector(VecLen(T), u16), @splat(@intCast(num)));
    const pad = switch (@typeInfo(T)) {
        .Int, .ComptimeInt => std.math.maxInt(T),
        .Float, .ComptimeFloat => std.math.floatMax,
        else => @compileError("bad type"),
    };
    const pad_vec: @Vector(VecLen(T), T) = @splat(pad);
    if (border == .safed) {
        // We has enough space to laod vector, so use blendedLoadVecOr function
        vecn_tuple[0] = simd.blendedLoadVecOr(T, pad_vec, mask, buf);
    } else {
        vecn_tuple[0] = simd.maskedLoadVecOr(T, pad_vec, mask, buf[0..num]);
    }
    vecn_tuple = sortv.sortNVecs(1, T, vecn_tuple);
    if (border == .safed) {
        // We has enough space to store vector, so use blendedStoreVecOr function
        simd.blendedStoreVec(T, mask, buf, vecn_tuple[0]);
    } else {
        simd.maskedStoreVec(T, mask, buf[0..num], vecn_tuple[0]);
    }
    return;
}

// Moves "<= pivot" keys to the front, and others to the back. pivot is
// broadcasted. Returns the index of the first key in the right partition.
//
// Time-critical, but aligned loads do not seem to be worthwhile because we
// are not bottlenecked by load ports.
//
// Partition splits the vector into 3 sections, left to right: Elements
// smaller or equal to the pivot, unpartitioned elements and elements larger
// than the pivot. To write elements unconditionally on the loop body without
// overwriting existing data, we maintain two regions of the loop where all
// elements have been copied elsewhere (e.g. vector registers.). I call these
// bufferL and bufferR, for left and right respectively.
//
// These regions are tracked by the indices (writeL, writeR, left, right) as
// presented in the diagram below.
//
//              writeL                                  writeR
//               \/                                       \/
//  |  <= pivot   | bufferL |   unpartitioned   | bufferR |   > pivot   |
//                          \/                  \/                      \/
//                         readL               readR                   num
//
fn partition(comptime T: type, buf: []T, start: usize, num: usize, pivot: T) usize {
    // number of vector lanes
    const N = comptime VecLen(T);

    var readL = start;
    var writeL = readL;
    var readR = start + num;
    // var writeR = readR;

    var remaining = num; // writeR - writeL
    var num_irreg = num;

    std.debug.print("partition num={d} pivot={d}, start={d}\n", .{ num, pivot, start });
    std.debug.print("partition readL={d}, readR={d}\n", .{ readL, readR });
    if (num < 2 * N_UNROLL * N) {
        var vn_arr: [2 * N_UNROLL]@Vector(N, T) = undefined;
        // writeR = writeL + remaining;
        var i: usize = 0;
        while (num_irreg >= N) : (i += 1) {
            vn_arr[i] = buf[readL..][0..N].*;
            readL += N;
            num_irreg -= N;
        }
        // std.debug.print("after vectors readL={d}, readR={d}, i={d}\n", .{ readL, readR, i });

        // Last iteration: avoid reading past the end. use maskedLoadVec function
        // to load partial vector, and combine with pad value
        var vlast: @Vector(N, T) = undefined;
        if (num_irreg > 0) {
            const part_mask = simd.maskFirstN(T, num_irreg);
            const pad = switch (@typeInfo(T)) {
                .Int, .ComptimeInt => std.math.maxInt(T),
                .Float, .ComptimeFloat => std.math.floatMax,
                else => @compileError("bad type"),
            };
            const pad_vec: @Vector(VecLen(T), T) = @splat(pad);
            vlast = simd.maskedLoadVecOr(T, pad_vec, part_mask, buf[readL .. readL + num_irreg]);
            readL += num_irreg;
        }

        // std.debug.print("after last readL={d}, readR={d}, num_irreg={d}\n", .{ readL, readR, num_irreg });
        // All data are readed to vectors
        assert(readL == readR);

        var j: usize = 0;
        while (j + 1 < i) : (j += 1) {
            storeLeftRight(T, vn_arr[j], pivot, buf, &writeL, &remaining);
        }

        // std.debug.print("store vectors  writeL={d}, remaining={d}, j={d}\n", .{ writeL, remaining, j });
        // Use funtion blendedStoreLeftRight for the last vector because
        // StoreLeftRight may overwrite partitioned data
        blendedStoreLeftRight(T, vn_arr[j], pivot, buf, &writeL, &remaining);

        // std.debug.print("last vector writeL={d}, remaining={d}, j={d}\n", .{ writeL, remaining, j });
        assert(remaining == num_irreg);
        if (num_irreg > 0) {
            // Use function lastStoreLeftRight for residual unpartitioned data less
            // than the size of a vector.
            lastStoreLeftRight(T, vlast, pivot, buf, &writeL, &remaining);
        }

        // std.debug.print("after last vector  writeL={d}\n", .{ writeL});
        // Ensure the all regualar data had been partitioned, the remaining
        // of regualar data is just 0
        assert(remaining == 0);
        return writeL;
    }

    // else   num >= 2 * N_UNROLL * N
    var vLn_tuple: VecNTuple(4, T) = undefined;
    var vRn_tuple: VecNTuple(4, T) = undefined;

    // partition mutiple blocks, the block size is N_UNROLL * N
    num_irreg = num & (2 * N_UNROLL * N - 1);
    const num_main = num - num_irreg;

    vLn_tuple[0] = buf[readL + 0 * N ..][0..N].*;
    vLn_tuple[1] = buf[readL + 1 * N ..][0..N].*;
    vLn_tuple[2] = buf[readL + 2 * N ..][0..N].*;
    vLn_tuple[3] = buf[readL + 3 * N ..][0..N].*;
    readL += N_UNROLL * N;
    readR -= N_UNROLL * N;
    vRn_tuple[0] = buf[readR + 0 * N ..][0..N].*;
    vRn_tuple[1] = buf[readR + 1 * N ..][0..N].*;
    vRn_tuple[2] = buf[readR + 2 * N ..][0..N].*;
    vRn_tuple[3] = buf[readR + 3 * N ..][0..N].*;
    // std.debug.print("partition before loop num_irreg={d}, readL={d}, readR={d}\n", .{ num_irreg, readL, readR });

    // In the main loop body below we choose a side, load some elements out of the
    // vector and move either `readL` or `readR`. Next we call into StoreLeftRight
    // to partition the data, and the partitioned elements will be written either
    // to writeR or writeL and the corresponding index will be moved accordingly.
    //
    // Note that writeR is not explicitly tracked as an optimization for platforms
    // with conditional operations. Instead we track writeL and the number of
    // not yet written elements (`remaining`). From the diagram above we can see
    // that:
    //    writeR - writeL = remaining => writeR = remaining + writeL
    //
    // Tracking `remaining` is advantageous because each iteration reduces the
    // number of unpartitioned elements by a fixed amount, so we can compute
    // `remaining` without data dependencies.

    // Check if size of unpartioned region is equal to num_irreg, if the result
    // is true than break the main loop.
    while (readR - readL != num_irreg) {
        const capacityL = readL - writeL;
        assert(capacityL <= num_main);

        // Load data from the end of the vector with less data (front or back).
        // The next paragraphs explain how this works.
        //
        // let block_size = (kUnroll * N)
        // On the loop prelude we load block_size elements from the front of the
        // vector and an additional block_size elements from the back. On each
        // iteration k elements are written to the front of the vector and
        // (block_size - k) to the back.
        //
        // This creates a loop invariant where the capacity on the front
        // (capacityL) and on the back (capacityR) always add to 2 * block_size.
        // In other words:
        //    capacityL + capacityR = 2 * block_size
        //    capacityR = 2 * block_size - capacityL
        //
        // This means that:
        //    capacityL > capacityR <=>
        //    capacityL > 2 * block_size - capacityL <=>
        //    2 * capacityL > 2 * block_size <=>
        //    capacityL > block_size
        var readCur: usize = undefined;
        var prefetchCur: usize = undefined;
        if (capacityL > N_UNROLL * N) {
            readR -= N_UNROLL * N;
            readCur = readR;
            prefetchCur = readR - 3 * N_UNROLL * N;
        } else {
            readCur = readL;
            readL += N_UNROLL * N;
            prefetchCur = readL + 3 * N_UNROLL * N;
        }

        // std.debug.print("partition mainloop readL={d}, readR={d}\n", .{ readL, readR });

        var vn_tuple: VecNTuple(4, T) = undefined;
        vn_tuple[0] = buf[readCur + 0 * N ..][0..N].*;
        vn_tuple[1] = buf[readCur + 1 * N ..][0..N].*;
        vn_tuple[2] = buf[readCur + 2 * N ..][0..N].*;
        vn_tuple[3] = buf[readCur + 3 * N ..][0..N].*;
        const fetchOps = std.builtin.PrefetchOptions{ .rw = .read, .cache = .data, .locality = 0 };
        @prefetch(&buf[prefetchCur], fetchOps);

        storeLeftRightN(4, T, vn_tuple, pivot, buf, &writeL, &remaining);
    }
    // There are last eight vector in vLn_tuple and vRn_tuple should store
    // to buf, ensure the remaining of regualar data is just 8 * N.
    assert(remaining - num_irreg == 8 * N);

    // partition remain irregular elements
    // For whole vectors, we can load entire vector
    while (num_irreg >= N) {
        var vtmp: @Vector(N, T) = undefined;
        //    In above comments, we have:
        //    capacityL > capacityR <=>
        //    capacityL > 2 * block_size - capacityL <=>
        //    2 * capacityL > 2 * block_size <=>
        //    capacityL > block_size
        const capacityL = readL - writeL;
        if (capacityL > N_UNROLL * N) {
            readR -= N;
            vtmp = buf[readR..][0..N].*;
        } else {
            vtmp = buf[readL..][0..N].*;
            readL += N;
        }
        num_irreg -= N;
        storeLeftRight(T, vtmp, pivot, buf, &writeL, &remaining);
    }

    // Last iteration: avoid reading past the end. use maskedLoadVec function
    // to load partial vector, and combine with pad value
    var vlast: @Vector(N, T) = undefined;
    if (num_irreg > 0) {
        const part_mask = simd.maskFirstN(T, num_irreg);
        const pad = switch (@typeInfo(T)) {
            .Int, .ComptimeInt => std.math.maxInt(T),
            .Float, .ComptimeFloat => std.math.floatMax,
            else => @compileError("bad type"),
        };
        const pad_vec: @Vector(VecLen(T), T) = @splat(pad);
        vlast = simd.maskedLoadVecOr(T, pad_vec, part_mask, buf[readL .. readL + num_irreg]);
        readL += num_irreg;
    }

    // Now finish writing the saved vectors to the middle.
    storeLeftRightN(4, T, vLn_tuple, pivot, buf, &writeL, &remaining);

    storeLeftRight(T, vRn_tuple[0], pivot, buf, &writeL, &remaining);
    storeLeftRight(T, vRn_tuple[1], pivot, buf, &writeL, &remaining);

    // There are last two vector in vR2/3 should store to buf, ensure the
    // remaining of regualar data is just 2 * N.
    assert(remaining - num_irreg == 2 * N);

    // Use funtion blendedStoreLeftRight for the last two vectors because
    // StoreLeftRight may overwrite partitioned data
    blendedStoreLeftRight(T, vRn_tuple[2], pivot, buf, &writeL, &remaining);
    blendedStoreLeftRight(T, vRn_tuple[3], pivot, buf, &writeL, &remaining);

    assert(remaining == num_irreg);
    if (num_irreg > 0) {
        // Use function lastStoreLeftRight for residual unpartitioned data less
        // than the size of a vector.
        lastStoreLeftRight(T, vlast, pivot, buf, &writeL, &remaining);
    }

    // Ensure the all regualar data had been partitioned, the remaining
    // of regualar data is just 0
    assert(remaining == 0);
    return writeL;
}

fn storeLeftRightN(comptime N: usize, comptime T: type, vtuple: VecNTuple(N, T), pivot: T, buf: []T, writeL: *usize, remaining: *usize) void {
    comptime var i = 0;
    inline while (i < N) : (i += 1) {
        storeLeftRight(T, vtuple[i], pivot, buf, writeL, remaining);
    }
}

fn storeLeftRight(comptime T: type, vec: @Vector(VecLen(T), T), pivot: T, buf: []T, writeL: *usize, remaining: *usize) void {
    const N = comptime VecLen(T);
    const mask = vec <= @as(@Vector(VecLen(T), T), @splat(pivot));
    const int_mask = @as(std.meta.Int(.unsigned, VecLen(T)), @bitCast(mask));
    const num_left = @popCount(int_mask);

    // ensure the remain space is large than 2 * VecLen(T), so we can store
    // entire vector to buf.
    // assert(remaining.* >= 2 * VecLen(T));
    remaining.* -= VecLen(T);
    const pack_pair = psel.packSelect(vec, mask);

    // std.debug.print("storeLeftRight vec={any}\n", .{vec});
    // std.debug.print("storeLeftRight mask={any} num_left={d}\n", .{ mask, num_left });

    // Because we store entire vectors, the contents between the updated writeL
    // and writeR are ignored and will be overwritten by subsequent calls. This
    // works because writeL and writeR are at least two vectors apart.
    buf[writeL.*..][0..N].* = pack_pair[0];
    buf[writeL.* + remaining.* ..][0..N].* = pack_pair[1];
    writeL.* += num_left;
}

// For the last two vectors, we can not use storeLeftRight because it might
// overwrite remain unpartitioned data. We must use blendedStoreVec to store
// entire vector.
fn blendedStoreLeftRight(comptime T: type, vec: @Vector(VecLen(T), T), pivot: T, buf: []T, writeL: *usize, remaining: *usize) void {
    const N = comptime VecLen(T);
    const mask = vec <= @as(@Vector(VecLen(T), T), @splat(pivot));
    const int_mask = @as(std.meta.Int(.unsigned, VecLen(T)), @bitCast(mask));
    const num_left = @popCount(int_mask);

    remaining.* -= VecLen(T);
    const pack_pair = psel.packSelect(vec, mask);

    // std.debug.print("blendedStoreLeftRight vec={any}\n", .{vec});
    // std.debug.print("blendedStoreLeftRight mask={any} num_left={d}\n", .{ mask, num_left });

    // Because we store entire vectors, so we blend the contents between the
    // writeL and writeR.
    const left_mask = simd.maskFirstN(T, num_left);
    const right_mask = left_mask != @as(@Vector(N, bool), @splat(true));
    simd.blendedStoreVec(T, left_mask, buf[writeL.*..][0..N], pack_pair[0]);
    simd.blendedStoreVec(T, right_mask, buf[writeL.* + remaining.* ..][0..N], pack_pair[1]);
    writeL.* += num_left;
}

// For the last vectors, we can not use blendedLeftRight because it might write
// past the end. We must use maskedStoreVec to store partial vector.
fn lastStoreLeftRight(comptime T: type, vec: @Vector(VecLen(T), T), pivot: T, buf: []T, writeL: *usize, remaining: *usize) void {
    const mask = vec <= @as(@Vector(VecLen(T), T), @splat(pivot));
    const int_mask = @as(std.meta.Int(.unsigned, VecLen(T)), @bitCast(mask));
    const num_left = @popCount(int_mask);

    // std.debug.print("lastStoreLeftRight vlast={any}\n", .{vec});
    // std.debug.print("lastStoreLeftRight mask={any} num_left={d}\n", .{ mask, num_left });

    const pack_pair = psel.packSelect(vec, mask);
    const left_mask = simd.maskFirstN(T, num_left);
    const pack_comb = @select(T, left_mask, pack_pair[0], pack_pair[1]);

    assert(remaining.* < VecLen(T));
    const part_mask = simd.maskFirstN(T, remaining.*);
    simd.maskedStoreVec(T, part_mask, buf[writeL.*..][0..remaining.*], pack_comb);
    writeL.* += num_left;
    remaining.* = 0;
}

fn compareLtSwap(comptime T: type, a: *T, b: *T) void {
    const v_min: T = @min(a.*, b.*);
    const v_max: T = @max(a.*, b.*);
    a.* = v_min;
    b.* = v_max;
}

fn getPivotNSamples(comptime T: type, buf: []T) T {
    const right = buf.len - 1;
    const N = 5;
    const step = @max(1, (right + N) / N);

    var samples = [_]T{ buf[0], buf[step], buf[step * 2], buf[step * 3], buf[right] };

    // use sorting network for 5
    // [(0,3),(1,4)]
    // [(0,2),(1,3)]
    // [(0,1),(2,4)]
    // [(1,2),(3,4)]
    // [(2,3)]
    compareLtSwap(T, &samples[0], &samples[3]);
    compareLtSwap(T, &samples[1], &samples[4]);
    compareLtSwap(T, &samples[0], &samples[2]);
    compareLtSwap(T, &samples[1], &samples[3]);
    compareLtSwap(T, &samples[0], &samples[1]);
    compareLtSwap(T, &samples[2], &samples[4]);
    compareLtSwap(T, &samples[1], &samples[2]);
    compareLtSwap(T, &samples[3], &samples[4]);
    compareLtSwap(T, &samples[2], &samples[3]);
    return samples[2];
}

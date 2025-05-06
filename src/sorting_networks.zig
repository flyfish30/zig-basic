const std = @import("std");
const testing = std.testing;
const simd = @import("simd_core.zig");
const vqsort = @import("vqsort.zig");

const VecLen = simd.VecLen;
const VecType = simd.VecType;

const SortNet = [][2]u8;

inline fn compareLtSwap(comptime T: type, a: *T, b: *T) void {
    const v_min: T = @min(a.*, b.*);
    const v_max: T = @max(a.*, b.*);
    a.* = v_min;
    b.* = v_max;
}

/// Sort n items by use sorting networks from
/// https://bertdobbelaere.github.io/sorting_networks.html.
/// The parameter N must be in range [2..<=16].
pub fn sortN2to16(comptime N: usize, comptime T: type, tuple: *[N]T) void {
    if (N < 2 and N > 16) {
        @compileError("sortN2to16 can't sort zero or too many items!");
    }

    switch (N) {
        2 => sort2(T, tuple),
        3 => sort3(T, tuple),
        4 => sort4(T, tuple),
        5 => sort5(T, tuple),
        6 => sort6(T, tuple),
        7 => sort7(T, tuple),
        8 => sort8(T, tuple),
        9 => sort9(T, tuple),
        10 => sort10(T, tuple),
        11 => sort11(T, tuple),
        12 => sort12(T, tuple),
        13 => sort13(T, tuple),
        14 => sort14(T, tuple),
        15 => sort15(T, tuple),
        16 => sort16(T, tuple),
        else => unreachable,
    }
}

pub fn sort2(comptime T: type, tuple: *[2]T) void {
    compareLtSwap(T, &tuple[0], &tuple[1]);
}

pub fn sort3(comptime T: type, tuple: *[3]T) void {
    // use sorting network for 3
    const sort_net = &[_][2]u8{ .{ 0, 2 }, .{ 0, 1 }, .{ 1, 2 } };
    sortWithNetwork(T, @constCast(sort_net), tuple[0..]);
}

pub fn sort4(comptime T: type, tuple: *[4]T) void {
    // use sorting network for 4
    const sort_net = &[_][2]u8{ .{ 0, 2 }, .{ 1, 3 }, .{ 0, 1 }, .{ 2, 3 }, .{ 1, 2 } };
    sortWithNetwork(T, @constCast(sort_net), tuple[0..]);
}

pub fn sort5(comptime T: type, tuple: *[5]T) void {
    // use sorting network for 5
    const sort_net = &[_][2]u8{ .{ 0, 3 }, .{ 1, 4 }, .{ 0, 2 }, .{ 1, 3 }, .{ 0, 1 }, .{ 2, 4 }, .{ 1, 2 }, .{ 3, 4 }, .{ 2, 3 } };
    sortWithNetwork(T, @constCast(sort_net), tuple[0..]);
}

pub fn sort6(comptime T: type, tuple: *[6]T) void {
    // use sorting network for 6
    const sort_net = &[_][2]u8{ .{ 0, 5 }, .{ 1, 3 }, .{ 2, 4 }, .{ 1, 2 }, .{ 3, 4 }, .{ 0, 3 }, .{ 2, 5 }, .{ 0, 1 }, .{ 2, 3 }, .{ 4, 5 }, .{ 1, 2 }, .{ 3, 4 } };
    sortWithNetwork(T, @constCast(sort_net), tuple[0..]);
}

pub fn sort7(comptime T: type, tuple: *[7]T) void {
    // use sorting network for 7
    const sort_net = &[_][2]u8{ .{ 0, 6 }, .{ 2, 3 }, .{ 4, 5 }, .{ 0, 2 }, .{ 1, 4 }, .{ 3, 6 }, .{ 0, 1 }, .{ 2, 5 }, .{ 3, 4 }, .{ 1, 2 }, .{ 4, 6 }, .{ 2, 3 }, .{ 4, 5 }, .{ 1, 2 }, .{ 3, 4 }, .{ 5, 6 } };
    sortWithNetwork(T, @constCast(sort_net), tuple[0..]);
}

pub fn sort8(comptime T: type, tuple: *[8]T) void {
    // use sorting network for 8
    const sort_net = &[_][2]u8{ .{ 0, 2 }, .{ 1, 3 }, .{ 4, 6 }, .{ 5, 7 }, .{ 0, 4 }, .{ 1, 5 }, .{ 2, 6 }, .{ 3, 7 }, .{ 0, 1 }, .{ 2, 3 }, .{ 4, 5 }, .{ 6, 7 }, .{ 2, 4 }, .{ 3, 5 }, .{ 1, 4 }, .{ 3, 6 }, .{ 1, 2 }, .{ 3, 4 }, .{ 5, 6 } };
    sortWithNetwork(T, @constCast(sort_net), tuple[0..]);
}

pub fn sort9(comptime T: type, tuple: *[9]T) void {
    // use sorting network for 9
    const sort_net = &[_][2]u8{ .{ 0, 3 }, .{ 1, 7 }, .{ 2, 5 }, .{ 4, 8 }, .{ 0, 7 }, .{ 2, 4 }, .{ 3, 8 }, .{ 5, 6 }, .{ 0, 2 }, .{ 1, 3 }, .{ 4, 5 }, .{ 7, 8 }, .{ 1, 4 }, .{ 3, 6 }, .{ 5, 7 }, .{ 0, 1 }, .{ 2, 4 }, .{ 3, 5 }, .{ 6, 8 }, .{ 2, 3 }, .{ 4, 5 }, .{ 6, 7 }, .{ 1, 2 }, .{ 3, 4 }, .{ 5, 6 } };
    sortWithNetwork(T, @constCast(sort_net), tuple[0..]);
}

pub fn sort10(comptime T: type, tuple: *[10]T) void {
    // use sorting network for 10
    const sort_net = &[_][2]u8{ .{ 0, 8 }, .{ 1, 9 }, .{ 2, 7 }, .{ 3, 5 }, .{ 4, 6 }, .{ 0, 2 }, .{ 1, 4 }, .{ 5, 8 }, .{ 7, 9 }, .{ 0, 3 }, .{ 2, 4 }, .{ 5, 7 }, .{ 6, 9 }, .{ 0, 1 }, .{ 3, 6 }, .{ 8, 9 }, .{ 1, 5 }, .{ 2, 3 }, .{ 4, 8 }, .{ 6, 7 }, .{ 1, 2 }, .{ 3, 5 }, .{ 4, 6 }, .{ 7, 8 }, .{ 2, 3 }, .{ 4, 5 }, .{ 6, 7 }, .{ 3, 4 }, .{ 5, 6 } };
    sortWithNetwork(T, @constCast(sort_net), tuple[0..]);
}

pub fn sort11(comptime T: type, tuple: *[11]T) void {
    // use sorting network for 11
    const sort_net = &[_][2]u8{ .{ 0, 9 }, .{ 1, 6 }, .{ 2, 4 }, .{ 3, 7 }, .{ 5, 8 }, .{ 0, 1 }, .{ 3, 5 }, .{ 4, 10 }, .{ 6, 9 }, .{ 7, 8 }, .{ 1, 3 }, .{ 2, 5 }, .{ 4, 7 }, .{ 8, 10 }, .{ 0, 4 }, .{ 1, 2 }, .{ 3, 7 }, .{ 5, 9 }, .{ 6, 8 }, .{ 0, 1 }, .{ 2, 6 }, .{ 4, 5 }, .{ 7, 8 }, .{ 9, 10 }, .{ 2, 4 }, .{ 3, 6 }, .{ 5, 7 }, .{ 8, 9 }, .{ 1, 2 }, .{ 3, 4 }, .{ 5, 6 }, .{ 7, 8 }, .{ 2, 3 }, .{ 4, 5 }, .{ 6, 7 } };
    sortWithNetwork(T, @constCast(sort_net), tuple[0..]);
}

pub fn sort12(comptime T: type, tuple: *[12]T) void {
    // use sorting network for 12
    const sort_net = &[_][2]u8{ .{ 0, 8 }, .{ 1, 7 }, .{ 2, 6 }, .{ 3, 11 }, .{ 4, 10 }, .{ 5, 9 }, .{ 0, 1 }, .{ 2, 5 }, .{ 3, 4 }, .{ 6, 9 }, .{ 7, 8 }, .{ 10, 11 }, .{ 0, 2 }, .{ 1, 6 }, .{ 5, 10 }, .{ 9, 11 }, .{ 0, 3 }, .{ 1, 2 }, .{ 4, 6 }, .{ 5, 7 }, .{ 8, 11 }, .{ 9, 10 }, .{ 1, 4 }, .{ 3, 5 }, .{ 6, 8 }, .{ 7, 10 }, .{ 1, 3 }, .{ 2, 5 }, .{ 6, 9 }, .{ 8, 10 }, .{ 2, 3 }, .{ 4, 5 }, .{ 6, 7 }, .{ 8, 9 }, .{ 4, 6 }, .{ 5, 7 }, .{ 3, 4 }, .{ 5, 6 }, .{ 7, 8 } };
    sortWithNetwork(T, @constCast(sort_net), tuple[0..]);
}

pub fn sort13(comptime T: type, tuple: *[13]T) void {
    // use sorting network for 13
    const sort_net = &[_][2]u8{ .{ 0, 12 }, .{ 1, 10 }, .{ 2, 9 }, .{ 3, 7 }, .{ 5, 11 }, .{ 6, 8 }, .{ 1, 6 }, .{ 2, 3 }, .{ 4, 11 }, .{ 7, 9 }, .{ 8, 10 }, .{ 0, 4 }, .{ 1, 2 }, .{ 3, 6 }, .{ 7, 8 }, .{ 9, 10 }, .{ 11, 12 }, .{ 4, 6 }, .{ 5, 9 }, .{ 8, 11 }, .{ 10, 12 }, .{ 0, 5 }, .{ 3, 8 }, .{ 4, 7 }, .{ 6, 11 }, .{ 9, 10 }, .{ 0, 1 }, .{ 2, 5 }, .{ 6, 9 }, .{ 7, 8 }, .{ 10, 11 }, .{ 1, 3 }, .{ 2, 4 }, .{ 5, 6 }, .{ 9, 10 }, .{ 1, 2 }, .{ 3, 4 }, .{ 5, 7 }, .{ 6, 8 }, .{ 2, 3 }, .{ 4, 5 }, .{ 6, 7 }, .{ 8, 9 }, .{ 3, 4 }, .{ 5, 6 } };
    sortWithNetwork(T, @constCast(sort_net), tuple[0..]);
}

pub fn sort14(comptime T: type, tuple: *[14]T) void {
    // use sorting network for 14
    const sort_net = &[_][2]u8{ .{ 0, 1 }, .{ 2, 3 }, .{ 4, 5 }, .{ 6, 7 }, .{ 8, 9 }, .{ 10, 11 }, .{ 12, 13 }, .{ 0, 2 }, .{ 1, 3 }, .{ 4, 8 }, .{ 5, 9 }, .{ 10, 12 }, .{ 11, 13 }, .{ 0, 4 }, .{ 1, 2 }, .{ 3, 7 }, .{ 5, 8 }, .{ 6, 10 }, .{ 9, 13 }, .{ 11, 12 }, .{ 0, 6 }, .{ 1, 5 }, .{ 3, 9 }, .{ 4, 10 }, .{ 7, 13 }, .{ 8, 12 }, .{ 2, 10 }, .{ 3, 11 }, .{ 4, 6 }, .{ 7, 9 }, .{ 1, 3 }, .{ 2, 8 }, .{ 5, 11 }, .{ 6, 7 }, .{ 10, 12 }, .{ 1, 4 }, .{ 2, 6 }, .{ 3, 5 }, .{ 7, 11 }, .{ 8, 10 }, .{ 9, 12 }, .{ 2, 4 }, .{ 3, 6 }, .{ 5, 8 }, .{ 7, 10 }, .{ 9, 11 }, .{ 3, 4 }, .{ 5, 6 }, .{ 7, 8 }, .{ 9, 10 }, .{ 6, 7 } };
    sortWithNetwork(T, @constCast(sort_net), tuple[0..]);
}

pub fn sort15(comptime T: type, tuple: *[15]T) void {
    // use sorting network for 15
    const sort_net = &[_][2]u8{ .{ 1, 2 }, .{ 3, 10 }, .{ 4, 14 }, .{ 5, 8 }, .{ 6, 13 }, .{ 7, 12 }, .{ 9, 11 }, .{ 0, 14 }, .{ 1, 5 }, .{ 2, 8 }, .{ 3, 7 }, .{ 6, 9 }, .{ 10, 12 }, .{ 11, 13 }, .{ 0, 7 }, .{ 1, 6 }, .{ 2, 9 }, .{ 4, 10 }, .{ 5, 11 }, .{ 8, 13 }, .{ 12, 14 }, .{ 0, 6 }, .{ 2, 4 }, .{ 3, 5 }, .{ 7, 11 }, .{ 8, 10 }, .{ 9, 12 }, .{ 13, 14 }, .{ 0, 3 }, .{ 1, 2 }, .{ 4, 7 }, .{ 5, 9 }, .{ 6, 8 }, .{ 10, 11 }, .{ 12, 13 }, .{ 0, 1 }, .{ 2, 3 }, .{ 4, 6 }, .{ 7, 9 }, .{ 10, 12 }, .{ 11, 13 }, .{ 1, 2 }, .{ 3, 5 }, .{ 8, 10 }, .{ 11, 12 }, .{ 3, 4 }, .{ 5, 6 }, .{ 7, 8 }, .{ 9, 10 }, .{ 2, 3 }, .{ 4, 5 }, .{ 6, 7 }, .{ 8, 9 }, .{ 10, 11 }, .{ 5, 6 }, .{ 7, 8 } };
    sortWithNetwork(T, @constCast(sort_net), tuple[0..]);
}

pub fn sort16(comptime T: type, tuple: *[16]T) void {
    // use sorting network for 16
    const sort_net = &[_][2]u8{ .{ 0, 13 }, .{ 1, 12 }, .{ 2, 15 }, .{ 3, 14 }, .{ 4, 8 }, .{ 5, 6 }, .{ 7, 11 }, .{ 9, 10 }, .{ 0, 5 }, .{ 1, 7 }, .{ 2, 9 }, .{ 3, 4 }, .{ 6, 13 }, .{ 8, 14 }, .{ 10, 15 }, .{ 11, 12 }, .{ 0, 1 }, .{ 2, 3 }, .{ 4, 5 }, .{ 6, 8 }, .{ 7, 9 }, .{ 10, 11 }, .{ 12, 13 }, .{ 14, 15 }, .{ 0, 2 }, .{ 1, 3 }, .{ 4, 10 }, .{ 5, 11 }, .{ 6, 7 }, .{ 8, 9 }, .{ 12, 14 }, .{ 13, 15 }, .{ 1, 2 }, .{ 3, 12 }, .{ 4, 6 }, .{ 5, 7 }, .{ 8, 10 }, .{ 9, 11 }, .{ 13, 14 }, .{ 1, 4 }, .{ 2, 6 }, .{ 5, 8 }, .{ 7, 10 }, .{ 9, 13 }, .{ 11, 14 }, .{ 2, 4 }, .{ 3, 6 }, .{ 9, 12 }, .{ 11, 13 }, .{ 3, 5 }, .{ 6, 8 }, .{ 7, 9 }, .{ 10, 12 }, .{ 3, 4 }, .{ 5, 6 }, .{ 7, 8 }, .{ 9, 10 }, .{ 11, 12 }, .{ 6, 7 }, .{ 8, 9 } };
    sortWithNetwork(T, @constCast(sort_net), tuple[0..]);
}

fn sortWithNetwork(comptime T: type, comptime sort_net: SortNet, tuple: []T) void {
    comptime var i = 0;
    inline while (i < sort_net.len) : (i += 1) {
        compareLtSwap(T, &(tuple[sort_net[i][0]]), &(tuple[sort_net[i][1]]));
    }
}

test "sortN2to16" {
    const all_datas = [_]u8{ 61, 30, 57, 146, 190, 170, 190, 91, 146, 8, 93, 211, 100, 29, 21, 169 };
    comptime var i = 2;
    inline while (i <= 16) : (i += 1) {
        var array: [i]u8 = undefined;
        @memcpy(array[0..], all_datas[0..i]);
        sortN2to16(i, u8, &array);
        const is_sorted = vqsort.isSorted(u8, &array);
        try testing.expectEqual(true, is_sorted);
    }
}

/// Sort n vectors that present as a nxm matrix items, in first, sort vectors
/// in column-wise, then merge sorted column by use bitonic sorting networks.
pub fn sortVecsNxM(comptime N: usize, comptime T: type, vtuple: *[N]VecType(T)) void {
    // the M must be powers of 2
    const M = comptime VecLen(T);

    if (N < 2 or N > 16) {
        @compileError("sortVecsNxM: the number of rows must be in range [2..<=16]");
    }
    if ((N & (N - 1)) != 0) {
        @compileError("sortVecsNxM: the number of rows must be powers of 2");
    }

    if (M < 2) {
        @compileError("sortVecsNxM: the number of cols must be greater equal 2");
    }

    sortN2to16(N, VecType(T), vtuple);

    comptime var m = 2;
    inline while (m <= M) : (m *= 2) {
        mergeVecsNGrpM(N, m, T, vtuple);
    }
    return;
}

fn mergeVecsNGrpM(comptime N: usize, comptime M: usize, comptime T: type, vtuple: *[N]VecType(T)) void {
    const VLEN = comptime VecLen(T);
    const asc_mask = std.simd.iota(i32, N);
    const rev_perm_masks, const rev_fftt_flags = comptime getBisortMaskFlags(VLEN, .BisortMerge);
    const col_perm_masks, const col_fftt_flags = comptime getBisortMaskFlags(N, .BisortMerge);
    const dummy_vec: VecType(T) = undefined;
    comptime var n = col_perm_masks.len;
    comptime var grp_size = 2;

    inline while (grp_size <= N) : (grp_size *= 2) {
        comptime var i = 0;
        n -= 1;
        inline while (i < N) : (i += 1) {
            if (!col_fftt_flags[n][i]) {
                const log2_M = comptime std.math.log2_int(usize, M);
                const M_IDX = log2_M - 1;
                const org_idx = asc_mask[i];
                const rev_idx = col_perm_masks[n][i];

                // reverse vector with group size M
                vtuple[rev_idx] = @shuffle(T, vtuple[rev_idx], dummy_vec, rev_perm_masks[M_IDX]);
                compareLtSwap(VecType(T), &vtuple[org_idx], &vtuple[rev_idx]);
            }
        }
    }

    comptime var log2_m = std.math.log2_int(usize, M);
    if (log2_m > 1) {
        comptime var i = 0;
        const m_idx = log2_m - 1;
        inline while (i < N) : (i += 1) {
            // Sort vector and self reversed with group size m
            // sortPairsReverse_log2_m
            const perm_vec = @shuffle(T, vtuple[i], dummy_vec, rev_perm_masks[m_idx]);
            const min_vec = @min(vtuple[i], perm_vec);
            const max_vec = @max(vtuple[i], perm_vec);
            vtuple[i] = @select(T, rev_fftt_flags[m_idx], max_vec, min_vec);
        }
    }

    const adj_perm_masks, const adj_fftt_flags = comptime getBisortMaskFlags(VLEN, .BisortSort);
    inline while (log2_m > 0) : (log2_m -= 1) {
        comptime var i = 0;
        const m_idx = log2_m - 1;
        inline while (i < N) : (i += 1) {
            // Sort data in a vector with adjacent intervals of m
            // sortPairsDistance_log2_m
            const perm_vec = @shuffle(T, vtuple[i], dummy_vec, adj_perm_masks[m_idx]);
            const min_vec = @min(vtuple[i], perm_vec);
            const max_vec = @max(vtuple[i], perm_vec);
            vtuple[i] = @select(T, adj_fftt_flags[m_idx], max_vec, min_vec);
        }
    }

    return;
}

const BisortStage = enum(u4) {
    BisortMerge, // Merge two monotonic sequence to a bitonic sequence
    BisortSort, // Sort the bitonic sequence
};

/// Get masks and bit flags of the vector permutation of the bitionic sorting
/// networks, return a tuple that has masks and bit flags
pub fn getBisortMaskFlags(comptime N: usize, stage: BisortStage) struct { []@Vector(N, i32), []@Vector(N, bool) } {
    @setEvalBranchQuota(1000 * N);
    const len = comptime std.math.log2_int(usize, N);
    var mask_arr: [len]@Vector(N, i32) = undefined;
    var fftt_flag_arr: [len]@Vector(N, bool) = undefined;

    const ffff_flag: @Vector(N / 2, bool) = @splat(false);
    const tttt_flag: @Vector(N / 2, bool) = @splat(true);
    var ft_flags = [_]@Vector(N / 2, bool){ ffff_flag, tttt_flag };
    var fftt_flag: @Vector(N, bool) = undefined;

    const asc_index: @Vector(N, i32) = std.simd.iota(i32, N);
    var inc_val = 1;
    var dec_val = -1;
    var perm_mask = asc_index;

    var step = 1;
    var i = 0;
    while (step < N) : (step *= 2) {
        fftt_flag = std.simd.interlace(ft_flags);
        const inc_vec: @Vector(N, i32) = @splat(inc_val);
        const dec_vec: @Vector(N, i32) = @splat(dec_val);
        perm_mask = switch (stage) {
            .BisortMerge => perm_mask + @select(i32, fftt_flag, dec_vec, inc_vec),
            .BisortSort => asc_index + @select(i32, fftt_flag, dec_vec, inc_vec),
        };

        ft_flags[0] = std.simd.extract(fftt_flag, 0, N / 2);
        ft_flags[1] = std.simd.extract(fftt_flag, N / 2, N / 2);
        inc_val = inc_val * 2;
        dec_val = dec_val * 2;

        mask_arr[i] = perm_mask;
        fftt_flag_arr[i] = fftt_flag;
        i += 1;
    }

    return .{ &mask_arr, &fftt_flag_arr };
}

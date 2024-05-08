const std = @import("std");
const simd = @import("simd_core.zig");
const sortn = @import("sorting_networks.zig");

const VecLen = simd.VecLen;
const VecType = simd.VecType;
const VecTupleN = simd.VecTupleN;

const getBisortMaskFlags = sortn.getBisortMaskFlags;

pub fn sortNVecs(comptime N: usize, comptime T: type, vtuple: *[N]VecType(T)) void {
    switch (N) {
        1 => vtuple[0] = bitonicSort1V(T, vtuple[0]),
        2, 4, 8, 16 => sortn.sortVecsNxM(N, T, vtuple),
        else => @compileError(std.fmt.comptimePrint("Not support {d} vectors to sort", .{N})),
    }
}

fn bitonicSort1V(comptime T: type, vec: VecType(T)) VecType(T) {
    const N = comptime VecLen(T);
    const dummy_vec: VecType(T) = undefined;
    var sorted_vec: VecType(T) = vec;

    const mask_flag_arr = comptime getBisortMaskFlags(N, .BisortMerge);
    const perm_masks = mask_flag_arr[0];
    const fftt_flags = mask_flag_arr[1];

    const sort_mask_flag_arr = comptime getBisortMaskFlags(N, .BisortSort);
    const sort_masks = sort_mask_flag_arr[0];
    const sort_fftt_flags = sort_mask_flag_arr[1];

    comptime var merge_step: u16 = 0;
    const merge_step_max = comptime std.math.log2_int(u16, N);
    inline while (merge_step < merge_step_max) : (merge_step += 1) {
        {
            const perm_mask = perm_masks[merge_step];
            const fftt_flag = fftt_flags[merge_step];
            const perm_vec = @shuffle(T, sorted_vec, dummy_vec, perm_mask);
            const min_vec = @min(sorted_vec, perm_vec);
            const max_vec = @max(sorted_vec, perm_vec);
            sorted_vec = @select(T, fftt_flag, max_vec, min_vec);
        }

        comptime var sort_step: u16 = merge_step;
        inline while (sort_step > 0) : (sort_step -= 1) {
            const sort_mask = sort_masks[sort_step - 1];
            const sort_fftt_flag = sort_fftt_flags[sort_step - 1];
            {
                const perm_vec = @shuffle(T, sorted_vec, dummy_vec, sort_mask);
                const min_vec = @min(sorted_vec, perm_vec);
                const max_vec = @max(sorted_vec, perm_vec);
                sorted_vec = @select(T, sort_fftt_flag, max_vec, min_vec);
            }
        }
    }
    return sorted_vec;
}

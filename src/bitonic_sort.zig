const std = @import("std");

const VEC_BITS_LEN = (std.simd.suggestVectorSize(u8) orelse 128) * @bitSizeOf(u8);

pub fn VecLen(comptime T: type) usize {
    return VEC_BITS_LEN / @bitSizeOf(T);
}

pub fn VecType(comptime T: type) type {
    return @Vector(VecLen(T), T);
}

pub fn bitonicSort1V(comptime T: type, vec: VecType(T)) VecType(T) {
    const dummy_vec: VecType(T) = undefined;
    var sorted_vec: VecType(T) = vec;

    const mask_flag_arr = comptime getPermMaskFlagArray(T, .BisortMerge);
    const perm_masks = mask_flag_arr[0];
    const fftt_flags = mask_flag_arr[1];

    const sort_mask_flag_arr = comptime getPermMaskFlagArray(T, .BisortSort);
    const sort_masks = sort_mask_flag_arr[0];
    const sort_fftt_flags = sort_mask_flag_arr[1];

    comptime var merge_step: u16 = 0;
    const merge_step_max = comptime std.math.log2_int(u16, VecLen(T));
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

const BisortStage = enum(u4) {
    BisortMerge, // Merge two monotonic sequence to a bitonic sequence
    BisortSort, // Sort the bitonic sequence
};

fn getPermMaskFlagArray(comptime T: type, stage: BisortStage) struct { []@Vector(VecLen(T), i32), []@Vector(VecLen(T), bool) } {
    const len = comptime std.math.log2_int(usize, VecLen(T));
    var mask_arr: [len]@Vector(VecLen(T), i32) = undefined;
    var fftt_flag_arr: [len]@Vector(VecLen(T), bool) = undefined;

    const ffff_flag: @Vector(VecLen(T) / 2, bool) = @splat(false);
    const tttt_flag: @Vector(VecLen(T) / 2, bool) = @splat(true);
    var ft_flags = [_]@Vector(VecLen(T) / 2, bool){ ffff_flag, tttt_flag };
    var fftt_flag: @Vector(VecLen(T), bool) = undefined;

    const asc_index: @Vector(VecLen(T), i32) = std.simd.iota(i32, VecLen(T));
    var inc_val = 1;
    var dec_val = -1;
    var perm_mask = asc_index;

    var step = 1;
    var i = 0;
    while (step < VecLen(T)) : (step *= 2) {
        fftt_flag = std.simd.interlace(ft_flags);
        const inc_vec: @Vector(VecLen(T), i32) = @splat(inc_val);
        const dec_vec: @Vector(VecLen(T), i32) = @splat(dec_val);
        perm_mask = switch (stage) {
            .BisortMerge => perm_mask + @select(i32, fftt_flag, dec_vec, inc_vec),
            .BisortSort => asc_index + @select(i32, fftt_flag, dec_vec, inc_vec),
        };

        ft_flags[0] = std.simd.extract(fftt_flag, 0, VecLen(T) / 2);
        ft_flags[1] = std.simd.extract(fftt_flag, VecLen(T) / 2, VecLen(T) / 2);
        inc_val = inc_val * 2;
        dec_val = dec_val * 2;

        mask_arr[i] = perm_mask;
        fftt_flag_arr[i] = fftt_flag;
        i += 1;
    }

    return .{ &mask_arr, &fftt_flag_arr };
}

const std = @import("std");
const simd = @import("simd_core.zig");

const VecLen = simd.VecLen;
const VecType = simd.VecType;
const asSlice = simd.asSlice;

const target = @import("builtin").target;
const arch = target.cpu.arch;

pub const SimdSamples = struct {
    pub fn binOpI16x8(vec1: simd.I16x8, vec2: simd.I16x8) simd.I16x8 {
        const acc = vec1 * vec2;
        return acc;
    }
};

/// Get the mask of @Vector(VecLen(T), bool) that have consecutive n bits is 1
/// from lsb.
pub fn maskFirstN(comptime T: type, n: usize) @Vector(VecLen(T), bool) {
    const splat_n: @Vector(VecLen(T), u16) = @splat(@intCast(n));
    return std.simd.iota(u16, VecLen(T)) < splat_n;
}

// load partial vector from buf then blend with val_vec, return blended vector
pub fn maskedLoadVecOr(comptime T: type, val_vec: @Vector(VecLen(T), T), mask: @Vector(VecLen(T), bool), buf: []T) @Vector(VecLen(T), T) {
    return @select(T, mask, maskedLoadPartVec(T, mask, buf), val_vec);
}

// load partial vector from buf then blend with zero, return blended vector
pub fn maskedLoadVec(comptime T: type, mask: @Vector(VecLen(T), bool), buf: []T) @Vector(VecLen(T), T) {
    const zero_vec: @Vector(VecLen(T), T) = @splat(0);
    return @select(T, mask, maskedLoadPartVec(T, mask, buf), zero_vec);
}

// only load partial vector from buf
inline fn maskedLoadPartVec(comptime T: type, mask: @Vector(VecLen(T), bool), buf: []T) @Vector(VecLen(T), T) {
    var vec: @Vector(VecLen(T), T) = undefined;

    const int_mask = @as(std.meta.Int(.unsigned, VecLen(T)), @bitCast(mask));
    const load_len = VecLen(T) - @clz(int_mask);
    var array = asSlice(T, &vec);
    @memcpy(array[0..load_len], buf);
    return vec;
}

// load partial vector from buf then blend with vec, store partial blended
// vector to buf
pub fn maskedStoreVec(comptime T: type, mask: @Vector(VecLen(T), bool), buf: []T, vec: @Vector(VecLen(T), T)) void {
    const int_mask = @as(std.meta.Int(.unsigned, VecLen(T)), @bitCast(mask));
    const store_len = VecLen(T) - @clz(int_mask);
    if (simd.isBitsPackedLeft(int_mask)) {
        // all bits of mask is packed left
        //    lsb ..             msb
        //  [ 1, 1, .. 1, 0, 0, .. 0 ]
        var array = asSlice(T, &vec);
        @memcpy(buf, array[0..store_len]);
        return;
    }

    var origin_vec: @Vector(VecLen(T), T) = undefined;
    var origin_arr = asSlice(T, &origin_vec);
    @memcpy(origin_arr[0..store_len], buf);
    var blended_vec = @select(T, mask, vec, origin_vec);
    var blended_arr = asSlice(T, &blended_vec);
    @memcpy(buf, blended_arr[0..store_len]);
}

// load entire vector from buf then blend with val_vec, return blended vector
pub fn blendedLoadVecOr(comptime T: type, val_vec: @Vector(VecLen(T), T), mask: @Vector(VecLen(T), bool), buf: []T) @Vector(VecLen(T), T) {
    const vec: @Vector(VecLen(T), T) = buf[0..comptime VecLen(T)].*;
    return @select(T, mask, vec, val_vec);
}

// load entire vector from buf then blend with zero, return blended vector
pub fn blendedLoadVec(comptime T: type, mask: @Vector(VecLen(T), bool), buf: []T) @Vector(VecLen(T), T) {
    const vec: @Vector(VecLen(T), T) = buf[0..comptime VecLen(T)].*;
    const zero_vec: @Vector(VecLen(T), T) = @splat(0);
    return @select(T, mask, vec, zero_vec);
}

// load entire vector from buf then blend with vec, store entire blended
// vector to buf.
pub fn blendedStoreVec(comptime T: type, mask: @Vector(VecLen(T), bool), buf: []T, vec: @Vector(VecLen(T), T)) void {
    var blend_vec: @Vector(VecLen(T), T) = buf[0..comptime VecLen(T)].*;
    blend_vec = @select(T, mask, vec, blend_vec);
    buf[0..comptime VecLen(T)].* = blend_vec;
}

pub fn tableLookupBytes(tbl: @Vector(VecLen(u8), u8), idx: @Vector(VecLen(i8), i8)) @TypeOf(tbl) {
    comptime var i = 0;
    var out_vec: @Vector(VecLen(u8), u8) = undefined;

    inline while (i < comptime VecLen(i8)) : (i += 1) {
        out_vec[i] = if (idx[i] < 0) 0 else tbl[@intCast(idx[i])];
    }

    return out_vec;
}

pub fn tableLookup16Bytes(tbl: @Vector(16, u8), idx: @Vector(16, i8)) @TypeOf(tbl) {
    comptime var i = 0;
    var out_vec: @Vector(16, u8) = undefined;

    inline while (i < 16) : (i += 1) {
        out_vec[i] = if (idx[i] < 0) 0 else tbl[@intCast(idx[i])];
    }

    return out_vec;
}

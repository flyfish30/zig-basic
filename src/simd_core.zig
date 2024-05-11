const std = @import("std");

const builtin = @import("builtin");
const target = builtin.target;
const arch = target.cpu.arch;

pub usingnamespace switch (arch) {
    .x86_64 => @import("simd_x86_64.zig"),
    .aarch64 => @import("simd_aarch64.zig"),
    // .riscv64 => @import("simd_riscv64.zig"),
    .wasm32 => @import("simd_wasm32.zig"),
    else => @import("simd_generic.zig"),
};

pub const I64x2 = @Vector(2, i64);
pub const U64x2 = @Vector(2, u64);
pub const I32x4 = @Vector(4, i32);
pub const U32x4 = @Vector(4, u32);
pub const I16x8 = @Vector(8, i16);
pub const U16x8 = @Vector(8, u16);

pub const I32x4x4 = @Vector(16, u32);
pub const U32x4x4 = @Vector(16, u32);

pub const VEC_BITS_LEN = (std.simd.suggestVectorLength(u8) orelse 16) * @bitSizeOf(u8);

pub fn VecLen(comptime T: type) usize {
    return VEC_BITS_LEN / @bitSizeOf(T);
}

pub fn VecType(comptime T: type) type {
    return @Vector(VecLen(T), T);
}

pub fn vectorLength(comptime VectorType: type) comptime_int {
    return switch (@typeInfo(VectorType)) {
        .Vector => |info| info.len,
        .Array => |info| info.len,
        else => @compileError("Invalid type " ++ @typeName(VectorType)),
    };
}

pub fn VecChild(comptime T: type) type {
    return std.meta.Child(T);
}

pub fn VecTupleN(comptime N: usize, comptime T: type) type {
    var fields: [N]type = undefined;
    for (&fields) |*field| {
        field.* = @Vector(VecLen(T), T);
    }
    return std.meta.Tuple(&fields);
}

fn CopyPtrAttrs(
    comptime source: type,
    comptime size: std.builtin.Type.Pointer.Size,
    comptime child: type,
) type {
    const info = @typeInfo(source).Pointer;
    return @Type(.{
        .Pointer = .{
            .size = size,
            .is_const = info.is_const,
            .is_volatile = info.is_volatile,
            .is_allowzero = info.is_allowzero,
            .alignment = info.alignment,
            .address_space = info.address_space,
            .child = child,
            .sentinel = null,
        },
    });
}

fn AsSliceReturnType(comptime T: type, comptime P: type) type {
    const size = @sizeOf(std.meta.Child(P));
    return CopyPtrAttrs(P, .One, [size / @sizeOf(T)]T);
}

/// Given a pointer to a single item, returns a slice of the underlying type, preserving pointer attributes.
pub fn asSlice(comptime T: type, ptr: anytype) AsSliceReturnType(T, @TypeOf(ptr)) {
    return @ptrCast(@alignCast(ptr));
}

pub fn isBitsPackedLeft(int_mask: anytype) bool {
    const info = @typeInfo(@TypeOf(int_mask));
    if (!(info == .Int or
        info == .Comptime_Int))
    {
        @compileError("The int_mask not a int type");
    }

    // check all bits of mask is packed left, as bellow
    //    lsb ..             msb
    //  [ 1, 1, .. 1, 0, 0, .. 0 ]
    const isPackedLeft: bool = int_mask & (~(int_mask << 1)) == 0x1;
    return isPackedLeft;
}

/// Given a bitmask, will return a mask where the bits are filled in between.
/// It is just reduce bits with XOR bit operator.
/// On modern x86 and aarch64 CPU's, it should have a latency of 3 and a throughput of 1.
pub fn prefix_xor(bitmask: anytype) @TypeOf(bitmask) {
    comptime std.debug.assert(std.math.isPowerOfTwo(@bitSizeOf(@TypeOf(bitmask))));

    const has_native_carryless_multiply = @bitSizeOf(@TypeOf(bitmask)) <= 64 and switch (builtin.cpu.arch) {
        // There should be no such thing with a processor supporting avx but not clmul.
        .x86_64 => std.Target.x86.featureSetHas(builtin.cpu.features, .pclmul) and
            std.Target.x86.featureSetHas(builtin.cpu.features, .avx2),
        .aarch64 => std.Target.aarch64.featureSetHas(builtin.cpu.features, .aes),
        else => false,
    };

    if (@inComptime() or !has_native_carryless_multiply) {
        var x = bitmask;
        inline for (0..(@bitSizeOf(std.math.Log2Int(@TypeOf(bitmask))))) |i|
            x ^= x << comptime (1 << i);
        return x;
    }

    // do a carryless multiply by all 1's,
    // adapted from zig/lib/std/crypto/ghash_polyval.zig
    const x: u128 = @bitCast([2]u64{ @as(u64, bitmask), 0 });
    const y: u128 = @bitCast(@as(@Vector(16, u8), @splat(0xff)));

    return @as(@TypeOf(bitmask), @truncate(switch (builtin.cpu.arch) {
        .x86_64 => asm (
            \\ vpclmulqdq $0x00, %[x], %[y], %[out]
            : [out] "=x" (-> @Vector(2, u64)),
            : [x] "x" (@as(@Vector(2, u64), @bitCast(x))),
              [y] "x" (@as(@Vector(2, u64), @bitCast(y))),
        ),

        .aarch64 => asm (
            \\ pmull %[out].1q, %[x].1d, %[y].1d
            : [out] "=w" (-> @Vector(2, u64)),
            : [x] "w" (@as(@Vector(2, u64), @bitCast(x))),
              [y] "w" (@as(@Vector(2, u64), @bitCast(y))),
        ),

        else => unreachable,
    }[0]));
}

// ----------------------------------------------------------------------------
// This code is copied from Accelerated-Zig-Parser, licensed
// under the MIT License which is included at the bottom of this file
// TODO: clean this up a bit
fn pext(src: anytype, comptime mask: @TypeOf(src)) @TypeOf(src) {
    if (mask == 0) return 0;

    const num_one_groups = @popCount(mask & ~(mask << 1));

    const cpu_name = builtin.cpu.model.llvm_name orelse builtin.cpu.model.name;
    if (!@inComptime() and comptime num_one_groups >= 3 and @bitSizeOf(@TypeOf(src)) <= 64 and builtin.cpu.arch == .x86_64 and
        std.Target.x86.featureSetHas(builtin.cpu.features, .bmi2) and

        // PEXT is microcoded (slow) on AMD architectures before Zen 3.
        (!std.mem.startsWith(u8, cpu_name, "znver") or cpu_name["znver".len] >= '3'))
    {
        return switch (@TypeOf(src)) {
            u64, u32 => asm ("pext %[mask], %[src], %[ret]"
                : [ret] "=r" (-> @TypeOf(src)),
                : [src] "r" (src),
                  [mask] "r" (mask),
            ),
            else => @intCast(pext(@as(if (@bitSizeOf(@TypeOf(src)) <= 32) u32 else u64, src), mask)),
        };
    } else if (num_one_groups >= 4) blk: {
        // Attempt to produce a `global_shift` value such that
        // the return statement at the end of this block moves the desired bits into the least significant
        // bit position.

        comptime var global_shift: @TypeOf(src) = 0;
        comptime {
            var x = mask;
            var t_mask = @as(@TypeOf(src), 1) << (@bitSizeOf(@TypeOf(src)) - 1);
            for (0..@popCount(x) - 1) |_| t_mask |= t_mask >> 1;

            // The maximum sum of the garbage data. If this overflows into the t_mask bits,
            // we can't use the global_shift.
            var left_overs: @TypeOf(src) = 0;
            var cur_pos: @TypeOf(src) = 0;

            while (true) {
                const shift = (@clz(x) - cur_pos);
                global_shift |= @as(@TypeOf(src), 1) << shift;
                var shifted_mask = x << shift;
                cur_pos = @clz(shifted_mask);
                cur_pos += @clz(~(shifted_mask << cur_pos));
                shifted_mask = shifted_mask << cur_pos >> cur_pos;
                left_overs += shifted_mask;
                if ((t_mask & left_overs) != 0) break :blk;
                if ((shifted_mask & t_mask) != 0) break :blk;
                x = shifted_mask >> shift;
                if (x == 0) break;
            }
        }

        return ((src & mask) *% global_shift) >> (@bitSizeOf(@TypeOf(src)) - @popCount(mask));
    }

    {
        var ans: @TypeOf(src) = 0;
        comptime var cur_pos = 0;
        comptime var x = mask;
        inline while (x != 0) {
            const mask_ctz = @ctz(x);
            const num_ones = @ctz(~(x >> mask_ctz));
            comptime var ones = 1;
            inline for (0..num_ones) |_| ones <<= 1;
            ones -%= 1;
            // @compileLog(std.fmt.comptimePrint("ans |= (src >> {}) & 0b{b}", .{ mask_ctz - cur_pos, (ones << cur_pos) }));
            ans |= (src >> (mask_ctz - cur_pos)) & (ones << cur_pos);
            cur_pos += num_ones;
            inline for (0..num_ones) |_| x &= x - 1;
        }
        return ans;
    }
}

// MIT License
//
// Copyright (c) 2023 Niles Salter
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

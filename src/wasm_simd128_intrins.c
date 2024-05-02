/**
 * The file provide some wasm simd128 instunctions that can not call by inline asm
 * in zig source file.
 */

#include "wasm_simd128_intrins.h"

extern  inline v128_t wasm128_shuffle_u8(v128_t tbl, v128_t idx)
{
    return  wasm_i8x16_swizzle(tbl, idx);
}

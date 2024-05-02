/**
 * The file provide some wasm simd128 instunctions that can not call by inline asm
 * in zig source file.
 */

#ifndef _ZIG_WASM_SIMD128_INTRINS_H
#define _ZIG_WASM_SIMD128_INTRINS_H

#ifdef IN_ZIG_INCLUDE
#include <stdint.h>
typedef int32_t v128_t __attribute__((__vector_size__(16), __aligned__(16)));
#else
#include "wasm_simd128.h"
#endif

extern  inline v128_t wasm128_shuffle_u8(v128_t tbl, v128_t idx);

#endif

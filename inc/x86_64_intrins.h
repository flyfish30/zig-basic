/**
 * The file provide some avx instunctions that can not call by inline asm
 * in zig source file.
 */

#ifndef _ZIG_X86_64_INTRINS_H
#define _ZIG_X86_64_INTRINS_H

#include "immintrin.h"

extern  inline __m256i avx_mm256_slli_epi16(__m256i vec, int count);

#endif

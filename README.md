# zig-basic
These project are used to collect some basic example of Zig program, it is only for myself.

# zig version
The supported zig version is 0.13.

# Build and Run
Run bellow command to build and run this project.
`zig build run`

# Features
## vqsort
This is a vectorized and performance-portable Quicksort that supports some SIMD instruction sets, including AVX for X86_64, Neon for ARM aarch64, wasm32.

## image processing
This is an example of image processing in Zig language, which uses zstbi to encode and decode image formats, load and store image files. 

## category theory supporting
Add some types and functions for support category theory in Zig. All types and functions are provided in functor_alg.zig file.
The list of supported concept of category theory is show in bellow:

**Functor**

**Natural Transformation**

**Applicative Functor**

**Monad**

**Compose Functor**

**Compose Applicative**

**Product Functor**

**Product Applicative**

**Coproduct Functor**

**Coproduct Applicative**

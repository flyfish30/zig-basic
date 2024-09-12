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
Add some types and functions for support category theory and functional programing in Zig. All types and functions are provided in functor_alg.zig file.

**Note**: This feature has been separated into a standalone project and is no longer developed or updated. Please go to new project [zig-cats](https://github.com/flyfish30/zig-cats).

The list of supported concept of category theory is show in bellow:
- [x] Functor
- [x] Natural Transformation
- [x] Applicative Functor
- [x] Monad
- [x] Compose Functor
- [x] Compose Applicative
- [x] Product Functor
- [x] Product Applicative
- [x] Coproduct Functor
- [x] Coproduct Applicative

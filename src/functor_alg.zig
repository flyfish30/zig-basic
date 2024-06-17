const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

pub fn algSample() !void {
    const ArrayListApplicative = Applicative(ArrayListFunctorInst, ArrayList);
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var arr = ArrayList(u32).init(allocator);
    defer arr.deinit();
    var i: u32 = 0;
    while (i < 8) : (i += 1) {
        try arr.append(i);
    }

    const array_f = ArrayListApplicative.init(.{ .allocator = allocator });
    arr = array_f.fmap(.InplaceMap, struct {
        pub fn f(a: u32) u32 {
            return a + 42;
        }
    }.f, arr);
    std.debug.print("arr mapped: {any}\n", .{arr.items});

    const arr_new = array_f.fmap(.NewValMap, struct {
        pub fn f(a: u32) f64 {
            return @as(f64, @floatFromInt(a)) * 3.14;
        }
    }.f, arr);
    defer arr_new.deinit();
    std.debug.print("arr_new: {any}\n", .{arr_new.items});

    const FloatToIntFn = *const fn (f64) u32;
    const fn_array = [_]FloatToIntFn{
        struct {
            pub fn f(x: f64) u32 {
                return @intFromFloat(@floor(x));
            }
        }.f,
        struct {
            pub fn f(x: f64) u32 {
                return @intFromFloat(@ceil(x * 4.0));
            }
        }.f,
    };

    var arr_fn = try ArrayList(FloatToIntFn).initCapacity(allocator, fn_array.len);
    defer arr_fn.deinit();
    for (fn_array) |f| {
        arr_fn.appendAssumeCapacity(f);
    }

    const arr_applied = array_f.apply(f64, u32, arr_fn, arr_new);
    defer arr_applied.deinit();
    std.debug.print("arr_applied: {any}\n", .{arr_applied.items});
    return;
}

fn MapFnInType(comptime MapFn: type) type {
    const len = @typeInfo(MapFn).Fn.params.len;

    if (len != 1) {
        @compileError("The map function must only one parameter");
    }
    return @typeInfo(MapFn).Fn.params[0].type.?;
}

fn MapFnRetType(comptime MapFn: type) type {
    const R = @typeInfo(MapFn).Fn.return_type.?;

    if (R == noreturn) {
        @compileError("The return type of map function must not be noreturn");
    }
    return R;
}

fn AnyMapFn(a: anytype, b: anytype) type {
    return fn (@TypeOf(a)) @TypeOf(b);
}

/// The kind of map function for new a translated value or inplace replace by
/// translated value.
pub const MapFnKind = enum {
    /// Need new a value for translated value, the caller should to free new
    /// value.
    NewValMap,
    /// Just inplace replace with translated value, the bitsize of translated
    /// value must equal bitsize of origin value.
    InplaceMap,
};

// fn FMapType(
//     // F is instance of Functor typeclass, such as Maybe, List
//     comptime F: fn (comptime T: type) type,
//     mapFn: anytype
// ) type {
//     const T = MapFnInType(@TypeOf(mapFn));
//     const R = MapFnRetType(@TypeOf(mapFn));
//     return *const fn (comptime T: type, comptime R: type, mapFn: fn(T) R, fa: F(T)) F(R);
// }

/// FMapFn create a struct type that will to run map function
// FMapFn: *const fn (comptime K: MapFnKind, comptime MapFnT: type) type,

/// Functor typeclass like in Haskell.
/// F is instance of Functor typeclass, such as Maybe, List
pub fn Functor(comptime FunctorInst: type, comptime F: fn (comptime T: type) type) type {
    return struct {
        const Self = @This();

        const FMapType = @TypeOf(struct {
            fn fmapFn(
                instance: FunctorInst,
                comptime K: MapFnKind,
                // f: a -> b, fa: F a
                f: anytype,
                fa: F(MapFnInType(@TypeOf(f))),
            ) F(MapFnInType(@TypeOf(f))) {
                _ = instance;
                _ = fa;
                _ = K;
            }
        }.fmapFn);

        pub fn init(instance: FunctorInst) FunctorInst {
            if (@TypeOf(FunctorInst.fmap) != FMapType) {
                @compileError("Funtor instance " ++ @typeName(FunctorInst) ++ " has incorrect type of fmap");
            }
            return instance;
        }
    };
}

/// Applicative Functor typeclass like in Haskell.
/// F is instance of Applicative Functor typeclass, such as Maybe, List
pub fn Applicative(comptime ApplicativeInst: type, comptime F: fn (comptime T: type) type) type {
    return struct {
        const Self = @This();
        const FunctorSup = Functor(ApplicativeInst, F);

        const PureType = @TypeOf(struct {
            fn pureFn(instance: ApplicativeInst, a: anytype) F(@TypeOf(a)) {
                _ = instance;
            }
        }.pureFn);

        const ApplyType = @TypeOf(struct {
            fn applyFn(
                instance: ApplicativeInst,
                comptime A: type,
                comptime B: type,
                // applicative function: F (a -> b), fa: F a
                ff: F(*const fn (A) B),
                fa: F(A),
            ) F(B) {
                _ = instance;
                _ = ff;
                _ = fa;
            }
        }.applyFn);

        pub fn init(instance: ApplicativeInst) ApplicativeInst {
            const functor = FunctorSup.init(instance);

            if (@TypeOf(ApplicativeInst.pure) != PureType) {
                @compileError("Applicative instance " ++ @typeName(ApplicativeInst) ++ " has incorrect type of pure");
            }
            if (@TypeOf(ApplicativeInst.apply) != ApplyType) {
                @compileError("Applicative instance " ++ @typeName(ApplicativeInst) ++ " has incorrect type of apply");
            }
            return functor;
        }
    };
}

const ArrayListFunctorInst = struct {
    allocator: Allocator,

    const Self = @This();

    const ARRAY_DEFAULT_LEN = 4;

    /// FMapFn create a struct type that will to run map function
    // fn FMapFn(comptime K: MapFnKind, comptime MapFnT: type) type;

    fn FaType(comptime Fn: type) type {
        return ArrayList(MapFnInType(Fn));
    }

    fn FbType(comptime Fn: type) type {
        return ArrayList(MapFnRetType(Fn));
    }

    pub fn fmap(self: Self, comptime K: MapFnKind, mapFn: anytype, fa: FaType(@TypeOf(mapFn))) FbType(@TypeOf(mapFn)) {
        switch (K) {
            .InplaceMap => {
                const fb = self.mapInplace(mapFn, fa) catch FbType(@TypeOf(mapFn)).init(self.allocator);
                return fb;
            },
            .NewValMap => {
                const fb = self.mapNewValue(mapFn, fa) catch FbType(@TypeOf(mapFn)).init(self.allocator);
                return fb;
            },
        }
    }

    fn mapInplace(self: Self, mapFn: anytype, fa: FaType(@TypeOf(mapFn))) !FbType(@TypeOf(mapFn)) {
        const A = MapFnInType(@TypeOf(mapFn));
        const B = MapFnRetType(@TypeOf(mapFn));
        if (@bitSizeOf(A) != @bitSizeOf(B)) {
            @compileError("The bitsize of translated value is not equal origin value, failed to map it");
        }

        var arr = fa;
        var slice = try arr.toOwnedSlice();
        var i: usize = 0;
        while (i < slice.len) : (i += 1) {
            slice[i] = @bitCast(mapFn(slice[i]));
        }
        return ArrayList(B).fromOwnedSlice(self.allocator, @ptrCast(slice));
    }

    fn mapNewValue(self: Self, mapFn: anytype, fa: FaType(@TypeOf(mapFn))) !FbType(@TypeOf(mapFn)) {
        const B = MapFnRetType(@TypeOf(mapFn));
        var fb = try ArrayList(B).initCapacity(self.allocator, fa.items.len);
        for (fa.items) |item| {
            fb.appendAssumeCapacity(mapFn(item));
        }
        return fb;
    }

    pub fn pure(self: Self, a: anytype) ArrayList(@TypeOf(a)) {
        var arr = ArrayList(@TypeOf(a)).initCapacity(self.allocator, ARRAY_DEFAULT_LEN);
        arr.append(a);
        return arr;
    }

    pub fn apply(
        self: Self,
        comptime A: type,
        comptime B: type,
        // applicative function: ArrayList (a -> b), fa: ArrayList a
        ff: ArrayList(*const fn (A) B),
        fa: ArrayList(A),
    ) ArrayList(B) {
        var fb = ArrayList(B)
            .initCapacity(self.allocator, ff.items.len * fa.items.len) catch ArrayList(B).init(self.allocator);
        for (ff.items) |f| {
            for (fa.items) |item| {
                fb.appendAssumeCapacity(f(item));
            }
        }
        return fb;
    }
};

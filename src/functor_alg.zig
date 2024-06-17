const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

pub fn algSample() !void {
    try maybeSample();
    try arraylistSample();
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

        fn FaType(comptime Fn: type) type {
            return F(MapFnInType(Fn));
        }

        fn FbType(comptime Fn: type) type {
            return F(MapFnRetType(Fn));
        }

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
                @compileError("Incorrect type of fmap for Funtor instance " ++ @typeName(FunctorInst));
            }
            return instance;
        }
    };
}

/// Applicative Functor typeclass like in Haskell, it inherit from Functor.
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
            fn fapplyFn(
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
        }.fapplyFn);

        pub fn init(instance: ApplicativeInst) ApplicativeInst {
            const sup = FunctorSup.init(instance);

            if (@TypeOf(ApplicativeInst.pure) != PureType) {
                @compileError("Incorrect type of pure for Funtor instance " ++ @typeName(ApplicativeInst));
            }
            if (@TypeOf(ApplicativeInst.fapply) != ApplyType) {
                @compileError("Incorrect type of fapply for Funtor instance " ++ @typeName(ApplicativeInst));
            }
            return sup;
        }
    };
}

/// Monad Functor typeclass like in Haskell, it inherit from Applicative Functor.
/// M is instance of Monad typeclass, such as Maybe, List
pub fn Monad(comptime MonadInst: type, comptime M: fn (comptime T: type) type) type {
    return struct {
        const Self = @This();
        const ApplicativeSup = Applicative(MonadInst, M);

        const BindType = @TypeOf(struct {
            fn bindFn(
                instance: MonadInst,
                comptime A: type,
                comptime B: type,
                // monad function: (a -> M b), ma: M a
                ma: M(A),
                f: *const fn (MonadInst, A) M(B),
            ) M(B) {
                _ = instance;
                _ = ma;
                _ = f;
            }
        }.bindFn);

        pub fn init(instance: MonadInst) MonadInst {
            const sup = ApplicativeSup.init(instance);

            if (@TypeOf(MonadInst.bind) != BindType) {
                @compileError("Incorrect type of bind for Funtor instance " ++ @typeName(MonadInst));
            }
            return sup;
        }
    };
}

fn Maybe(comptime a: type) type {
    return ?a;
}

const MaybeMonadInst = struct {
    none: void,

    const Self = @This();

    const FaType = Functor(Self, Maybe).FaType;
    const FbType = Functor(Self, Maybe).FbType;

    pub fn fmap(self: Self, comptime K: MapFnKind, mapFn: anytype, fa: FaType(@TypeOf(mapFn))) FbType(@TypeOf(mapFn)) {
        _ = self;
        _ = K;
        if (fa) |a| {
            return mapFn(a);
        }

        return null;
    }

    pub fn pure(self: Self, a: anytype) Maybe(@TypeOf(a)) {
        _ = self;
        return a;
    }

    pub fn fapply(
        self: Self,
        comptime A: type,
        comptime B: type,
        // applicative function: Maybe (a -> b), fa: Maybe a
        ff: Maybe(*const fn (A) B),
        fa: Maybe(A),
    ) Maybe(B) {
        _ = self;
        if (ff) |f| {
            if (fa) |a| {
                return f(a);
            }
        }
        return null;
    }

    pub fn bind(
        self: Self,
        comptime A: type,
        comptime B: type,
        // monad function: (a -> M b), ma: M a
        ma: Maybe(A),
        f: *const fn (Self, A) Maybe(B),
    ) Maybe(B) {
        if (ma) |a| {
            return f(self, a);
        }
        return null;
    }
};

fn maybeSample() !void {
    const MaybeMonad = Monad(MaybeMonadInst, Maybe);
    const maybe_m = MaybeMonad.init(.{ .none = {} });

    var maybe_a: ?u32 = 42;
    maybe_a = maybe_m.fmap(.InplaceMap, struct {
        fn f(a: u32) u32 {
            return a + 10;
        }
    }.f, maybe_a);

    const maybe_b = maybe_m.fmap(.NewValMap, struct {
        fn f(a: u32) f64 {
            return @as(f64, @floatFromInt(a)) + 3.14;
        }
    }.f, maybe_a);
    std.debug.print("mapped maybe_a: {any}, maybe_b: {any}\n", .{ maybe_a, maybe_b });

    const maybe_fn: ?*const fn (f64) u32 = struct {
        pub fn f(x: f64) u32 {
            return @intFromFloat(@floor(x));
        }
    }.f;
    var maybe_applied = maybe_m.fapply(f64, u32, maybe_fn, maybe_b);
    std.debug.print("maybe_applied: {any}\n", .{maybe_applied});
    maybe_applied = maybe_m.fapply(u32, u32, null, maybe_applied);
    std.debug.print("applied with null function: {any}\n", .{maybe_applied});

    const maybe_binded = maybe_m.bind(f64, u32, maybe_b, struct {
        pub fn f(self: MaybeMonadInst, x: f64) ?u32 {
            _ = self;
            return @intFromFloat(@ceil(x * 4.0));
        }
    }.f);
    std.debug.print("maybe_binded: {any}\n", .{maybe_binded});
}

const ArrayListMonadInst = struct {
    allocator: Allocator,

    const Self = @This();

    const ARRAY_DEFAULT_LEN = 4;

    const FaType = Functor(Self, ArrayList).FaType;
    const FbType = Functor(Self, ArrayList).FbType;

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

    pub fn fapply(
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

    pub fn bind(
        self: Self,
        comptime A: type,
        comptime B: type,
        // monad function: (a -> M b), ma: M a
        ma: ArrayList(A),
        f: *const fn (Self, A) ArrayList(B),
    ) ArrayList(B) {
        var mb = ArrayList(B).init(self.allocator);
        for (ma.items) |a| {
            const tmp_mb = f(self, a);
            defer tmp_mb.deinit();
            for (tmp_mb.items) |b| {
                mb.append(b) catch break;
            }
        }
        return mb;
    }
};

fn arraylistSample() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const ArrayListMonad = Monad(ArrayListMonadInst, ArrayList);
    const array_m = ArrayListMonad.init(.{ .allocator = allocator });

    var arr = ArrayList(u32).init(allocator);
    defer arr.deinit();
    var i: u32 = 0;
    while (i < 8) : (i += 1) {
        try arr.append(i);
    }

    // example of functor
    arr = array_m.fmap(.InplaceMap, struct {
        pub fn f(a: u32) u32 {
            return a + 42;
        }
    }.f, arr);
    std.debug.print("arr mapped: {any}\n", .{arr.items});

    const arr_new = array_m.fmap(.NewValMap, struct {
        pub fn f(a: u32) f64 {
            return @as(f64, @floatFromInt(a)) * 3.14;
        }
    }.f, arr);
    defer arr_new.deinit();
    std.debug.print("arr_new: {any}\n", .{arr_new.items});

    // example of applicative functor
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

    const arr_applied = array_m.fapply(f64, u32, arr_fn, arr_new);
    defer arr_applied.deinit();
    std.debug.print("arr_applied: {any}\n", .{arr_applied.items});

    // example of monad
    const arr_binded = array_m.bind(f64, u32, arr_new, struct {
        pub fn f(inst: @TypeOf(array_m), a: f64) ArrayList(u32) {
            var arr_b = ArrayList(u32).initCapacity(inst.allocator, 2) catch ArrayList(u32).init(inst.allocator);
            arr_b.appendAssumeCapacity(@intFromFloat(@ceil(a * 4.0)));
            arr_b.appendAssumeCapacity(@intFromFloat(@ceil(a * 9.0)));
            return arr_b;
        }
    }.f);
    defer arr_binded.deinit();
    std.debug.print("arr_binded: {any}\n", .{arr_binded.items});
    return;
}

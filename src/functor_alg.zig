const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

pub fn algSample() !void {
    try maybeSample();
    try arraylistSample();
    try composeSample();
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

fn MapSelfFnInType(comptime MapSelfFn: type) type {
    const len = @typeInfo(MapSelfFn).Fn.params.len;

    if (len != 2) {
        @compileError("The map self function must only two parameter");
    }
    return @typeInfo(MapSelfFn).Fn.params[1].type.?;
}

fn MapSelfFnRetType(comptime MapSelfFn: type) type {
    const R = @typeInfo(MapSelfFn).Fn.return_type.?;

    if (R == noreturn) {
        @compileError("The return type of map self function must not be noreturn");
    }
    return R;
}

fn GenericMapFnInType(comptime M: FMapMode, comptime MapFn: type) type {
    if (M == .NormalMap) {
        return MapFnInType(MapFn);
    } else {
        return MapSelfFnInType(MapFn);
    }
}

fn GenericMapFnRetType(comptime M: FMapMode, comptime MapFn: type) type {
    if (M == .NormalMap) {
        return MapFnRetType(MapFn);
    } else {
        return MapSelfFnRetType(MapFn);
    }
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

/// The mode of fmap is used to indicate whether the map function has a self
/// parameter.
pub const FMapMode = enum {
    /// The map function has not a self parameter.
    NormalMap,
    /// The map function has a self parameter.
    SelfMap,
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
        const InstanceType = FunctorInst;

        fn FaType(comptime MapFn: type) type {
            return F(MapFnInType(MapFn));
        }

        fn FbType(comptime MapFn: type) type {
            return F(MapFnRetType(MapFn));
        }

        fn SelfFaType(comptime MapFn: type) type {
            return F(MapSelfFnInType(MapFn));
        }

        fn SelfFbType(comptime MapFn: type) type {
            return F(MapSelfFnRetType(MapFn));
        }

        fn GenericFaType(comptime M: FMapMode, comptime MapFn: type) type {
            if (M == .NormalMap) {
                return FaType(MapFn);
            } else {
                return SelfFaType(MapFn);
            }
        }

        fn GenericFbType(comptime M: FMapMode, comptime MapFn: type) type {
            if (M == .NormalMap) {
                return FbType(MapFn);
            } else {
                return SelfFbType(MapFn);
            }
        }

        const FMapType = @TypeOf(struct {
            fn fmapFn(
                instance: InstanceType,
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

        pub fn init(instance: InstanceType) InstanceType {
            if (@TypeOf(InstanceType.fmap) != FMapType) {
                @compileError("Incorrect type of fmap for Funtor instance " ++ @typeName(InstanceType));
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
        const InstanceType = ApplicativeInst;

        const PureType = @TypeOf(struct {
            fn pureFn(instance: InstanceType, a: anytype) F(@TypeOf(a)) {
                _ = instance;
            }
        }.pureFn);

        const ApplyType = @TypeOf(struct {
            fn fapplyFn(
                instance: InstanceType,
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

        pub fn init(instance: InstanceType) InstanceType {
            const sup = FunctorSup.init(instance);

            if (@TypeOf(InstanceType.pure) != PureType) {
                @compileError("Incorrect type of pure for Funtor instance " ++ @typeName(InstanceType));
            }
            if (@TypeOf(InstanceType.fapply) != ApplyType) {
                @compileError("Incorrect type of fapply for Funtor instance " ++ @typeName(InstanceType));
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
        const InstanceType = MonadInst;

        const BindType = @TypeOf(struct {
            fn bindFn(
                instance: InstanceType,
                comptime A: type,
                comptime B: type,
                // monad function: (a -> M b), ma: M a
                ma: M(A),
                f: *const fn (InstanceType, A) M(B),
            ) M(B) {
                _ = instance;
                _ = ma;
                _ = f;
            }
        }.bindFn);

        pub fn init(instance: InstanceType) InstanceType {
            const sup = ApplicativeSup.init(instance);

            if (@TypeOf(InstanceType.bind) != BindType) {
                @compileError("Incorrect type of bind for Funtor instance " ++ @typeName(InstanceType));
            }
            return sup;
        }
    };
}

/// Compose two Type constructor to one Type constructor, the parameter
/// F and G are one parameter Type consturctor.
pub fn Compose(comptime F: fn (comptime type) type, comptime G: fn (comptime type) type) fn (comptime type) type {
    return struct {
        fn Composed(comptime A: type) type {
            return F(G(A));
        }
    }.Composed;
}

pub fn ComposeInst(comptime InstanceF: type, comptime InstanceG: type) type {
    return struct {
        instanceF: InstanceF,
        instanceG: InstanceG,

        const Self = @This();
        const FunctorF = Functor(InstanceF, InstanceF.F);
        const FunctorG = Functor(InstanceG, InstanceG.F);
        const F = Compose(InstanceF.F, InstanceG.F);

        const FaType = struct {
            fn FaType(comptime Fn: type) type {
                return F(MapFnInType(Fn));
            }
        }.FaType;
        const FbType = struct {
            fn FbType(comptime Fn: type) type {
                return F(MapFnRetType(Fn));
            }
        }.FbType;

        const SelfFaType = struct {
            fn SelfFaType(comptime Fn: type) type {
                return F(MapSelfFnInType(Fn));
            }
        }.SelfFaType;
        const SelfFbType = struct {
            fn SelfFbType(comptime Fn: type) type {
                return F(MapSelfFnRetType(Fn));
            }
        }.SelfFbType;

        const GenericFaType = struct {
            fn GenericFaType(comptime M: FMapMode, comptime Fn: type) type {
                return F(GenericMapFnInType(M, Fn));
            }
        }.GenericFaType;
        const GenericFbType = struct {
            fn GenericFbType(comptime M: FMapMode, comptime Fn: type) type {
                return F(GenericMapFnRetType(M, Fn));
            }
        }.GenericFbType;

        pub fn fmap(
            self: Self,
            comptime K: MapFnKind,
            mapFn: anytype,
            fa: FaType(@TypeOf(mapFn)),
        ) FbType(@TypeOf(mapFn)) {
            return fmapGeneric(self, .NormalMap, K, mapFn, fa);
        }

        pub fn fmapSelf(
            self: Self,
            comptime K: MapFnKind,
            mapSelfFn: anytype,
            fa: SelfFaType(@TypeOf(mapSelfFn)),
        ) SelfFbType(@TypeOf(mapSelfFn)) {
            return fmapGeneric(self, .SelfMap, K, mapSelfFn, fa);
        }

        pub fn fmapGeneric(
            self: Self,
            comptime M: FMapMode,
            comptime K: MapFnKind,
            mapFn: anytype,
            fa: GenericFaType(M, @TypeOf(mapFn)),
        ) GenericFbType(M, @TypeOf(mapFn)) {
            const mapInner = struct {
                fn mapInner(
                    selfF: InstanceF,
                    ga: FunctorG.FaType(@TypeOf(mapFn)),
                ) FunctorG.FbType(@TypeOf(mapFn)) {
                    const outerSelf: *Self = @constCast(@fieldParentPtr("instanceF", &selfF));
                    if (M == .NormalMap) {
                        return outerSelf.instanceG.fmap(K, mapFn, ga);
                    } else {
                        return outerSelf.instanceG.fmapSelf(K, mapFn, ga);
                    }
                }
            }.mapInner;

            return self.instanceF.fmapSelf(K, mapInner, fa);
        }
    };
}

/// Compose two Functor to one Functor, the parameter FunctorF and FunctorG
/// are Functor type.
pub fn ComposeFunctor(comptime FunctorF: type, comptime FunctorG: type) type {
    const InstanceFG = ComposeInst(FunctorF.InstanceType, FunctorG.InstanceType);
    return Functor(InstanceFG, InstanceFG.F);
}

fn castInplaceValue(comptime T: type, val: anytype) T {
    const info = @typeInfo(@TypeOf(val));
    if (info == .Optional) {
        const v = val orelse return null;
        const retv: std.meta.Child(T) = @bitCast(v);
        return retv;
    } else {
        return @bitCast(val);
    }
}

fn Maybe(comptime a: type) type {
    return ?a;
}

const MaybeMonadInst = struct {
    none: void,

    const Self = @This();

    const F = Maybe;
    const FaType = Functor(Self, F).FaType;
    const FbType = Functor(Self, F).FbType;
    const SelfFaType = Functor(Self, F).SelfFaType;
    const SelfFbType = Functor(Self, F).SelfFbType;

    pub fn fmap(
        self: Self,
        comptime K: MapFnKind,
        mapFn: anytype,
        fa: FaType(@TypeOf(mapFn)),
    ) FbType(@TypeOf(mapFn)) {
        _ = self;
        _ = K;
        if (fa) |a| {
            return mapFn(a);
        }

        return null;
    }

    // the mapSelfFn has a self parameter for map functor
    pub fn fmapSelf(
        self: Self,
        comptime K: MapFnKind,
        mapSelfFn: anytype,
        fa: SelfFaType(@TypeOf(mapSelfFn)),
    ) SelfFbType(@TypeOf(mapSelfFn)) {
        _ = K;
        if (fa) |a| {
            return mapSelfFn(self, a);
        }

        return null;
    }

    pub fn pure(self: Self, a: anytype) F(@TypeOf(a)) {
        _ = self;
        return a;
    }

    pub fn fapply(
        self: Self,
        comptime A: type,
        comptime B: type,
        // applicative function: F (a -> b), fa: F a
        ff: F(*const fn (A) B),
        fa: F(A),
    ) F(B) {
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
        ma: F(A),
        f: *const fn (Self, A) F(B),
    ) F(B) {
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
        fn f(x: f64) u32 {
            return @intFromFloat(@floor(x));
        }
    }.f;
    var maybe_applied = maybe_m.fapply(f64, u32, maybe_fn, maybe_b);
    std.debug.print("maybe_applied: {any}\n", .{maybe_applied});
    maybe_applied = maybe_m.fapply(u32, u32, null, maybe_applied);
    std.debug.print("applied with null function: {any}\n", .{maybe_applied});

    const maybe_binded = maybe_m.bind(f64, u32, maybe_b, struct {
        fn f(self: MaybeMonadInst, x: f64) ?u32 {
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

    const F = ArrayList;
    const FaType = Functor(Self, F).FaType;
    const FbType = Functor(Self, F).FbType;
    const SelfFaType = Functor(Self, F).SelfFaType;
    const SelfFbType = Functor(Self, F).SelfFbType;
    const GenericFaType = Functor(Self, F).GenericFaType;
    const GenericFbType = Functor(Self, F).GenericFbType;

    // the mapSelfFn has a self parameter for map functor
    pub fn fmapSelf(
        self: Self,
        comptime K: MapFnKind,
        mapSelfFn: anytype,
        fa: SelfFaType(@TypeOf(mapSelfFn)),
    ) SelfFbType(@TypeOf(mapSelfFn)) {
        return fmapGeneric(self, .SelfMap, K, mapSelfFn, fa);
    }

    pub fn fmap(self: Self, comptime K: MapFnKind, mapFn: anytype, fa: FaType(@TypeOf(mapFn))) FbType(@TypeOf(mapFn)) {
        return fmapGeneric(self, .NormalMap, K, mapFn, fa);
    }

    fn fmapGeneric(
        self: Self,
        comptime M: FMapMode,
        comptime K: MapFnKind,
        mapFn: anytype,
        fa: GenericFaType(M, @TypeOf(mapFn)),
    ) GenericFbType(M, @TypeOf(mapFn)) {
        switch (K) {
            .InplaceMap => {
                const fb = self.mapInplace(M, mapFn, fa) catch FbType(@TypeOf(mapFn)).init(self.allocator);
                return fb;
            },
            .NewValMap => {
                const fb = self.mapNewValue(M, mapFn, fa) catch FbType(@TypeOf(mapFn)).init(self.allocator);
                return fb;
            },
        }
    }

    fn mapInplace(self: Self, comptime M: FMapMode, mapFn: anytype, fa: GenericFaType(M, @TypeOf(mapFn))) !GenericFbType(M, @TypeOf(mapFn)) {
        const A = GenericMapFnInType(M, @TypeOf(mapFn));
        const B = GenericMapFnRetType(M, @TypeOf(mapFn));
        if (@bitSizeOf(A) != @bitSizeOf(B)) {
            @compileError("The bitsize of translated value is not equal origin value, failed to map it");
        }

        var arr = fa;
        var slice = try arr.toOwnedSlice();
        var i: usize = 0;
        while (i < slice.len) : (i += 1) {
            if (M == .NormalMap) {
                slice[i] = castInplaceValue(B, mapFn(slice[i]));
            } else {
                slice[i] = castInplaceValue(B, mapFn(self, slice[i]));
            }
        }
        return ArrayList(B).fromOwnedSlice(self.allocator, @ptrCast(slice));
    }

    fn mapNewValue(self: Self, comptime M: FMapMode, mapFn: anytype, fa: GenericFaType(M, @TypeOf(mapFn))) !GenericFbType(M, @TypeOf(mapFn)) {
        const B = GenericMapFnRetType(M, @TypeOf(mapFn));
        var fb = try ArrayList(B).initCapacity(self.allocator, fa.items.len);
        for (fa.items) |item| {
            if (M == .NormalMap) {
                fb.appendAssumeCapacity(mapFn(item));
            } else {
                fb.appendAssumeCapacity(mapFn(self, item));
            }
        }
        return fb;
    }

    pub fn pure(self: Self, a: anytype) F(@TypeOf(a)) {
        var arr = ArrayList(@TypeOf(a)).initCapacity(self.allocator, ARRAY_DEFAULT_LEN);
        arr.append(a);
        return arr;
    }

    pub fn fapply(
        self: Self,
        comptime A: type,
        comptime B: type,
        // applicative function: F (a -> b), fa: F a
        ff: F(*const fn (A) B),
        fa: F(A),
    ) F(B) {
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
        ma: F(A),
        f: *const fn (Self, A) F(B),
    ) F(B) {
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
        fn f(a: u32) u32 {
            return a + 42;
        }
    }.f, arr);
    std.debug.print("arr mapped: {any}\n", .{arr.items});

    const arr_new = array_m.fmap(.NewValMap, struct {
        fn f(a: u32) f64 {
            return @as(f64, @floatFromInt(a)) * 3.14;
        }
    }.f, arr);
    defer arr_new.deinit();
    std.debug.print("arr_new: {any}\n", .{arr_new.items});

    // example of applicative functor
    const FloatToIntFn = *const fn (f64) u32;
    const fn_array = [_]FloatToIntFn{
        struct {
            fn f(x: f64) u32 {
                return @intFromFloat(@floor(x));
            }
        }.f,
        struct {
            fn f(x: f64) u32 {
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
        fn f(inst: @TypeOf(array_m), a: f64) ArrayList(u32) {
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

fn composeSample() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};

    const allocator = gpa.allocator();
    const ArrayListFunctor = Functor(ArrayListMonadInst, ArrayList);
    const MaybeFunctor = Functor(MaybeMonadInst, Maybe);
    const ArrayListMaybeFunctor = ComposeFunctor(ArrayListFunctor, MaybeFunctor);
    const arrayMaybeInst = .{
        .instanceF = .{ .allocator = allocator },
        .instanceG = .{ .none = {} },
    };
    const arrayMaybe = ArrayListMaybeFunctor.init(arrayMaybeInst);

    var arr = ArrayList(Maybe(u32)).init(allocator);
    defer arr.deinit();

    var i: u32 = 8;
    while (i < 16) : (i += 1) {
        if ((i & 0x1) == 0) {
            try arr.append(i);
        } else {
            try arr.append(null);
        }
    }
    arr = arrayMaybe.fmap(.InplaceMap, struct {
        fn f(a: u32) u32 {
            return a + 42;
        }
    }.f, arr);
    std.debug.print("arr mapped: {any}\n", .{arr.items});
    return;
}

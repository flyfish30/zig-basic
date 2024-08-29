const std = @import("std");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const assert = std.debug.assert;

pub fn algSample() !void {
    try maybeSample();
    try arraylistSample();
    try composeSample();
    try productSample();
    try coproductSample();
}

fn MapFnInType(comptime K: MapFnKind, comptime MapFn: type) type {
    const len = @typeInfo(MapFn).Fn.params.len;

    if (len != 1) {
        @compileError("The map function must has only one parameter!");
    }

    const InType = @typeInfo(MapFn).Fn.params[0].type.?;
    if (comptime isMapRef(K)) {
        comptime assert(@typeInfo(InType) == .Pointer);
        return std.meta.Child(InType);
    } else {
        return InType;
    }
}

fn MapFnRetType(comptime MapFn: type) type {
    const R = @typeInfo(MapFn).Fn.return_type.?;

    if (R == noreturn) {
        @compileError("The return type of map function must not be noreturn!");
    }
    return R;
}

fn MapLamInType(comptime K: MapFnKind, comptime MapLam: type) type {
    const info = @typeInfo(MapLam);
    if (info != .Struct) {
        @compileError("The map lambda must be a struct!");
    }

    const mapFnInfo = @typeInfo(@TypeOf(MapLam.call));
    const len = mapFnInfo.Fn.params.len;

    if (len != 2) {
        @compileError("The call function of map lambda must have only two parameters!");
    }
    if (mapFnInfo.Fn.params[0].type.? != *MapLam and mapFnInfo.Fn.params[0].type.? != *const MapLam) {
        @compileError("The first parameter of call function must be a pointer of MapLam!");
    }

    const InType = mapFnInfo.Fn.params[1].type.?;
    if (comptime isMapRef(K)) {
        comptime assert(@typeInfo(InType) == .Pointer);
        return std.meta.Child(InType);
    } else {
        return InType;
    }
}

fn MapLamRetType(comptime MapLam: type) type {
    const info = @typeInfo(MapLam);
    if (info != .Struct) {
        @compileError("The map lambda must be a struct!");
    }

    const mapFnInfo = @typeInfo(@TypeOf(MapLam.call));
    const R = mapFnInfo.Fn.return_type.?;

    if (R == noreturn) {
        @compileError("The return type of call function must not be noreturn!");
    }
    return R;
}

fn AnyMapFn(a: anytype, b: anytype) type {
    return fn (@TypeOf(a)) @TypeOf(b);
}

/// The kind of map function for new a translated value or inplace replaced by
/// translated value.
pub const MapFnKind = enum {
    /// Need new a value for translated value, the caller should to free new
    /// value.
    NewValMap,
    /// Need new a value for translated value, the caller should to free new
    /// value.
    /// The input value of map function is a reference.
    /// The fa paramerter of fmap function is also a reference.
    NewValMapRef,
    /// Just inplace replace with translated value, the bitsize of translated
    /// value must equal bitsize of origin value.
    InplaceMap,
    /// Just inplace replace with translated value, the bitsize of translated
    /// value must equal bitsize of origin value.
    /// The input value of map function is a reference.
    /// The fa paramerter of fmap function is also a reference.
    InplaceMapRef,
};

pub fn isInplaceMap(comptime K: MapFnKind) bool {
    return K == .InplaceMap or K == .InplaceMapRef;
}

pub fn isMapRef(comptime K: MapFnKind) bool {
    return K == .NewValMapRef or K == .InplaceMapRef;
}

/// The mode of fmap is used to indicate whether the map function has a self
/// parameter.
const FMapMode = enum {
    /// The map function has only a input parameter.
    NormalMap,
    /// The map function is a lambda struct that has a map function with a
    /// self parameter.
    LambdaMap,
};

/// Check the type E whether it is a ErrorUnion, if true then return A as under
/// type of ErrorUnion, else just return type E.
pub fn isErrorUnionOrVal(comptime E: type) struct { bool, type } {
    const info = @typeInfo(E);
    const has_error = if (info == .ErrorUnion) true else false;
    const A = if (has_error) info.ErrorUnion.payload else E;
    return .{ has_error, A };
}

// fn FMapType(
//     // F is instance of Functor typeclass, such as Maybe, List
//     comptime F: fn (comptime T: type) type,
//     map_fn: anytype
// ) type {
//     const T = MapFnInType(@TypeOf(map_fn));
//     const R = MapFnRetType(@TypeOf(map_fn));
//     return *const fn (comptime T: type, comptime R: type, map_fn: fn(T) R, fa: F(T)) F(R);
// }

/// FMapFn create a struct type that will to run map function
// FMapFn: *const fn (comptime K: MapFnKind, comptime MapFnT: type) type,

pub fn FunctorFxTypes(comptime F: fn (comptime T: type) type, comptime E: type) type {
    return struct {
        fn FaType(comptime K: MapFnKind, comptime MapFn: type) type {
            if (comptime isMapRef(K)) {
                // The fa paramerter of fmap function is also a reference.
                return *F(MapFnInType(K, MapFn));
            } else {
                return F(MapFnInType(K, MapFn));
            }
        }

        fn FbType(comptime MapFn: type) type {
            const info = @typeInfo(MapFnRetType(MapFn));
            if (info != .ErrorUnion) {
                return E!F(MapFnRetType(MapFn));
            }

            return (E || info.ErrorUnion.error_set)!F(info.ErrorUnion.payload);
        }

        fn FaLamType(comptime K: MapFnKind, comptime MapLam: type) type {
            if (comptime isMapRef(K)) {
                // The fa paramerter of fmapLam function is also a reference.
                return *F(MapLamInType(K, MapLam));
            } else {
                return F(MapLamInType(K, MapLam));
            }
        }

        fn FbLamType(comptime MapLam: type) type {
            const info = @typeInfo((MapLamRetType(MapLam)));
            if (info != .ErrorUnion) {
                return E!F(MapLamRetType(MapLam));
            }

            return (E || info.ErrorUnion.error_set)!F(info.ErrorUnion.payload);
        }
    };
}

/// Functor typeclass like in Haskell.
/// F is Constructor Type of Functor typeclass, such as Maybe, List.
pub fn Functor(comptime FunctorInst: type, comptime F: fn (comptime T: type) type) type {
    if (!@hasDecl(FunctorInst, "F")) {
        @compileError("The Functor instance must has F type!");
    }

    if (!@hasDecl(FunctorInst, "BaseType")) {
        @compileError("The Functor instance must has type function: BaseType!");
    }

    if (!@hasDecl(FunctorInst, "Error")) {
        @compileError("The Functor instance must has Error type!");
    }

    if (!@hasDecl(FunctorInst, "deinitFa")) {
        @compileError("The Functor instance must has deinitFa function!");
    }

    return struct {
        const Self = @This();
        const InstanceType = FunctorInst;

        pub const Error = InstanceType.Error;

        pub const FxTypes = FunctorFxTypes(F, Error);
        pub const FaType = FxTypes.FaType;
        pub const FbType = FxTypes.FbType;
        pub const FaLamType = FxTypes.FaLamType;
        pub const FbLamType = FxTypes.FbLamType;

        /// Typeclass function for map with function
        const FMapType = @TypeOf(struct {
            fn fmapFn(
                instance: *InstanceType,
                comptime K: MapFnKind,
                // f: a -> b, fa: F a
                f: anytype,
                fa: FaType(K, @TypeOf(f)),
            ) FbType(@TypeOf(f)) {
                _ = instance;
                _ = fa;
            }
        }.fmapFn);

        /// Typeclass function for map with lambda
        const FMapLamType = @TypeOf(struct {
            fn fmapLam(
                instance: *InstanceType,
                comptime K: MapFnKind,
                // f: a -> b, fa: F a
                lam: anytype,
                fa: FaLamType(K, @TypeOf(lam)),
            ) FbLamType(@TypeOf(lam)) {
                _ = instance;
                _ = fa;
            }
        }.fmapLam);

        pub fn init(instance: InstanceType) InstanceType {
            if (@TypeOf(InstanceType.fmap) != FMapType) {
                @compileError("Incorrect type of fmap for Funtor instance " ++ @typeName(InstanceType));
            }
            if (@TypeOf(InstanceType.fmapLam) != FMapLamType) {
                @compileError("Incorrect type of fmapLam for Funtor instance " ++ @typeName(InstanceType));
            }
            return instance;
        }
    };
}

pub fn NatTransType(
    comptime F: fn (comptime T: type) type,
    comptime G: fn (comptime T: type) type,
) type {
    return @TypeOf(struct {
        fn transFn(comptime A: type, fa: F(A)) G(A) {
            _ = fa;
        }
    }.transFn);
}

/// Natural Transformation typeclass like in Haskell.
/// F and G is Constructor Type of Functor typeclass, such as Maybe, List.
pub fn NatTrans(
    comptime NatTransInst: type,
    comptime F: fn (comptime T: type) type,
    comptime G: fn (comptime T: type) type,
) type {
    if (!(@hasDecl(NatTransInst, "F") and @hasDecl(NatTransInst, "G"))) {
        @compileError("The natural transformation instance must has F and G type!");
    }

    if (!(@hasDecl(NatTransInst, "Error"))) {
        @compileError("The natural transformation instance must has Error type!");
    }

    return struct {
        const Self = @This();
        const InstanceType = NatTransInst;

        const FTransType = @TypeOf(struct {
            fn transFn(
                instance: *InstanceType,
                comptime A: type,
                fa: F(A),
            ) NatTransInst.Error!G(A) {
                _ = instance;
                _ = fa;
            }
        }.transFn);

        pub fn init(instance: InstanceType) InstanceType {
            if (@TypeOf(InstanceType.trans) != FTransType) {
                @compileError("Incorrect type of fmap for Funtor instance " ++ @typeName(InstanceType));
            }
            return instance;
        }
    };
}

pub fn ApplicativeFxTypes(comptime F: fn (comptime T: type) type, comptime E: type) type {
    return struct {
        /// return type of pure a
        fn APaType(comptime A: type) type {
            return E!F(A);
        }

        /// return type of fapply
        fn AFbType(comptime B: type) type {
            const has_err, const _B = comptime isErrorUnionOrVal(B);
            if (has_err) {
                return (E || @typeInfo(B).ErrorUnion.error_set)!F(_B);
            } else {
                return E!F(B);
            }
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

        pub const Error = InstanceType.Error;

        const AFxTypes = ApplicativeFxTypes(F, Error);
        pub const APaType = AFxTypes.APaType;
        pub const AFbType = AFxTypes.AFbType;

        const PureType = @TypeOf(struct {
            fn pureFn(instance: *InstanceType, a: anytype) APaType(@TypeOf(a)) {
                _ = instance;
            }
        }.pureFn);

        const ApplyType = @TypeOf(struct {
            fn fapplyFn(
                instance: *InstanceType,
                comptime A: type,
                comptime B: type,
                // applicative function: F (a -> b), fa: F a
                ff: F(*const fn (A) B),
                fa: F(A),
            ) AFbType(B) {
                _ = instance;
                _ = ff;
                _ = fa;
            }
        }.fapplyFn);

        const ApplyLamType = @TypeOf(struct {
            fn fapplyLam(
                instance: *InstanceType,
                comptime A: type,
                comptime B: type,
                // applicative function: F (a -> b), fa: F a
                flam: anytype, // a F(lambda) that present F(*const fn (A) B),
                fa: F(A),
            ) AFbType(B) {
                _ = instance;
                _ = flam;
                _ = fa;
            }
        }.fapplyLam);

        // pub fn liftA2(
        //     instance: InstanceType,
        //     // map2 function f: a -> b -> c
        //     f: anytype,
        //     fa: Map2FaType(@TypeOf(f)),
        //     fb: Map2FbType(@TypeOf(f)),
        // ) Map2FcType(@TypeOf(f)) {
        //     // liftA2 f fa fb = pure f <*> fa <*> fb
        // }

        pub fn init(instance: InstanceType) InstanceType {
            const sup = FunctorSup.init(instance);

            if (@TypeOf(InstanceType.pure) != PureType) {
                @compileError("Incorrect type of pure for Funtor instance " ++ @typeName(InstanceType));
            }
            if (@TypeOf(InstanceType.fapply) != ApplyType) {
                @compileError("Incorrect type of fapply for Funtor instance " ++ @typeName(InstanceType));
            }
            if (@TypeOf(InstanceType.fapplyLam) != ApplyLamType) {
                @compileError("Incorrect type of fapply lambda for Funtor instance " ++ @typeName(InstanceType));
            }
            return sup;
        }
    };
}

pub fn MonadFxTypes(comptime F: fn (comptime T: type) type, comptime E: type) type {
    return struct {
        /// return type of bind
        fn MbType(comptime B: type) type {
            return E!F(B);
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

        pub const Error = InstanceType.Error;

        pub const MbType = MonadFxTypes(M, Error).MbType;

        const BindType = @TypeOf(struct {
            fn bindFn(
                instance: *InstanceType,
                comptime A: type,
                comptime B: type,
                // monad function: (a -> M b), ma: M a
                ma: M(A),
                f: *const fn (*InstanceType, A) MbType(B),
            ) MbType(B) {
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
pub fn composeFG(
    comptime F: fn (comptime type) type,
    comptime G: fn (comptime type) type,
) fn (comptime type) type {
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

        /// Constructor Type for Functor, Applicative, Monad, ...
        const F = composeFG(InstanceF.F, InstanceG.F);

        /// Get base type of F(A), it is must just is A.
        /// In this instance, type F(A) is composed FG(A) by InstanceF and
        /// InstanceG.
        pub fn BaseType(comptime FGA: type) type {
            return InstanceG.BaseType(InstanceF.BaseType(FGA));
        }

        /// Error set of ComposeInst, it is a merge set of error sets in
        /// InstanceF and InstanceG
        pub const Error = InstanceF.Error || InstanceG.Error;

        const FxTypes = FunctorFxTypes(F, Error);
        pub const FaType = FxTypes.FaType;
        pub const FbType = FxTypes.FbType;
        pub const FaLamType = FxTypes.FaLamType;
        pub const FbLamType = FxTypes.FbLamType;

        const AFxTypes = ApplicativeFxTypes(F, Error);
        pub const APaType = AFxTypes.APaType;
        pub const AFbType = AFxTypes.AFbType;

        pub fn deinitFa(
            fga: anytype, // F(G(A))
            comptime free_fn: fn (BaseType(@TypeOf(fga))) void,
        ) void {
            const free_ga_fn = struct {
                fn freeGa(ga: InstanceF.BaseType(@TypeOf(fga))) void {
                    InstanceG.deinitFa(ga, free_fn);
                }
            }.freeGa;
            InstanceF.deinitFa(fga, free_ga_fn);
        }

        pub fn fmap(
            self: *Self,
            comptime K: MapFnKind,
            map_fn: anytype,
            fga: FaType(K, @TypeOf(map_fn)),
        ) FbType(@TypeOf(map_fn)) {
            const MapFn = @TypeOf(map_fn);
            const map_lam = struct {
                map_fn: *const fn (a: MapFnInType(K, MapFn)) MapFnRetType(MapFn),

                const MapSelf = @This();
                pub fn call(map_self: *const MapSelf, a: MapFnInType(K, MapFn)) MapFnRetType(MapFn) {
                    return map_self.map_fn(a);
                }
            }{ .map_fn = &map_fn };

            return fmapLam(self, K, map_lam, fga);
        }

        pub fn fmapLam(
            self: *Self,
            comptime K: MapFnKind,
            map_lam: anytype,
            fga: FaLamType(K, @TypeOf(map_lam)),
        ) FbLamType(@TypeOf(map_lam)) {
            const MapLam = @TypeOf(map_lam);
            const map_inner = struct {
                inner_g: *InstanceG,
                map_lam: MapLam,

                const InnerSelf = @This();
                fn call(
                    inner_self: *const InnerSelf,
                    ga: FunctorG.FaLamType(K, MapLam),
                ) FunctorG.FbLamType(MapLam) {
                    return inner_self.inner_g.fmapLam(K, inner_self.map_lam, ga);
                }
            }{
                .inner_g = &self.instanceG,
                .map_lam = map_lam,
            };

            return self.instanceF.fmapLam(K, map_inner, fga);
        }

        pub fn pure(self: *Self, a: anytype) APaType(@TypeOf(a)) {
            return self.instanceF.pure(self.instanceG.pure(a));
        }

        pub fn fapply(
            self: *Self,
            comptime A: type,
            comptime B: type,
            // applicative function: F (a -> b), fa: F a
            fgf: F(*const fn (A) B),
            fga: F(A),
        ) AFbType(B) {
            return fapplyGeneric(self, .NormalMap, A, B, fgf, fga);
        }

        pub fn fapplyLam(
            self: *Self,
            comptime A: type,
            comptime B: type,
            // applicative function: F (a -> b), fa: F a
            fgf: anytype,
            fga: F(A),
        ) AFbType(B) {
            return fapplyGeneric(self, .LambdaMap, A, B, fgf, fga);
        }

        fn fapplyGeneric(
            self: *Self,
            comptime M: FMapMode,
            comptime A: type,
            comptime B: type,
            // applicative function: F (a -> b), fa: F a
            fgf: anytype,
            fga: F(A),
        ) AFbType(B) {
            // inner_fapply: G (a -> b) -> G a -> G b
            // outer_fapply: F (G a -> G b) -> F (G a) -> F (G b)
            // fmap inner_fapply: F (G (a -> b)) -> F (G a -> G b)
            // outer_fapply (fmap inner_fapply): F (G (a -> b)) -> F (G a) -> F (G b)
            // fapply = outer_fapply (fmap inner_fapply)

            // A function with type *const fn (A) B
            // or a lambda that has function *const fn (LamSelf, A) B
            const FnOrLambdaType = BaseType(@TypeOf(fgf));

            const inner_fapply = struct {
                inner_instance: *InstanceG,

                const InnerSelf = @This();
                const ApplyLam = struct {
                    apply_instanceG: *InstanceG,
                    apply_gf_p: *InstanceG.F(FnOrLambdaType),

                    const ApplySelf = @This();
                    // applyFn: G a -> G b
                    fn call(applySelf: *const ApplySelf, ga: InstanceG.F(A)) InstanceG.AFbType(B) {
                        if (M == .NormalMap) {
                            return applySelf.apply_instanceG.fapply(A, B, applySelf.apply_gf_p.*, ga);
                        } else {
                            return applySelf.apply_instanceG.fapplyLam(A, B, applySelf.apply_gf_p.*, ga);
                        }
                    }
                };

                // mapFn \gf_p -> apply_lam : G (a -> b) -> G a -> G b
                fn call(
                    inner_self: *const InnerSelf,
                    gf_p: *InstanceG.F(FnOrLambdaType),
                ) ApplyLam {
                    const apply_lam = .{
                        .apply_instanceG = inner_self.inner_instance,
                        .apply_gf_p = gf_p,
                    };
                    // apply lambda \ga -> fapply instanceG gf ga : G a -> G b
                    return apply_lam;
                }
            }{ .inner_instance = &self.instanceG };

            const free_fn = struct {
                fn free_fn(lam: @TypeOf(inner_fapply).ApplyLam) void {
                    _ = lam;
                }
            }.free_fn;

            const flam = try self.instanceF.fmapLam(.NewValMapRef, inner_fapply, @constCast(&fgf));
            defer InstanceF.deinitFa(flam, free_fn);
            return self.instanceF.fapplyLam(
                InstanceG.F(A),
                InstanceG.AFbType(B),
                flam,
                fga,
            );
        }
    };
}

/// Compose two Functor to one Functor, the parameter FunctorF and FunctorG
/// are Functor type.
pub fn ComposeFunctor(comptime FunctorF: type, comptime FunctorG: type) type {
    const InstanceFG = ComposeInst(FunctorF.InstanceType, FunctorG.InstanceType);
    return Functor(InstanceFG, InstanceFG.F);
}

/// Compose two Applicative Functor to one Applicative Functor, the parameter
/// ApplicativeF and ApplicativeG are Applicative Functor type.
pub fn ComposeApplicative(comptime ApplicativeF: type, comptime ApplicativeG: type) type {
    const InstanceFG = ComposeInst(ApplicativeF.InstanceType, ApplicativeG.InstanceType);
    return Applicative(InstanceFG, InstanceFG.F);
}

/// Get a Product Type constructor from two Type constructor, the parameter
/// F and G are one parameter Type consturctor.
pub fn productFG(
    comptime F: fn (comptime type) type,
    comptime G: fn (comptime type) type,
) fn (comptime type) type {
    return struct {
        fn Producted(comptime A: type) type {
            return struct { F(A), G(A) };
        }
    }.Producted;
}

pub fn productLeftRightType(comptime P: type) struct { type, type } {
    const info = @typeInfo(P);
    comptime assert(info == .Struct and info.Struct.is_tuple == true);
    comptime assert(info.Struct.fields.len == 2);

    const l_type = info.Struct.fields[0].type;
    const r_type = info.Struct.fields[1].type;
    return .{ l_type, r_type };
}

pub fn ProductInst(comptime InstanceF: type, comptime InstanceG: type) type {
    return struct {
        instanceF: InstanceF,
        instanceG: InstanceG,

        const Self = @This();
        const FunctorF = Functor(InstanceF, InstanceF.F);
        const FunctorG = Functor(InstanceG, InstanceG.F);

        /// Constructor Type for Functor, Applicative, Monad, ...
        const F = productFG(InstanceF.F, InstanceG.F);

        /// Get base type of F(A), it is must just is A.
        /// In this instance, type F(A) is product (F(A), G(A)) by InstanceF and
        /// InstanceG.
        pub fn BaseType(comptime FGA: type) type {
            const l_type, const r_type = productLeftRightType(FGA);
            comptime assert(InstanceF.BaseType(l_type) == InstanceG.BaseType(r_type));
            return InstanceF.BaseType(l_type);
        }

        pub const Error = InstanceF.Error || InstanceG.Error;

        const FxTypes = FunctorFxTypes(F, Error);
        pub const FaType = FxTypes.FaType;
        pub const FbType = FxTypes.FbType;
        pub const FaLamType = FxTypes.FaLamType;
        pub const FbLamType = FxTypes.FbLamType;

        const AFxTypes = ApplicativeFxTypes(F, Error);
        pub const APaType = AFxTypes.APaType;
        pub const AFbType = AFxTypes.AFbType;

        pub fn deinitFa(
            fga: anytype, // (F(A), G(A))
            comptime free_fn: fn (BaseType(@TypeOf(fga))) void,
        ) void {
            InstanceF.deinitFa(fga[0], free_fn);
            InstanceG.deinitFa(fga[1], free_fn);
        }

        pub fn fmap(
            self: *Self,
            comptime K: MapFnKind,
            map_fn: anytype,
            fga: FaType(K, @TypeOf(map_fn)),
        ) FbType(@TypeOf(map_fn)) {
            return .{
                try self.instanceF.fmap(K, map_fn, fga[0]),
                try self.instanceG.fmap(K, map_fn, fga[1]),
            };
        }

        pub fn fmapLam(
            self: *Self,
            comptime K: MapFnKind,
            map_lam: anytype,
            fga: FaLamType(K, @TypeOf(map_lam)),
        ) FbLamType(@TypeOf(map_lam)) {
            return .{
                try self.instanceF.fmapLam(K, map_lam, fga[0]),
                try self.instanceG.fmapLam(K, map_lam, fga[1]),
            };
        }

        pub fn pure(self: *Self, a: anytype) APaType(@TypeOf(a)) {
            return .{
                try self.instanceF.pure(a),
                try self.instanceG.pure(a),
            };
        }

        pub fn fapply(
            self: *Self,
            comptime A: type,
            comptime B: type,
            // applicative function: F (a -> b), fa: F a
            fgf: F(*const fn (A) B),
            fga: F(A),
        ) AFbType(B) {
            return .{
                try self.instanceF.fapply(A, B, fgf[0], fga[0]),
                try self.instanceG.fapply(A, B, fgf[1], fga[1]),
            };
        }

        pub fn fapplyLam(
            self: *Self,
            comptime A: type,
            comptime B: type,
            // applicative function: F (a -> b), fa: F a
            fgf: anytype,
            fga: F(A),
        ) AFbType(B) {
            return .{
                try self.instanceF.fapplyLam(A, B, fgf[0], fga[0]),
                try self.instanceG.fapplyLam(A, B, fgf[1], fga[1]),
            };
        }
    };
}

/// Get a Product Functor from two Functor, the parameter FunctorF and FunctorG
/// are Functor type.
pub fn ProductFunctor(comptime FunctorF: type, comptime FunctorG: type) type {
    const InstanceFG = ProductInst(FunctorF.InstanceType, FunctorG.InstanceType);
    return Functor(InstanceFG, InstanceFG.F);
}

/// Get a Product Applicative from two Applicative, the parameter
/// ApplicativeF and ApplicativeG are Applicative Functor type.
pub fn ProductApplicative(comptime ApplicativeF: type, comptime ApplicativeG: type) type {
    const InstanceFG = ProductInst(ApplicativeF.InstanceType, ApplicativeG.InstanceType);
    return Applicative(InstanceFG, InstanceFG.F);
}

/// Get a Coproduct Type constructor from two Type constructor, the parameter
/// F and G are one parameter Type consturctor.
pub fn coproductFG(
    comptime F: fn (comptime type) type,
    comptime G: fn (comptime type) type,
) fn (comptime type) type {
    return struct {
        fn Coproducted(comptime A: type) type {
            return union(enum) {
                inl: F(A),
                inr: G(A),
            };
        }
    }.Coproducted;
}

pub fn coproductLeftRightType(comptime U: type) struct { type, type } {
    const info = @typeInfo(U);
    comptime assert(info == .Union);
    comptime assert(info.Union.fields.len == 2);

    const l_type = info.Union.fields[0].type;
    const r_type = info.Union.fields[1].type;
    return .{ l_type, r_type };
}

pub fn CoproductInst(comptime InstanceF: type, comptime InstanceG: type) type {
    return CoproductApplicativeInst(InstanceF, InstanceG, void);
}

pub fn CoproductApplicativeInst(
    comptime InstanceF: type,
    comptime InstanceG: type,
    comptime InstanceNat: type,
) type {
    return struct {
        instanceF: InstanceF,
        instanceG: InstanceG,
        /// The InstanceNat type must is void for instance of Coproduct Functor
        natural_gf: InstanceNat,

        const Self = @This();
        const FunctorF = Functor(InstanceF, InstanceF.F);
        const FunctorG = Functor(InstanceG, InstanceG.F);

        /// Constructor Type for Functor, Applicative, Monad, ...
        const F = coproductFG(InstanceF.F, InstanceG.F);

        /// Get base type of F(A), it is must just is A.
        /// In this instance, type F(A) is product (F(A), G(A)) by InstanceF and
        /// InstanceG.
        pub fn BaseType(comptime FGA: type) type {
            const l_type, const r_type = coproductLeftRightType(FGA);
            comptime assert(InstanceF.BaseType(l_type) == InstanceG.BaseType(r_type));
            return InstanceF.BaseType(l_type);
        }

        pub const Error = InstanceF.Error || InstanceG.Error;

        const FxTypes = FunctorFxTypes(F, Error);
        pub const FaType = FxTypes.FaType;
        pub const FbType = FxTypes.FbType;
        pub const FaLamType = FxTypes.FaLamType;
        pub const FbLamType = FxTypes.FbLamType;

        const AFxTypes = ApplicativeFxTypes(F, Error);
        pub const APaType = AFxTypes.APaType;
        pub const AFbType = AFxTypes.AFbType;

        pub fn deinitFa(
            fga: anytype, // (F(A), G(A))
            comptime free_fn: fn (BaseType(@TypeOf(fga))) void,
        ) void {
            InstanceF.deinitFa(fga[0], free_fn);
            InstanceG.deinitFa(fga[1], free_fn);
        }

        pub fn fmap(
            self: *Self,
            comptime K: MapFnKind,
            map_fn: anytype,
            fga: FaType(K, @TypeOf(map_fn)),
        ) FbType(@TypeOf(map_fn)) {
            return switch (fga) {
                .inl => |fa| .{ .inl = try self.instanceF.fmap(K, map_fn, fa) },
                .inr => |ga| .{ .inr = try self.instanceG.fmap(K, map_fn, ga) },
            };
        }

        pub fn fmapLam(
            self: *Self,
            comptime K: MapFnKind,
            map_lam: anytype,
            fga: FaLamType(K, @TypeOf(map_lam)),
        ) FbLamType(@TypeOf(map_lam)) {
            return switch (fga) {
                .inl => |fa| .{ .inl = try self.instanceF.fmapLam(K, map_lam, fa) },
                .inr => |ga| .{ .inr = try self.instanceG.fmapLam(K, map_lam, ga) },
            };
        }

        pub fn pure(self: *Self, a: anytype) APaType(@TypeOf(a)) {
            return .{ .inr = try self.instanceG.pure(a) };
        }

        pub fn fapply(
            self: *Self,
            comptime A: type,
            comptime B: type,
            // applicative function: F (a -> b), fa: F a
            fgf: F(*const fn (A) B),
            fga: F(A),
        ) AFbType(B) {
            const FnType = BaseType(@TypeOf(fgf));
            return switch (fgf) {
                .inl => |ff| switch (fga) {
                    .inl => |fa| .{ .inl = try self.instanceF.fapply(A, B, ff, fa) },
                    .inr => |ga| {
                        // fa is ArrayList(A), so we should be free it.
                        const fa = try self.natural_gf.trans(A, ga);
                        defer fa.deinit();
                        return .{ .inl = try self.instanceF.fapply(A, B, ff, fa) };
                    },
                },
                .inr => |gf| switch (fga) {
                    .inl => |fa| {
                        // ff is ArrayList(FnType), so we should be free it.
                        const ff = try self.natural_gf.trans(FnType, gf);
                        defer ff.deinit();
                        return .{ .inl = try self.instanceF.fapply(A, B, ff, fa) };
                    },
                    .inr => |ga| .{ .inr = try self.instanceG.fapply(A, B, gf, ga) },
                },
            };
        }

        pub fn fapplyLam(
            self: *Self,
            comptime A: type,
            comptime B: type,
            // applicative function: F (a -> b), fa: F a
            fgf: anytype,
            fga: F(A),
        ) AFbType(B) {
            const LamType = BaseType(@TypeOf(fgf));
            return switch (fgf) {
                .inl => |ff| switch (fga) {
                    .inl => |fa| .{ .inl = try self.instanceF.fapplyLam(A, B, ff, fa) },
                    .inr => |ga| {
                        // fa is ArrayList(A), so we should be free it.
                        const fa = try self.natural_gf.trans(A, ga);
                        defer fa.deinit();
                        return .{ .inl = try self.instanceF.fapplyLam(A, B, ff, fa) };
                    },
                },
                .inr => |gf| switch (fga) {
                    .inl => |fa| {
                        // ff is ArrayList(FnType), so we should be free it.
                        const ff = try self.natural_gf.trans(LamType, gf);
                        defer ff.deinit();
                        return .{ .inl = try self.instanceF.fapplyLam(A, B, ff, fa) };
                    },
                    .inr => |ga| .{ .inr = try self.instanceG.fapplyLam(A, B, gf, ga) },
                },
            };
        }
    };
}

/// Get a Coproduct Functor from two Functor, the parameter FunctorF and FunctorG
/// are Functor type.
pub fn CoproductFunctor(comptime FunctorF: type, comptime FunctorG: type) type {
    const InstanceFG = CoproductInst(FunctorF.InstanceType, FunctorG.InstanceType);
    return Functor(InstanceFG, InstanceFG.F);
}

/// Get a Coproduct Applicative from two Applicative, the parameter
/// ApplicativeF and ApplicativeG are Applicative Functor type.
pub fn CoproductApplicative(
    comptime ApplicativeF: type,
    comptime ApplicativeG: type,
    comptime NaturalGF: type,
) type {
    const InstanceFG = CoproductApplicativeInst(
        ApplicativeF.InstanceType,
        ApplicativeG.InstanceType,
        NaturalGF.InstanceType,
    );
    return Applicative(InstanceFG, InstanceFG.F);
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

    /// Constructor Type for Functor, Applicative, Monad, ...
    const F = Maybe;

    /// Get base type of F(A), it is must just is A.
    pub fn BaseType(comptime MaybeA: type) type {
        return std.meta.Child(MaybeA);
    }

    pub const Error = error{};

    const FaType = Functor(Self, F).FaType;
    const FbType = Functor(Self, F).FbType;
    const FaLamType = Functor(Self, F).FaLamType;
    const FbLamType = Functor(Self, F).FbLamType;

    const APaType = Applicative(Self, F).APaType;
    const AFbType = Applicative(Self, F).AFbType;

    const MbType = Monad(Self, F).MbType;

    pub fn deinitFa(
        fa: anytype, // Maybe(A)
        comptime free_fn: fn (BaseType(@TypeOf(fa))) void,
    ) void {
        if (fa) |a| {
            free_fn(a);
        }
    }

    pub fn fmap(
        self: *Self,
        comptime K: MapFnKind,
        map_fn: anytype,
        fa: FaType(K, @TypeOf(map_fn)),
    ) FbType(@TypeOf(map_fn)) {
        _ = self;
        const MapFn = @TypeOf(map_fn);
        const has_err, const B = isErrorUnionOrVal(MapFnRetType(MapFn));
        if (comptime isMapRef(K)) {
            if (fa.* != null) {
                const b = map_fn(&(fa.*.?));
                const fb: ?B = if (has_err) try b else b;
                return fb;
            }
        } else {
            if (fa) |a| {
                const b = map_fn(a);
                const fb: ?B = if (has_err) try b else b;
                return fb;
            }
        }

        return null;
    }

    pub fn fmapLam(
        self: *Self,
        comptime K: MapFnKind,
        map_lam: anytype,
        fa: FaLamType(K, @TypeOf(map_lam)),
    ) FbLamType(@TypeOf(map_lam)) {
        _ = self;
        const MapLam = @TypeOf(map_lam);
        const has_err, const B = isErrorUnionOrVal(MapLamRetType(MapLam));
        if (comptime isMapRef(K)) {
            if (fa.* != null) {
                const b = map_lam.call(@constCast(&(fa.*.?)));
                const fb: ?B = if (has_err) try b else b;
                return fb;
            }
        } else {
            if (fa) |a| {
                const b = map_lam.call(a);
                const fb: ?B = if (has_err) try b else b;
                return fb;
            }
        }

        return null;
    }

    pub fn pure(self: *Self, a: anytype) APaType(@TypeOf(a)) {
        _ = self;
        return a;
    }

    pub fn fapply(
        self: *Self,
        comptime A: type,
        comptime B: type,
        // applicative function: F (a -> b), fa: F a
        ff: F(*const fn (A) B),
        fa: F(A),
    ) AFbType(B) {
        _ = self;
        const has_err, const _B = isErrorUnionOrVal(B);
        if (ff) |f| {
            if (fa) |a| {
                const b = f(a);
                const fb: ?_B = if (has_err) try b else b;
                return fb;
            }
        }
        return null;
    }

    pub fn fapplyLam(
        self: *Self,
        comptime A: type,
        comptime B: type,
        // applicative function: F (a -> b), fa: F a
        flam: anytype, // a F(lambda) that present F(*const fn (A) B),
        fa: F(A),
    ) AFbType(B) {
        _ = self;
        const has_err, const _B = isErrorUnionOrVal(B);
        if (flam) |lam| {
            if (fa) |a| {
                const b = lam.call(a);
                const fb: ?_B = if (has_err) try b else b;
                return fb;
            }
        }
        return null;
    }

    pub fn bind(
        self: *Self,
        comptime A: type,
        comptime B: type,
        // monad function: (a -> M b), ma: M a
        ma: F(A),
        f: *const fn (*Self, A) MbType(B),
    ) MbType(B) {
        if (ma) |a| {
            return f(self, a);
        }
        return null;
    }
};

fn maybeSample() !void {
    const MaybeMonad = Monad(MaybeMonadInst, Maybe);
    var maybe_m = MaybeMonad.init(.{ .none = {} });

    var maybe_a: ?u32 = 42;
    maybe_a = try maybe_m.fmap(.InplaceMap, struct {
        fn f(a: u32) u32 {
            return a + 10;
        }
    }.f, maybe_a);

    const maybe_b = try maybe_m.fmap(.NewValMap, struct {
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
    var maybe_applied = try maybe_m.fapply(f64, u32, maybe_fn, maybe_b);
    std.debug.print("maybe_applied: {any}\n", .{maybe_applied});
    maybe_applied = try maybe_m.fapply(u32, u32, null, maybe_applied);
    std.debug.print("applied with null function: {any}\n", .{maybe_applied});

    const maybe_binded = try maybe_m.bind(f64, u32, maybe_b, struct {
        fn f(self: *MaybeMonadInst, x: f64) MaybeMonad.MbType(u32) {
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

    /// Constructor Type for Functor, Applicative, Monad, ...
    const F = ArrayList;

    /// Get base type of F(A), it is must just is A.
    pub fn BaseType(comptime ArrayA: type) type {
        return std.meta.Child(ArrayA.Slice);
    }

    pub const Error = Allocator.Error;

    const FaType = Functor(Self, F).FaType;
    const FbType = Functor(Self, F).FbType;
    const FaLamType = Functor(Self, F).FaLamType;
    const FbLamType = Functor(Self, F).FbLamType;

    const APaType = Applicative(Self, F).APaType;
    const AFbType = Applicative(Self, F).AFbType;

    const MbType = Monad(Self, F).MbType;

    pub fn deinitFa(
        fa: anytype, // ArrayList(A)
        comptime free_fn: fn (BaseType(@TypeOf(fa))) void,
    ) void {
        for (fa.items) |item| {
            free_fn(item);
        }
        fa.deinit();
    }

    /// If the returned array list of inplace map function assign to a new
    /// variable, then the array list in original variable should be reset
    /// to empty.
    pub fn fmap(
        self: *Self,
        comptime K: MapFnKind,
        map_fn: anytype,
        fa: FaType(K, @TypeOf(map_fn)),
    ) FbType(@TypeOf(map_fn)) {
        const MapFn = @TypeOf(map_fn);
        const map_lam = struct {
            map_fn: *const fn (a: MapFnInType(K, MapFn)) MapFnRetType(MapFn),

            const MapSelf = @This();
            pub fn call(
                map_self: *const MapSelf,
                a: MapFnInType(K, MapFn),
            ) MapFnRetType(MapFn) {
                return map_self.map_fn(a);
            }
        }{ .map_fn = &map_fn };

        return fmapLam(self, K, map_lam, fa);
    }

    pub fn fmapLam(
        self: *Self,
        comptime K: MapFnKind,
        map_lam: anytype,
        fa: FaLamType(K, @TypeOf(map_lam)),
    ) FbLamType(@TypeOf(map_lam)) {
        if (comptime isInplaceMap(K)) {
            return self.mapInplace(K, map_lam, fa);
        } else {
            return self.mapNewValue(K, map_lam, fa);
        }
    }

    fn mapInplace(
        self: *Self,
        comptime K: MapFnKind,
        map_lam: anytype,
        fa: FaLamType(K, @TypeOf(map_lam)),
    ) FbLamType(@TypeOf(map_lam)) {
        const A = MapLamInType(K, @TypeOf(map_lam));
        const has_err, const B = comptime isErrorUnionOrVal(MapLamRetType(@TypeOf(map_lam)));
        const ValA = if (comptime isMapRef(K)) std.meta.Child(A) else A;
        if (@bitSizeOf(ValA) != @bitSizeOf(B)) {
            @compileError("The bitsize of translated value is not equal origin value, failed to map it");
        }

        const arr = if (@typeInfo(@TypeOf(fa)) == .Pointer)
            @constCast(fa).moveToUnmanaged()
        else
            @constCast(&fa).moveToUnmanaged();
        var slice = arr.items;
        var i: usize = 0;
        while (i < slice.len) : (i += 1) {
            const a = if (comptime isMapRef(K)) &slice[i] else slice[i];
            const b = if (has_err) try map_lam.call(a) else map_lam.call(a);
            slice[i] = castInplaceValue(A, b);
        }
        return ArrayList(B).fromOwnedSlice(self.allocator, @ptrCast(slice));
    }

    fn mapNewValue(
        self: *Self,
        comptime K: MapFnKind,
        map_lam: anytype,
        fa: FaLamType(K, @TypeOf(map_lam)),
    ) FbLamType(@TypeOf(map_lam)) {
        const has_err, const B = comptime isErrorUnionOrVal(MapLamRetType(@TypeOf(map_lam)));
        var fb = try ArrayList(B).initCapacity(self.allocator, fa.items.len);

        var i: usize = 0;
        while (i < fa.items.len) : (i += 1) {
            const a = if (comptime isMapRef(K)) @constCast(&fa.items[i]) else fa.items[i];
            const b = if (has_err) try map_lam.call(a) else map_lam.call(a);
            fb.appendAssumeCapacity(b);
        }
        return fb;
    }

    pub fn pure(self: *Self, a: anytype) APaType(@TypeOf(a)) {
        var arr = try ArrayList(@TypeOf(a)).initCapacity(self.allocator, ARRAY_DEFAULT_LEN);

        arr.appendAssumeCapacity(a);
        return arr;
    }

    pub fn fapply(
        self: *Self,
        comptime A: type,
        comptime B: type,
        // applicative function: F (a -> b), fa: F a
        ff: F(*const fn (A) B),
        fa: F(A),
    ) AFbType(B) {
        return fapplyGeneric(self, .NormalMap, A, B, ff, fa);
    }

    pub fn fapplyLam(
        self: *Self,
        comptime A: type,
        comptime B: type,
        // applicative function: F (a -> b), fa: F a
        flam: anytype, // a F(lambda) that present F(*const fn (A) B),
        fa: F(A),
    ) AFbType(B) {
        return fapplyGeneric(self, .LambdaMap, A, B, flam, fa);
    }

    fn fapplyGeneric(
        self: *Self,
        comptime M: FMapMode,
        comptime A: type,
        comptime B: type,
        // applicative function: F (a -> b), fa: F a
        ff: anytype,
        fa: F(A),
    ) AFbType(B) {
        const has_err, const _B = comptime isErrorUnionOrVal(B);
        var fb = try ArrayList(_B)
            .initCapacity(self.allocator, ff.items.len * fa.items.len);

        for (ff.items) |f| {
            for (fa.items) |item| {
                const b = if (M == .NormalMap) f(item) else f.call(item);
                fb.appendAssumeCapacity(if (has_err) try b else b);
            }
        }
        return fb;
    }

    pub fn bind(
        self: *Self,
        comptime A: type,
        comptime B: type,
        // monad function: (a -> M b), ma: M a
        ma: F(A),
        f: *const fn (*Self, A) MbType(B),
    ) MbType(B) {
        var mb = ArrayList(B).init(self.allocator);
        for (ma.items) |a| {
            const tmp_mb = try f(self, a);
            defer tmp_mb.deinit();
            for (tmp_mb.items) |b| {
                try mb.append(b);
            }
        }
        return mb;
    }
};

pub const NatMaybeToArrayListInst = struct {
    instanceArray: ArrayListMonadInst,

    const Self = @This();

    const F = Maybe;
    const G = ArrayList;
    const Error = Functor(ArrayListMonadInst, ArrayList).Error;

    pub fn trans(self: Self, comptime A: type, fa: F(A)) Error!G(A) {
        if (fa) |a| {
            var array = try ArrayList(A).initCapacity(self.instanceArray.allocator, 1);
            array.appendAssumeCapacity(a);
            return array;
        } else {
            // return empty ArrayList
            return ArrayList(A).init(self.instanceArray.allocator);
        }
    }
};

pub const NatArrayListToMaybeInst = struct {
    const Self = @This();

    const F = ArrayList;
    const G = Maybe;
    const Error = Functor(MaybeMonadInst, Maybe).Error;

    pub fn trans(self: Self, comptime A: type, fa: F(A)) Error!G(A) {
        _ = self;
        if (fa.items.len > 0) {
            return fa.items[0];
        }

        return null;
    }
};

fn arraylistSample() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const ArrayListMonad = Monad(ArrayListMonadInst, ArrayList);
    var array_m = ArrayListMonad.init(.{ .allocator = allocator });

    var arr = ArrayList(u32).init(allocator);
    defer arr.deinit();
    var i: u32 = 0;
    while (i < 8) : (i += 1) {
        try arr.append(i);
    }

    // example of functor
    arr = try array_m.fmap(.InplaceMap, struct {
        fn f(a: u32) u32 {
            return a + 42;
        }
    }.f, arr);
    std.debug.print("arr inplace mapped: {any}\n", .{arr.items});

    const arr_f32 = try array_m.fmap(.InplaceMap, struct {
        fn f(a: u32) f32 {
            return @as(f32, @floatFromInt(a)) + 6.18;
        }
    }.f, arr);
    std.debug.print("arr float32 inplace mapped: {any}\n", .{arr_f32.items});

    arr = try array_m.fmap(.InplaceMap, struct {
        fn f(a: f32) u32 {
            return @as(u32, @intFromFloat(a)) + 58;
        }
    }.f, arr_f32);
    std.debug.print("arr inplace mapped again: {any}\n", .{arr.items});

    const arr_new = try array_m.fmap(.NewValMap, struct {
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

    var arr_fns = try ArrayList(FloatToIntFn).initCapacity(allocator, fn_array.len);
    defer arr_fns.deinit();
    for (fn_array) |f| {
        arr_fns.appendAssumeCapacity(f);
    }

    const arr_applied = try array_m.fapply(f64, u32, arr_fns, arr_new);
    defer arr_applied.deinit();
    std.debug.print("arr_applied: {any}\n", .{arr_applied.items});

    // example of monad
    const arr_binded = try array_m.bind(f64, u32, arr_new, struct {
        fn f(inst: *@TypeOf(array_m), a: f64) ArrayListMonad.MbType(u32) {
            var arr_b = ArrayList(u32).initCapacity(inst.allocator, 2) catch @panic("arraylistSample: No memory to create result arraylist monad!");
            arr_b.appendAssumeCapacity(@intFromFloat(@ceil(a * 4.0)));
            arr_b.appendAssumeCapacity(@intFromFloat(@ceil(a * 9.0)));
            return arr_b;
        }
    }.f);
    defer arr_binded.deinit();
    std.debug.print("arr_binded: {any}\n", .{arr_binded.items});
}

fn composeSample() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    const ArrayListApplicative = Applicative(ArrayListMonadInst, ArrayList);
    const MaybeApplicative = Applicative(MaybeMonadInst, Maybe);
    const ArrayListMaybeApplicative = ComposeApplicative(ArrayListApplicative, MaybeApplicative);

    var array_maybe = ArrayListMaybeApplicative.init(.{
        .instanceF = .{ .allocator = allocator },
        .instanceG = .{ .none = {} },
    });
    var arr = try ArrayList(Maybe(u32)).initCapacity(allocator, 8);
    defer arr.deinit();

    var i: u32 = 8;
    while (i < 8 + 8) : (i += 1) {
        if ((i & 0x1) == 0) {
            arr.appendAssumeCapacity(i);
        } else {
            arr.appendAssumeCapacity(null);
        }
    }

    // example of applicative functor
    arr = try array_maybe.fmap(.InplaceMap, struct {
        fn f(a: u32) u32 {
            return a + 42;
        }
    }.f, arr);
    std.debug.print("arr mapped: {any}\n", .{arr.items});

    const arr_new = try array_maybe.fmap(.NewValMap, struct {
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

    var arr_fns = try ArrayList(Maybe(FloatToIntFn)).initCapacity(allocator, fn_array.len + 1);
    defer arr_fns.deinit();
    for (fn_array) |f| {
        arr_fns.appendAssumeCapacity(f);
    }
    arr_fns.appendAssumeCapacity(null);

    const arr_applied = try array_maybe.fapply(f64, u32, arr_fns, arr_new);
    defer arr_applied.deinit();
    std.debug.print("arr_applied: {any}\n", .{arr_applied.items});

    // pretty print the arr3 with type ArrayList(Maybe(ArrayList(A))
    const prettyPrintArr3 = struct {
        fn prettyPrint(arr3: anytype) void {
            std.debug.print("{{ \n", .{});
            var j: u32 = 0;
            for (arr3.items) |item| {
                if (item) |o| {
                    std.debug.print(" {{ ", .{});
                    for (o.items) |a| {
                        std.debug.print("{any},", .{a});
                    }
                    std.debug.print(" }},", .{});
                } else {
                    std.debug.print(" {any},", .{item});
                }

                j += 1;
                if (j == 16) {
                    j = 0;
                    std.debug.print("\n", .{});
                }
            }
            std.debug.print("}}\n", .{});
        }
    }.prettyPrint;

    // example of compose three applicative functor
    const IntToIntFn = *const fn (u32) u32;
    var fn_int_array = [_]IntToIntFn{
        struct {
            fn f(x: u32) u32 {
                return x + 20;
            }
        }.f,
        struct {
            fn f(x: u32) u32 {
                return x * 2;
            }
        }.f,
    };

    const intToFns = struct {
        allocator: Allocator,
        fns: []IntToIntFn,

        const FnSelf = @This();
        fn call(self: *const FnSelf, a: u32) Allocator.Error!ArrayList(IntToIntFn) {
            _ = a;
            var arr1_fn = try ArrayList(IntToIntFn).initCapacity(self.allocator, self.fns.len);
            for (self.fns) |f| {
                arr1_fn.appendAssumeCapacity(f);
            }
            return arr1_fn;
        }
    }{ .allocator = allocator, .fns = fn_int_array[0..2] };

    var arr3_fns = try array_maybe.fmapLam(.NewValMap, intToFns, arr);
    defer {
        for (arr3_fns.items) |item| {
            if (item) |o| {
                o.deinit();
            }
        }
        arr3_fns.deinit();
    }

    const intToArr = struct {
        allocator: Allocator,

        const FnSelf = @This();
        fn call(self: *const FnSelf, a: u32) Allocator.Error!ArrayList(u32) {
            var tmp = a;
            var j: u32 = 0;
            var int_arr = try ArrayList(u32).initCapacity(self.allocator, 3);
            while (j < 3) : ({
                j += 1;
                tmp += 2;
            }) {
                int_arr.appendAssumeCapacity(tmp);
            }
            return int_arr;
        }
    }{ .allocator = allocator };

    var arr3_ints = try array_maybe.fmapLam(.NewValMap, intToArr, arr_applied);
    defer {
        for (arr3_ints.items) |item| {
            if (item) |o| {
                o.deinit();
            }
        }
        arr3_ints.deinit();
    }
    // std.debug.print("arr3_ints: {any}\n", .{arr3_ints.items});

    const ArrayMaybeArrayApplicative = ComposeApplicative(ArrayListMaybeApplicative, ArrayListApplicative);
    var array_maybe_array = ArrayMaybeArrayApplicative.init(.{
        .instanceF = array_maybe,
        .instanceG = ArrayListApplicative.init(.{
            .allocator = allocator,
        }),
    });

    const arr3_appried = try array_maybe_array.fapply(u32, u32, arr3_fns, arr3_ints);
    defer {
        for (arr3_appried.items) |item| {
            if (item) |o| {
                o.deinit();
            }
        }
        arr3_appried.deinit();
    }
    std.debug.print("arr3_appried: ", .{});
    prettyPrintArr3(arr3_appried);
}

const ArrayAndMaybe = productFG(ArrayList, Maybe);

fn productSample() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    const ArrayListApplicative = Applicative(ArrayListMonadInst, ArrayList);
    const MaybeApplicative = Applicative(MaybeMonadInst, Maybe);
    const ArrayListAndMaybeApplicative = ProductApplicative(ArrayListApplicative, MaybeApplicative);

    var array_and_maybe = ArrayListAndMaybeApplicative.init(.{
        .instanceF = .{ .allocator = allocator },
        .instanceG = .{ .none = {} },
    });

    // pretty print the arr3 with type ArrayList(Maybe(ArrayList(A))
    const prettyArrayAndMaybe = struct {
        fn prettyPrint(arr_and_maybe: anytype) void {
            std.debug.print("{{ {any}, {any} }}\n", .{ arr_and_maybe[0].items, arr_and_maybe[1] });
        }
    }.prettyPrint;

    var arr = try ArrayList(u32).initCapacity(allocator, 8);
    defer arr.deinit();
    var i: u32 = 8;
    while (i < 8 + 8) : (i += 1) {
        arr.appendAssumeCapacity(i);
    }
    var arr_and_maybe = ArrayAndMaybe(u32){ arr, 42 };

    // example of applicative functor
    arr_and_maybe = try array_and_maybe.fmap(.InplaceMap, struct {
        fn f(a: u32) u32 {
            return a + 42;
        }
    }.f, arr_and_maybe);
    std.debug.print("arr_and_maybe mapped: ", .{});
    prettyArrayAndMaybe(arr_and_maybe);

    const arr_and_maybe_new = try array_and_maybe.fmap(.NewValMap, struct {
        fn f(a: u32) f64 {
            return @as(f64, @floatFromInt(a)) * 3.14;
        }
    }.f, arr_and_maybe);
    defer arr_and_maybe_new[0].deinit();
    std.debug.print("arr_and_maybe_new: ", .{});
    prettyArrayAndMaybe(arr_and_maybe_new);

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

    var arr_fns = try ArrayList(FloatToIntFn).initCapacity(allocator, fn_array.len);
    defer arr_fns.deinit();
    for (fn_array) |f| {
        arr_fns.appendAssumeCapacity(f);
    }
    const arr_and_maybe_fns = ArrayAndMaybe(FloatToIntFn){ arr_fns, fn_array[0] };

    const arr_and_maybe_applied = try array_and_maybe.fapply(f64, u32, arr_and_maybe_fns, arr_and_maybe_new);
    defer arr_and_maybe_applied[0].deinit();
    std.debug.print("arr_and_maybe_applied: ", .{});
    prettyArrayAndMaybe(arr_and_maybe_applied);
}

const ArrayOrMaybe = coproductFG(ArrayList, Maybe);

fn coproductSample() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    const ArrayListApplicative = Applicative(ArrayListMonadInst, ArrayList);
    const MaybeApplicative = Applicative(MaybeMonadInst, Maybe);
    const NatMaybeToArray = NatTrans(NatMaybeToArrayListInst, Maybe, ArrayList);
    const ArrayListOrMaybeApplicative = CoproductApplicative(ArrayListApplicative, MaybeApplicative, NatMaybeToArray);

    var array_or_maybe = ArrayListOrMaybeApplicative.init(.{
        // ArrayList Applicative instance
        .instanceF = .{ .allocator = allocator },
        // Maybe Applicative instance
        .instanceG = .{ .none = {} },
        // NatMaybeToArray Applicative instance
        .natural_gf = .{ .instanceArray = .{ .allocator = allocator } },
    });

    // pretty print the arr_or_maybe with type Coproduct(ArrayList, Maybe)
    const prettyArrayOrMaybe = struct {
        fn prettyPrint(arr_or_maybe: anytype) void {
            if (arr_or_maybe == .inl) {
                std.debug.print("{{ inl: {any} }}\n", .{arr_or_maybe.inl.items});
            } else {
                std.debug.print("{{ inr: {any} }}\n", .{arr_or_maybe.inr});
            }
        }
    }.prettyPrint;

    var arr = try ArrayList(u32).initCapacity(allocator, 8);
    defer arr.deinit();
    var i: u32 = 8;
    while (i < 8 + 8) : (i += 1) {
        arr.appendAssumeCapacity(i);
    }
    var arr_or_maybe = ArrayOrMaybe(u32){ .inl = arr };

    // example of applicative functor
    arr_or_maybe = try array_or_maybe.fmap(.InplaceMap, struct {
        fn f(a: u32) u32 {
            return a + 42;
        }
    }.f, arr_or_maybe);
    std.debug.print("arr_or_maybe mapped: ", .{});
    prettyArrayOrMaybe(arr_or_maybe);

    const arr_or_maybe_new = try array_or_maybe.fmap(.NewValMap, struct {
        fn f(a: u32) f64 {
            return @as(f64, @floatFromInt(a)) * 3.14;
        }
    }.f, arr_or_maybe);
    defer {
        if (arr_or_maybe_new == .inl) {
            arr_or_maybe_new.inl.deinit();
        }
    }
    std.debug.print("arr_or_maybe_new: ", .{});
    prettyArrayOrMaybe(arr_or_maybe_new);

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

    var arr_fns = try ArrayList(FloatToIntFn).initCapacity(allocator, fn_array.len);
    defer arr_fns.deinit();
    for (fn_array) |f| {
        arr_fns.appendAssumeCapacity(f);
    }
    const or_array_fns = ArrayOrMaybe(FloatToIntFn){ .inl = arr_fns };
    const or_maybe_fns = ArrayOrMaybe(FloatToIntFn){ .inr = fn_array[1] };

    const maybe_array_applied = try array_or_maybe.fapply(f64, u32, or_maybe_fns, arr_or_maybe_new);
    defer {
        if (maybe_array_applied == .inl) {
            maybe_array_applied.inl.deinit();
        }
    }
    std.debug.print("maybe_array_applied: ", .{});
    prettyArrayOrMaybe(maybe_array_applied);

    const array_array_applied = try array_or_maybe.fapply(f64, u32, or_array_fns, arr_or_maybe_new);
    defer {
        if (array_array_applied == .inl) {
            array_array_applied.inl.deinit();
        }
    }
    std.debug.print("array_array_applied: ", .{});
    prettyArrayOrMaybe(array_array_applied);

    const or_maybe_float = ArrayOrMaybe(f64){ .inr = 2.71828 };
    const array_maybe_applied = try array_or_maybe.fapply(f64, u32, or_array_fns, or_maybe_float);
    defer {
        if (array_maybe_applied == .inl) {
            array_maybe_applied.inl.deinit();
        }
    }
    std.debug.print("array_maybe_applied: ", .{});
    prettyArrayOrMaybe(array_maybe_applied);

    const maybe_maybe_applied = try array_or_maybe.fapply(f64, u32, or_maybe_fns, or_maybe_float);
    defer {
        if (maybe_maybe_applied == .inl) {
            maybe_maybe_applied.inl.deinit();
        }
    }
    std.debug.print("maybe_maybe_applied: ", .{});
    prettyArrayOrMaybe(maybe_maybe_applied);
}

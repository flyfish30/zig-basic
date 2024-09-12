//! Implement Functor/Applicative/Monad for pure functional.
//!
//! There is no error returned from fmap/fmapLam/fapply/fapplyLam/bind
//! function, the map_fn/apply_fn/bind_fn function also don't return error.

const std = @import("std");

const assert = std.debug.assert;

pub fn pureAlgSample() void {
    maybeSample();
    arraySample();
    composeSample();
    productSample();
    coproductSample();
}

/// A single-argument type function for type constructor
pub const TCtor = fn (comptime type) type;

fn MapFnInType(comptime MapFn: type) type {
    const len = @typeInfo(MapFn).Fn.params.len;

    if (len != 1) {
        @compileError("The map function must has only one parameter!");
    }

    return @typeInfo(MapFn).Fn.params[0].type.?;
}

fn MapFnRetType(comptime MapFn: type) type {
    const R = @typeInfo(MapFn).Fn.return_type.?;

    if (R == noreturn) {
        @compileError("The return type of map function must not be noreturn!");
    }
    return R;
}

fn MapLamInType(comptime MapLam: type) type {
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

    return mapFnInfo.Fn.params[1].type.?;
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

// fn FMapType(
//     // F is instance of Functor typeclass, such as Maybe, List
//     comptime F: TCtor,
//     map_fn: anytype
// ) type {
//     const T = MapFnInType(@TypeOf(map_fn));
//     const R = MapFnRetType(@TypeOf(map_fn));
//     return *const fn (comptime T: type, comptime R: type, map_fn: fn(T) R, fa: F(T)) F(R);
// }

/// FMapFn create a struct type that will to run map function
// FMapFn: *const fn (comptime K: MapFnKind, comptime MapFnT: type) type,

pub fn FunctorFxTypes(comptime F: TCtor) type {
    return struct {
        fn FaType(comptime K: MapFnKind, comptime MapFn: type) type {
            if (comptime isMapRef(K)) {
                // The fa paramerter of fmap function is also a reference.
                return *F(std.meta.Child(MapFnInType(MapFn)));
            } else {
                return F(MapFnInType(MapFn));
            }
        }

        fn FbType(comptime MapFn: type) type {
            return F(MapFnRetType(MapFn));
        }

        fn FaLamType(comptime K: MapFnKind, comptime MapLam: type) type {
            if (comptime isMapRef(K)) {
                // The fa paramerter of fmapLam function is also a reference.
                return *F(std.meta.Child(MapLamInType(MapLam)));
            } else {
                return F(MapLamInType(MapLam));
            }
        }

        fn FbLamType(comptime MapLam: type) type {
            return F(MapLamRetType(MapLam));
        }
    };
}

/// Functor typeclass like in Haskell.
/// F is Constructor Type of Functor typeclass, such as Maybe, List.
pub fn Functor(comptime FunctorImpl: type) type {
    if (!@hasDecl(FunctorImpl, "F")) {
        @compileError("The Functor instance must has F type!");
    }

    if (!@hasDecl(FunctorImpl, "BaseType")) {
        @compileError("The Functor instance must has type function: BaseType!");
    }

    if (!@hasDecl(FunctorImpl, "deinitFa")) {
        @compileError("The Functor instance must has deinitFa function!");
    }

    const F = FunctorImpl.F;
    const InstanceType = struct {
        const InstanceImpl = FunctorImpl;

        pub const FxTypes = FunctorFxTypes(F);
        pub const FaType = FxTypes.FaType;
        pub const FbType = FxTypes.FbType;
        pub const FaLamType = FxTypes.FaLamType;
        pub const FbLamType = FxTypes.FbLamType;

        /// Typeclass function for map with function
        const FMapType = @TypeOf(struct {
            fn fmapFn(
                comptime K: MapFnKind,
                // f: a -> b, fa: F a
                f: anytype,
                fa: FaType(K, @TypeOf(f)),
            ) FbType(@TypeOf(f)) {
                _ = fa;
            }
        }.fmapFn);

        /// Typeclass function for map with lambda
        const FMapLamType = @TypeOf(struct {
            fn fmapLam(
                comptime K: MapFnKind,
                // f: a -> b, fa: F a
                lam: anytype,
                fa: FaLamType(K, @TypeOf(lam)),
            ) FbLamType(@TypeOf(lam)) {
                _ = fa;
            }
        }.fmapLam);

        pub fn init() void {
            if (@TypeOf(InstanceImpl.fmap) != FMapType) {
                @compileError("Incorrect type of fmap for Functor instance " ++ @typeName(InstanceImpl));
            }
            if (@TypeOf(InstanceImpl.fmapLam) != FMapLamType) {
                @compileError("Incorrect type of fmapLam for Functor instance " ++ @typeName(InstanceImpl));
            }
        }

        pub const fmap = InstanceImpl.fmap;
        pub const fmapLam = InstanceImpl.fmapLam;
    };

    InstanceType.init();
    return InstanceType;
}

pub fn NatTransType(comptime F: TCtor, comptime G: TCtor) type {
    return @TypeOf(struct {
        fn transFn(comptime A: type, fa: F(A)) G(A) {
            _ = fa;
        }
    }.transFn);
}

/// Natural Translation typeclass like in Haskell.
/// F and G is Constructor Type of Functor typeclass, such as Maybe, List.
pub fn NatTrans(
    comptime NatTransImpl: type,
) type {
    if (!(@hasDecl(NatTransImpl, "F") and @hasDecl(NatTransImpl, "G"))) {
        @compileError("The NatTrans instance must has F and G type!");
    }

    const F = NatTransImpl.F;
    const G = NatTransImpl.G;

    const InstanceType = struct {
        const InstanceImpl = NatTransImpl;

        const FTransType = @TypeOf(struct {
            fn transFn(comptime A: type, fa: F(A)) G(A) {
                _ = fa;
            }
        }.transFn);

        pub fn init() void {
            if (@TypeOf(InstanceImpl.trans) != FTransType) {
                @compileError("Incorrect type of fmap for NatTrans instance " ++ @typeName(InstanceImpl));
            }
        }

        pub const trans = InstanceImpl.trans;
    };

    InstanceType.init();
    return InstanceType;
}

/// Applicative Functor typeclass like in Haskell, it inherit from Functor.
/// F is instance of Applicative Functor typeclass, such as Maybe, List
pub fn Applicative(comptime ApplicativeImpl: type) type {
    const F = ApplicativeImpl.F;
    const has_sup_impl = @hasField(ApplicativeImpl, "SupImpl");

    const InstanceType = struct {
        const InstanceImpl = ApplicativeImpl;
        const FunctorSup = if (has_sup_impl)
            Functor(InstanceImpl.SupImpl)
        else
            Functor(InstanceImpl);

        const PureType = @TypeOf(struct {
            fn pureFn(a: anytype) F(@TypeOf(a)) {}
        }.pureFn);

        const ApplyType = @TypeOf(struct {
            fn fapplyFn(
                comptime A: type,
                comptime B: type,
                // applicative function: F (a -> b), fa: F a
                ff: F(*const fn (A) B),
                fa: F(A),
            ) F(B) {
                _ = ff;
                _ = fa;
            }
        }.fapplyFn);

        const ApplyLamType = @TypeOf(struct {
            fn fapplyLam(
                comptime A: type,
                comptime B: type,
                // applicative function: F (a -> b), fa: F a
                flam: anytype, // a F(lambda) that present F(*const fn (A) B),
                fa: F(A),
            ) F(B) {
                _ = flam;
                _ = fa;
            }
        }.fapplyLam);

        // pub fn liftA2(
        //     // map2 function f: a -> b -> c
        //     f: anytype,
        //     fa: Map2FaType(@TypeOf(f)),
        //     fb: Map2FbType(@TypeOf(f)),
        // ) Map2FcType(@TypeOf(f)) {
        //     // liftA2 f fa fb = pure f <*> fa <*> fb
        // }

        pub fn init() void {
            if (@TypeOf(InstanceImpl.pure) != PureType) {
                @compileError("Incorrect type of pure for Applicative instance " ++ @typeName(InstanceImpl));
            }
            if (@TypeOf(InstanceImpl.fapply) != ApplyType) {
                @compileError("Incorrect type of fapply for Applicative instance " ++ @typeName(InstanceImpl));
            }
            if (@TypeOf(InstanceImpl.fapplyLam) != ApplyLamType) {
                @compileError("Incorrect type of fapply lambda for Applicative instance " ++ @typeName(InstanceImpl));
            }
        }

        pub const fmap = FunctorSup.fmap;
        pub const fmapLam = FunctorSup.fmapLam;
        pub const pure = InstanceImpl.pure;
        pub const fapply = InstanceImpl.fapply;
        pub const fapplyLam = InstanceImpl.fapplyLam;
    };

    InstanceType.init();
    return InstanceType;
}

/// Monad typeclass like in Haskell, it inherit from Applicative Functor.
/// M is instance of Monad typeclass, such as Maybe, List
pub fn Monad(comptime MonadImpl: type) type {
    const M = MonadImpl.F;
    const has_sup_impl = @hasField(MonadImpl, "SupImpl");

    const InstanceType = struct {
        const InstanceImpl = MonadImpl;
        const ApplicativeSup = if (has_sup_impl)
            Applicative(InstanceImpl.SupImpl)
        else
            Applicative(InstanceImpl);

        const BindType = @TypeOf(struct {
            fn bindFn(
                comptime A: type,
                comptime B: type,
                // monad function: (a -> M b), ma: M a
                ma: M(A),
                f: *const fn (*InstanceImpl, A) M(B),
            ) M(B) {
                _ = ma;
                _ = f;
            }
        }.bindFn);

        pub fn init() void {
            if (@TypeOf(InstanceImpl.bind) != BindType) {
                @compileError("Incorrect type of bind for Monad instance " ++ @typeName(InstanceImpl));
            }
        }

        pub const fmap = ApplicativeSup.fmap;
        pub const fmapLam = ApplicativeSup.fmapLam;
        pub const pure = ApplicativeSup.pure;
        pub const fapply = ApplicativeSup.fapply;
        pub const fapplyLam = ApplicativeSup.fapplyLam;
        pub const bind = InstanceImpl.bind;
    };

    InstanceType.init();
    return InstanceType;
}

/// Compose two Type constructor to one Type constructor, the parameter
/// F and G are one parameter Type consturctor.
pub fn composeFG(comptime F: TCtor, comptime G: TCtor) TCtor {
    return struct {
        fn Composed(comptime A: type) type {
            return F(G(A));
        }
    }.Composed;
}

pub fn ComposeFunctorImpl(comptime ImplF: type, comptime ImplG: type) type {
    return struct {
        const FunctorF = Functor(ImplF);
        const FunctorG = Functor(ImplG);

        /// Constructor Type for Functor, Applicative, Monad, ...
        const F = composeFG(ImplF.F, ImplG.F);

        /// Get base type of F(A), it is must just is A.
        /// In this instance, type F(A) is composed FG(A) by ImplF and
        /// ImplG.
        pub fn BaseType(comptime FGA: type) type {
            return ImplG.BaseType(ImplF.BaseType(FGA));
        }

        pub const FxTypes = FunctorFxTypes(F);
        pub const FaType = FxTypes.FaType;
        pub const FbType = FxTypes.FbType;
        pub const FaLamType = FxTypes.FaLamType;
        pub const FbLamType = FxTypes.FbLamType;

        pub fn deinitFa(
            fga: anytype, // F(G(A))
            comptime free_fn: fn (BaseType(@TypeOf(fga))) void,
        ) void {
            const free_ga_fn = struct {
                fn freeGa(ga: ImplF.BaseType(@TypeOf(fga))) void {
                    ImplG.deinitFa(ga, free_fn);
                }
            }.freeGa;
            ImplF.deinitFa(fga, free_ga_fn);
        }

        pub fn fmap(
            comptime K: MapFnKind,
            map_fn: anytype,
            fga: FaType(K, @TypeOf(map_fn)),
        ) FbType(@TypeOf(map_fn)) {
            const MapFn = @TypeOf(map_fn);
            const map_lam = struct {
                map_fn: *const fn (a: MapFnInType(MapFn)) MapFnRetType(MapFn),

                const MapSelf = @This();
                pub fn call(mapSelf: *const MapSelf, a: MapFnInType(MapFn)) MapFnRetType(MapFn) {
                    return mapSelf.map_fn(a);
                }
            }{ .map_fn = &map_fn };

            return fmapLam(K, map_lam, fga);
        }

        pub fn fmapLam(
            comptime K: MapFnKind,
            map_lam: anytype,
            fga: FaLamType(K, @TypeOf(map_lam)),
        ) FbLamType(@TypeOf(map_lam)) {
            const MapLam = @TypeOf(map_lam);
            const map_inner = struct {
                map_lam: MapLam,

                const InnerSelf = @This();
                fn call(
                    inner_self: *const InnerSelf,
                    ga: FunctorG.FaLamType(K, MapLam),
                ) FunctorG.FbLamType(MapLam) {
                    return ImplG.fmapLam(K, inner_self.map_lam, ga);
                }
            }{
                .map_lam = map_lam,
            };

            return ImplF.fmapLam(K, map_inner, fga);
        }
    };
}

pub fn ComposeApplicativeImpl(comptime ImplF: type, comptime ImplG: type) type {
    return struct {
        const SupImpl = ComposeFunctorImpl(ImplF, ImplG);

        /// Constructor Type for Functor, Applicative, Monad, ...
        const F = SupImpl.F;

        /// Get base type of F(A), it is must just is A.
        /// In this instance, type F(A) is composed FG(A) by ImplF and
        /// ImplG.
        const BaseType = SupImpl.BaseType;

        pub const FaType = SupImpl.FaType;
        pub const FbType = SupImpl.FbType;
        pub const FaLamType = SupImpl.FaLamType;
        pub const FbLamType = SupImpl.FbLamType;

        pub const deinitFa = SupImpl.deinitFa;
        pub const fmap = SupImpl.fmap;
        pub const fmapLam = SupImpl.fmapLam;

        pub fn pure(a: anytype) F(@TypeOf(a)) {
            return ImplF.pure(ImplG.pure(a));
        }

        pub fn fapply(
            comptime A: type,
            comptime B: type,
            // applicative function: F (a -> b), fa: F a
            fgf: F(*const fn (A) B),
            fga: F(A),
        ) F(B) {
            return fapplyGeneric(.NormalMap, A, B, fgf, fga);
        }

        pub fn fapplyLam(
            comptime A: type,
            comptime B: type,
            // applicative function: F (a -> b), fa: F a
            fgf: anytype,
            fga: F(A),
        ) F(B) {
            return fapplyGeneric(.LambdaMap, A, B, fgf, fga);
        }

        fn fapplyGeneric(
            comptime M: FMapMode,
            comptime A: type,
            comptime B: type,
            // applicative function: F (a -> b), fa: F a
            fgf: anytype,
            fga: F(A),
        ) F(B) {
            // inner_fapply: G (a -> b) -> G a -> G b
            // outer_fapply: F (G a -> G b) -> F (G a) -> F (G b)
            // fmap inner_fapply: F (G (a -> b)) -> F (G a -> G b)
            // outer_fapply (fmap inner_fapply): F (G (a -> b)) -> F (G a) -> F (G b)
            // fapply = outer_fapply (fmap inner_fapply)

            // A function with type *const fn (A) B
            // or a lambda that has function *const fn (LamSelf, A) B
            const FnOrLambdaType = BaseType(@TypeOf(fgf));

            const InnerApply = struct {
                pub const ApplyLam = struct {
                    apply_gf_p: *ImplG.F(FnOrLambdaType),

                    const ApplySelf = @This();
                    // applyFn: G a -> G b
                    fn call(applySelf: *const ApplySelf, ga: ImplG.F(A)) ImplG.F(B) {
                        if (M == .NormalMap) {
                            return ImplG.fapply(A, B, applySelf.apply_gf_p.*, ga);
                        } else {
                            return ImplG.fapplyLam(A, B, applySelf.apply_gf_p.*, ga);
                        }
                    }
                };

                // mapFn \gf_p -> apply_lam : G (a -> b) -> G a -> G b
                fn fapply(
                    gf_p: *ImplG.F(FnOrLambdaType),
                ) ApplyLam {
                    const apply_lam = .{
                        .apply_gf_p = gf_p,
                    };
                    // apply lambda \ga -> fapply instanceG gf ga : G a -> G b
                    return apply_lam;
                }
            };

            const free_fn = struct {
                fn free_fn(lam: InnerApply.ApplyLam) void {
                    _ = lam;
                }
            }.free_fn;

            const inner_fapply = InnerApply.fapply;
            const flam = ImplF.fmap(.NewValMapRef, inner_fapply, @constCast(&fgf));
            defer ImplF.deinitFa(flam, free_fn);
            return ImplF.fapplyLam(
                ImplG.F(A),
                ImplG.F(B),
                flam,
                fga,
            );
        }
    };
}

/// Compose two Functor to one Functor, the parameter FunctorF and FunctorG
/// are Functor type.
pub fn ComposeFunctor(comptime FunctorF: type, comptime FunctorG: type) type {
    const ImplFG = ComposeFunctorImpl(FunctorF.InstanceImpl, FunctorG.InstanceImpl);
    return Functor(ImplFG);
}

/// Compose two Applicative Functor to one Applicative Functor, the parameter
/// ApplicativeF and ApplicativeG are Applicative Functor type.
pub fn ComposeApplicative(comptime ApplicativeF: type, comptime ApplicativeG: type) type {
    const ImplFG = ComposeApplicativeImpl(ApplicativeF.InstanceImpl, ApplicativeG.InstanceImpl);
    return Applicative(ImplFG);
}

/// Get a Product Type constructor from two Type constructor, the parameter
/// F and G are one parameter Type consturctor.
pub fn productFG(comptime F: TCtor, comptime G: TCtor) TCtor {
    return struct {
        fn Producted(comptime A: type) type {
            return struct { F(A), G(A) };
        }
    }.Producted;
}

/// Get tuple of left and right type of product
pub fn getProductTypeTuple(comptime P: type) struct { type, type } {
    const info = @typeInfo(P);
    comptime assert(info == .Struct and info.Struct.is_tuple == true);
    comptime assert(info.Struct.fields.len == 2);

    const l_type = info.Struct.fields[0].type;
    const r_type = info.Struct.fields[1].type;
    return .{ l_type, r_type };
}

pub fn ProductFunctorImpl(comptime ImplF: type, comptime ImplG: type) type {
    return struct {
        const FunctorF = Functor(ImplF);
        const FunctorG = Functor(ImplG);

        /// Constructor Type for Functor, Applicative, Monad, ...
        const F = productFG(ImplF.F, ImplG.F);

        /// Get base type of F(A), it is must just is A.
        /// In this instance, type F(A) is product (F(A), G(A)) by ImplF and
        /// ImplG.
        pub fn BaseType(comptime FGA: type) type {
            const l_type, const r_type = getProductTypeTuple(FGA);
            comptime assert(ImplF.BaseType(l_type) == ImplG.BaseType(r_type));
            return ImplF.BaseType(l_type);
        }

        pub const FxTypes = FunctorFxTypes(F);
        pub const FaType = FxTypes.FaType;
        pub const FbType = FxTypes.FbType;
        pub const FaLamType = FxTypes.FaLamType;
        pub const FbLamType = FxTypes.FbLamType;

        pub fn deinitFa(
            fga: anytype, // (F(A), G(A))
            comptime free_fn: fn (BaseType(@TypeOf(fga))) void,
        ) void {
            ImplF.deinitFa(fga[0], free_fn);
            ImplG.deinitFa(fga[1], free_fn);
        }

        pub fn fmap(
            comptime K: MapFnKind,
            map_fn: anytype,
            fga: FaType(K, @TypeOf(map_fn)),
        ) FbType(@TypeOf(map_fn)) {
            return .{
                ImplF.fmap(K, map_fn, fga[0]),
                ImplG.fmap(K, map_fn, fga[1]),
            };
        }

        pub fn fmapLam(
            comptime K: MapFnKind,
            map_lam: anytype,
            fga: FaLamType(K, @TypeOf(map_lam)),
        ) FbLamType(@TypeOf(map_lam)) {
            return .{
                ImplF.fmapLam(K, map_lam, fga[0]),
                ImplG.fmapLam(K, map_lam, fga[1]),
            };
        }
    };
}

pub fn ProductApplicativeImpl(comptime ImplF: type, comptime ImplG: type) type {
    return struct {
        const SupImpl = ProductFunctorImpl(ImplF, ImplG);

        /// Constructor Type for Functor, Applicative, Monad, ...
        const F = SupImpl.F;

        /// Get base type of F(A), it is must just is A.
        /// In this instance, type F(A) is product (F(A), G(A)) by ImplF and
        /// ImplG.
        const BaseType = SupImpl.BaseType;

        pub const FaType = SupImpl.FaType;
        pub const FbType = SupImpl.FbType;
        pub const FaLamType = SupImpl.FaLamType;
        pub const FbLamType = SupImpl.FbLamType;

        pub const deinitFa = SupImpl.deinitFa;
        pub const fmap = SupImpl.fmap;
        pub const fmapLam = SupImpl.fmapLam;

        pub fn pure(a: anytype) F(@TypeOf(a)) {
            return .{
                ImplF.pure(a),
                ImplG.pure(a),
            };
        }

        pub fn fapply(
            comptime A: type,
            comptime B: type,
            // applicative function: F (a -> b), fa: F a
            fgf: F(*const fn (A) B),
            fga: F(A),
        ) F(B) {
            return .{
                ImplF.fapply(A, B, fgf[0], fga[0]),
                ImplG.fapply(A, B, fgf[1], fga[1]),
            };
        }

        pub fn fapplyLam(
            comptime A: type,
            comptime B: type,
            // applicative function: F (a -> b), fa: F a
            fgf: anytype,
            fga: F(A),
        ) F(B) {
            return .{
                ImplF.fapplyLam(A, B, fgf[0], fga[0]),
                ImplG.fapplyLam(A, B, fgf[1], fga[1]),
            };
        }
    };
}

/// Get a Product Functor from two Functor, the parameter FunctorF and FunctorG
/// are Functor type.
pub fn ProductFunctor(comptime FunctorF: type, comptime FunctorG: type) type {
    const ImplFG = ProductFunctorImpl(FunctorF.InstanceImpl, FunctorG.InstanceImpl);
    return Functor(ImplFG);
}

/// Get a Product Applicative from two Applicative, the parameter
/// ApplicativeF and ApplicativeG are Applicative Functor type.
pub fn ProductApplicative(comptime ApplicativeF: type, comptime ApplicativeG: type) type {
    const ImplFG = ProductApplicativeImpl(ApplicativeF.InstanceImpl, ApplicativeG.InstanceImpl);
    return Applicative(ImplFG);
}

/// Get a Coproduct Type constructor from two Type constructor, the parameter
/// F and G are one parameter Type consturctor.
pub fn coproductFG(comptime F: TCtor, comptime G: TCtor) TCtor {
    return struct {
        fn Coproducted(comptime A: type) type {
            return union(enum) {
                inl: F(A),
                inr: G(A),
            };
        }
    }.Coproducted;
}

/// Get tuple of left and right type of coproduct
pub fn getCoproductTypeTuple(comptime U: type) struct { type, type } {
    const info = @typeInfo(U);
    comptime assert(info == .Union);
    comptime assert(info.Union.fields.len == 2);

    const l_type = info.Union.fields[0].type;
    const r_type = info.Union.fields[1].type;
    return .{ l_type, r_type };
}

pub fn CoproductFunctorImpl(comptime ImplF: type, comptime ImplG: type) type {
    return struct {
        /// Constructor Type for Functor, Applicative, Monad, ...
        const F = coproductFG(ImplF.F, ImplG.F);

        /// Get base type of F(A), it is must just is A.
        /// In this instance, type F(A) is product (F(A), G(A)) by ImplF and
        /// ImplG.
        pub fn BaseType(comptime FGA: type) type {
            const l_type, const r_type = getCoproductTypeTuple(FGA);
            comptime assert(ImplF.BaseType(l_type) == ImplG.BaseType(r_type));
            return ImplF.BaseType(l_type);
        }

        pub const FxTypes = FunctorFxTypes(F);
        pub const FaType = FxTypes.FaType;
        pub const FbType = FxTypes.FbType;
        pub const FaLamType = FxTypes.FaLamType;
        pub const FbLamType = FxTypes.FbLamType;

        pub fn deinitFa(
            fga: anytype, // (F(A), G(A))
            comptime free_fn: fn (BaseType(@TypeOf(fga))) void,
        ) void {
            ImplF.deinitFa(fga[0], free_fn);
            ImplG.deinitFa(fga[1], free_fn);
        }

        pub fn fmap(
            comptime K: MapFnKind,
            map_fn: anytype,
            fga: FaType(K, @TypeOf(map_fn)),
        ) FbType(@TypeOf(map_fn)) {
            return switch (fga) {
                .inl => |fa| .{ .inl = ImplF.fmap(K, map_fn, fa) },
                .inr => |ga| .{ .inr = ImplG.fmap(K, map_fn, ga) },
            };
        }

        pub fn fmapLam(
            comptime K: MapFnKind,
            map_lam: anytype,
            fga: FaLamType(K, @TypeOf(map_lam)),
        ) FbLamType(@TypeOf(map_lam)) {
            return switch (fga) {
                .inl => |fa| .{ .inl = ImplF.fmapLam(K, map_lam, fa) },
                .inr => |ga| .{ .inr = ImplG.fmapLam(K, map_lam, ga) },
            };
        }
    };
}

pub fn CoproductApplicativeImpl(
    comptime ImplF: type,
    comptime ImplG: type,
    comptime ImplNat: type,
) type {
    return struct {
        const SupImpl = CoproductFunctorImpl(ImplF, ImplG);

        /// Constructor Type for Functor, Applicative, Monad, ...
        const F = SupImpl.F;

        /// Get base type of F(A), it is must just is A.
        /// In this instance, type F(A) is product (F(A), G(A)) by ImplF and
        /// ImplG.
        const BaseType = SupImpl.BaseType;

        pub const FaType = SupImpl.FaType;
        pub const FbType = SupImpl.FbType;
        pub const FaLamType = SupImpl.FaLamType;
        pub const FbLamType = SupImpl.FbLamType;

        pub const deinitFa = SupImpl.deinitFa;
        pub const fmap = SupImpl.fmap;
        pub const fmapLam = SupImpl.fmapLam;

        pub fn pure(a: anytype) F(@TypeOf(a)) {
            return .{ .inr = ImplG.pure(a) };
        }

        pub fn fapply(
            comptime A: type,
            comptime B: type,
            // applicative function: F (a -> b), fa: F a
            fgf: F(*const fn (A) B),
            fga: F(A),
        ) F(B) {
            const FnType = BaseType(@TypeOf(fgf));
            return switch (fgf) {
                .inl => |ff| switch (fga) {
                    .inl => |fa| .{ .inl = ImplF.fapply(A, B, ff, fa) },
                    .inr => |ga| {
                        const fa = ImplNat.trans(A, ga);
                        return .{ .inl = ImplF.fapply(A, B, ff, fa) };
                    },
                },
                .inr => |gf| switch (fga) {
                    .inl => |fa| {
                        const ff = ImplNat.trans(FnType, gf);
                        return .{ .inl = ImplF.fapply(A, B, ff, fa) };
                    },
                    .inr => |ga| .{ .inr = ImplG.fapply(A, B, gf, ga) },
                },
            };
        }

        pub fn fapplyLam(
            comptime A: type,
            comptime B: type,
            // applicative function: F (a -> b), fa: F a
            fgf: anytype,
            fga: F(A),
        ) F(B) {
            const LamType = BaseType(@TypeOf(fgf));
            return switch (fgf) {
                .inl => |ff| switch (fga) {
                    .inl => |fa| .{ .inl = ImplF.fapplyLam(A, B, ff, fa) },
                    .inr => |ga| {
                        const fa = ImplNat.trans(A, ga);
                        return .{ .inl = ImplF.fapplyLam(A, B, ff, fa) };
                    },
                },
                .inr => |gf| switch (fga) {
                    .inl => |fa| {
                        const ff = ImplNat.trans(LamType, gf);
                        return .{ .inl = ImplF.fapplyLam(A, B, ff, fa) };
                    },
                    .inr => |ga| .{ .inr = ImplG.fapplyLam(A, B, gf, ga) },
                },
            };
        }
    };
}

/// Get a Coproduct Functor from two Functor, the parameter FunctorF and FunctorG
/// are Functor type.
pub fn CoproductFunctor(comptime FunctorF: type, comptime FunctorG: type) type {
    const ImplFG = CoproductFunctorImpl(FunctorF.InstanceImpl, FunctorG.InstanceImpl);
    return Functor(ImplFG);
}

/// Get a Coproduct Applicative from two Applicative, the parameter
/// ApplicativeF and ApplicativeG are Applicative Functor type.
pub fn CoproductApplicative(
    comptime ApplicativeF: type,
    comptime ApplicativeG: type,
    comptime NaturalGF: type,
) type {
    const ImplFG = CoproductApplicativeImpl(
        ApplicativeF.InstanceImpl,
        ApplicativeG.InstanceImpl,
        NaturalGF.InstanceImpl,
    );
    return Applicative(ImplFG);
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

fn Maybe(comptime A: type) type {
    return ?A;
}

const MaybeMonadImpl = struct {
    none: void,

    const Self = @This();

    /// Constructor Type for Functor, Applicative, Monad, ...
    const F = Maybe;

    /// Get base type of F(A), it is must just is A.
    pub fn BaseType(comptime MaybeA: type) type {
        return std.meta.Child(MaybeA);
    }

    pub const FxTypes = FunctorFxTypes(F);
    pub const FaType = FxTypes.FaType;
    pub const FbType = FxTypes.FbType;
    pub const FaLamType = FxTypes.FaLamType;
    pub const FbLamType = FxTypes.FbLamType;

    pub fn deinitFa(
        fa: anytype, // Maybe(A)
        comptime free_fn: fn (BaseType(@TypeOf(fa))) void,
    ) void {
        if (fa) |a| {
            free_fn(a);
        }
    }

    pub fn fmap(
        comptime K: MapFnKind,
        map_fn: anytype,
        fa: FaType(K, @TypeOf(map_fn)),
    ) FbType(@TypeOf(map_fn)) {
        if (comptime isMapRef(K)) {
            if (fa.* != null) {
                return map_fn(&(fa.*.?));
            }
        } else {
            if (fa) |a| {
                return map_fn(a);
            }
        }

        return null;
    }

    pub fn fmapLam(
        comptime K: MapFnKind,
        map_lam: anytype,
        fa: FaLamType(K, @TypeOf(map_lam)),
    ) FbLamType(@TypeOf(map_lam)) {
        if (comptime isMapRef(K)) {
            if (fa.* != null) {
                return map_lam.call(@constCast(&(fa.*.?)));
            }
        } else {
            if (fa) |a| {
                return map_lam.call(a);
            }
        }

        return null;
    }

    pub fn pure(a: anytype) F(@TypeOf(a)) {
        return a;
    }

    pub fn fapply(
        comptime A: type,
        comptime B: type,
        // applicative function: F (a -> b), fa: F a
        ff: F(*const fn (A) B),
        fa: F(A),
    ) F(B) {
        if (ff) |f| {
            if (fa) |a| {
                return f(a);
            }
        }
        return null;
    }

    pub fn fapplyLam(
        comptime A: type,
        comptime B: type,
        // applicative function: F (a -> b), fa: F a
        flam: anytype, // a F(lambda) that present F(*const fn (A) B),
        fa: F(A),
    ) F(B) {
        if (flam) |lam| {
            if (fa) |a| {
                return lam.call(a);
            }
        }
        return null;
    }

    pub fn bind(
        comptime A: type,
        comptime B: type,
        // monad function: (a -> M b), ma: M a
        ma: F(A),
        f: *const fn (A) F(B),
    ) F(B) {
        if (ma) |a| {
            return f(a);
        }
        return null;
    }
};

fn maybeSample() void {
    const MaybeMonad = Monad(MaybeMonadImpl);

    var maybe_a: ?u32 = 42;
    maybe_a = MaybeMonad.fmap(.InplaceMap, struct {
        fn f(a: u32) u32 {
            return a + 10;
        }
    }.f, maybe_a);

    const maybe_b = MaybeMonad.fmap(.NewValMap, struct {
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
    var maybe_applied = MaybeMonad.fapply(f64, u32, maybe_fn, maybe_b);
    std.debug.print("maybe_applied: {any}\n", .{maybe_applied});
    maybe_applied = MaybeMonad.fapply(u32, u32, null, maybe_applied);
    std.debug.print("applied with null function: {any}\n", .{maybe_applied});

    const maybe_binded = MaybeMonad.bind(f64, u32, maybe_b, struct {
        fn f(x: f64) ?u32 {
            return @intFromFloat(@ceil(x * 4.0));
        }
    }.f);
    std.debug.print("maybe_binded: {any}\n", .{maybe_binded});
}

fn Array(comptime len: usize) TCtor {
    return struct {
        fn ArrayType(comptime A: type) type {
            return [len]A;
        }
    }.ArrayType;
}

pub fn ArrayMonadImpl(comptime len: usize) type {
    return struct {
        const Self = @This();

        /// Constructor Type for Functor, Applicative, Monad, ...
        const F = Array(len);

        /// Get base type of F(A), it is must just is A.
        pub fn BaseType(comptime ArrayA: type) type {
            return std.meta.Child(ArrayA);
        }

        pub const FxTypes = FunctorFxTypes(F);
        pub const FaType = FxTypes.FaType;
        pub const FbType = FxTypes.FbType;
        pub const FaLamType = FxTypes.FaLamType;
        pub const FbLamType = FxTypes.FbLamType;

        fn FaFnOrLamType(
            comptime K: MapFnKind,
            comptime M: FMapMode,
            comptime FnOrLam: type,
        ) type {
            if (M == .NormalMap) {
                return FaType(K, FnOrLam);
            } else {
                return FaLamType(K, FnOrLam);
            }
        }

        fn FbFnOrLamType(comptime M: FMapMode, comptime FnOrLam: type) type {
            if (M == .NormalMap) {
                return FbType(FnOrLam);
            } else {
                return FbLamType(FnOrLam);
            }
        }

        pub fn deinitFa(
            fa: anytype, // Array(len)(A)
            comptime free_fn: fn (BaseType(@TypeOf(fa))) void,
        ) void {
            for (fa) |item| {
                free_fn(item);
            }
        }

        /// If the returned array list of inplace map function assign to a new
        /// variable, then the array list in original variable should be reset
        /// to empty.
        pub fn fmap(
            comptime K: MapFnKind,
            map_fn: anytype,
            fa: FaType(K, @TypeOf(map_fn)),
        ) FbType(@TypeOf(map_fn)) {
            return fmapGeneric(K, .NormalMap, map_fn, fa);
        }

        pub fn fmapLam(
            comptime K: MapFnKind,
            map_lam: anytype,
            fa: FaLamType(K, @TypeOf(map_lam)),
        ) FbLamType(@TypeOf(map_lam)) {
            return fmapGeneric(K, .LambdaMap, map_lam, fa);
        }

        pub fn fmapGeneric(
            comptime K: MapFnKind,
            comptime M: FMapMode,
            fn_or_lam: anytype,
            fa: FaFnOrLamType(K, M, @TypeOf(fn_or_lam)),
        ) FbFnOrLamType(M, @TypeOf(fn_or_lam)) {
            comptime assert(fa.len == len);

            if (comptime isInplaceMap(K)) {
                const fb = mapInplace(K, M, fn_or_lam, fa);
                return fb;
            } else {
                const fb = mapNewValue(K, M, fn_or_lam, fa);
                return fb;
            }
        }

        fn mapInplace(
            comptime K: MapFnKind,
            comptime M: FMapMode,
            fn_or_lam: anytype,
            fa: FaFnOrLamType(K, M, @TypeOf(fn_or_lam)),
        ) FbFnOrLamType(M, @TypeOf(fn_or_lam)) {
            const A = if (M == .NormalMap)
                MapFnInType(@TypeOf(fn_or_lam))
            else
                MapLamInType(@TypeOf(fn_or_lam));

            const B = if (M == .NormalMap)
                MapFnRetType(@TypeOf(fn_or_lam))
            else
                MapLamRetType(@TypeOf(fn_or_lam));

            const ValA = if (comptime isMapRef(K)) std.meta.Child(A) else A;
            if (@bitSizeOf(ValA) != @bitSizeOf(B)) {
                @compileError("The bitsize of translated value is not equal origin value, failed to map it");
            }

            // const arr = if (comptime isMapRef(K)) fa.* else fa;
            var slice = @constCast(fa[0..len]);
            var i: usize = 0;
            while (i < slice.len) : (i += 1) {
                const a = if (comptime isMapRef(K)) &slice[i] else slice[i];
                if (M == .NormalMap) {
                    slice[i] = castInplaceValue(A, fn_or_lam(a));
                } else {
                    slice[i] = castInplaceValue(A, fn_or_lam.call(a));
                }
            }
            return @bitCast(slice.*);
        }

        fn mapNewValue(
            comptime K: MapFnKind,
            comptime M: FMapMode,
            fn_or_lam: anytype,
            fa: FaFnOrLamType(K, M, @TypeOf(fn_or_lam)),
        ) FbFnOrLamType(M, @TypeOf(fn_or_lam)) {
            const B = if (M == .NormalMap)
                MapFnRetType(@TypeOf(fn_or_lam))
            else
                MapLamRetType(@TypeOf(fn_or_lam));
            var fb: [len]B = undefined;

            var slice = fa[0..len];
            var i: usize = 0;
            while (i < len) : (i += 1) {
                const a = if (comptime isMapRef(K)) &slice[i] else slice[i];
                fb[i] = if (M == .NormalMap) fn_or_lam(a) else fn_or_lam.call(a);
            }
            return fb;
        }

        pub fn pure(a: anytype) F(@TypeOf(a)) {
            return [1]@TypeOf(a){a} ** len;
        }

        pub fn fapply(
            comptime A: type,
            comptime B: type,
            // applicative function: F (a -> b), fa: F a
            ff: F(*const fn (A) B),
            fa: F(A),
        ) F(B) {
            return fapplyGeneric(.NormalMap, A, B, ff, fa);
        }

        pub fn fapplyLam(
            comptime A: type,
            comptime B: type,
            // applicative function: F (a -> b), fa: F a
            flam: anytype, // a F(lambda) that present F(*const fn (A) B),
            fa: F(A),
        ) F(B) {
            return fapplyGeneric(.LambdaMap, A, B, flam, fa);
        }

        fn fapplyGeneric(
            comptime M: FMapMode,
            comptime A: type,
            comptime B: type,
            // applicative function: F (a -> b), fa: F a
            ff: anytype,
            fa: F(A),
        ) F(B) {
            var fb: [len]B = undefined;

            var i: usize = 0;
            while (i < len) : (i += 1) {
                if (M == .NormalMap) {
                    fb[i] = ff[i](fa[i]);
                } else {
                    fb[i] = ff[i].call(fa[i]);
                }
            }
            return fb;
        }

        fn imap(
            comptime A: type,
            comptime B: type,
            map_lam: anytype,
            fa: F(A),
        ) F(B) {
            var fb: [len]B = undefined;
            var i: usize = 0;
            while (i < len) : (i += 1) {
                fb[i] = map_lam.call(i, fa[i]);
            }

            return fb;
        }

        pub fn bind(
            comptime A: type,
            comptime B: type,
            // monad function: (a -> M b), ma: M a
            ma: F(A),
            f: *const fn (A) F(B),
        ) F(B) {
            const imap_lam = struct {
                bind_fn: *const fn (A) F(B),
                fn call(map_self: @This(), i: usize, a: A) B {
                    return map_self.bind_fn(a)[i];
                }
            }{ .bind_fn = f };

            return imap(A, B, imap_lam, ma);
        }
    };
}

fn getDefaultFn(comptime Fn: type) fn (MapFnInType(Fn)) MapFnRetType(Fn) {
    return struct {
        const A = MapFnInType(Fn);
        const B = MapFnRetType(Fn);
        fn defaultFn(a: A) B {
            _ = a;
            return std.mem.zeroes(B);
        }
    }.defaultFn;
}

pub fn MaybeToArrayNatImpl(comptime len: usize) type {
    return struct {
        const F = Maybe;
        const G = Array(len);

        pub fn trans(comptime A: type, fa: F(A)) G(A) {
            if (fa) |a| {
                return [1]A{a} ** len;
            } else {
                const info_a = @typeInfo(A);
                if (info_a == .Fn) {
                    return [1]A{getDefaultFn(A)} ** len;
                } else if (info_a == .Pointer and @typeInfo(std.meta.Child(A)) == .Fn) {
                    return [1]A{getDefaultFn(std.meta.Child(A))} ** len;
                }
                return std.mem.zeroes([len]A);
            }
        }
    };
}

pub fn ArrayToMaybeNatImpl(comptime len: usize) type {
    return struct {
        const F = Array(len);
        const G = Maybe;

        pub fn trans(comptime A: type, fa: F(A)) G(A) {
            return fa[0];
        }
    };
}

fn arraySample() void {
    const ARRAY_LEN = 4;
    const ArrayF = Array(ARRAY_LEN);
    const ArrayMonad = Monad(ArrayMonadImpl(ARRAY_LEN));

    var arr: ArrayF(u32) = undefined;
    var i: u32 = 0;
    while (i < arr.len) : (i += 1) {
        arr[i] = i;
    }

    // example of functor
    arr = ArrayMonad.fmap(.InplaceMap, struct {
        fn f(a: u32) u32 {
            return a + 42;
        }
    }.f, arr);
    std.debug.print("arr inplace mapped: {any}\n", .{arr});

    const arr_f32 = ArrayMonad.fmap(.InplaceMap, struct {
        fn f(a: u32) f32 {
            return @as(f32, @floatFromInt(a)) + 6.18;
        }
    }.f, arr);
    std.debug.print("arr float32 inplace mapped: {any}\n", .{arr_f32});

    arr = ArrayMonad.fmap(.InplaceMap, struct {
        fn f(a: f32) u32 {
            return @as(u32, @intFromFloat(a)) + 58;
        }
    }.f, arr_f32);
    std.debug.print("arr inplace mapped again: {any}\n", .{arr});

    const arr_new = ArrayMonad.fmap(.NewValMap, struct {
        fn f(a: u32) f64 {
            return @as(f64, @floatFromInt(a)) * 3.14;
        }
    }.f, arr);
    std.debug.print("arr_new: {any}\n", .{arr_new});

    // example of applicative functor
    const FloatToIntFn = *const fn (f64) u32;
    const arr_fns = [_]FloatToIntFn{
        struct {
            fn f(x: f64) u32 {
                return @intFromFloat(@floor(x));
            }
        }.f,
        struct {
            fn f(x: f64) u32 {
                return @intFromFloat(@ceil(x + 8.0));
            }
        }.f,
        struct {
            fn f(x: f64) u32 {
                return @intFromFloat(@ceil(x * 2.0));
            }
        }.f,
        struct {
            fn f(x: f64) u32 {
                return @intFromFloat(@ceil(x * 4.0));
            }
        }.f,
    };

    const arr_applied = ArrayMonad.fapply(f64, u32, arr_fns, arr_new);
    std.debug.print("arr_applied: {any}\n", .{arr_applied});

    const arr_comptime = [_]f64{ 2, 4, 5, 9 };
    const comptime_applied = comptime ArrayMonad.fapply(f64, u32, arr_fns, arr_comptime);
    std.debug.print("comptime_applied: {any}\n", .{comptime_applied});

    // example of monad
    const arr_binded = ArrayMonad.bind(f64, u32, arr_new, struct {
        fn f(a: f64) ArrayF(u32) {
            var arr_b: ArrayF(u32) = undefined;
            var j: usize = 0;
            while (j < arr_b.len) : (j += 1) {
                if ((j & 0x1) == 0) {
                    arr_b[j] = @intFromFloat(@ceil(a * 4.0));
                } else {
                    arr_b[j] = @intFromFloat(@ceil(a * 9.0));
                }
            }
            return arr_b;
        }
    }.f);
    std.debug.print("arr_binded: {any}\n", .{arr_binded});

    const comptime_binded = comptime ArrayMonad.bind(f64, u32, arr_comptime, struct {
        fn f(a: f64) ArrayF(u32) {
            var arr_b: ArrayF(u32) = undefined;
            var j: usize = 0;
            while (j < arr_b.len) : (j += 1) {
                if ((j & 0x1) == 0) {
                    arr_b[j] = @intFromFloat(@ceil(a * 4.0));
                } else {
                    arr_b[j] = @intFromFloat(@ceil(a * 9.0));
                }
            }
            return arr_b;
        }
    }.f);
    std.debug.print("comptime_binded: {any}\n", .{comptime_binded});
}

fn composeSample() void {
    const ARRAY_LEN = 4;
    const ArrayF = Array(ARRAY_LEN);
    const ArrayApplicative = Applicative(ArrayMonadImpl(ARRAY_LEN));
    const MaybeApplicative = Applicative(MaybeMonadImpl);

    const ArrayMaybeApplicative = ComposeApplicative(ArrayApplicative, MaybeApplicative);

    var arr: ArrayF(Maybe(u32)) = undefined;
    var i: u32 = 0;
    while (i < arr.len) : (i += 1) {
        if ((i & 0x1) == 0) {
            arr[i] = i;
        } else {
            arr[i] = null;
        }
    }

    // example of applicative functor
    arr = ArrayMaybeApplicative.fmap(.InplaceMap, struct {
        fn f(a: u32) u32 {
            return a + 42;
        }
    }.f, arr);
    std.debug.print("arr mapped: {any}\n", .{arr});

    const arr_new = ArrayMaybeApplicative.fmap(.NewValMap, struct {
        fn f(a: u32) f64 {
            return @as(f64, @floatFromInt(a)) * 3.14;
        }
    }.f, arr);
    std.debug.print("arr_new: {any}\n", .{arr_new});

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

    var arr_fns: ArrayF(Maybe(FloatToIntFn)) = undefined;
    i = 0;
    for (fn_array) |f| {
        arr_fns[i] = f;
        i += 1;
    }
    while (i < arr_fns.len) : (i += 1) {
        arr_fns[i] = null;
    }

    const arr_applied = ArrayMaybeApplicative.fapply(f64, u32, arr_fns, arr_new);
    std.debug.print("arr_applied: {any}\n", .{arr_applied});

    // pretty print the arr3 with type ArrayF(Maybe(AraayF(A)))
    const prettyPrintArr3 = struct {
        fn prettyPrint(arr3: anytype) void {
            std.debug.print("{{ \n", .{});
            var j: u32 = 0;
            for (arr3) |item| {
                if (item) |o| {
                    std.debug.print(" {{ ", .{});
                    for (o) |a| {
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
        fns: []IntToIntFn,

        const FnSelf = @This();
        fn call(self: *const FnSelf, a: u32) ArrayF(IntToIntFn) {
            _ = a;
            var arr1_fn: ArrayF(IntToIntFn) = undefined;
            var j: usize = 0;
            while (j < arr1_fn.len) : (j += 1) {
                if (j < self.fns.len) {
                    arr1_fn[j] = self.fns[j];
                } else {
                    arr1_fn[j] = self.fns[self.fns.len - 1];
                }
            }
            return arr1_fn;
        }
    }{ .fns = fn_int_array[0..] };
    const arr3_fns = ArrayMaybeApplicative.fmapLam(.NewValMap, intToFns, arr);

    const intToArr = struct {
        fn intToArr(a: u32) ArrayF(u32) {
            var tmp = a;
            var j: u32 = 0;
            var int_arr: ArrayF(u32) = undefined;
            while (j < int_arr.len) : ({
                j += 1;
                tmp += 2;
            }) {
                int_arr[j] = tmp;
            }
            return int_arr;
        }
    }.intToArr;

    const arr3_ints = ArrayMaybeApplicative.fmap(.NewValMap, intToArr, arr_applied);
    // std.debug.print("arr3_ints: {any}\n", .{arr3_ints});

    const ArrayMaybeArrayApplicative = ComposeApplicative(ArrayMaybeApplicative, ArrayApplicative);

    const arr3_appried = ArrayMaybeArrayApplicative.fapply(u32, u32, arr3_fns, arr3_ints);
    std.debug.print("arr3_appried: ", .{});
    prettyPrintArr3(arr3_appried);
}

fn productSample() void {
    const ARRAY_LEN = 4;
    const ArrayF = Array(ARRAY_LEN);
    const ArrayAndMaybe = productFG(ArrayF, Maybe);
    const ArrayApplicative = Applicative(ArrayMonadImpl(ARRAY_LEN));
    const MaybeApplicative = Applicative(MaybeMonadImpl);

    const ArrayAndMaybeApplicative = ProductApplicative(ArrayApplicative, MaybeApplicative);

    // pretty print the array maybe tuple with type { ArrayF(A), Maybe(A) }
    const prettyArrayAndMaybe = struct {
        fn prettyPrint(arr_and_maybe: anytype) void {
            std.debug.print("{{ {any}, {any} }}\n", .{ arr_and_maybe[0], arr_and_maybe[1] });
        }
    }.prettyPrint;

    var arr: ArrayF(u32) = undefined;
    var i: u32 = 0;
    while (i < arr.len) : (i += 1) {
        arr[i] = i;
    }
    var arr_and_maybe = ArrayAndMaybe(u32){ arr, 42 };

    // example of applicative functor
    arr_and_maybe = ArrayAndMaybeApplicative.fmap(.InplaceMap, struct {
        fn f(a: u32) u32 {
            return a + 42;
        }
    }.f, arr_and_maybe);
    std.debug.print("arr_and_maybe mapped: ", .{});
    prettyArrayAndMaybe(arr_and_maybe);

    const arr_and_maybe_new = ArrayAndMaybeApplicative.fmap(.NewValMap, struct {
        fn f(a: u32) f64 {
            return @as(f64, @floatFromInt(a)) * 3.14;
        }
    }.f, arr_and_maybe);
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

    var arr_fns: ArrayF(FloatToIntFn) = undefined;
    i = 0;
    while (i < arr_fns.len) : (i += 1) {
        if (i < fn_array.len) {
            arr_fns[i] = fn_array[i];
        } else {
            arr_fns[i] = fn_array[fn_array.len - 1];
        }
    }
    const arr_and_maybe_fns = ArrayAndMaybe(FloatToIntFn){ arr_fns, fn_array[0] };

    const arr_and_maybe_applied = ArrayAndMaybeApplicative.fapply(f64, u32, arr_and_maybe_fns, arr_and_maybe_new);
    std.debug.print("arr_and_maybe_applied: ", .{});
    prettyArrayAndMaybe(arr_and_maybe_applied);
}

fn coproductSample() void {
    const ARRAY_LEN = 4;
    const ArrayF = Array(ARRAY_LEN);
    const ArrayOrMaybe = coproductFG(ArrayF, Maybe);
    const ArrayApplicative = Applicative(ArrayMonadImpl(ARRAY_LEN));
    const MaybeApplicative = Applicative(MaybeMonadImpl);
    const NatMaybeToArray = NatTrans(MaybeToArrayNatImpl(ARRAY_LEN));

    const ArrayOrMaybeApplicative = CoproductApplicative(ArrayApplicative, MaybeApplicative, NatMaybeToArray);

    // pretty print the arr_or_maybe with type Coproduct(ArrayF, Maybe)
    const prettyArrayOrMaybe = struct {
        fn prettyPrint(arr_or_maybe: anytype) void {
            if (arr_or_maybe == .inl) {
                std.debug.print("{{ inl: {any} }}\n", .{arr_or_maybe.inl});
            } else {
                std.debug.print("{{ inr: {any} }}\n", .{arr_or_maybe.inr});
            }
        }
    }.prettyPrint;

    var arr: ArrayF(u32) = undefined;
    var i: u32 = 0;
    while (i < arr.len) : (i += 1) {
        arr[i] = i;
    }
    var arr_or_maybe = ArrayOrMaybe(u32){ .inl = arr };

    // example of applicative functor
    arr_or_maybe = ArrayOrMaybeApplicative.fmap(.InplaceMap, struct {
        fn f(a: u32) u32 {
            return a + 42;
        }
    }.f, arr_or_maybe);
    std.debug.print("arr_or_maybe mapped: ", .{});
    prettyArrayOrMaybe(arr_or_maybe);

    const arr_or_maybe_new = ArrayOrMaybeApplicative.fmap(.NewValMap, struct {
        fn f(a: u32) f64 {
            return @as(f64, @floatFromInt(a)) * 3.14;
        }
    }.f, arr_or_maybe);
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

    var arr_fns: ArrayF(FloatToIntFn) = undefined;
    i = 0;
    while (i < arr_fns.len) : (i += 1) {
        if (i < fn_array.len) {
            arr_fns[i] = fn_array[i];
        } else {
            arr_fns[i] = fn_array[fn_array.len - 1];
        }
    }
    const or_array_fns = ArrayOrMaybe(FloatToIntFn){ .inl = arr_fns };
    const or_maybe_fns = ArrayOrMaybe(FloatToIntFn){ .inr = fn_array[1] };

    const maybe_array_applied = ArrayOrMaybeApplicative.fapply(f64, u32, or_maybe_fns, arr_or_maybe_new);
    std.debug.print("maybe_array_applied: ", .{});
    prettyArrayOrMaybe(maybe_array_applied);

    const array_array_applied = ArrayOrMaybeApplicative.fapply(f64, u32, or_array_fns, arr_or_maybe_new);
    std.debug.print("array_array_applied: ", .{});
    prettyArrayOrMaybe(array_array_applied);

    const or_maybe_float = ArrayOrMaybe(f64){ .inr = 2.71828 };
    const array_maybe_applied = ArrayOrMaybeApplicative.fapply(f64, u32, or_array_fns, or_maybe_float);
    std.debug.print("array_maybe_applied: ", .{});
    prettyArrayOrMaybe(array_maybe_applied);

    const maybe_maybe_applied = ArrayOrMaybeApplicative.fapply(f64, u32, or_maybe_fns, or_maybe_float);
    std.debug.print("maybe_maybe_applied: ", .{});
    prettyArrayOrMaybe(maybe_maybe_applied);
}

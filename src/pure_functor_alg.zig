//! Implement Functor/Applicative/Monad for pure functional.
//!
//! There is no error returned from fmap/fmapLam/fapply/fapplyLam/bind
//! function, the map_fn/apply_fn/bind_fn function also don't return error.

const std = @import("std");

const assert = std.debug.assert;

pub fn pureAlgSample() !void {
    try maybeSample();
    try arraySample();
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

pub fn FunctorFxTypes(comptime F: fn (comptime T: type) type) type {
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
            return F(MapFnRetType(MapFn));
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
            return F(MapLamRetType(MapLam));
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

    if (!@hasDecl(FunctorInst, "deinitFa")) {
        @compileError("The Functor instance must has deinitFa function!");
    }

    return struct {
        const Self = @This();
        const InstanceType = FunctorInst;

        pub const FxTypes = FunctorFxTypes(F);
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

/// Natural Translation typeclass like in Haskell.
/// F and G is Constructor Type of Functor typeclass, such as Maybe, List.
pub fn NatTrans(
    comptime NatTransInst: type,
    comptime F: fn (comptime T: type) type,
    comptime G: fn (comptime T: type) type,
) type {
    if (!(@hasDecl(NatTransInst, "F") and @hasDecl(NatTransInst, "G"))) {
        @compileError("The Functor instance must has F and G type!");
    }

    return struct {
        const Self = @This();
        const InstanceType = NatTransInst;

        const FTransType = @TypeOf(struct {
            fn transFn(instance: *InstanceType, comptime A: type, fa: F(A)) G(A) {
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

/// Applicative Functor typeclass like in Haskell, it inherit from Functor.
/// F is instance of Applicative Functor typeclass, such as Maybe, List
pub fn Applicative(comptime ApplicativeInst: type, comptime F: fn (comptime T: type) type) type {
    return struct {
        const Self = @This();
        const FunctorSup = Functor(ApplicativeInst, F);
        const InstanceType = ApplicativeInst;

        const PureType = @TypeOf(struct {
            fn pureFn(instance: *InstanceType, a: anytype) F(@TypeOf(a)) {
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
            ) F(B) {
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
            ) F(B) {
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

/// Monad Functor typeclass like in Haskell, it inherit from Applicative Functor.
/// M is instance of Monad typeclass, such as Maybe, List
pub fn Monad(comptime MonadInst: type, comptime M: fn (comptime T: type) type) type {
    return struct {
        const Self = @This();
        const ApplicativeSup = Applicative(MonadInst, M);
        const InstanceType = MonadInst;

        const BindType = @TypeOf(struct {
            fn bindFn(
                instance: *InstanceType,
                comptime A: type,
                comptime B: type,
                // monad function: (a -> M b), ma: M a
                ma: M(A),
                f: *const fn (*InstanceType, A) M(B),
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
                pub fn call(mapSelf: *const MapSelf, a: MapFnInType(K, MapFn)) MapFnRetType(MapFn) {
                    return mapSelf.map_fn(a);
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

        pub fn pure(self: *Self, a: anytype) F(@TypeOf(a)) {
            return self.instanceF.pure(self.instanceG.pure(a));
        }

        pub fn fapply(
            self: *Self,
            comptime A: type,
            comptime B: type,
            // applicative function: F (a -> b), fa: F a
            fgf: F(*const fn (A) B),
            fga: F(A),
        ) F(B) {
            return fapplyGeneric(self, .NormalMap, A, B, fgf, fga);
        }

        pub fn fapplyLam(
            self: *Self,
            comptime A: type,
            comptime B: type,
            // applicative function: F (a -> b), fa: F a
            fgf: anytype,
            fga: F(A),
        ) F(B) {
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
        ) F(B) {
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
                    fn call(applySelf: *const ApplySelf, ga: InstanceG.F(A)) InstanceG.F(B) {
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

            const flam = self.instanceF.fmapLam(.NewValMapRef, inner_fapply, @constCast(&fgf));
            defer InstanceF.deinitFa(flam, free_fn);
            return self.instanceF.fapplyLam(
                InstanceG.F(A),
                InstanceG.F(B),
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

        pub const FxTypes = FunctorFxTypes(F);
        pub const FaType = FxTypes.FaType;
        pub const FbType = FxTypes.FbType;
        pub const FaLamType = FxTypes.FaLamType;
        pub const FbLamType = FxTypes.FbLamType;

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
                self.instanceF.fmap(K, map_fn, fga[0]),
                self.instanceG.fmap(K, map_fn, fga[1]),
            };
        }

        pub fn fmapLam(
            self: *Self,
            comptime K: MapFnKind,
            map_lam: anytype,
            fga: FaLamType(K, @TypeOf(map_lam)),
        ) FbLamType(@TypeOf(map_lam)) {
            return .{
                self.instanceF.fmapLam(K, map_lam, fga[0]),
                self.instanceG.fmapLam(K, map_lam, fga[1]),
            };
        }

        pub fn pure(self: *Self, a: anytype) F(@TypeOf(a)) {
            return .{
                self.instanceF.pure(a),
                self.instanceG.pure(a),
            };
        }

        pub fn fapply(
            self: *Self,
            comptime A: type,
            comptime B: type,
            // applicative function: F (a -> b), fa: F a
            fgf: F(*const fn (A) B),
            fga: F(A),
        ) F(B) {
            return .{
                self.instanceF.fapply(A, B, fgf[0], fga[0]),
                self.instanceG.fapply(A, B, fgf[1], fga[1]),
            };
        }

        pub fn fapplyLam(
            self: *Self,
            comptime A: type,
            comptime B: type,
            // applicative function: F (a -> b), fa: F a
            fgf: anytype,
            fga: F(A),
        ) F(B) {
            return .{
                self.instanceF.fapplyLam(A, B, fgf[0], fga[0]),
                self.instanceG.fapplyLam(A, B, fgf[1], fga[1]),
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

        pub const FxTypes = FunctorFxTypes(F);
        pub const FaType = FxTypes.FaType;
        pub const FbType = FxTypes.FbType;
        pub const FaLamType = FxTypes.FaLamType;
        pub const FbLamType = FxTypes.FbLamType;

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
                .inl => |fa| .{ .inl = self.instanceF.fmap(K, map_fn, fa) },
                .inr => |ga| .{ .inr = self.instanceG.fmap(K, map_fn, ga) },
            };
        }

        pub fn fmapLam(
            self: *Self,
            comptime K: MapFnKind,
            map_lam: anytype,
            fga: FaLamType(K, @TypeOf(map_lam)),
        ) FbLamType(@TypeOf(map_lam)) {
            return switch (fga) {
                .inl => |fa| .{ .inl = self.instanceF.fmapLam(K, map_lam, fa) },
                .inr => |ga| .{ .inr = self.instanceG.fmapLam(K, map_lam, ga) },
            };
        }

        pub fn pure(self: *Self, a: anytype) F(@TypeOf(a)) {
            return .{ .inr = self.instanceG.pure(a) };
        }

        pub fn fapply(
            self: *Self,
            comptime A: type,
            comptime B: type,
            // applicative function: F (a -> b), fa: F a
            fgf: F(*const fn (A) B),
            fga: F(A),
        ) F(B) {
            const FnType = BaseType(@TypeOf(fgf));
            return switch (fgf) {
                .inl => |ff| switch (fga) {
                    .inl => |fa| .{ .inl = self.instanceF.fapply(A, B, ff, fa) },
                    .inr => |ga| {
                        const fa = self.natural_gf.trans(A, ga);
                        return .{ .inl = self.instanceF.fapply(A, B, ff, fa) };
                    },
                },
                .inr => |gf| switch (fga) {
                    .inl => |fa| {
                        const ff = self.natural_gf.trans(FnType, gf);
                        return .{ .inl = self.instanceF.fapply(A, B, ff, fa) };
                    },
                    .inr => |ga| .{ .inr = self.instanceG.fapply(A, B, gf, ga) },
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
        ) F(B) {
            const LamType = BaseType(@TypeOf(fgf));
            return switch (fgf) {
                .inl => |ff| switch (fga) {
                    .inl => |fa| .{ .inl = self.instanceF.fapplyLam(A, B, ff, fa) },
                    .inr => |ga| {
                        const fa = self.natural_gf.trans(A, ga);
                        return .{ .inl = self.instanceF.fapplyLam(A, B, ff, fa) };
                    },
                },
                .inr => |gf| switch (fga) {
                    .inl => |fa| {
                        const ff = self.natural_gf.trans(LamType, gf);
                        return .{ .inl = self.instanceF.fapplyLam(A, B, ff, fa) };
                    },
                    .inr => |ga| .{ .inr = self.instanceG.fapplyLam(A, B, gf, ga) },
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

fn Maybe(comptime A: type) type {
    return ?A;
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

    const FaType = Functor(Self, F).FaType;
    const FbType = Functor(Self, F).FbType;
    const FaLamType = Functor(Self, F).FaLamType;
    const FbLamType = Functor(Self, F).FbLamType;

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
        self: *Self,
        comptime K: MapFnKind,
        map_lam: anytype,
        fa: FaLamType(K, @TypeOf(map_lam)),
    ) FbLamType(@TypeOf(map_lam)) {
        _ = self;
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

    pub fn pure(self: *Self, a: anytype) F(@TypeOf(a)) {
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
    ) F(B) {
        _ = self;
        if (ff) |f| {
            if (fa) |a| {
                return f(a);
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
    ) F(B) {
        _ = self;
        if (flam) |lam| {
            if (fa) |a| {
                return lam.call(a);
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
        f: *const fn (*Self, A) F(B),
    ) F(B) {
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
        fn f(self: *MaybeMonadInst, x: f64) ?u32 {
            _ = self;
            return @intFromFloat(@ceil(x * 4.0));
        }
    }.f);
    std.debug.print("maybe_binded: {any}\n", .{maybe_binded});
}

fn Array(comptime len: usize) fn (comptime T: type) type {
    return struct {
        fn ArrayType(comptime A: type) type {
            return [len]A;
        }
    }.ArrayType;
}

pub fn ArrayMonadInst(comptime len: usize) type {
    return struct {
        none: void,

        const Self = @This();

        /// Constructor Type for Functor, Applicative, Monad, ...
        const F = Array(len);

        /// Get base type of F(A), it is must just is A.
        pub fn BaseType(comptime ArrayA: type) type {
            return std.meta.Child(ArrayA);
        }

        const FaType = Functor(Self, F).FaType;
        const FbType = Functor(Self, F).FbType;
        const FaLamType = Functor(Self, F).FaLamType;
        const FbLamType = Functor(Self, F).FbLamType;

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
            self: *Self,
            comptime K: MapFnKind,
            map_fn: anytype,
            fa: FaType(K, @TypeOf(map_fn)),
        ) FbType(@TypeOf(map_fn)) {
            return self.fmapGeneric(K, .NormalMap, map_fn, fa);
        }

        pub fn fmapLam(
            self: *Self,
            comptime K: MapFnKind,
            map_lam: anytype,
            fa: FaLamType(K, @TypeOf(map_lam)),
        ) FbLamType(@TypeOf(map_lam)) {
            return self.fmapGeneric(K, .LambdaMap, map_lam, fa);
        }

        pub fn fmapGeneric(
            self: *Self,
            comptime K: MapFnKind,
            comptime M: FMapMode,
            fn_or_lam: anytype,
            fa: FaFnOrLamType(K, M, @TypeOf(fn_or_lam)),
        ) FbFnOrLamType(M, @TypeOf(fn_or_lam)) {
            _ = self;
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
                MapFnInType(K, @TypeOf(fn_or_lam))
            else
                MapLamInType(K, @TypeOf(fn_or_lam));

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

        pub fn pure(self: *Self, a: anytype) F(@TypeOf(a)) {
            _ = self;
            return [1]@TypeOf(a){a} ** len;
        }

        pub fn fapply(
            self: *Self,
            comptime A: type,
            comptime B: type,
            // applicative function: F (a -> b), fa: F a
            ff: F(*const fn (A) B),
            fa: F(A),
        ) F(B) {
            return fapplyGeneric(self, .NormalMap, A, B, ff, fa);
        }

        pub fn fapplyLam(
            self: *Self,
            comptime A: type,
            comptime B: type,
            // applicative function: F (a -> b), fa: F a
            flam: anytype, // a F(lambda) that present F(*const fn (A) B),
            fa: F(A),
        ) F(B) {
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
        ) F(B) {
            _ = self;
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
            self: *Self,
            comptime A: type,
            comptime B: type,
            // monad function: (a -> M b), ma: M a
            ma: F(A),
            f: *const fn (A) F(B),
        ) F(B) {
            _ = self;
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

/// Get input parameter type of single parameter function
fn P1FnInType(comptime Fn: type) type {
    const len = @typeInfo(Fn).Fn.params.len;

    if (len != 1) {
        @compileError("The single parameter function must has only one parameter!");
    }

    return @typeInfo(Fn).Fn.params[0].type.?;
}

/// Get return type of single parameter function
fn P1FnRetType(comptime Fn: type) type {
    const R = @typeInfo(Fn).Fn.return_type.?;

    if (R == noreturn) {
        @compileError("The return type of single parameter function must not be noreturn!");
    }
    return R;
}

fn getDefaultFn(comptime Fn: type) fn (P1FnInType(Fn)) P1FnRetType(Fn) {
    return struct {
        const A = P1FnInType(Fn);
        const B = P1FnRetType(Fn);
        fn defaultFn(a: A) B {
            _ = a;
            return std.mem.zeroes(B);
        }
    }.defaultFn;
}

pub fn NatMaybeToArrayInst(comptime len: usize) type {
    return struct {
        instanceArray: ArrayMonadInst(len),

        const Self = @This();

        const F = Maybe;
        const G = Array(len);

        pub fn trans(self: Self, comptime A: type, fa: F(A)) G(A) {
            _ = self;
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

pub fn NatArrayToMaybeInst(comptime len: usize) type {
    return struct {
        const Self = @This();

        const F = Array(len);
        const G = Maybe;

        pub fn trans(self: Self, comptime A: type, fa: F(A)) G(A) {
            _ = self;
            return fa[0];
        }
    };
}

fn arraySample() !void {
    const ARRAY_LEN = 4;
    const ArrayF = Array(ARRAY_LEN);
    const ArrayMonad = Monad(ArrayMonadInst(ARRAY_LEN), ArrayF);
    var array_m = ArrayMonad.init(.{ .none = {} });

    var arr: ArrayF(u32) = undefined;
    var i: u32 = 0;
    while (i < arr.len) : (i += 1) {
        arr[i] = i;
    }

    // example of functor
    arr = array_m.fmap(.InplaceMap, struct {
        fn f(a: u32) u32 {
            return a + 42;
        }
    }.f, arr);
    std.debug.print("arr inplace mapped: {any}\n", .{arr});

    const arr_f32 = array_m.fmap(.InplaceMap, struct {
        fn f(a: u32) f32 {
            return @as(f32, @floatFromInt(a)) + 6.18;
        }
    }.f, arr);
    std.debug.print("arr float32 inplace mapped: {any}\n", .{arr_f32});

    arr = array_m.fmap(.InplaceMap, struct {
        fn f(a: f32) u32 {
            return @as(u32, @intFromFloat(a)) + 58;
        }
    }.f, arr_f32);
    std.debug.print("arr inplace mapped again: {any}\n", .{arr});

    const arr_new = array_m.fmap(.NewValMap, struct {
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

    const arr_applied = array_m.fapply(f64, u32, arr_fns, arr_new);
    std.debug.print("arr_applied: {any}\n", .{arr_applied});

    // example of monad
    const arr_binded = array_m.bind(f64, u32, arr_new, struct {
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
}

fn composeSample() !void {
    const ARRAY_LEN = 4;
    const ArrayF = Array(ARRAY_LEN);
    const ArrayApplicative = Applicative(ArrayMonadInst(ARRAY_LEN), ArrayF);
    const MaybeApplicative = Applicative(MaybeMonadInst, Maybe);
    const ArrayMaybeApplicative = ComposeApplicative(ArrayApplicative, MaybeApplicative);

    var array_maybe = ArrayMaybeApplicative.init(.{
        .instanceF = .{ .none = {} },
        .instanceG = .{ .none = {} },
    });

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
    arr = array_maybe.fmap(.InplaceMap, struct {
        fn f(a: u32) u32 {
            return a + 42;
        }
    }.f, arr);
    std.debug.print("arr mapped: {any}\n", .{arr});

    const arr_new = array_maybe.fmap(.NewValMap, struct {
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

    const arr_applied = array_maybe.fapply(f64, u32, arr_fns, arr_new);
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
    const arr3_fns = array_maybe.fmapLam(.NewValMap, intToFns, arr);

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

    const arr3_ints = array_maybe.fmap(.NewValMap, intToArr, arr_applied);
    // std.debug.print("arr3_ints: {any}\n", .{arr3_ints});

    const ArrayMaybeArrayApplicative = ComposeApplicative(ArrayMaybeApplicative, ArrayApplicative);
    var array_maybe_array = ArrayMaybeArrayApplicative.init(.{
        .instanceF = array_maybe,
        .instanceG = ArrayApplicative.init(.{
            .none = {},
        }),
    });

    const arr3_appried = array_maybe_array.fapply(u32, u32, arr3_fns, arr3_ints);
    std.debug.print("arr3_appried: ", .{});
    prettyPrintArr3(arr3_appried);
}

fn productSample() !void {
    const ARRAY_LEN = 4;
    const ArrayF = Array(ARRAY_LEN);
    const ArrayAndMaybe = productFG(ArrayF, Maybe);
    const ArrayApplicative = Applicative(ArrayMonadInst(ARRAY_LEN), ArrayF);
    const MaybeApplicative = Applicative(MaybeMonadInst, Maybe);
    const ArrayAndMaybeApplicative = ProductApplicative(ArrayApplicative, MaybeApplicative);

    var array_and_maybe = ArrayAndMaybeApplicative.init(.{
        .instanceF = .{ .none = {} },
        .instanceG = .{ .none = {} },
    });

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
    arr_and_maybe = array_and_maybe.fmap(.InplaceMap, struct {
        fn f(a: u32) u32 {
            return a + 42;
        }
    }.f, arr_and_maybe);
    std.debug.print("arr_and_maybe mapped: ", .{});
    prettyArrayAndMaybe(arr_and_maybe);

    const arr_and_maybe_new = array_and_maybe.fmap(.NewValMap, struct {
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

    const arr_and_maybe_applied = array_and_maybe.fapply(f64, u32, arr_and_maybe_fns, arr_and_maybe_new);
    std.debug.print("arr_and_maybe_applied: ", .{});
    prettyArrayAndMaybe(arr_and_maybe_applied);
}

fn coproductSample() !void {
    const ARRAY_LEN = 4;
    const ArrayF = Array(ARRAY_LEN);
    const ArrayOrMaybe = coproductFG(ArrayF, Maybe);
    const ArrayApplicative = Applicative(ArrayMonadInst(ARRAY_LEN), ArrayF);
    const MaybeApplicative = Applicative(MaybeMonadInst, Maybe);
    const NatMaybeToArray = NatTrans(NatMaybeToArrayInst(ARRAY_LEN), Maybe, ArrayF);
    const ArrayOrMaybeApplicative = CoproductApplicative(ArrayApplicative, MaybeApplicative, NatMaybeToArray);

    var array_or_maybe = ArrayOrMaybeApplicative.init(.{
        // Array Applicative instance
        .instanceF = .{ .none = {} },
        // Maybe Applicative instance
        .instanceG = .{ .none = {} },
        // NatMaybeToArray Applicative instance
        .natural_gf = .{ .instanceArray = .{ .none = {} } },
    });

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
    arr_or_maybe = array_or_maybe.fmap(.InplaceMap, struct {
        fn f(a: u32) u32 {
            return a + 42;
        }
    }.f, arr_or_maybe);
    std.debug.print("arr_or_maybe mapped: ", .{});
    prettyArrayOrMaybe(arr_or_maybe);

    const arr_or_maybe_new = array_or_maybe.fmap(.NewValMap, struct {
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

    const maybe_array_applied = array_or_maybe.fapply(f64, u32, or_maybe_fns, arr_or_maybe_new);
    std.debug.print("maybe_array_applied: ", .{});
    prettyArrayOrMaybe(maybe_array_applied);

    const array_array_applied = array_or_maybe.fapply(f64, u32, or_array_fns, arr_or_maybe_new);
    std.debug.print("array_array_applied: ", .{});
    prettyArrayOrMaybe(array_array_applied);

    const or_maybe_float = ArrayOrMaybe(f64){ .inr = 2.71828 };
    const array_maybe_applied = array_or_maybe.fapply(f64, u32, or_array_fns, or_maybe_float);
    std.debug.print("array_maybe_applied: ", .{});
    prettyArrayOrMaybe(array_maybe_applied);

    const maybe_maybe_applied = array_or_maybe.fapply(f64, u32, or_maybe_fns, or_maybe_float);
    std.debug.print("maybe_maybe_applied: ", .{});
    prettyArrayOrMaybe(maybe_maybe_applied);
}

const std = @import("std");

/// Default typeclass like in Haskell, T is instance of Default typeclass.
pub fn Default(comptime DefaultInst: type, comptime T: type) type {
    return struct {
        const Self = @This();

        const DefaultType = @TypeOf(struct {
            fn default(instance: DefaultInst) T {
                _ = instance;
            }
        }.default);

        pub fn init(instance: DefaultInst) DefaultInst {
            if (@TypeOf(DefaultInst.default) != DefaultType) {
                @compileError("Incorrect type of default for Default instance " ++ @typeName(DefaultInst));
            }
            return instance;
        }
    };
}

/// Get the instance of base type, the instance only has none field that type
/// is void.
pub fn BaseNoneDefaultInst(comptime T: type) type {
    switch (@typeInfo(T)) {
        .Type, .Void, .Bool, .Int, .Float, .Optional => return struct {
            none: void,

            const Self = @This();

            pub fn default(self: Self) T {
                _ = self;
                return defaultValueOfType(T);
            }
        },
        else => @compileError("Expected Type, void, bool, integer, float or optional type, found '" ++ @typeName(T) ++ "'"),
    }
}

pub fn ArrayDefaultInst(comptime T: type) type {
    switch (@typeInfo(T)) {
        .Array => return struct {
            none: void,

            const Self = @This();

            pub fn default(self: Self) T {
                _ = self;
                return defaultArrayValue(T);
            }
        },
        else => @compileError("Expected array type, found '" ++ @typeName(T) ++ "'"),
    }
}

pub fn VectorDefaultInst(comptime T: type) type {
    switch (@typeInfo(T)) {
        .Vector => return struct {
            none: void,

            const Self = @This();

            pub fn default(self: Self) T {
                _ = self;
                return defaultVectorValue(T);
            }
        },
        else => @compileError("Expected vector type, found '" ++ @typeName(T) ++ "'"),
    }
}

// The instance has none field that type is void
pub fn DeriveNoneDefaultInst(comptime T: type) type {
    switch (@typeInfo(T)) {
        .Struct => return struct {
            none: void,

            const Self = @This();

            pub fn default(self: Self) T {
                _ = self;
                return defaultStructValue(T);
            }
        },
        .Union => return struct {
            none: void,

            const Self = @This();

            pub fn default(self: Self) T {
                _ = self;
                return defaultUnionValue(T);
            }
        },
        .Enum => return struct {
            none: void,

            const Self = @This();

            pub fn default(self: Self) T {
                _ = self;
                return defaultEnumValue(T);
            }
        },
        else => @compileError("Expected struct or enum type, found '" ++ @typeName(T) ++ "'"),
    }
}

const MAX_LOCAL_ARRAY_LEN = 2048;

fn defaultArrayValue(comptime T: type) T {
    const info = @typeInfo(T);
    if (info.Array.len > MAX_LOCAL_ARRAY_LEN) {
        @compileError("The length of array too large to create array");
    }

    var array: [info.Array.len]info.Array.child = undefined;
    comptime var i = 0;
    inline while (i < info.Array.len) : (i += 1) {
        array[i] = defaultValueOfType(info.Array.child);
    }
    return array;
}

fn defaultVectorValue(comptime T: type) T {
    const info = @typeInfo(T);
    if (info.Vector.len > MAX_LOCAL_ARRAY_LEN) {
        @compileError("The length of vector too large to create vector");
    }

    var array: [info.Vector.len]info.Vector.child = undefined;
    comptime var i = 0;
    inline while (i < info.Vector.len) : (i += 1) {
        array[i] = defaultValueOfType(info.Vector.child);
    }
    return array;
}

fn defaultPointerValue(comptime T: type) T {
    const info = @typeInfo(T).Pointer;
    switch (info.size) {
        .Slice => {
            if (info.sentinel) |sentinel| {
                const p: *info.child = @constCast(@ptrCast(sentinel));
                const array = [_]info.child{p.*};
                return @constCast(@ptrCast(array[0..]));
            } else {
                const array = [_]info.child{};
                return &array;
            }
        },
        else => @compileError("Only support slice pointer"),
    }
}

fn defaultStructValue(comptime T: type) T {
    var val: T = undefined;
    const info = @typeInfo(T).Struct;
    inline for (info.fields) |field_info| {
        @field(val, field_info.name) = defaultValueOfType(field_info.type);
    }

    return val;
}

fn defaultUnionValue(comptime T: type) T {
    const info = @typeInfo(T).Union;
    return @unionInit(T, info.fields[0].name, defaultValueOfType(info.fields[0].type));
}

fn defaultEnumValue(comptime T: type) T {
    return @as(T, @enumFromInt(0));
}

inline fn defaultValueOfType(comptime T: type) T {
    return switch (@typeInfo(T)) {
        .Type => void,
        .Void => {},
        .Bool => false,
        .Int, .Float => @as(T, 0),
        .Optional => @as(T, null),
        .Array => defaultArrayValue(T),
        .Vector => defaultVectorValue(T),
        .Pointer => defaultPointerValue(T),
        .Struct => defaultStructValue(T),
        .Union => defaultUnionValue(T),
        .Enum => defaultEnumValue(T),
        else => @compileError("default field value not support type: " ++ @typeName(T)),
    };
}

const std = @import("std");
const zstbi = @import("zstbi.zig");
const sd = @import("simd_sample.zig");

const Allocator = std.mem.Allocator;

// export fn _start() callconv(.C) noreturn {
//     try @call(.auto, main, .{});
// }

pub fn main() !void {
    // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

    // for (std.os.argv) |arg| {
    //     std.debug.print("arg: {s}\n", .{arg});
    // }

    // stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try stdout.print("Run `zig build test` to run the tests.\n", .{});

    try bw.flush(); // don't forget to flush!

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var list = try IntList.init(allocator);
    defer list.deinit();

    for (0..10) |i| {
        try list.add(@intCast(i));
    }

    std.debug.print("list: {any}\n", .{list.terms[0..list.pos]});
    std.debug.print("list.add type: {any}\n", .{@typeInfo(@TypeOf(IntList))});

    try sd.simdSample();

    typeSample();

    if (std.os.argv.len > 1) {
        try readAndProcessImage(std.mem.span(std.os.argv[1]));
    }
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

const IntList = struct {
    pos: usize,
    terms: []i64,
    allocator: Allocator,

    fn init(allocator: Allocator) !IntList {
        return .{
            .pos = 0,
            .allocator = allocator,
            .terms = try allocator.alloc(i64, 4),
        };
    }

    fn deinit(self: IntList) void {
        self.allocator.free(self.terms);
    }

    fn add(self: *IntList, value: i64) !void {
        const pos = self.pos;
        const len = self.terms.len;

        if (pos == len) {
            // the space of terms is out of memory, create a new slice that's
            // twice as large.
            var large = try self.allocator.alloc(i64, len * 2);

            // copy the items we previously added to our new slice
            @memcpy(large[0..pos], self.terms);

            self.allocator.free(self.terms);
            self.terms = large;
        }

        self.terms[pos] = value;
        self.pos = pos + 1;
    }
};

const testing = std.testing;

test "IntList: add" {
    // We're using testing.allocator herer!
    var list = try IntList.init(testing.allocator);
    defer list.deinit();

    for (0..5) |i| {
        try list.add(@intCast(i + 10));
    }

    try testing.expectEqual(@as(usize, 5), list.pos);
    try testing.expectEqual(@as(i64, 10), list.terms[0]);
    try testing.expectEqual(@as(i64, 11), list.terms[1]);
    try testing.expectEqual(@as(i64, 12), list.terms[2]);
    try testing.expectEqual(@as(i64, 13), list.terms[3]);
    try testing.expectEqual(@as(i64, 14), list.terms[4]);
}

fn typeSample() void {
    const i: u32 = 2;

    const T = getEnumType(i);
    std.debug.print("enum type = {any}\n", .{T});
}

const SchoolType = enum {
    little,
    low_middle,
    high_middle,
};

const EmpoleeType = enum {
    sales,
    engineer,
    manager,
};

fn getEnumType(comptime i: u32) type {
    if (i == 1) {
        return SchoolType;
    } else {
        return EmpoleeType;
    }
}

fn readAndProcessImage(path: []u8) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    zstbi.init(allocator);
    defer zstbi.deinit();

    const c_path = try allocator.dupeZ(u8, path);
    var image = try zstbi.Image.loadFromFile(c_path, 0);
    defer image.deinit();

    var small_image = zstbi.Image.resize(&image, 480, 270);
    defer small_image.deinit();

    const dir = if (std.fs.path.dirname(path)) |dir| set_dir: {
        break :set_dir dir;
    } else {
        return error.BadPathName;
    };

    const base = std.fs.path.basename(path);
    const index = std.mem.lastIndexOfScalar(u8, base, '.') orelse base.len;
    const small_base = try std.mem.concat(allocator, u8, &[_][]const u8{ base[0..index], "_small", base[index..] });
    const small_path = try std.fs.path.joinZ(allocator, &[_][]const u8{ dir, small_base });
    std.debug.print("small image path: {s}\n", .{small_path});

    try zstbi.Image.writeToFile(small_image, small_path, .{ .jpg = .{ .quality = 95 } });
}

const std = @import("std");
const zstbi = @import("zstbi");

pub fn readAndProcessImage(path: []u8) !void {
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
    // std.debug.print("image info: {any}\n", .{small_image});

    try zstbi.Image.writeToFile(small_image, small_path, .{ .jpg = .{ .quality = 95 } });
}

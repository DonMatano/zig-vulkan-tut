const std = @import("std");

const HelloTriangle = @import("HelloTriangle.zig");

const log = std.log;
pub fn main() !void {
    var debugAlloc = std.heap.DebugAllocator(.{}).init;
    defer _ = debugAlloc.deinit();
    const allocator = debugAlloc.allocator();
    var app: HelloTriangle = .init(allocator);
    app.run() catch |err| {
        log.err("Failed to run Hello Triange, got {any}", .{err});
    };
}

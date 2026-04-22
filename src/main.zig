const std = @import("std");
const HelloTriangle = @import("examples/HelloTriangle.zig");
const main_log = std.log.scoped(.Main);

pub fn main(init: std.process.Init) !void {
    var arena = init.arena;
    defer arena.deinit();
    HelloTriangle.run(arena.allocator()) catch |err| {
        main_log.err("Got Error running {}", .{err});
        return error.ExitFailure;
    };
}

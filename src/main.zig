const std = @import("std");
const HelloTriangle = @import("examples/HelloTriangle.zig");
const main_log = std.log.scoped(.Main);

pub fn main(init: std.process.Init) !void {
    HelloTriangle.run(init.arena.allocator()) catch |err| {
        main_log.err("Got Error running {}", .{err});
        return error.ExitFailure;
    };
}

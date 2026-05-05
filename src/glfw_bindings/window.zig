const std = @import("std");
const cglfw = @import("c");
const glfw = @import("glfw.zig");

glfw_window: *cglfw.GLFWwindow,
width: u32,
height: u32,

const window_log = std.log.scoped(.GLFW_Window);

pub const WindowHints = enum(i32) {
    glfw_no_api = 0,
    glfw_client_api = 0x00022004,
};

const Window = @This();

pub fn init(width: u32, height: u32, title: []const u8) !Window {
    const window = cglfw.glfwCreateWindow(@intCast(width), @intCast(height), title.ptr, null, null);
    if (window == null) {
        glfw.logCErr(null);
        return error.WindowCreateFailed;
    }
    return .{
        .glfw_window = window.?,
        .height = height,
        .width = width,
    };
}

pub fn shouldClose(self: *Window) bool {
    const res = cglfw.glfwWindowShouldClose(self.glfw_window);
    return res == 1;
}

pub fn createSurface(self: Window, instance: ?*cglfw.struct_VkInstance_T, surface: [*c]?*cglfw.struct_VkSurfaceKHR_T) !void {
    const res = cglfw.glfwCreateWindowSurface(instance, self.glfw_window, null, surface);
    if (res != 0) {
        window_log.err("Got VK Result error: code {d}", .{res});
        return error.VKSurfaceCreationError;
    }
}

pub fn destroy(self: *Window) void {
    cglfw.glfwDestroyWindow(self.glfw_window);
}

const std = @import("std");
const cglfw = @import("c");
const glfw = @import("glfw.zig");

const Window = @This();

glfw_window: *cglfw.GLFWwindow,
width: u32,
height: u32,
// frameBufferResizeCallback: ?*const fn (*Window, u32, u32) void = null,

const window_log = std.log.scoped(.GLFW_Window);

pub const WindowHints = enum(i32) {
    glfw_no_api = 0,
    glfw_client_api = 0x00022004,
};

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

pub fn getFrameBufferSize(self: Window) struct { width: u32, height: u32 } {
    var width: c_int = undefined;
    var height: c_int = undefined;
    cglfw.glfwGetFramebufferSize(self.glfw_window, &width, &height);
    return .{
        .width = @intCast(width),
        .height = @intCast(height),
    };
}
pub fn setFrameBufferSizeCallback(
    self: *Window,
    frameBufferResizeCallback: *const fn (?*cglfw.struct_GLFWwindow, c_int, c_int) callconv(.c) void,
) !void {
    _ = cglfw.glfwSetFramebufferSizeCallback(self.glfw_window, @ptrCast(frameBufferResizeCallback));
}

pub fn setUserPointer(self: *Window, pointer: ?*anyopaque) void {
    cglfw.glfwSetWindowUserPointer(self.glfw_window, pointer);
}

pub fn getUserPointer(self: *Window, T: type) T {
    const val: *T = @ptrCast(@alignCast(cglfw.glfwGetWindowUserPointer(self.glfw_window)));
    return val.*;
}

pub fn destroy(self: *Window) void {
    cglfw.glfwDestroyWindow(self.glfw_window);
}

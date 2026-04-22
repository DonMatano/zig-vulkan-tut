const std = @import("std");
const glfw = @import("../glfw_bindings/glfw.zig");
const vk = @import("vulkan");
//
var window: glfw.Window = undefined;
context: ?vk.Instance = null,

pub fn run() !void {
    // std
    try initWindow();
    initVulkan();
    defer cleanup();
    mainLoop();
}

fn initWindow() !void {
    try glfw.init();
    try glfw.setClientApi(.glfw_no_api);
    try glfw.isResizable(false);
    window = try glfw.Window.init(800, 1280, "Vulkan");
}
fn initVulkan() void {}
fn mainLoop() void {
    while (!window.shouldClose()) {
        glfw.pollEvents();
    }
}
fn cleanup() void {
    window.destroy();
    glfw.terminate();
}

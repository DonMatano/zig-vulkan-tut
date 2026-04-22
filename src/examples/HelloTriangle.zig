const std = @import("std");
const glfw = @import("../glfw_bindings/glfw.zig");
const vk = @import("vulkan");

const Alloc = std.mem.Allocator;
//
window: glfw.Window = undefined,
instance: ?vk.Instance = null,
vkb: vk.BaseWrapper = undefined,

const App = @This();

fn getGLFWInstanceProc(instance: vk.Instance, proc_name: [*:0]const u8) vk.PfnVoidFunction {
    return glfw.getInstanceProcAddress(@intFromEnum(instance), proc_name);
}
pub fn run(alloc: Alloc) !void {
    // std
    var app = App{};
    try app.initWindow();
    try app.initVulkan(alloc);
    defer app.cleanup();
    app.mainLoop();
}

fn initWindow(self: *App) !void {
    try glfw.init();
    try glfw.setClientApi(.glfw_no_api);
    try glfw.isResizable(false);
    self.window = try glfw.Window.init(800, 1280, "Vulkan");
}
fn initVulkan(self: *App, alloc: Alloc) !void {
    self.vkb = vk.BaseWrapper.load(getGLFWInstanceProc);
    var extension_names: std.ArrayList([*:0]const u8) = .empty;
    defer extension_names.deinit(alloc);
    const application_info: vk.ApplicationInfo = .{
        .p_application_name = "Hello Triangle",
        .application_version = vk.makeApiVersion(1, 0, 0, 0).toU32(),
        .p_engine_name = "No Engine",
        .engine_version = vk.makeApiVersion(1, 0, 0, 0).toU32(),
        .api_version = vk.API_VERSION_1_4.toU32(),
    };
    try glfw.getRequiredInstanceExtensions(&extension_names, alloc);
    const create_info: vk.InstanceCreateInfo = .{
        .p_application_info = &application_info,
        .enabled_extension_count = @intCast(extension_names.items.len),
        .pp_enabled_extension_names = extension_names.items.ptr,
        .flags = .{ .enumerate_portability_bit_khr = true },
    };
    const instance = try self.vkb.createInstance(&create_info, null);
    const vki = try alloc.create(vk.InstanceWrapper);
    errdefer alloc.destroy(vki);
    vki.* = vk.InstanceWrapper.load(instance, self.vkb.dispatch.vkGetInstanceProcAddr.?);
}
fn mainLoop(self: *App) void {
    while (!self.window.shouldClose()) {
        glfw.pollEvents();
    }
}
fn cleanup(self: *App) void {
    self.window.destroy();
    glfw.terminate();
}

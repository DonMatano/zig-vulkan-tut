const std = @import("std");
const builtin = @import("builtin");
const glfw = @import("../glfw_bindings/glfw.zig");
const vk = @import("vulkan");

const Alloc = std.mem.Allocator;

const BaseWrapper = vk.BaseWrapper;
//
window: glfw.Window = undefined,
instance: vk.Instance = undefined,
vkb: BaseWrapper = undefined,

const App = @This();

const required_layer_names = [_][*:0]const u8{"VK_LAYER_KHRONOS_validation"};
const validationLayersEnabled: bool = builtin.mode == .Debug;

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
    if (validationLayersEnabled and !try checkLayerSupport(&self.vkb, alloc)) {
        return error.MissingLayer;
    }
    var extension_names: std.ArrayList([*:0]const u8) = .empty;
    defer extension_names.deinit(alloc);

    try extension_names.append(alloc, vk.extensions.khr_portability_enumeration.name);
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

fn checkLayerSupport(vkb: *const BaseWrapper, alloc: Alloc) !bool {
    const available_layers = try vkb.enumerateInstanceLayerPropertiesAlloc(alloc);
    defer alloc.free(available_layers);
    for (required_layer_names) |required_layer| {
        for (available_layers) |available_layer| {
            if (std.mem.eql(u8, std.mem.span(required_layer), std.mem.sliceTo(&available_layer.layer_name, 0))) {
                break;
            }
        } else {
            return false;
        }
    }
    return true;
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

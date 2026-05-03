const std = @import("std");
const builtin = @import("builtin");
const glfw = @import("../glfw_bindings/glfw.zig");
const vk = @import("vulkan");

const Alloc = std.mem.Allocator;

const BaseWrapper = vk.BaseWrapper;
const InstanceWrapper = vk.InstanceWrapper;
const Instance = vk.InstanceProxy;
//
window: glfw.Window = undefined,
instance: Instance = undefined,
vkb: BaseWrapper = undefined,
debug_messenger: vk.DebugUtilsMessengerEXT = undefined,

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
    if (validationLayersEnabled) {
        try extension_names.append(alloc, vk.extensions.ext_debug_utils.name);
    }
    const create_info: vk.InstanceCreateInfo = .{
        .p_application_info = &application_info,
        .enabled_extension_count = @intCast(extension_names.items.len),
        .pp_enabled_extension_names = extension_names.items.ptr,
        .flags = .{ .enumerate_portability_bit_khr = true },
        .enabled_layer_count = if (validationLayersEnabled) required_layer_names.len else 0,
        .pp_enabled_layer_names = if (validationLayersEnabled) @ptrCast(&required_layer_names) else null,
    };
    const instance = try self.vkb.createInstance(&create_info, null);
    const vki = try alloc.create(InstanceWrapper);
    errdefer alloc.destroy(vki);
    vki.* = InstanceWrapper.load(instance, self.vkb.dispatch.vkGetInstanceProcAddr.?);
    self.instance = Instance.init(instance, vki);
    errdefer self.instance.destroyInstance(null);
    try self.setupDebugMessenger();
}

fn setupDebugMessenger(self: *App) !void {
    if (!validationLayersEnabled) return;
    // self.instance.destroyDebugUtilsMessengerEXT(messenger: DebugUtilsMessengerEXT, p_allocator: ?*const AllocationCallbacks)
    const debug_utils: vk.DebugUtilsMessengerCreateInfoEXT = .{
        .message_severity = .{
            // .verbose_bit_ext = true,
            .warning_bit_ext = true,
            .error_bit_ext = true,
        },
        .message_type = .{
            .general_bit_ext = true,
            .performance_bit_ext = true,
            .validation_bit_ext = true,
        },
        .pfn_user_callback = &debugUtilsMessengerCallback,
    };
    self.debug_messenger = try self.instance.createDebugUtilsMessengerEXT(&debug_utils, null);
}

fn debugUtilsMessengerCallback(severity: vk.DebugUtilsMessageSeverityFlagsEXT, msg_type: vk.DebugUtilsMessageTypeFlagsEXT, callback_data: ?*const vk.DebugUtilsMessengerCallbackDataEXT, _: ?*anyopaque) callconv(.c) vk.Bool32 {
    const severity_str = if (severity.verbose_bit_ext) "verbose" else if (severity.info_bit_ext) "info" else if (severity.warning_bit_ext) "warning" else if (severity.error_bit_ext) "error" else "unknown";

    const type_str = if (msg_type.general_bit_ext) "general" else if (msg_type.validation_bit_ext) "validation" else if (msg_type.performance_bit_ext) "performance" else if (msg_type.device_address_binding_bit_ext) "device addr" else "unknown";

    const message: [*c]const u8 = if (callback_data) |cb_data| cb_data.p_message else "NO MESSAGE!";
    // std.debug.print("[{s}][{s}]. Message:\n  {s}\n", .{ severity_str, type_str, message });
    // if (severity >= .) {}
    std.debug.print("{s}: validation layer type {s}\n msg:{s}\n", .{ severity_str, type_str, message });

    return .false;
}

fn checkLayerSupport(vkb: *const BaseWrapper, alloc: Alloc) !bool {
    std.log.debug("Checking layer support", .{});
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
    if (validationLayersEnabled) {
        self.instance.destroyDebugUtilsMessengerEXT(self.debug_messenger, null);
    }
    self.instance.destroyInstance(null);
    self.window.destroy();
    glfw.terminate();
}

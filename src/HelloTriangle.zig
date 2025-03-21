const std = @import("std");
const builtin = @import("builtin");
const vk = @import("vk.zig");
const glfw = @import("mach-glfw");

const HelloTriangleApp = @This();
pub const GLFWErrors = error{
    GLFWInitFailed,
    WindowCreateFailed,
    CreateInstanceError,
};
const Allocator = std.mem.Allocator;
const log = std.log;

const width = 800;
const height = 600;

const apis: []const vk.ApiInfo = &.{
    .{
        .base_commands = .{
            .createInstance = true,
            .enumerateInstanceExtensionProperties = true,
            .enumerateInstanceLayerProperties = true,
            .getInstanceProcAddr = true,
        },
        .instance_commands = .{
            .getDeviceProcAddr = true,
            .createDevice = true,
            .destroyInstance = true,
            .createDebugUtilsMessengerEXT = enable_validation_layers,
            .destroyDebugUtilsMessengerEXT = enable_validation_layers,
            .enumeratePhysicalDevices = true,
            .enumerateDeviceExtensionProperties = true,
            .getPhysicalDeviceQueueFamilyProperties = true,
            .getPhysicalDeviceSurfaceSupportKHR = true,
            .destroySurfaceKHR = true,
        },
        .device_commands = .{
            .destroyDevice = true,
            .getDeviceQueue = true,
        },
    },
};

const BaseDispatch = vk.BaseWrapper(apis);
const InstanceDispatch = vk.InstanceWrapper(apis);
const DeviceDispatch = vk.DeviceWrapper(apis);

const Instance = vk.InstanceProxy(apis);
const Device = vk.DeviceProxy(apis);

instance: Instance = undefined,
window: glfw.Window = undefined,
vkb: BaseDispatch = undefined,
vki: *InstanceDispatch = undefined,
vkd: DeviceDispatch = undefined,
debug_messenger: vk.DebugUtilsMessengerEXT = .null_handle,
physical_device: vk.PhysicalDevice = .null_handle,
device: Device = undefined,
graphics_queue: vk.Queue = undefined,
surface: vk.SurfaceKHR = undefined,
present_queue: vk.Queue = undefined,

allocator: Allocator,

const QueueFamilyIndices = struct {
    graphics_family: ?u32 = null,
    presentation_family: ?u32 = null,
    pub fn isComplete(self: QueueFamilyIndices) bool {
        return self.graphics_family != null and self.presentation_family != null;
    }
};

const required_device_extensions = [_][*:0]const u8{vk.extensions.khr_swapchain.name};

/// Default GLFW error handling callback
fn errorCallback(error_code: glfw.ErrorCode, description: [:0]const u8) void {
    std.log.err("glfw: {}: {s}\n", .{ error_code, description });
}

fn debugCallBack(
    _: vk.DebugUtilsMessageSeverityFlagsEXT,
    _: vk.DebugUtilsMessageTypeFlagsEXT,
    p_callback_data: ?*const vk.DebugUtilsMessengerCallbackDataEXT,
    _: ?*anyopaque,
) callconv(vk.vulkan_call_conv) vk.Bool32 {
    if (p_callback_data != null) {
        std.log.debug("validation layer: {?s}", .{p_callback_data.?.p_message});
    }

    return vk.FALSE;
}

const validation_layers = [_][*:0]const u8{"VK_LAYER_KHRONOS_validation"};

const enable_validation_layers: bool = switch (builtin.mode) {
    .Debug, .ReleaseSafe => true,
    else => false,
};
pub fn init(allocator: Allocator) HelloTriangleApp {
    return .{ .allocator = allocator };
}

pub fn run(self: *HelloTriangleApp) !void {
    try self.initWindow();
    try self.initVulkan();
    try self.mainLoop();
    self.cleanUp();
}

fn initWindow(self: *HelloTriangleApp) GLFWErrors!void {
    glfw.setErrorCallback(errorCallback);
    if (!glfw.init(.{})) {
        log.err("Failed to init glfw, {?s}", .{glfw.getErrorString()});
        std.process.exit(1);
    }
    self.window = glfw.Window.create(
        width,
        height,
        "Vulkan window",
        null,
        null,
        .{
            .client_api = .no_api,
            .resizable = false,
        },
    ) orelse {
        log.err("Failed to create window, {?s}", .{glfw.getErrorString()});
        std.process.exit(1);
    };
}

fn initVulkan(self: *HelloTriangleApp) !void {
    self.createInstance() catch |err| {
        log.err("Error creating an instance, got err {}", .{err});
        return error.CreateInstanceError;
    };
    self.setupDebugMessenger() catch |err| {
        log.err("Error setting up debug messenger {}", .{err});
        return error.DebugMessengerCreationFailed;
    };
    self.createSurface() catch |err| {
        log.err("Error creating surface {}", .{err});
        return error.CreateSurfaceFailed;
    };
    self.pickPhysicalDevice() catch |err| {
        log.err("Error picking physical device {}", .{err});
        return error.PickPhysicalDeviceFailed;
    };
    self.createLogicalDevice() catch |err| {
        log.err("Error creating logical device{}", .{err});
        return error.CreateLogicalDeviceFailed;
    };
}

fn createInstance(self: *HelloTriangleApp) !void {
    self.vkb = try BaseDispatch.load(@as(vk.PfnGetInstanceProcAddr, @ptrCast(&glfw.getInstanceProcAddress)));
    if (enable_validation_layers and !try self.checkValidationLayerSupport()) {
        return error.RequestedValidationLayerNotAvailable;
    }

    const extensions = try getRequiredExtensions(self.allocator);
    defer extensions.deinit();

    var instance_exts = try std.ArrayList([*:0]const u8).initCapacity(self.allocator, extensions.items.len + 1);
    defer instance_exts.deinit();
    try instance_exts.appendSlice(extensions.items);

    var count: u32 = undefined;
    _ = try self.vkb.enumerateInstanceExtensionProperties(null, &count, null);

    const array_of_ext_props = try self.allocator.alloc(vk.ExtensionProperties, count);
    defer self.allocator.free(array_of_ext_props);
    _ = try self.vkb.enumerateInstanceExtensionProperties(null, &count, array_of_ext_props.ptr);

    log.info("\navailable extensions:\n", .{});

    for (array_of_ext_props) |ext_prop| {
        log.info("\t {s} \n", .{ext_prop.extension_name});
    }

    const appInfo: vk.ApplicationInfo = .{
        .s_type = .application_info,
        .p_application_name = "Hello Triangle",
        .application_version = vk.makeApiVersion(1, 0, 0, 0),
        .p_engine_name = "No Engine",
        .engine_version = vk.makeApiVersion(1, 0, 0, 0),
        .api_version = vk.API_VERSION_1_0,
    };

    var createInfo: vk.InstanceCreateInfo = .{
        .p_application_info = &appInfo,
        .p_next = null,
        .enabled_extension_count = @intCast(extensions.items.len),
        .pp_enabled_extension_names = @ptrCast(extensions.items.ptr),
    };
    var createDebugInfo: vk.DebugUtilsMessengerCreateInfoEXT = undefined;
    if (enable_validation_layers) {
        createInfo.enabled_layer_count = validation_layers.len;
        createInfo.pp_enabled_layer_names = &validation_layers;
        populateDebugMessengerCreateInfo(&createDebugInfo);
        createInfo.p_next = &createDebugInfo;
    }
    const instance = try self.vkb.createInstance(&createInfo, null);

    self.vki = try self.allocator.create(InstanceDispatch);
    self.vki.* = try InstanceDispatch.load(instance, self.vkb.dispatch.vkGetInstanceProcAddr);
    self.instance = Instance.init(instance, self.vki);
    errdefer self.instance.destroyInstance(null);
}

fn setupDebugMessenger(self: *HelloTriangleApp) !void {
    if (!enable_validation_layers) return;
    var createDebugInfo: vk.DebugUtilsMessengerCreateInfoEXT = undefined;
    populateDebugMessengerCreateInfo(&createDebugInfo);
    self.debug_messenger = try self.instance.createDebugUtilsMessengerEXT(&createDebugInfo, null);
}

fn checkValidationLayerSupport(self: *HelloTriangleApp) !bool {
    const available_layers = try self.vkb.enumerateInstanceLayerPropertiesAlloc(self.allocator);
    defer self.allocator.free(available_layers);

    for (validation_layers, 0..) |layer_name, i| {
        log.debug("validation layer {d}, {s}", .{ i, layer_name });
        var layerFound = false;
        for (available_layers) |available_layer| {
            if (std.mem.eql(u8, std.mem.span(layer_name), std.mem.sliceTo(&available_layer.layer_name, 0))) {
                layerFound = true;
                break;
            }
        }
        if (!layerFound) {
            return false;
        }
    }
    return true;
}

fn populateDebugMessengerCreateInfo(createDebugInfo: *vk.DebugUtilsMessengerCreateInfoEXT) void {
    createDebugInfo.* = .{
        .message_severity = .{
            .verbose_bit_ext = true,
            .warning_bit_ext = true,
            .error_bit_ext = true,
        },
        .message_type = .{
            .general_bit_ext = true,
            .validation_bit_ext = true,
            .performance_bit_ext = true,
        },
        .pfn_user_callback = debugCallBack,
        .p_user_data = null,
    };
}

fn getRequiredExtensions(allocator: Allocator) !std.ArrayListAligned([*:0]const u8, null) {
    var extensions = std.ArrayList([*:0]const u8).init(allocator);
    const glfw_exts = glfw.getRequiredInstanceExtensions() orelse return blk: {
        const err = glfw.mustGetError();
        log.err("failed to get required instance extensions: error={s}", .{err.description});
        break :blk error.FailedInstanceInit;
    };
    try extensions.appendSlice(glfw_exts);

    if (enable_validation_layers) {
        try extensions.append(vk.extensions.ext_debug_utils.name);
    }
    return extensions;
}

fn createSurface(self: *HelloTriangleApp) !void {
    if ((glfw.createWindowSurface(self.instance.handle, self.window, null, &self.surface)) != @intFromEnum(vk.Result.success)) {
        return error.SurfaceInitFailed;
    }
}

fn pickPhysicalDevice(self: *HelloTriangleApp) !void {
    const devices = try self.instance.enumeratePhysicalDevicesAlloc(self.allocator);
    defer self.allocator.free(devices);

    for (devices) |device| {
        if (try self.isDeviceSuitable(device)) {
            self.physical_device = device;
            break;
        }
    }
    if (self.physical_device == .null_handle) {
        return error.FailedToFindSuitableGPU;
    }
}

fn isDeviceSuitable(self: *HelloTriangleApp, device: vk.PhysicalDevice) !bool {
    const indices = try self.findQueueFamilies(device);
    const extensions_supported = try checkDeviceExtensionSupport(self.instance, device, self.allocator);
    return indices.isComplete() and extensions_supported;
}

fn checkDeviceExtensionSupport(instance: Instance, p_device: vk.PhysicalDevice, allocator: Allocator) !bool {
    const available_extensions = try instance.enumerateDeviceExtensionPropertiesAlloc(p_device, null, allocator);
    defer allocator.free(available_extensions);

    for (required_device_extensions) |ext| {
        for (available_extensions) |available_ext| {
            if (std.mem.eql(u8, std.mem.span(ext), std.mem.sliceTo(&available_ext.extension_name, 0))) {
                break;
            }
        } else {
            return false;
        }
    }
    return true;
}

fn findQueueFamilies(self: *HelloTriangleApp, device: vk.PhysicalDevice) !QueueFamilyIndices {
    var indices: QueueFamilyIndices = .{};
    const queue_families = try self.instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(device, self.allocator);
    defer self.allocator.free(queue_families);

    for (queue_families, 0..) |queue_family, i| {
        const family: u32 = @intCast(i);

        if (queue_family.queue_flags.graphics_bit) {
            indices.graphics_family = family;
        }
        const present_support = try self.instance.getPhysicalDeviceSurfaceSupportKHR(device, @intCast(i), self.surface) == vk.TRUE;
        if (present_support) {
            indices.presentation_family = @intCast(i);
        }
        if (indices.isComplete()) {
            break;
        }
    }

    return indices;
}

fn createLogicalDevice(self: *HelloTriangleApp) !void {
    const indices = try self.findQueueFamilies(self.physical_device);
    const queue_priority = [_]f32{1};
    var queue_create_info = [_]vk.DeviceQueueCreateInfo{
        .{
            .queue_family_index = indices.graphics_family.?,
            .queue_count = 1,
            .p_queue_priorities = &queue_priority,
        },
        .{
            .queue_family_index = indices.presentation_family.?,
            .queue_count = 1,
            .p_queue_priorities = &queue_priority,
        },
    };
    // Check if device gotten is same, if so return 1 in the queue if not return 2
    const queue_count: u32 = if (indices.graphics_family.? == indices.presentation_family.?) 1 else 2;

    var device_create_info: vk.DeviceCreateInfo = .{
        .queue_create_info_count = queue_count,
        .p_queue_create_infos = &queue_create_info,
        .enabled_extension_count = required_device_extensions.len,
        .pp_enabled_extension_names = &required_device_extensions,
    };
    if (enable_validation_layers) {
        device_create_info.enabled_layer_count = validation_layers.len;
        device_create_info.pp_enabled_layer_names = &validation_layers;
    }
    const device = try self.instance.createDevice(self.physical_device, &device_create_info, null);
    const vkd = try self.allocator.create(DeviceDispatch);
    errdefer self.allocator.destroy(vkd);
    vkd.* = try DeviceDispatch.load(device, self.instance.wrapper.dispatch.vkGetDeviceProcAddr);
    self.device = Device.init(device, vkd);
    self.graphics_queue = self.device.getDeviceQueue(indices.graphics_family.?, 0);
    self.present_queue = self.device.getDeviceQueue(indices.presentation_family.?, 0);
}

fn mainLoop(self: HelloTriangleApp) !void {
    while (!self.window.shouldClose()) {
        glfw.pollEvents();
    }
}

fn cleanUp(self: *HelloTriangleApp) void {
    self.device.destroyDevice(null);
    if (enable_validation_layers and self.debug_messenger != .null_handle) self.instance.destroyDebugUtilsMessengerEXT(
        self.debug_messenger,
        null,
    );
    self.instance.destroySurfaceKHR(self.surface, null);
    self.instance.destroyInstance(null);
    self.allocator.destroy(self.device.wrapper);
    self.allocator.destroy(self.instance.wrapper);
    self.window.destroy();
    glfw.terminate();
}

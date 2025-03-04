const std = @import("std");
const vk = @import("vk.zig");
// const glfw = @cImport(
//     @cInclude("GLFW/glfw3.h"),
// );
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
    // .{ .base_commands = .{
    //     .createInstance = true,
    // } },
    .{
        .base_commands = .{
            .createInstance = true,
            .enumerateInstanceExtensionProperties = true,
            .getInstanceProcAddr = true,
        },
        .instance_commands = .{
            .createDevice = true,
            .destroyInstance = true,
        },
    },
    // vk.features.version_1_0,
};

const BaseDispatch = vk.BaseWrapper(apis);
const InstanceDispatch = vk.InstanceWrapper(apis);
const Instance = vk.InstanceProxy(apis);

instance: Instance = undefined,
window: glfw.Window = undefined,
vkb: BaseDispatch = undefined,
vki: *InstanceDispatch = undefined,

allocator: Allocator,

/// Default GLFW error handling callback
fn errorCallback(error_code: glfw.ErrorCode, description: [:0]const u8) void {
    std.log.err("glfw: {}: {s}\n", .{ error_code, description });
}

// pub extern fn glfwGetInstanceProcAddress(instance: vk.Instance, procname: [*:0]const u8) vk.PfnVoidFunction;

pub fn init(allocator: Allocator) HelloTriangleApp {
    return HelloTriangleApp{ .allocator = allocator };
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
    };
}

fn createInstance(self: *HelloTriangleApp) !void {
    // const func_ptr = glfw.getInstanceProcAddress(null, "vkCreateInstance") orelse {
    //     log.err("Failed to load instance proc {?s}\n", .{glfw.getErrorString()});
    //     std.process.exit(1);
    // };
    // const func: vk.PfnGetInstanceProcAddr = @ptrCast(func_ptr);
    self.vkb = try BaseDispatch.load(@as(vk.PfnGetInstanceProcAddr, @ptrCast(&glfw.getInstanceProcAddress)));
    const glfw_exts = glfw.getRequiredInstanceExtensions() orelse return blk: {
        const err = glfw.mustGetError();
        log.err("failed to get required instance extensions: error={s}", .{err.description});
        break :blk error.FailedInstanceInit;
    };

    var instance_exts = try std.ArrayList([*:0]const u8).initCapacity(self.allocator, glfw_exts.len + 1);
    defer instance_exts.deinit();
    try instance_exts.appendSlice(glfw_exts);

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

    const createInfo: vk.InstanceCreateInfo = .{
        .p_application_info = &appInfo,
        .p_next = null,
        .enabled_extension_count = @intCast(glfw_exts.len),
        .pp_enabled_extension_names = @ptrCast(glfw_exts),
    };
    // std.log.debug("\ncreateInfo value {any}", .{createInfo});
    // std.log.debug("\nvkb value {any}", .{self.vkb});
    // std.log.debug("\ndispatch value {any}", .{self.vkb.dispatch});
    const instance = try self.vkb.createInstance(&createInfo, null);

    self.vki = try self.allocator.create(InstanceDispatch);
    self.vki.* = try InstanceDispatch.load(instance, self.vkb.dispatch.vkGetInstanceProcAddr);
    self.instance = Instance.init(instance, self.vki);
    errdefer self.instance.destroyInstance(null);
}

fn mainLoop(self: HelloTriangleApp) !void {
    while (!self.window.shouldClose()) {
        glfw.pollEvents();
    }
}

fn cleanUp(self: *HelloTriangleApp) void {
    self.instance.destroyInstance(null);
    self.allocator.destroy(self.vki);
    self.window.destroy();
    glfw.terminate();
}

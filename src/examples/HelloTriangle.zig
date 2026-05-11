const std = @import("std");
const builtin = @import("builtin");
const glfw = @import("../glfw_bindings/glfw.zig");
const vk = @import("vulkan");

const Alloc = std.mem.Allocator;

const BaseWrapper = vk.BaseWrapper;
const DeviceWrapper = vk.DeviceWrapper;
const InstanceWrapper = vk.InstanceWrapper;
const Instance = vk.InstanceProxy;
const Device = vk.DeviceProxy;
const Queue = struct {
    handle: vk.Queue,
    family: u32,
    fn init(device: Device, family: u32) Queue {
        return .{
            .family = family,
            .handle = device.getDeviceQueue(family, 0),
        };
    }
};
//
const MAX_INFLIGHT_FRAMES: u32 = 2;
window: glfw.Window = undefined,
instance: Instance = undefined,
device: Device = undefined,
vkb: BaseWrapper = undefined,
debug_messenger: vk.DebugUtilsMessengerEXT = undefined,
physical_device: vk.PhysicalDevice = undefined,
device_features: vk.PhysicalDeviceFeatures = undefined,
queue: Queue = undefined,
queue_index: u32 = undefined,
surface: vk.SurfaceKHR = undefined,
swap_chain: vk.SwapchainKHR = undefined,
swap_chain_images: []vk.Image = undefined,
swap_chain_image_format: vk.Format = undefined,
swap_chain_extent: vk.Extent2D = undefined,
swap_chain_image_views: []vk.ImageView = undefined,
pipeline_layout: vk.PipelineLayout = undefined,
graphics_pipeline: vk.Pipeline = undefined,
command_pool: vk.CommandPool = undefined,
frame_index: u32 = 0,

const App = @This();

const app_log = std.log.scoped(.App);
const validation_log = std.log.scoped(.Validation_Log);

const required_layer_names = [_][*:0]const u8{"VK_LAYER_KHRONOS_validation"};
const required_device_extensions = [_][*:0]const u8{
    vk.extensions.khr_swapchain.name,
    vk.extensions.khr_shader_draw_parameters.name,
    vk.extensions.khr_synchronization_2.name,
};
const validationLayersEnabled: bool = builtin.mode == .Debug;
const QueueFamilyIndices = struct {
    graphics_family: u32,
};

fn getGLFWInstanceProc(instance: vk.Instance, proc_name: [*:0]const u8) vk.PfnVoidFunction {
    return glfw.getInstanceProcAddress(@intFromEnum(instance), proc_name);
}
pub fn run(alloc: Alloc) !void {
    // std
    var app = App{};
    try app.initWindow();
    try app.initVulkan(alloc);
    defer app.cleanup(alloc);
    try app.mainLoop(alloc);
}

fn initWindow(self: *App) !void {
    try glfw.init();
    try glfw.setClientApi(.glfw_no_api);
    try glfw.isResizable(false);
    self.window = try glfw.Window.init(1080, 720, "Vulkan");
}
fn initVulkan(self: *App, alloc: Alloc) !void {
    try self.createInstance(alloc);
    try self.setupDebugMessenger();
    try self.createSurface();
    try self.pickPhysicalDevice(alloc);
    try self.createLogicalDevice(alloc);
    try self.createSwapChain(alloc);
    try self.createImageViews(alloc);
    try self.createGraphicsPipeline();
    try self.createCommandPool();
}

fn listInstanceExtensionSupport(self: App, alloc: Alloc) !void {
    const extensions = try self.vkb.enumerateInstanceExtensionPropertiesAlloc(null, alloc);
    defer alloc.free(extensions);
    app_log.debug("Instance Extensions:\n", .{});
    for (extensions, 0..) |ext, i| {
        app_log.debug("{d}: {s}\n", .{ i, ext.extension_name });
    }
}

fn createInstance(self: *App, alloc: Alloc) !void {
    self.vkb = vk.BaseWrapper.load(getGLFWInstanceProc);
    try self.listInstanceExtensionSupport(alloc);
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
    // defer alloc.destroy(&vki);
    errdefer alloc.destroy(vki);
    vki.* = InstanceWrapper.load(instance, self.vkb.dispatch.vkGetInstanceProcAddr.?);
    self.instance = Instance.init(instance, vki);
    errdefer self.instance.destroyInstance(null);
}

fn setupDebugMessenger(self: *App) !void {
    if (!validationLayersEnabled) return;
    const debug_utils: vk.DebugUtilsMessengerCreateInfoEXT = .{
        .message_severity = .{
            .verbose_bit_ext = true,
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
    validation_log.debug("{s}: validation layer type {s}\n msg:{s}\n", .{ severity_str, type_str, message });

    return .false;
}

fn createSurface(self: *App) !void {
    try self.window.createSurface(@ptrFromInt(@intFromEnum(self.instance.handle)), @ptrCast(&self.surface));
}
fn createSwapChain(self: *App, alloc: Alloc) !void {
    const surface_capabilities = try self.instance.getPhysicalDeviceSurfaceCapabilitiesKHR(self.physical_device, self.surface);
    const swap_chain_extent = chooseSwapExtent(&self.window, surface_capabilities);
    const min_image_count = chooseSwapMinImageCount(surface_capabilities);
    const available_formats = try self.instance.getPhysicalDeviceSurfaceFormatsAllocKHR(self.physical_device, self.surface, alloc);
    const available_present_modes = try self.instance.getPhysicalDeviceSurfacePresentModesAllocKHR(self.physical_device, self.surface, alloc);
    defer {
        alloc.free(available_formats);
        alloc.free(available_present_modes);
    }
    const swap_chain_surface_format = try chooseSwapSurfaceFormat(available_formats);
    const swap_chain_create_info: vk.SwapchainCreateInfoKHR = .{
        .surface = self.surface,
        .min_image_count = min_image_count,
        .image_format = swap_chain_surface_format.format,
        .image_color_space = swap_chain_surface_format.color_space,
        .image_extent = swap_chain_extent,
        .image_array_layers = 1,
        .image_usage = .{ .color_attachment_bit = true },
        .image_sharing_mode = .exclusive,
        .pre_transform = surface_capabilities.current_transform,
        .composite_alpha = .{ .opaque_bit_khr = true },
        .present_mode = try chooseSwapPresentMode(available_present_modes),
        .clipped = .true,
    };
    self.swap_chain = self.device.createSwapchainKHR(&swap_chain_create_info, null) catch {
        app_log.err("SwapChain creationg Failed", .{});
        return error.SwapChainCreationFailed;
    };
    self.swap_chain_image_format = swap_chain_surface_format.format;
    errdefer self.device.destroySwapchainKHR(self.swap_chain, null);

    const images = try self.device.getSwapchainImagesAllocKHR(self.swap_chain, alloc);
    // defer alloc.free(images);
    self.swap_chain_images = images;
    self.swap_chain_extent = swap_chain_extent;
    // @memcpy(self.swap_chain_images.ptr, images);
}

fn createImageViews(self: *App, alloc: Alloc) !void {
    var swap_chain_image_views = try std.ArrayList(vk.ImageView).initCapacity(alloc, self.swap_chain_images.len);
    defer swap_chain_image_views.deinit(alloc);
    if (swap_chain_image_views.items.len != 0) {
        app_log.err("Expected no image_views but got {d}", .{swap_chain_image_views.items.len});
        return error.ImageViewsListIsNotEmpty;
    }
    var image_view_info: vk.ImageViewCreateInfo = .{
        .view_type = .@"2d",
        .image = undefined,
        .format = self.swap_chain_image_format,
        .subresource_range = .{ .aspect_mask = .{ .color_bit = true }, .level_count = 1, .layer_count = 1, .base_mip_level = 0, .base_array_layer = 0 },
        .components = .{ .a = .identity, .b = .identity, .g = .identity, .r = .identity },
    };

    for (self.swap_chain_images) |swap_chain_image| {
        image_view_info.image = swap_chain_image;
        const image_view = try self.device.createImageView(&image_view_info, null);
        try swap_chain_image_views.append(alloc, image_view);
    }
    defer {
        for (swap_chain_image_views.items) |image_view| {
            self.device.destroyImageView(image_view, null);
        }
    }
    self.swap_chain_image_views = try swap_chain_image_views.toOwnedSlice(alloc);
}

fn chooseSwapSurfaceFormat(available_formats: []vk.SurfaceFormatKHR) !vk.SurfaceFormatKHR {
    if (available_formats.len == 0) return error.EmptySurfaceFormat;
    const found_format = for (available_formats) |format| {
        if (format.format == .b8g8r8a8_srgb and format.color_space == .srgb_nonlinear_khr) {
            app_log.debug("Found srg and non linear format", .{});
            break format;
        }
    } else available_formats[0];
    return found_format;
}

fn chooseSwapPresentMode(availabe_present_modes: []vk.PresentModeKHR) !vk.PresentModeKHR {
    const fifo_mode_exists = for (availabe_present_modes) |mode| {
        if (mode == .fifo_khr) {
            break true;
        }
    } else false;
    if (!fifo_mode_exists) {
        return error.MissingFifoPresentationFormat;
    }
    return for (availabe_present_modes) |mode| {
        if (mode == .mailbox_khr) {
            app_log.debug("Found mailbox presentation mode", .{});
            break .mailbox_khr;
        }
    } else vk.PresentModeKHR.fifo_khr;
}

fn chooseSwapExtent(window: *glfw.Window, capabilites: vk.SurfaceCapabilitiesKHR) vk.Extent2D {
    if (capabilites.current_extent.width != std.math.maxInt(u32)) {
        return capabilites.current_extent;
    }
    const dimen = window.getFrameBufferSize();
    const width = std.math.clamp(dimen.width, capabilites.min_image_extent.width, capabilites.max_image_extent.width);
    const height = std.math.clamp(dimen.height, capabilites.min_image_extent.height, capabilites.max_image_extent.height);
    app_log.debug("swap extent width: {d}, height: {d}", .{ width, height });
    return .{
        .height = height,
        .width = width,
    };
}

fn chooseSwapMinImageCount(capabilities: vk.SurfaceCapabilitiesKHR) u32 {
    var min_image_count: u32 = @max(3, capabilities.min_image_count);
    if ((0 < capabilities.max_image_count) and (capabilities.max_image_count < min_image_count)) {
        min_image_count = capabilities.max_image_count;
    }
    app_log.debug("swap min image count: {d}", .{min_image_count});
    return min_image_count;
}

fn checkLayerSupport(vkb: *const BaseWrapper, alloc: Alloc) !bool {
    app_log.debug("Checking layer support", .{});
    const available_layers = try vkb.enumerateInstanceLayerPropertiesAlloc(alloc);
    defer alloc.free(available_layers);
    for (required_layer_names) |required_layer| {
        for (available_layers) |available_layer| {
            app_log.debug("Checking required layer {s}, with layer {s}", .{ required_layer, available_layer.layer_name });
            if (std.mem.eql(u8, std.mem.span(required_layer), std.mem.sliceTo(&available_layer.layer_name, 0))) {
                break;
            }
        } else {
            return false;
        }
    }
    return true;
}

fn pickPhysicalDevice(self: *App, alloc: Alloc) !void {
    const physical_devices = try self.instance.enumeratePhysicalDevicesAlloc(alloc);
    app_log.debug("Physical devices found :", .{});
    for (physical_devices, 0..) |ph_dev, i| {
        const device_properties = self.instance.getPhysicalDeviceProperties(ph_dev);
        app_log.debug("{d}: {s}, type: {s}", .{ i, device_properties.device_name, @tagName(device_properties.device_type) });
    }
    defer alloc.free(physical_devices);
    if (physical_devices.len == 0) {
        app_log.err("Failed to find GPUs with Vulkan support", .{});
        return error.NoPhysicalDevicesFound;
    }

    for (physical_devices) |physical_device| {
        if (try isDeviceSuitable(self.instance, physical_device, alloc)) {
            const device_properties = self.instance.getPhysicalDeviceProperties(physical_device);
            app_log.debug("Got suitable physical device: {s}, type: {s}", .{ device_properties.device_name, @tagName(device_properties.device_type) });
            self.physical_device = physical_device;
            break;
        }
    }
}

fn isDeviceSuitable(instance: Instance, physical_device: vk.PhysicalDevice, alloc: Alloc) !bool {
    const device_props = instance.getPhysicalDeviceProperties(physical_device);
    const device_features = instance.getPhysicalDeviceFeatures(physical_device);
    var dynamic_state_features = vk.PhysicalDeviceExtendedDynamicStateFeaturesEXT{ .p_next = null };
    const is_device_ext_supported = try checkExtensionSupport(instance, physical_device, alloc);

    var vk_13_features = vk.PhysicalDeviceVulkan13Features{
        .p_next = &dynamic_state_features,
    };

    var feature_2 = vk.PhysicalDeviceFeatures2{ .p_next = &vk_13_features, .features = device_features };
    instance.getPhysicalDeviceFeatures2(physical_device, &feature_2);
    const device_families = try instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(physical_device, alloc);
    defer alloc.free(device_families);

    const supports_Vulkan_1_3 = device_props.api_version >= vk.API_VERSION_1_3.toU32();
    const supports_graphics = for (device_families) |device_family| {
        if (device_family.queue_flags.graphics_bit) {
            break true;
        }
    } else false;

    const supports_required_features = (vk_13_features.dynamic_rendering == .true) and (dynamic_state_features.extended_dynamic_state == .true);

    return is_device_ext_supported and supports_Vulkan_1_3 and supports_graphics and supports_required_features;
}

// fn findQueueFamilies(instance: Instance, physical_device: vk.PhysicalDevice, alloc: Alloc) !QueueFamilyIndices {
//     const families = try instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(physical_device, alloc);
//     defer alloc.free(families);
//     var graphics_family: ?u32 = null;
//     return .{};
// }

fn checkExtensionSupport(instance: Instance, physical_device: vk.PhysicalDevice, alloc: Alloc) !bool {
    const device_props = try instance.enumerateDeviceExtensionPropertiesAlloc(physical_device, null, alloc);
    defer alloc.free(device_props);

    // if (builtin.mode == .Debug) {
    //     app_log.debug("Available device extensions: ", .{});
    //     for (device_props, 0..) |ext, i| {
    //         app_log.debug("{d}: {s}", .{ i, ext.extension_name });
    //     }
    // }

    for (required_device_extensions) |required_extension| {
        for (device_props) |device_prop| {
            if (std.mem.eql(u8, std.mem.span(required_extension), std.mem.sliceTo(&device_prop.extension_name, 0))) {
                break;
            }
        } else {
            return false;
        }
    }
    return true;
}

fn createLogicalDevice(self: *App, alloc: Alloc) !void {
    // _ = self;
    const families = try self.instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(self.physical_device, alloc);
    defer alloc.free(families);
    var queue_family_index: ?u32 = null;
    for (families, 0..) |family, i| {
        const has_surface_control = try self.instance.getPhysicalDeviceSurfaceSupportKHR(self.physical_device, @intCast(i), self.surface) == .true;
        if (family.queue_flags.graphics_bit and has_surface_control) {
            queue_family_index = @intCast(i);
            break;
        }
    }
    var dynamic_state_features = vk.PhysicalDeviceExtendedDynamicStateFeaturesEXT{
        .p_next = null,
        .extended_dynamic_state = .true,
    };

    var vk_13_features = vk.PhysicalDeviceVulkan13Features{
        .p_next = &dynamic_state_features,
        .dynamic_rendering = .true,
        .synchronization_2 = .true,
    };

    const feature_2 = vk.PhysicalDeviceFeatures2{ .p_next = &vk_13_features, .features = .{} };

    if (queue_family_index == null) {
        app_log.err("Failed to get a graphics & presentation family", .{});
        return error.MissingGraphicsFamily;
    }
    const queuePriority: f32 = 0.5;

    const device_queue_create_info: vk.DeviceQueueCreateInfo = .{
        .queue_family_index = queue_family_index.?,
        .p_queue_priorities = @ptrCast(&queuePriority),
        .queue_count = 1,
    };

    const device_create_info: vk.DeviceCreateInfo = .{
        .p_next = &feature_2,
        .queue_create_info_count = 1,
        .p_queue_create_infos = @ptrCast(&device_queue_create_info),
        .enabled_extension_count = required_device_extensions.len,
        .pp_enabled_extension_names = @ptrCast(&required_device_extensions),
    };

    const dev = try self.instance.createDevice(self.physical_device, &device_create_info, null);
    const vkd = try alloc.create(DeviceWrapper);
    errdefer alloc.destroy(vkd);
    vkd.* = DeviceWrapper.load(dev, self.instance.wrapper.dispatch.vkGetDeviceProcAddr.?);
    self.device = Device.init(dev, vkd);
    errdefer self.device.destroyDevice(null);
    self.queue = Queue.init(self.device, queue_family_index.?);
    self.queue_index = queue_family_index.?;
}

fn createGraphicsPipeline(self: *App) !void {
    const shader_module = try createShaderModule(&self.device);
    defer self.device.destroyShaderModule(shader_module, null);
    const vert_shader_stage_info: vk.PipelineShaderStageCreateInfo = .{
        .stage = .{ .vertex_bit = true },
        .module = shader_module,
        .p_name = "vertMain",
    };
    const frag_shader_stage_info: vk.PipelineShaderStageCreateInfo = .{
        .stage = .{ .fragment_bit = true },
        .module = shader_module,
        .p_name = "fragMain",
    };

    const shader_stages = [_]vk.PipelineShaderStageCreateInfo{ vert_shader_stage_info, frag_shader_stage_info };
    const vertex_input_info: vk.PipelineVertexInputStateCreateInfo = .{};
    const input_assembly: vk.PipelineInputAssemblyStateCreateInfo = .{ .topology = .triangle_list, .primitive_restart_enable = .false };

    const dynamic_states = [_]vk.DynamicState{ .viewport, .scissor };

    const dynamic_state = vk.PipelineDynamicStateCreateInfo{
        .dynamic_state_count = dynamic_states.len,
        .p_dynamic_states = @ptrCast(&dynamic_states),
    };

    const viewport_state = vk.PipelineViewportStateCreateInfo{
        .scissor_count = 1,
        .viewport_count = 1,
    };

    const rasterizer = vk.PipelineRasterizationStateCreateInfo{
        .depth_clamp_enable = .false,
        .depth_bias_clamp = 0,
        .depth_bias_constant_factor = 0,
        .depth_bias_slope_factor = 0,
        .rasterizer_discard_enable = .false,
        .polygon_mode = .fill,
        .cull_mode = .{ .back_bit = true },
        .front_face = .clockwise,
        .depth_bias_enable = .false,
        .line_width = 1,
    };

    const multisampling = vk.PipelineMultisampleStateCreateInfo{
        .rasterization_samples = .{ .@"1_bit" = true },
        .sample_shading_enable = .false,
        .min_sample_shading = 1,
        .alpha_to_coverage_enable = .false,
        .alpha_to_one_enable = .false,
    };
    const color_blend_attachment = vk.PipelineColorBlendAttachmentState{
        .blend_enable = .false,
        .color_write_mask = .{ .r_bit = true, .g_bit = true, .b_bit = true, .a_bit = true },
        .src_color_blend_factor = .one,
        .dst_color_blend_factor = .zero,
        .color_blend_op = .add,
        .src_alpha_blend_factor = .one,
        .dst_alpha_blend_factor = .zero,
        .alpha_blend_op = .add,
    };
    const color_blending = vk.PipelineColorBlendStateCreateInfo{
        .logic_op_enable = .false,
        .logic_op = .copy,
        .attachment_count = 1,
        .p_attachments = &.{color_blend_attachment},
        .blend_constants = .{ 0, 0, 0, 0 },
    };
    const pipeline_rendering_create_info = vk.PipelineRenderingCreateInfo{
        .color_attachment_count = 1,
        .p_color_attachment_formats = &.{self.swap_chain_image_format},
        .view_mask = 0,
        .depth_attachment_format = .undefined,
        .stencil_attachment_format = .undefined,
    };

    const pipeline_layout_info = vk.PipelineLayoutCreateInfo{};
    self.pipeline_layout = try self.device.createPipelineLayout(&pipeline_layout_info, null);
    const graphics_pipeline_create_info = vk.GraphicsPipelineCreateInfo{
        .stage_count = 2,
        .p_stages = @ptrCast(&shader_stages),
        .p_vertex_input_state = &vertex_input_info,
        .p_input_assembly_state = &input_assembly,
        .p_viewport_state = &viewport_state,
        .p_rasterization_state = &rasterizer,
        .p_multisample_state = &multisampling,
        .p_color_blend_state = &color_blending,
        .p_dynamic_state = &dynamic_state,
        .layout = self.pipeline_layout,
        .p_next = &pipeline_rendering_create_info,
        .subpass = 0,
        .base_pipeline_index = -1,
        .base_pipeline_handle = .null_handle,
    };

    _ = try self.device.createGraphicsPipelines(.null_handle, &.{graphics_pipeline_create_info}, null, (&self.graphics_pipeline)[0..1]);
}

fn createShaderModule(device: *Device) !vk.ShaderModule {
    const shader_spv align(@alignOf(u32)) = @embedFile("shader").*;
    const create_info: vk.ShaderModuleCreateInfo = .{
        .code_size = shader_spv.len,
        .p_code = @ptrCast(&shader_spv),
    };
    return try device.createShaderModule(&create_info, null);
}

fn createCommandPool(self: *App) !void {
    const pool_info = vk.CommandPoolCreateInfo{
        .flags = .{ .reset_command_buffer_bit = true },
        .queue_family_index = self.queue_index,
    };
    self.command_pool = try self.device.createCommandPool(&pool_info, null);
}

fn createCommandBuffers(self: *App, command_buffers: *[MAX_INFLIGHT_FRAMES]vk.CommandBuffer) !void {
    const alloc_info = vk.CommandBufferAllocateInfo{
        .command_pool = self.command_pool,
        .command_buffer_count = MAX_INFLIGHT_FRAMES,
        .level = .primary,
    };
    // var cmd_buf_array = try alloc.alloc(vk.CommandBuffer, MAX_INFLIGHT_FRAMES);

    // var command_buffers: [MAX_INFLIGHT_FRAMES]vk.CommandBuffer = undefined;
    // self.command_buffers = try std.ArrayList(vk.CommandBuffer).initCapacity(alloc, MAX_INFLIGHT_FRAMES);
    // app_log.debug("comm 0 {any}", .{cmd_buf_array});
    try self.device.allocateCommandBuffers(&alloc_info, @ptrCast(command_buffers));
    errdefer {
        app_log.debug("Failed to allocate command buffers, cleaning up", .{});
        self.device.freeCommandBuffers(self.command_pool, command_buffers);
    }
    // app_log.debug("comm 1 {any}", .{cmd_buf_array});
    // app_log.debug("self comm 1 {any}", .{self.command_buffers});
}

const Transition_Image_Layout_Params = struct {
    image_index: u32,
    old_layout: vk.ImageLayout,
    new_layout: vk.ImageLayout,
    src_access_mask: vk.AccessFlags2,
    dest_access_mask: vk.AccessFlags2,
    src_stage_mask: vk.PipelineStageFlags2,
    dest_stage_mask: vk.PipelineStageFlags2,
};
fn recordCommandBuffer(self: *App, command_buffer: vk.CommandBuffer, image_index: u32) !void {
    try self.device.beginCommandBuffer(command_buffer, &.{});
    var transition_image_layout_params = Transition_Image_Layout_Params{
        .image_index = image_index,
        .old_layout = .undefined,
        .new_layout = .color_attachment_optimal,
        .src_access_mask = .{},
        .dest_access_mask = .{ .color_attachment_write_bit = true },
        .src_stage_mask = .{ .color_attachment_output_bit = true },
        .dest_stage_mask = .{ .color_attachment_output_bit = true },
    };
    self.transitionImageLayout(transition_image_layout_params, command_buffer);
    const clear_color = vk.ClearValue{
        .color = .{ .float_32 = .{ 0, 0, 0, 1 } },
    };
    const attachment_info = vk.RenderingAttachmentInfo{
        .image_view = self.swap_chain_image_views[image_index],
        .image_layout = .color_attachment_optimal,
        .load_op = .clear,
        .store_op = .store,
        .clear_value = clear_color,
        .resolve_mode = .{},
        .resolve_image_layout = .undefined,
    };

    const rendering_info = vk.RenderingInfo{
        .render_area = .{ .offset = .{ .x = 0, .y = 0 }, .extent = self.swap_chain_extent },
        .layer_count = 1,
        .color_attachment_count = 1,
        .p_color_attachments = &.{attachment_info},
        .view_mask = 0,
    };
    self.device.cmdBeginRendering(command_buffer, &rendering_info);
    self.device.cmdBindPipeline(command_buffer, .graphics, self.graphics_pipeline);
    // app_log.debug("swap chain extent width {d}", .{self.swap_chain_extent.width});
    const view_port = vk.Viewport{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(self.swap_chain_extent.width),
        .height = @floatFromInt(self.swap_chain_extent.height),
        .min_depth = 0,
        .max_depth = 1,
    };
    // app_log.debug("View port width {d}", .{view_port.width});
    const scissor = vk.Rect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = self.swap_chain_extent,
    };
    self.device.cmdSetViewport(command_buffer, 0, &.{view_port});
    self.device.cmdSetScissor(command_buffer, 0, &.{scissor});
    self.device.cmdDraw(command_buffer, 3, 1, 0, 0);
    self.device.cmdEndRendering(command_buffer);
    transition_image_layout_params.old_layout = .color_attachment_optimal;
    transition_image_layout_params.new_layout = .present_src_khr;
    transition_image_layout_params.src_access_mask = .{ .color_attachment_write_bit = true };
    transition_image_layout_params.dest_access_mask = .{};
    transition_image_layout_params.dest_stage_mask = .{ .bottom_of_pipe_bit = true };
    self.transitionImageLayout(transition_image_layout_params, command_buffer);
    try self.device.endCommandBuffer(command_buffer);
}

fn transitionImageLayout(self: App, params: Transition_Image_Layout_Params, command_buffer: vk.CommandBuffer) void {
    const subresource_range = vk.ImageSubresourceRange{
        .aspect_mask = .{ .color_bit = true },
        .base_mip_level = 0,
        .level_count = 1,
        .base_array_layer = 0,
        .layer_count = 1,
    };
    const barrier = vk.ImageMemoryBarrier2{
        .src_stage_mask = params.src_stage_mask,
        .src_access_mask = params.src_access_mask,
        .dst_stage_mask = params.dest_stage_mask,
        .dst_access_mask = params.dest_access_mask,
        .old_layout = params.old_layout,
        .new_layout = params.new_layout,
        .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
        .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
        .image = self.swap_chain_images[params.image_index],
        .subresource_range = subresource_range,
    };
    const dependency_info = vk.DependencyInfo{
        .dependency_flags = .{},
        .image_memory_barrier_count = 1,
        .p_image_memory_barriers = &.{barrier},
    };
    self.device.cmdPipelineBarrier2(command_buffer, &dependency_info);
}
fn createSyncObjects(self: *App, alloc: Alloc) !struct { render_finished_semaphores: []vk.Semaphore, present_complete_semaphores: []vk.Semaphore, in_flight_fences: []vk.Fence } {
    // if (self.present_complete_semaphores.items.len != 0 or self.render_finished_semaphores.items.len != 0 or self.in_flight_fences.items.len != 0) {
    //     app_log.err("Present semaphore, render semaphore and inflightframe lists should be empty", .{});
    //     return error.NonEmptyList;
    // }
    var render_finished_semaphores = try std.ArrayList(vk.Semaphore).initCapacity(alloc, self.swap_chain_images.len);
    for (self.swap_chain_images) |_| {
        const render_semaphore = try self.device.createSemaphore(&.{}, null);
        try render_finished_semaphores.append(alloc, render_semaphore);
    }
    var present_complete_semaphores = try std.ArrayList(vk.Semaphore).initCapacity(alloc, MAX_INFLIGHT_FRAMES);
    var in_flight_fences = try std.ArrayList(vk.Fence).initCapacity(alloc, MAX_INFLIGHT_FRAMES);
    for (0..MAX_INFLIGHT_FRAMES) |_| {
        const present_semaphore = try self.device.createSemaphore(&.{}, null);
        const fence_create_info = vk.FenceCreateInfo{ .flags = .{ .signaled_bit = true } };
        const in_flight_fence = try self.device.createFence(&fence_create_info, null);
        try present_complete_semaphores.append(alloc, present_semaphore);
        try in_flight_fences.append(alloc, in_flight_fence);
    }
    return .{
        .in_flight_fences = try in_flight_fences.toOwnedSlice(alloc),
        .present_complete_semaphores = try present_complete_semaphores.toOwnedSlice(alloc),
        .render_finished_semaphores = try render_finished_semaphores.toOwnedSlice(alloc),
    };
}
fn drawFrame(
    self: *App,
    in_flight_fence: vk.Fence,
    present_compelete_semaphore: vk.Semaphore,
    render_finished_semaphore: vk.Semaphore,
    command_buffer: *vk.CommandBuffer,
) !void {
    _ = try self.device.waitForFences(&.{in_flight_fence}, .true, @intCast(std.math.maxInt(u64)));
    try self.device.resetFences(&.{in_flight_fence});
    const swap_chain_aquired_image = try self.device.acquireNextImageKHR(self.swap_chain, @intCast(std.math.maxInt(u64)), present_compelete_semaphore, .null_handle);
    try self.device.resetCommandBuffer(command_buffer.*, .{});
    try self.recordCommandBuffer(command_buffer.*, swap_chain_aquired_image.image_index);
    const wait_destination_stage_mask = vk.PipelineStageFlags{ .color_attachment_output_bit = true };
    const submit_info = vk.SubmitInfo{
        .wait_semaphore_count = 1,
        .p_wait_semaphores = &.{present_compelete_semaphore},
        .p_wait_dst_stage_mask = &.{wait_destination_stage_mask},
        .command_buffer_count = 1,
        .p_command_buffers = &.{command_buffer.*},
        .signal_semaphore_count = 1,
        .p_signal_semaphores = &.{render_finished_semaphore},
    };
    try self.device.queueSubmit(self.queue.handle, &.{submit_info}, in_flight_fence);
    const presentation_info = vk.PresentInfoKHR{
        .wait_semaphore_count = 1,
        .p_wait_semaphores = &.{render_finished_semaphore},
        .swapchain_count = 1,
        .p_swapchains = &.{self.swap_chain},
        .p_image_indices = &.{swap_chain_aquired_image.image_index},
    };
    _ = try self.device.queuePresentKHR(self.queue.handle, &presentation_info);
    try self.device.deviceWaitIdle();
    self.frame_index = (self.frame_index + 1) % MAX_INFLIGHT_FRAMES;
}
fn mainLoop(self: *App, alloc: Alloc) !void {
    var command_buffers: [MAX_INFLIGHT_FRAMES]vk.CommandBuffer = undefined;
    try self.createCommandBuffers(&command_buffers);
    const sync_objects = try self.createSyncObjects(alloc);
    defer {
        for (self.swap_chain_images, 0..) |_, i| {
            self.device.destroySemaphore(sync_objects.render_finished_semaphores[i], null);
        }
        for (0..MAX_INFLIGHT_FRAMES) |i| {
            self.device.destroyFence(sync_objects.in_flight_fences[i], null);
            self.device.destroySemaphore(sync_objects.present_complete_semaphores[i], null);
        }
    }
    while (!self.window.shouldClose()) {
        glfw.pollEvents();
        try self.drawFrame(
            sync_objects.in_flight_fences[self.frame_index],
            sync_objects.present_complete_semaphores[self.frame_index],
            sync_objects.render_finished_semaphores[self.frame_index],
            &command_buffers[self.frame_index],
        );
    }
}
fn cleanup(self: *App, alloc: Alloc) void {
    self.device.destroyCommandPool(self.command_pool, null);
    self.device.destroyPipeline(self.graphics_pipeline, null);
    self.device.destroyPipelineLayout(self.pipeline_layout, null);
    for (self.swap_chain_image_views) |image_view| {
        self.device.destroyImageView(image_view, null);
    }
    alloc.free(self.swap_chain_images);

    self.device.destroySwapchainKHR(self.swap_chain, null);
    self.device.destroyDevice(null);
    if (validationLayersEnabled) {
        self.instance.destroyDebugUtilsMessengerEXT(self.debug_messenger, null);
    }
    self.instance.destroySurfaceKHR(self.surface, null);
    self.instance.destroyInstance(null);
    self.window.destroy();
    glfw.terminate();
}

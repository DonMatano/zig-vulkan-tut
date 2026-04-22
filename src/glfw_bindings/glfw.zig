const std = @import("std");
const glfw = @import("c");
pub const Window = @import("window.zig");

pub const GLFW_Errors = error{
    InitFailed,
    NotInitialized,
    InvalidEnum,
};

pub const ClientApi = enum(i32) {
    glfw_no_api = 0,
};

const GLFW_log = std.log.scoped(.GLFW);

const Glfw = @This();

// Types

pub fn init() !void {
    const res = glfw.glfwInit();
    if (res != glfw.GLFW_TRUE) {
        logCErr(null);

        return GLFW_Errors.InitFailed;
    }
}

pub fn isVulkanSupported() !bool {
    const res = glfw.glfwVulkanSupported();
    if (res == glfw.GLFW_TRUE) {
        return true;
    } else if (res == glfw.GLFW_FALSE) {
        return false;
    }
    // Got Error
    logCErr(null);
    return GLFW_Errors.NotInitialized;
}

pub fn terminate() void {
    glfw.glfwTerminate();
}

pub fn logCErr(err: ?c_int) void {
    var c_err = err;
    if (c_err == null) {
        c_err = glfw.glfwGetError(null);
    }
    GLFW_log.err("Got err {d}", .{c_err.?});
}
pub fn setClientApi(value: ClientApi) !void {
    const tv: i32 = @intFromEnum(value);
    glfw.glfwWindowHint(glfw.GLFW_CLIENT_API, @intCast(tv));
    try checkWindowHintError();
}
pub fn isResizable(value: bool) !void {
    const v = if (value) glfw.GLFW_TRUE else glfw.GLFW_FALSE;
    glfw.glfwWindowHint(glfw.GLFW_RESIZABLE, v);
    try checkWindowHintError();
}

fn checkWindowHintError() !void {
    const c_err = glfw.glfwGetError(null);
    if (c_err != 0) {
        if (c_err == glfw.GLFW_NOT_INITIALIZED) {
            return GLFW_Errors.NotInitialized;
        }
        if (c_err == glfw.GLFW_INVALID_ENUM) {
            return GLFW_Errors.InvalidEnum;
        }
        logCErr(c_err);
        return error.GLFW_WindowHintError;
    }
}

pub fn pollEvents() void {
    glfw.glfwPollEvents();
}

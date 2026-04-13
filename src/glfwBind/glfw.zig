const std = @import("std");
const c_glfw = @cImport({
    @cDefine("GLFW_INCLUDE_NONE", {});
    @cInclude("GLFW/glfw3.h");
});

pub const GLFW_Errors = error{
    InitFailed,
    NotInitialized,
};

const GLFW_log = std.log.scoped(.GLFW);

// Types

pub fn init() !@This() {
    const res = c_glfw.glfwInit();
    if (res != c_glfw.GLFW_TRUE) {
        logCErr();

        return GLFW_Errors.InitFailed;
    }

    return @This();
}

pub fn isVulkanSupported() !bool {
    const res = c_glfw.glfwVulkanSupported();
    if (res == c_glfw.GLFW_TRUE) {
        return true;
    } else if (res == c_glfw.GLFW_FALSE) {
        return false;
    }
    // Got Error
    logCErr();
    return GLFW_Errors.NotInitialized;
}

pub fn terminate() void {
    c_glfw.glfwTerminate();
}

fn logCErr() void {
    const c_err = c_glfw.glfwGetError(c_glfw.NULL);
    GLFW_log.err("Got err {d}", .{c_err});
}

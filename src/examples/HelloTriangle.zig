pub fn run() !void {
    try initWindow();
    initVulkan();
    defer cleanup();
    mainLoop();
}

fn initWindow() !void {}
fn initVulkan() void {}
fn mainLoop() void {}
fn cleanup() void {}

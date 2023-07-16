const std = @import("std");
const testing = std.testing;

const glfw = @import("glfw");
const imgui = @import("cimgui");

const gl_log = std.log.scoped(.gl);

/// Default GLFW error handling callback
fn errorCallback(error_code: glfw.ErrorCode, description: [:0]const u8) void {
    gl_log.err("glfw error ({}): {s}\n", .{ error_code, description });
}

fn runGlk() !void {
    glfw.setErrorCallback(errorCallback);
    if (!glfw.init(.{})) {
        gl_log.err("failed to initialise glfw: {?s}", .{glfw.getErrorString()});
        return;
    }
    defer glfw.terminate();

    var window = glfw.Window.create(640, 480, "imglk", null, null, .{
        .context_version_major = 3,
        .context_version_minor = 2,
        .opengl_profile = .opengl_core_profile,
        .opengl_forward_compat = true,
        .context_debug = true,
    }) orelse {
        gl_log.err("failed to create window: {?s}", .{glfw.getErrorString()});
        std.process.exit(2);
    };
    defer window.destroy();

    // Set window as OpenGL current context.
    glfw.makeContextCurrent(window);

    const gui = imgui.Context.init();
    defer gui.deinit();

    const gui_io = gui.getIO();
    gui_io.setConfigFlag(.nav_enable_keyboard, true);
    gui_io.setConfigFlag(.nav_enable_gamepad, true);
    gui_io.setConfigFlag(.docking_enable, true);

    imgui.setCurrentContext(gui);

    try imgui.glfw.initForOpenGL(window.handle, true);
    try imgui.opengl3.init(.@"1.50");
}

// --- Entry point ---

pub export fn imglk_start() callconv(.C) void {
    runGlk() catch |err| {
        std.log.err("failed with error: {}", .{err});
        std.process.exit(1);
    };
}

const std = @import("std");
const testing = std.testing;

const glfw = @import("glfw");
const gl = @import("gl");
const imgui = @import("cimgui");

const gl_log = std.log.scoped(.gl);

const StreamSubsystem = @import("StreamSubsystem.zig");

comptime {
    std.testing.refAllDecls(StreamSubsystem);
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
        .context_version_minor = 3,
        .opengl_profile = .opengl_core_profile,
        .opengl_forward_compat = true,
        .context_debug = true,
    }) orelse {
        gl_log.err("failed to create window: {?s}", .{glfw.getErrorString()});
        std.process.exit(2);
    };
    defer window.destroy();

    // TODO: set up input callbacks here

    // Set window as OpenGL current context.
    glfw.makeContextCurrent(window);

    // Load OpenGL function pointers.
    try gl.loadExtensions({}, getProcAddress);

    const gui = imgui.Context.init();
    defer gui.deinit();

    const gui_io = gui.getIO();
    gui_io.setConfigFlag(.nav_enable_keyboard, true);
    gui_io.setConfigFlag(.nav_enable_gamepad, true);
    gui_io.setConfigFlag(.docking_enable, true);

    imgui.setCurrentContext(gui);

    try imgui.glfw.initForOpenGL(window.handle, true);
    defer imgui.glfw.deinit();
    try imgui.opengl3.init(.@"3.30");
    defer imgui.opengl3.deinit();

    glk_main();

    var show_demo_window = true;
    while (!window.shouldClose()) {
        glfw.pollEvents();

        imgui.opengl3.newFrame();
        imgui.glfw.newFrame();
        imgui.newFrame();

        if (show_demo_window) imgui.showDemoWindow(&show_demo_window);

        {
            _ = imgui.begin("Hello, world!", null, .{});
            defer imgui.end();

            imgui.text("This is some text.");
            _ = imgui.checkbox("Show demo window", &show_demo_window);
        }

        imgui.render();

        glfw.makeContextCurrent(window);
        gl.viewport(
            0,
            0,
            @intFromFloat(gui_io.ptr.DisplaySize.x),
            @intFromFloat(gui_io.ptr.DisplaySize.y),
        );
        gl.clearColor(0.2, 0.3, 0.3, 1.0);
        gl.clear(.{ .color = true });
        imgui.opengl3.renderDrawData(imgui.getDrawData());

        window.swapBuffers();
    }
}

// --- Callbacks ---

pub extern fn glk_main() void;

/// Default GLFW error handling callback
fn errorCallback(error_code: glfw.ErrorCode, description: [:0]const u8) void {
    gl_log.err("glfw error ({}): {s}\n", .{ error_code, description });
}

/// GL function loader
fn getProcAddress(_: void, proc_name: [:0]const u8) ?*const anyopaque {
    return @as(?*const anyopaque, @ptrCast(glfw.getProcAddress(proc_name.ptr)));
}

// --- Entry point ---

pub export fn imglk_start() callconv(.C) void {
    runGlk() catch |err| {
        std.log.err("failed with error: {}", .{err});
        std.process.exit(1);
    };
}

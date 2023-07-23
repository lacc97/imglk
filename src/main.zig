const std = @import("std");
const testing = std.testing;

const core = @import("core.zig");
const StreamSubsystem = @import("StreamSubsystem.zig");
const FileRefSubsystem = @import("FileRefSubsystem.zig");
const WindowSubsystem = @import("WindowSubsystem.zig");

const glfw = @import("glfw");
const gl = @import("gl");
const imgui = @import("cimgui");

const gl_log = std.log.scoped(.gl);

comptime {
    std.testing.refAllDecls(@import("latin1.zig"));
}

fn runGlk() !void {
    try FileRefSubsystem.initSubsystem(std.heap.c_allocator);
    errdefer FileRefSubsystem.deinitSubsystem();

    try StreamSubsystem.initSubsystem(std.heap.c_allocator);
    errdefer StreamSubsystem.deinitSubsystem();

    try WindowSubsystem.initSubsystem(std.heap.c_allocator);
    errdefer WindowSubsystem.deinitSubsystem();

    glk_main();
    glk_exit();

    // var show_demo_window = true;
    // while (!window.shouldClose()) {
    //     glfw.pollEvents();

    //     imgui.opengl3.newFrame();
    //     imgui.glfw.newFrame();
    //     imgui.newFrame();

    //     if (show_demo_window) imgui.showDemoWindow(&show_demo_window);

    //     {
    //         _ = imgui.begin("Hello, world!", null, .{});
    //         defer imgui.end();

    //         imgui.text("This is some text.");
    //         _ = imgui.checkbox("Show demo window", &show_demo_window);
    //     }

    //     imgui.render();

    //     glfw.makeContextCurrent(window);
    //     gl.viewport(
    //         0,
    //         0,
    //         @intFromFloat(gui_io.ptr.DisplaySize.x),
    //         @intFromFloat(gui_io.ptr.DisplaySize.y),
    //     );
    //     gl.clearColor(0.2, 0.3, 0.3, 1.0);
    //     gl.clear(.{ .color = true });
    //     imgui.opengl3.renderDrawData(imgui.getDrawData());

    //     window.swapBuffers();
    // }
}

// --- Callbacks ---

pub extern fn glk_main() void;

// --- Exported ---

pub export fn glk_exit() noreturn {
    std.process.exit(0);
}

// --- Entry point ---

pub export fn imglk_start() callconv(.C) void {
    runGlk() catch |err| {
        std.log.err("failed with error: {}", .{err});
        std.process.exit(1);
    };
}

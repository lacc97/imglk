const std = @import("std");
const core = @import("core.zig");

const glfw = @import("glfw");
const gl = @import("gl");
const imgui = @import("cimgui");

const stream_sys = @import("StreamSubsystem.zig");

const ObjectPool = @import("object_pool.zig").ObjectPool;
const Stream = stream_sys.Stream;
const strid_t = stream_sys.strid_t;

const glk_log = std.log.scoped(.glk);

// --- Globals ---

var main_window: glfw.Window = undefined;
var main_ui: imgui.Context = undefined;

var pool: ObjectPool(Window) = undefined;

// --- Public functions ---

pub fn initSubsystem(alloc: std.mem.Allocator) !void {
    glfw.setErrorCallback(errorCallback);
    if (!glfw.init(.{})) {
        glk_log.err("failed to initialise glfw: {?s}", .{glfw.getErrorString()});
        return Error.GLFW;
    }
    errdefer glfw.terminate();

    main_window = glfw.Window.create(640, 480, "imglk", null, null, .{
        .context_version_major = 3,
        .context_version_minor = 3,
        .opengl_profile = .opengl_core_profile,
        .opengl_forward_compat = true,
        .context_debug = true,
    }) orelse {
        glk_log.err("failed to create window: {?s}", .{glfw.getErrorString()});
        return Error.GLFW;
    };
    errdefer main_window.destroy();

    glfw.makeContextCurrent(main_window);
    try gl.loadExtensions({}, getProcAddress);

    main_ui = imgui.Context.init();
    errdefer main_ui.deinit();

    const gui_io = main_ui.getIO();
    gui_io.setConfigFlag(.nav_enable_keyboard, true);
    gui_io.setConfigFlag(.nav_enable_gamepad, true);
    gui_io.setConfigFlag(.docking_enable, true);

    imgui.setCurrentContext(main_ui);
    errdefer imgui.setCurrentContext(null);

    try imgui.glfw.initForOpenGL(main_window.handle, true);
    errdefer imgui.glfw.deinit();
    try imgui.opengl3.init(.@"3.30");
    errdefer imgui.opengl3.deinit();

    pool = ObjectPool(Window).init(alloc);
}

pub fn deinitSubsystem() void {
    pool.deinit();
    imgui.opengl3.deinit();
    imgui.glfw.deinit();
    imgui.setCurrentContext(null);
    main_ui.deinit();
    main_window.destroy();
    glfw.terminate();
}

// --- Public types ---

pub const Error = error{
    GLFW,
};

pub const Window = struct {
    // --- Fields ---

    rock: u32,
    str: *Stream,
    data: union(enum) {
        nil: void,
    },

    // --- Public functions ---

    pub fn deinit(
        self: *@This(),
        result: ?*stream_result_t,
    ) void {
        stream_sys.imglk_window_stream_close(self.str, result);
    }
};

// --- Private functions ---

fn getNextWindow(
    win: ?*Window,
    rockptr: ?*u32,
) ?*Window {
    const next_win = pool.next(win) orelse return null;
    if (rockptr) |r| r.* = next_win.rock;
    return next_win;
}

fn closeWindow(
    win: *Window,
    result: ?*stream_result_t,
) void {
    win.deinit(result);
    pool.dealloc(win);
}

// -- Callbacks

/// Default GLFW error handling callback
fn errorCallback(error_code: glfw.ErrorCode, description: [:0]const u8) void {
    glk_log.warn("glfw error ({}): {s}\n", .{ error_code, description });
}

/// GL function loader
fn getProcAddress(_: void, proc_name: [:0]const u8) ?*const anyopaque {
    return @as(?*const anyopaque, @ptrCast(glfw.getProcAddress(proc_name.ptr)));
}

// --- Exported ---

pub const winid_t = ?*Window;

const stream_result_t = core.c_glk.stream_result_t;

pub export fn glk_window_get_rock(
    win: winid_t,
) callconv(.C) u32 {
    std.debug.assert(win != null);

    return win.?.rock;
}

pub export fn glk_window_iterate(
    win: winid_t,
    rockptr: ?*u32,
) callconv(.C) winid_t {
    return getNextWindow(win, rockptr);
}

pub export fn glk_set_window(
    win: winid_t,
) void {
    stream_sys.glk_stream_set_current(if (win) |w| w.str else null);
}

pub export fn glk_window_open(
    split: winid_t,
    method: u32,
    size: u32,
    wintype: u32,
    rock: u32,
) winid_t {
    _ = rock;
    _ = wintype;
    _ = size;
    _ = method;
    _ = split;
    return null;
}

pub export fn glk_window_close(
    win: winid_t,
    result: ?*stream_result_t,
) void {
    if (win == null) return;
    closeWindow(win.?, result);
}

pub export fn glk_window_get_size(
    win: winid_t,
    widthptr: ?*u32,
    heightptr: ?*u32,
) void {
    std.debug.assert(win != null);

    _ = heightptr;
    _ = widthptr;

    // TODO: stub
}

pub export fn glk_window_set_echo_stream(
    win: winid_t,
    str: strid_t,
) void {
    std.debug.assert(win != null);

    _ = str;

    // TODO: stub
}

pub export fn glk_window_clear(
    win: winid_t,
) void {
    std.debug.assert(win != null);

    // TODO: stub
}

pub export fn glk_window_move_cursor(
    win: winid_t,
    xpos: u32,
    ypos: u32,
) void {
    std.debug.assert(win != null);

    _ = ypos;
    _ = xpos;
}

pub export fn glk_request_line_event(
    win: winid_t,
    buf: ?[*]u8,
    buflen: u32,
    initlen: u32,
) void {
    std.debug.assert(win != null);
    std.debug.assert(buf != null);
    std.debug.assert(buflen > 0);
    std.debug.assert(initlen <= buflen);

    // TODO: stub
}

pub export fn glk_request_line_event_uni(
    win: winid_t,
    buf_uni: ?[*]u32,
    buflen: u32,
    initlen: u32,
) void {
    std.debug.assert(win != null);
    std.debug.assert(buf_uni != null);
    std.debug.assert(buflen > 0);
    std.debug.assert(initlen <= buflen);

    // TODO: stub
}

// TODO: this should go in a separate file

pub const event_t = extern struct {
    type: u32,
    win: winid_t,
    val1: u32,
    val2: u32,
};

pub export fn glk_select(
    event: ?*event_t,
) void {
    std.debug.assert(event != null);

    const e = event.?;
    if (main_window.shouldClose()) glk_exit();

    glfw.pollEvents();

    imgui.opengl3.newFrame();
    imgui.glfw.newFrame();
    imgui.newFrame();

    imgui.showDemoWindow(null);
    imgui.render();

    const io = main_ui.getIO();

    glfw.makeContextCurrent(main_window);
    gl.viewport(
        0,
        0,
        @intFromFloat(io.ptr.DisplaySize.x),
        @intFromFloat(io.ptr.DisplaySize.y),
    );
    gl.clearColor(0.2, 0.3, 0.3, 1.0);
    gl.clear(.{ .color = true });
    imgui.opengl3.renderDrawData(imgui.getDrawData());

    main_window.swapBuffers();

    e.type = 0;
}

extern fn glk_exit() void;

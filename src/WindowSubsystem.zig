const std = @import("std");
const assert = std.debug.assert;
const core = @import("core.zig");

const glfw = @import("glfw");
const gl = @import("gl");
const imgui = @import("cimgui");

const unicode = @import("unicode.zig");
const stream_sys = @import("StreamSubsystem.zig");

const ObjectPool = @import("object_pool.zig").ObjectPool;
const Stream = stream_sys.Stream;
const strid_t = stream_sys.strid_t;

const glk_log = std.log.scoped(.glk);

// --- Globals ---

var main_window: glfw.Window = undefined;
var main_ui: imgui.Context = undefined;

var pool: ObjectPool(Window) = undefined;

var root: winid_t = null;

var window_styles: std.EnumArray(WindowKind, std.EnumArray(Style, StyleDescriptor)) = blk: {
    var ws = std.EnumArray(WindowKind, std.EnumArray(Style, StyleDescriptor)).initUndefined();

    ws.set(.text_grid, .{});
    ws.set(.text_buffer, .{});

    // The other window kinds do not use styles.

    break :blk ws;
};

// --- Public functions ---

pub fn initSubsystem(alloc: std.mem.Allocator) !void {
    glfw.setErrorCallback(errorCallback);
    if (!glfw.init(.{ .platform = .wayland })) {
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
    InvalidArgument,
};

pub const WindowKind = enum(u3) {
    blank = core.c_glk.wintype_Blank,
    graphics = core.c_glk.wintype_Graphics,
    pair = core.c_glk.wintype_Pair,
    text_buffer = core.c_glk.wintype_TextBuffer,
    text_grid = core.c_glk.wintype_TextGrid,
};

pub const WindowMethod = packed struct {
    direction: enum(u4) {
        left = core.c_glk.winmethod_Left,
        right = core.c_glk.winmethod_Right,
        above = core.c_glk.winmethod_Above,
        below = core.c_glk.winmethod_Below,
    },
    division: enum(u4) {
        fixed = core.c_glk.winmethod_Fixed >> 4,
        proportional = core.c_glk.winmethod_Proportional >> 4,
    },
    border: enum(u1) {
        border = core.c_glk.winmethod_Border >> 8,
        no_border = core.c_glk.winmethod_NoBorder >> 8,
    },

    pub fn from(c: u32) WindowMethod {
        return .{
            .direction = @enumFromInt(@as(u4, @truncate((c & core.c_glk.winmethod_DirMask) >> 0))),
            .division = @enumFromInt(@as(u4, @truncate((c & core.c_glk.winmethod_DivisionMask) >> 4))),
            .border = @enumFromInt(@as(u1, @truncate((c & core.c_glk.winmethod_BorderMask) >> 8))),
        };
    }
};

pub const Style = enum(u32) {
    normal = core.c_glk.style_Normal,
    emphasized = core.c_glk.style_Emphasized,
    preformatted = core.c_glk.style_Preformatted,
    header = core.c_glk.style_Header,
    subheader = core.c_glk.style_Subheader,
    alert = core.c_glk.style_Alert,
    note = core.c_glk.style_Note,
    block_quote = core.c_glk.style_BlockQuote,
    input = core.c_glk.style_Input,
    user1 = core.c_glk.style_User1,
    user2 = core.c_glk.style_User2,
};

pub const StyleDescriptor = struct {};

pub const WindowData = struct {
    // --- Fields ---

    allocator: std.mem.Allocator,
    // arena: std.heap.ArenaAllocator,
    vtable: VTable,
    w: union(WindowKind) {
        blank: void,
        graphics: void,
        pair: void,
        text_buffer: std.ArrayListUnmanaged(u8),
        text_grid: void,
    },

    // --- Globals ---

    const text_buffer_vtable: VTable = .{
        .clear = tbClear,
        .put_text = tbPutText,
        .draw = tbDraw,
    };

    // --- Public types ---

    pub const Error = std.mem.Allocator.Error;

    // --- Public functions ---

    pub fn init(
        allocator: std.mem.Allocator,
        kind: WindowKind,
    ) @This() {
        return .{
            .allocator = allocator,
            .vtable = switch (kind) {
                .text_buffer => text_buffer_vtable,
                else => .{},
            },
            .w = switch (kind) {
                .text_buffer => .{ .text_buffer = .{} },
                .blank => .{ .blank = {} },
                .graphics => .{ .graphics = {} },
                .pair => .{ .pair = {} },
                .text_grid => .{ .text_grid = {} },
            },
        };
    }

    pub fn deinit(self: *@This()) void {
        switch (self.w) {
            .text_buffer => |*tb| tb.deinit(self.allocator),
            else => {},
        }
    }

    pub fn clear(
        self: *@This(),
    ) WindowData.Error!void {
        return self.vtable.clear(self);
    }

    pub fn setStyle(
        self: *@This(),
        style: Style,
    ) WindowData.Error!void {
        return self.vtable.set_style(self, style);
    }

    pub fn putText(
        self: *@This(),
        codepoints: []const u32,
    ) WindowData.Error!void {
        return self.vtable.put_text(self, codepoints);
    }

    pub fn draw(
        self: *@This(),
        avail_region: imgui.Vec2,
    ) WindowData.Error!void {
        var name_buf: [64]u8 = undefined;
        const name = std.fmt.bufPrintZ(&name_buf, "#{*}", .{self}) catch unreachable;

        _ = imgui.beginChild(
            name,
            avail_region,
            true, // for now
            .{},
        );
        defer imgui.endChild();
        return try self.vtable.draw(self);
    }

    // --- Private types ---

    const VTable = struct {
        clear: *const fn (self: *WindowData) WindowData.Error!void = noopClear,
        set_style: *const fn (self: *WindowData, style: Style) WindowData.Error!void = noopSetStyle,
        put_text: *const fn (self: *WindowData, codepoints: []const u32) WindowData.Error!void = noopPutText,

        draw: *const fn (self: *WindowData) WindowData.Error!void = noopDraw,
    };

    // --- Private functions ---

    // -- Blank

    fn noopClear(
        self: *@This(),
    ) @This().Error!void {
        _ = self;
    }

    fn noopSetStyle(
        self: *@This(),
        style: Style,
    ) @This().Error!void {
        _ = style;
        _ = self;
    }

    fn noopPutText(
        self: *@This(),
        codepoints: []const u32,
    ) @This().Error!void {
        _ = codepoints;
        _ = self;
    }

    fn noopDraw(
        self: *@This(),
    ) WindowData.Error!void {
        _ = self;
    }

    // -- Text buffer

    fn tbClear(
        self: *@This(),
    ) @This().Error!void {
        assert(self.w == .text_buffer);

        self.w.text_buffer.clearRetainingCapacity();
    }

    fn tbPutText(
        self: *@This(),
        codepoints: []const u32,
    ) @This().Error!void {
        assert(self.w == .text_buffer);

        const tb = &self.w.text_buffer;

        const old_text_size = blk: {
            var size = tb.items.len;
            // Don't count the null termintator.
            if (size > 0) size -= 1;
            break :blk size;
        };
        const new_text_size = old_text_size + 4 * codepoints.len;

        // Add one to count the null terminator.
        try tb.ensureTotalCapacity(self.allocator, new_text_size + 1);

        // We have reserved enough capacity in the previous line.
        assert(tb.capacity >= new_text_size);
        tb.items.len = new_text_size;

        // Encode utf8.
        const actual_new_text_size = unicode.codepoint.utf8EncodeSlice(
            codepoints,
            tb.items[old_text_size..],
        ).len + old_text_size;

        // Write null terminator.
        tb.items[actual_new_text_size] = 0;

        // Resize to correct size.
        assert(tb.capacity >= actual_new_text_size + 1);
        tb.items.len = actual_new_text_size + 1;
    }

    fn tbDraw(
        self: *@This(),
    ) WindowData.Error!void {
        assert(self.w == .text_buffer);

        const text = self.w.text_buffer.items;
        if (text.len > 0) imgui.textWrapped(text[0..(text.len - 1) :0]);
    }
};

pub const Window = struct {
    // --- Fields ---

    rock: u32,
    str: *Stream,
    data: WindowData,

    // --- Public functions ---

    pub fn deinit(
        self: *@This(),
        result: ?*stream_result_t,
    ) void {
        stream_sys.closeWindowStream(self.str, result);
        self.data.deinit();
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

fn openWindow(
    split: ?*Window,
    size: u32,
    kind: WindowKind,
    method: ?WindowMethod,
    rock: u32,
) !*Window {
    _ = size;
    if ((split == null or method == null) and root != null) return Error.InvalidArgument;

    const win = try pool.alloc();
    errdefer pool.dealloc(win);

    win.* = Window{
        .rock = rock,
        .str = undefined,
        .data = WindowData.init(pool.arena.child_allocator, kind),
    };
    win.str = try stream_sys.openWindowStream(&win.data);

    if (root == null) root = win;
    return win;
}

fn closeWindow(
    win: *Window,
    result: ?*stream_result_t,
) void {
    if (root == win) root = null;
    win.deinit(result);
    pool.dealloc(win);
}

fn drawUi() !void {
    imgui.setNextWindowPos(.{ .x = 0, .y = 0 }, .always);
    imgui.setNextWindowSize(imgui.getIO().ptr.DisplaySize, .always);
    _ = imgui.begin("root", null, .{
        .no_title_bar = true,
        .no_resize = true,
    });
    defer imgui.end();

    if (root) |w| {
        try w.data.draw(imgui.getContentRegionAvail());
    }
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
    if (root != null) return null;
    return openWindow(
        split,
        size,
        @enumFromInt(wintype),
        if (method != 0) WindowMethod.from(method) else null,
        rock,
    ) catch |err| {
        glk_log.warn("failed to open window: {}", .{err});
        return null;
    };
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
    _ = str;
    std.debug.assert(win != null);

    const w = win.?;
    _ = w;
}

pub export fn glk_window_clear(
    win: winid_t,
) void {
    std.debug.assert(win != null);

    const w = win.?;
    w.data.clear() catch |err| {
        glk_log.warn("failed to clear: {}", .{err});
    };
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

    drawUi() catch {
        glk_log.err("error drawing ui", .{});
    };
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

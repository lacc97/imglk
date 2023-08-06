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

var main_arena: std.heap.ArenaAllocator = undefined;

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

    main_arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
}

pub fn deinitSubsystem() void {
    main_arena.deinit();
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
    vtable: VTable,
    parent: ?*WindowData,
    cached_ui_size: imgui.Vec2,
    cached_glk_size: GlkSize,
    w: union(WindowKind) {
        blank: void,
        graphics: void,
        pair: PairWindow,
        text_buffer: std.ArrayListUnmanaged(u8),
        text_grid: struct {
            cursor: struct { x: u32, y: u32 } = .{ .x = 0, .y = 0 },
            grid: std.ArrayListUnmanaged(u32) = .{},
        },
    },

    // --- Globals ---

    const pair_vtable: VTable = .{
        .draw = pDraw,
    };
    const text_buffer_vtable: VTable = .{
        .clear = tbClear,
        .put_text = tbPutText,
        .draw = tbDraw,
    };
    const text_grid_vtable: VTable = .{
        .clear = tgClear,
        .put_text = tgPutText,
        .move_cursor = tgMoveCursor,
        .draw = tgDraw,
    };

    // --- Public types ---

    pub const Error = std.mem.Allocator.Error;

    pub const GlkSize = struct { w: u32, h: u32 };

    // --- Public functions ---

    /// Not to be used for pair windows, use initPair() instead.
    pub fn init(
        allocator: std.mem.Allocator,
        parent: ?*WindowData,
        kind: WindowKind,
    ) @This() {
        assert(parent == null or parent.?.w == .pair);
        assert(kind != .pair);

        return .{
            .allocator = allocator,
            .vtable = switch (kind) {
                .text_buffer => text_buffer_vtable,
                .text_grid => text_grid_vtable,
                .blank, .graphics => .{},
                .pair => unreachable,
            },
            .parent = parent,
            .cached_ui_size = .{ .x = 0, .y = 0 },
            .cached_glk_size = .{ .w = 0, .h = 0 },
            .w = switch (kind) {
                .text_buffer => .{ .text_buffer = .{} },
                .blank => .{ .blank = {} },
                .graphics => .{ .graphics = {} },
                .pair => unreachable,
                .text_grid => .{ .text_grid = .{} },
            },
        };
    }

    pub fn initPair(
        allocator: std.mem.Allocator,
        parent: ?*WindowData,
        key: ?*WindowData,
        method: WindowMethod,
        size: u32,
        first: *WindowData,
        second: *WindowData,
    ) WindowData {
        assert(parent == null or parent.?.w == .pair);

        return .{
            .allocator = allocator,
            .vtable = pair_vtable,
            .parent = parent,
            .cached_ui_size = .{ .x = 0, .y = 0 },
            .cached_glk_size = .{ .w = 0, .h = 0 },
            .w = .{
                .pair = .{
                    .key = key,
                    .method = method,
                    .size = size,
                    .first = first,
                    .second = second,
                },
            },
        };
    }

    pub fn deinit(
        self: *@This(),
    ) void {
        var ancestor = self.parent;
        while (ancestor) |a| : (ancestor = a.parent) {
            assert(a.w == .pair);
            if (a.w.pair.key == self) a.w.pair.key = null;
        }

        switch (self.w) {
            .text_buffer => |*tb| tb.deinit(self.allocator),
            .blank, .graphics, .pair, .text_grid => {},
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
        with_border: bool,
    ) WindowData.Error!void {
        var name_buf: [64]u8 = undefined;
        const name = std.fmt.bufPrintZ(&name_buf, "#{*}", .{self}) catch unreachable;

        _ = imgui.beginChild(
            name,
            avail_region,
            with_border,
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
        move_cursor: *const fn (self: *WindowData, x: u32, y: u32) WindowData.Error!void = noopMoveCursor,

        draw: *const fn (self: *WindowData) WindowData.Error!void = noopDraw,
    };

    const PairWindow = struct {
        // --- Fields ---
        key: ?*WindowData,
        method: WindowMethod,
        size: u32,

        first: *WindowData,
        second: *WindowData,
    };

    // --- Private functions ---

    fn uiSizeToTextExtent(ig_size: imgui.Vec2) GlkSize {
        // TODO: margins
        const scale = uiZeroCharSize(); // TODO: cache this?
        const txt_size: imgui.Vec2 = .{
            .x = ig_size.x / scale.x,
            .y = ig_size.y / scale.y,
        };
        return .{
            .w = @intFromFloat(@floor(txt_size.x)),
            .h = @intFromFloat(@floor(txt_size.y)),
        };
    }
    fn uiTextExtentToSize(txt_size: GlkSize) imgui.Vec2 {
        // TODO: margins
        const scale = uiZeroCharSize(); // TODO: cache this?
        return .{
            .x = scale.x * @as(f32, @floatFromInt(txt_size.w)),
            .y = scale.y * @as(f32, @floatFromInt(txt_size.h)),
        };
    }

    fn uiZeroCharSize() imgui.Vec2 {
        const font = imgui.getFont();
        return font.calcTextSize(
            font.ptr.FontSize,
            std.math.floatMax(f32),
            0.0,
            "0",
            null,
        );
    }

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

    fn noopMoveCursor(
        self: *@This(),
        x: u32,
        y: u32,
    ) WindowData.Error!void {
        _ = y;
        _ = x;
        _ = self;
    }

    fn noopDraw(
        self: *@This(),
    ) WindowData.Error!void {
        self.cached_ui_size = imgui.getContentRegionAvail();
        self.cached_glk_size = .{ .w = 0, .h = 0 };
    }

    // -- Text grid

    fn tgIndex(size: GlkSize, x: u32, y: u32) u32 {
        return size.w * y + x;
    }

    fn tgClear(
        self: *@This(),
    ) WindowData.Error!void {
        assert(self.w == .text_grid);

        const tg = &self.w.text_grid;
        tg.cursor = .{ .x = 0, .y = 0 };
        @memset(tg.grid.items, ' ');
    }

    fn tgPutText(
        self: *@This(),
        codepoints: []const u32,
    ) WindowData.Error!void {
        assert(self.w == .text_grid);

        const tg = &self.w.text_grid;
        const tg_size = self.cached_glk_size;

        if (tg_size.w == 0 or tg_size.h == 0) return;

        assert(tg_size.w * tg_size.h == tg.grid.items.len);
        for (codepoints) |cp| {
            if (tg.cursor.x >= tg_size.w) {
                tg.cursor.x = 0;
                tg.cursor.y += 1;
            }
            if (tg.cursor.y >= tg_size.h) break;
            if (cp == '\n') {
                tg.cursor.x = 0;
                tg.cursor.y += 1;
                continue;
            }

            tg.grid.items[tgIndex(self.cached_glk_size, tg.cursor.x, tg.cursor.y)] = cp;

            tg.cursor.x += 1;
        }
    }

    fn tgMoveCursor(
        self: *@This(),
        x: u32,
        y: u32,
    ) WindowData.Error!void {
        assert(self.w == .text_grid);

        self.w.text_grid.cursor = .{ .x = x, .y = y };
    }

    fn tgDraw(
        self: *@This(),
    ) WindowData.Error!void {
        assert(self.w == .text_grid);

        const tg = &self.w.text_grid;

        self.cached_ui_size = imgui.getContentRegionAvail();
        const tg_size = uiSizeToTextExtent(self.cached_ui_size);

        if (!std.meta.eql(tg_size, self.cached_glk_size)) {
            // We have resized.

            if (tg_size.w == 0 or tg_size.h == 0) {
                tg.grid.clearRetainingCapacity();
                return;
            }

            const tmp = try main_arena.allocator().alloc(u32, tg_size.w * tg_size.h);
            @memset(tmp, ' ');

            for (0..@min(tg_size.h, self.cached_glk_size.h)) |y| {
                for (0..@min(tg_size.w, self.cached_glk_size.w)) |x| {
                    const src_index = tgIndex(
                        self.cached_glk_size,
                        @intCast(x),
                        @intCast(y),
                    );
                    const dst_index = tgIndex(
                        tg_size,
                        @intCast(x),
                        @intCast(y),
                    );
                    tmp[dst_index] = tg.grid.items[src_index];
                }
            }

            try tg.grid.resize(std.heap.c_allocator, tmp.len);
            @memcpy(tg.grid.items, tmp);

            self.cached_glk_size = tg_size;
        }

        // Each codepoint maps to at most 4 bytes, so this won't overflow the buffer size. We add
        // height to the length so we can put newlines in there.
        const txt = try main_arena.allocator().alloc(u8, 4 * (tg.grid.items.len + tg_size.h));
        var i: usize = 0;
        for (0..tg_size.h) |y| {
            for (tg.grid.items[(y * tg_size.w)..][0..tg_size.w]) |cp| {
                var utf8: [4]u8 = undefined;
                const utf8_len = unicode.codepoint.utf8Encode(cp, &utf8) catch err: {
                    utf8[0] = '?';
                    break :err 1;
                };
                @memcpy(txt[i..][0..utf8_len], utf8[0..utf8_len]);
                i += utf8_len;
            }
            txt[i] = '\n';
            i += 1;
        }
        imgui.text(txt[0..i]);
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

        const old_text_size = tb.items.len;
        const new_text_size = old_text_size + 4 * codepoints.len;

        try tb.ensureTotalCapacity(self.allocator, new_text_size);

        // We have reserved enough capacity in the previous line.
        assert(tb.capacity >= new_text_size);
        tb.items.len = new_text_size;

        // Encode utf8.
        const actual_new_text_size = unicode.codepoint.utf8EncodeSlice(
            codepoints,
            tb.items[old_text_size..],
        ).len + old_text_size;

        // Resize to correct size.
        assert(tb.capacity >= actual_new_text_size);
        tb.items.len = actual_new_text_size;
    }

    fn tbDraw(
        self: *@This(),
    ) WindowData.Error!void {
        assert(self.w == .text_buffer);

        self.cached_ui_size = imgui.getContentRegionAvail();
        self.cached_glk_size = uiSizeToTextExtent(self.cached_ui_size);

        const text = self.w.text_buffer.items;
        if (text.len > 0) imgui.textWrapped(text);
    }

    // -- Pair

    fn pDraw(
        self: *@This(),
    ) WindowData.Error!void {
        assert(self.w == .pair);

        self.cached_ui_size = imgui.getContentRegionAvail();
        self.cached_glk_size = .{ .w = 0, .h = 0 };

        const p = &self.w.pair;

        const with_border: bool = p.method.border == .border;
        const border_compensation: imgui.Vec2 = blk: {
            if (!with_border) break :blk .{ .x = 0, .y = 0 };

            const style = imgui.getStyle();
            break :blk switch (p.method.direction) {
                .left, .right => .{ .x = style.ItemSpacing.x / 2, .y = 0 },
                .above, .below => .{ .x = 0, .y = style.ItemSpacing.y / 2 },
            };
        };

        // TODO: implement actual logic, for now it just splits it down the middle
        const child: [2]*WindowData = switch (p.method.direction) {
            .left, .above => .{ p.first, p.second },
            .right, .below => .{ p.second, p.first },
        };

        // TODO: pull this into separate functions?
        const child_region: [2]imgui.Vec2 = blk: {
            var region: [2]imgui.Vec2 = undefined;
            switch (p.method.division) {
                .proportional => {
                    // The fraction as given by the single size parameter value.
                    const primary_frac = @as(f32, @floatFromInt(p.size)) / 100.0;

                    // The fraction of the total available region along the primary direction per child.
                    const primary_dir_frac: [2]f32 = switch (p.method.direction) {
                        .left, .above => .{ primary_frac, 1 - primary_frac },
                        .right, .below => .{ 1 - primary_frac, primary_frac },
                    };

                    // The scaling factor for each coordinate for each child.
                    const factor: [2]imgui.Vec2 = blk_factor: {
                        var factor: [2]imgui.Vec2 = undefined;
                        switch (p.method.direction) {
                            .left, .right => for (&factor, primary_dir_frac) |*f, dir_frac| {
                                f.* = .{ .x = dir_frac, .y = 1 };
                            },
                            .above, .below => for (&factor, primary_dir_frac) |*f, dir_frac| {
                                f.* = .{ .x = 1, .y = dir_frac };
                            },
                        }
                        break :blk_factor factor;
                    };

                    for (&region, factor) |*reg, f| {
                        reg.* = .{
                            .x = self.cached_ui_size.x * f.x - border_compensation.x,
                            .y = self.cached_ui_size.y * f.y - border_compensation.y,
                        };
                    }
                },
                .fixed => {
                    if (p.key == null or p.size == 0) break :blk .{ .{ .x = 0, .y = 0 }, self.cached_ui_size };

                    // The required size along the primary direction,
                    // as given by the key window's type and size parameters.
                    const req_size: f32 = switch (p.key.?.w) {
                        .text_buffer, .text_grid => blk_txt: {
                            const lines: f32 = @floatFromInt(p.size);

                            const vertical_spacing = imgui.getStyle().ItemSpacing.y;
                            const zero = uiZeroCharSize(); // TODO: cached?
                            // TODO: margins
                            break :blk_txt switch (p.method.direction) {
                                .left, .right => lines * zero.x,
                                .above, .below => lines * zero.y + (lines - 1) * vertical_spacing,
                            };
                        },
                        .graphics => @floatFromInt(p.size),
                        else => {
                            glk_log.warn("using {} window as key window", .{p.key.?.w});

                            // Because of invalid key window, we make it behave
                            // as if it was a zero size window.
                            break :blk .{ .{ .x = 0, .y = 0 }, self.cached_ui_size };
                        },
                    };

                    const actual_size: f32 = switch (p.method.direction) {
                        .left, .right => @min(self.cached_ui_size.x, req_size),
                        .above, .below => @min(self.cached_ui_size.y, req_size),
                    };

                    switch (p.method.direction) {
                        .left, .right => {
                            region[0] = .{
                                .x = actual_size - border_compensation.x,
                                .y = self.cached_ui_size.y - border_compensation.y,
                            };
                            region[1] = .{
                                .x = self.cached_ui_size.x - actual_size - border_compensation.x,
                                .y = self.cached_ui_size.y - border_compensation.y,
                            };
                        },
                        .above, .below => {
                            region[0] = .{
                                .x = self.cached_ui_size.x - border_compensation.x,
                                .y = actual_size - border_compensation.y,
                            };
                            region[1] = .{
                                .x = self.cached_ui_size.x - border_compensation.x,
                                .y = self.cached_ui_size.y - actual_size - border_compensation.y,
                            };
                        },
                    }
                },
            }
            break :blk region;
        };

        try child[0].draw(child_region[0], with_border);
        switch (p.method.direction) {
            .left, .right => imgui.sameLine(0.0, -1.0),
            else => {},
        }
        try child[1].draw(child_region[1], with_border);
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
    if ((split == null or method == null) and root != null) return Error.InvalidArgument;
    if (kind == .pair) return Error.InvalidArgument;

    const data_allocator = std.heap.c_allocator;

    const win = try pool.alloc();
    errdefer pool.dealloc(win);

    win.* = Window{
        .rock = rock,
        .str = undefined,
        .data = WindowData.init(
            data_allocator,
            // Parent will be properly set when initialising the parent window.
            // At the moment setting it null doesn't affect anything regarding
            // the deinitialisation of window in case of error.
            null,
            kind,
        ),
    };
    {
        errdefer win.data.deinit();
        win.str = try stream_sys.openWindowStream(&win.data);
    }
    errdefer win.deinit(null);

    const parent = blk: {
        // The window to create will become the root window.
        if (split == null) break :blk null;

        // Otherwise, need to create a pair window to hold the new window. Note that in this branch method must not be null (checked at the start of the function)
        assert(method != null);
        const w = try pool.alloc();
        errdefer pool.dealloc(w);

        w.* = Window{
            .rock = 0,
            .str = undefined, // TODO: make the stream nullable (pair windows should never have a stream)
            .data = WindowData.initPair(
                data_allocator,
                split.?.data.parent,
                &win.data,
                method.?,
                size,
                &win.data,
                &split.?.data,
            ),
        };

        // Here we properly initialise the window parent.
        win.data.parent = &w.data;

        break :blk w;
    };

    // TODO: replace split in split.data.parent

    if (root == null) {
        root = win;
    } else if (root == split) {
        root = parent;
    }
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

fn resetMainArena() void {
    if (!main_arena.reset(.{ .retain_capacity = {} })) {
        // Always succeeds.
        _ = main_arena.reset(.{ .free_all = {} });
    }
}

fn drawUi() !void {
    // Reset the arena at the start and end of the function.
    resetMainArena();
    defer resetMainArena();

    imgui.setNextWindowPos(.{ .x = 0, .y = 0 }, .always);
    imgui.setNextWindowSize(imgui.getIO().ptr.DisplaySize, .always);
    _ = imgui.begin("root", null, .{
        .no_title_bar = true,
        .no_resize = true,
    });
    defer imgui.end();

    if (root) |w| {
        try w.data.draw(imgui.getContentRegionAvail(), false);
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
    assert(win != null);

    const w = win.?;
    const size = w.data.cached_glk_size;
    if (widthptr) |wp| wp.* = size.w;
    if (heightptr) |hp| hp.* = size.h;
}

pub export fn glk_window_set_echo_stream(
    win: winid_t,
    str: strid_t,
) void {
    _ = str;
    assert(win != null);

    const w = win.?;
    _ = w;
}

pub export fn glk_window_clear(
    win: winid_t,
) void {
    assert(win != null);

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
    assert(win != null);

    _ = ypos;
    _ = xpos;
}

pub export fn glk_request_line_event(
    win: winid_t,
    buf: ?[*]u8,
    buflen: u32,
    initlen: u32,
) void {
    assert(win != null);
    assert(buf != null);
    assert(buflen > 0);
    assert(initlen <= buflen);

    // TODO: stub
}

pub export fn glk_request_line_event_uni(
    win: winid_t,
    buf_uni: ?[*]u32,
    buflen: u32,
    initlen: u32,
) void {
    assert(win != null);
    assert(buf_uni != null);
    assert(buflen > 0);
    assert(initlen <= buflen);

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

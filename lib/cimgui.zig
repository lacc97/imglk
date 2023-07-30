const std = @import("std");

const c = @cImport({
    @cDefine("CIMGUI_DEFINE_ENUMS_AND_STRUCTS", {});

    @cInclude("cimgui.h");

    @cDefine("CIMGUI_USE_GLFW", {});
    @cDefine("CIMGUI_USE_OPENGL3", {});
    @cInclude("cimgui_impl.h");
});

// --- Public types ---

pub const Error = error{
    dear_imgui,

    WrongGLSLVersion,
};

pub const Vec2 = c.ImVec2;

pub const WindowFlags = packed struct(u32) {
    no_title_bar: bool = false,
    no_resize: bool = false,
    no_move: bool = false,
    no_scrollbar: bool = false,
    no_scroll_with_mouse: bool = false,
    no_collapse: bool = false,
    always_auto_resize: bool = false,
    no_background: bool = false,
    no_saved_settings: bool = false,
    no_mouse_inputs: bool = false,
    menu_bar: bool = false,
    horizontal_scrollbar: bool = false,
    no_focus_on_appearing: bool = false,
    no_bring_to_front_on_focus: bool = false,
    always_vertical_scrollbar: bool = false,
    always_horizontal_scrollbar: bool = false,
    always_use_window_padding: bool = false,
    no_nav_inputs: bool = false,
    no_nav_focus: bool = false,
    unsaved_document: bool = false,
    no_docking: bool = false,
    nav_flattened: bool = false,
    child_window: bool = false,
    tooltip: bool = false,
    popup: bool = false,
    modal: bool = false,
    child_menu: bool = false,
    dock_node_host: bool = false,

    // padding
    _: u4 = 0,
};

pub const WindowCondition = enum(c_int) {
    always = c.ImGuiCond_Always,
    once = c.ImGuiCond_Once,
    first_use_ever = c.ImGuiCond_FirstUseEver,
    appearing = c.ImGuiCond_Appearing,
};

pub const Context = struct {
    // --- Fields ---

    ptr: *c.ImGuiContext,

    // --- Public functions ---

    pub inline fn init() @This() {
        return .{ .ptr = c.igCreateContext(null) };
    }
    pub inline fn deinit(self: @This()) void {
        c.igDestroyContext(self.ptr);
    }

    pub inline fn getIO(self: @This()) IO {
        return .{ .ptr = &self.ptr.IO };
    }
};

pub const IO = struct {
    // --- Fields ---

    ptr: *c.ImGuiIO,

    // --- Public types ---

    pub const ConfigBitFlag = enum(c_int) {
        nav_enable_keyboard = c.ImGuiConfigFlags_NavEnableKeyboard,
        nav_enable_gamepad = c.ImGuiConfigFlags_NavEnableGamepad,
        nav_enable_set_mouse_pos = c.ImGuiConfigFlags_NavEnableSetMousePos,
        nav_no_capture_keyboard = c.ImGuiConfigFlags_NavNoCaptureKeyboard,
        no_mouse = c.ImGuiConfigFlags_NoMouse,
        no_mouse_cursor_change = c.ImGuiConfigFlags_NoMouseCursorChange,
        docking_enable = c.ImGuiConfigFlags_DockingEnable,
        viewports_enable = c.ImGuiConfigFlags_ViewportsEnable,
        dpi_enable_scale_viewports = c.ImGuiConfigFlags_DpiEnableScaleViewports,
        dpi_enable_scale_fonts = c.ImGuiConfigFlags_DpiEnableScaleFonts,

        is_srgb = c.ImGuiConfigFlags_IsSRGB,
        is_touchscreen = c.ImGuiConfigFlags_IsTouchScreen,
    };

    // --- Public functions ---
    pub inline fn setConfigFlag(self: @This(), flag: ConfigBitFlag, value: bool) void {
        // Reset flag bit.
        self.ptr.ConfigFlags &= ~@intFromEnum(flag);

        // Conditionally set flag bit.
        if (value) self.ptr.ConfigFlags |= @intFromEnum(flag);
    }
};

// --- Namespaces ---

pub const glfw = struct {
    pub inline fn initForOpenGL(window: *anyopaque, install_callbacks: bool) !void {
        if (!c.ImGui_ImplGlfw_InitForOpenGL(@ptrCast(window), install_callbacks)) {
            return Error.dear_imgui;
        }
    }
    pub inline fn deinit() void {
        c.ImGui_ImplGlfw_Shutdown();
    }

    pub inline fn newFrame() void {
        c.ImGui_ImplGlfw_NewFrame();
    }
};

const GLSLVersion = enum {
    @"1.10", // OpenGL 2.0
    @"1.20", // OpenGL 2.1
    @"1.30", // OpenGL 3.0
    @"1.40", // OpenGL 3.1
    @"1.50", // OpenGL 3.2
    @"3.30",
    @"4.00",
    @"4.10",
    @"4.20",
    @"4.30",
    @"4.40",
    @"4.50",
    @"4.60",
};

pub const opengl3 = struct {
    pub inline fn init(glsl_version: GLSLVersion) !void {
        switch (glsl_version) {
            .@"1.10", .@"1.20" => std.debug.panic("wrong glsl version: expected at least {s}, got {s}", .{
                @tagName(.@"1.30"),
                @tagName(glsl_version),
            }),

            else => {},
        }

        const raw_version = make_raw: {
            var raw: [3:0]u8 = undefined;

            const name = @tagName(glsl_version);
            raw[0] = name[0];
            // Skip '.'.
            raw[1] = name[2];
            raw[2] = name[3];

            break :make_raw raw;
        };

        const version = "#version " ++ raw_version;

        if (!c.ImGui_ImplOpenGL3_Init(version.ptr)) {
            return Error.dear_imgui;
        }
    }
    pub inline fn deinit() void {
        c.ImGui_ImplOpenGL3_Shutdown();
    }

    pub inline fn newFrame() void {
        c.ImGui_ImplOpenGL3_NewFrame();
    }

    pub inline fn renderDrawData(draw_data: *c.ImDrawData) void {
        c.ImGui_ImplOpenGL3_RenderDrawData(draw_data);
    }
};

// --- Public functions ---

pub inline fn getCurrentContext() ?Context {
    if (c.igGetCurrentContext()) |ctx| {
        return .{ .ptr = ctx };
    } else {
        return null;
    }
}
pub inline fn setCurrentContext(ctx_opt: ?Context) void {
    c.igSetCurrentContext(if (ctx_opt) |ctx| ctx.ptr else null);
}

// -- Functions that require a valid current context.

pub inline fn getIO() IO {
    return getCurrentContext().?.getIO();
}

pub inline fn newFrame() void {
    c.igNewFrame();
}

pub inline fn render() void {
    c.igRender();
}

// TODO: zig wrapper
pub inline fn getDrawData() *c.ImDrawData {
    return c.igGetDrawData();
}

pub inline fn showDemoWindow(p_open: ?*bool) void {
    c.igShowDemoWindow(p_open);
}

pub inline fn getContentRegionAvail() Vec2 {
    var v: Vec2 = undefined;
    c.igGetContentRegionAvail(&v);
    return v;
}

// -- Drawing functions

pub inline fn setNextWindowPos(pos: Vec2, cond: WindowCondition) void {
    c.igSetNextWindowPos(pos, @intFromEnum(cond), .{ .x = 0, .y = 0 });
}
pub inline fn setNextWindowPosPivot(pos: Vec2, cond: WindowCondition, pivot: Vec2) void {
    c.igSetNextWindowPos(pos, @intFromEnum(cond), pivot);
}
pub inline fn setNextWindowSize(size: Vec2, cond: WindowCondition) void {
    c.igSetNextWindowSize(size, @intFromEnum(cond));
}

pub inline fn begin(name: [:0]const u8, p_open: ?*bool, flags: WindowFlags) bool {
    return c.igBegin(name.ptr, p_open, @bitCast(flags));
}
pub inline fn end() void {
    return c.igEnd();
}

pub inline fn beginChild(name: [:0]const u8, size: Vec2, border: bool, flags: WindowFlags) bool {
    return c.igBeginChild_Str(name.ptr, size, border, @bitCast(flags));
}
pub inline fn endChild() void {
    return c.igEndChild();
}

pub inline fn text(txt: []const u8) void {
    c.igTextEx(txt.ptr, txt.ptr + txt.len, c.ImGuiTextFlags_NoWidthForLargeClippedText);
}

pub inline fn textFmt(comptime fmt: []const u8, args: anytype) void {
    const txt = tmpBufPrint(fmt, args);
    text(txt);
}

pub inline fn textWrapped(txt: []const u8) void {
    c.igPushTextWrapPos(0.0);
    defer c.igPopTextWrapPos();

    text(txt);
}

pub inline fn textFmtWrapped(comptime fmt: []const u8, args: anytype) void {
    const txt = tmpBufPrint(fmt, args);
    textWrapped(txt);
}

pub inline fn checkbox(txt: [:0]const u8, b: *bool) bool {
    return c.igCheckbox(txt.ptr, b);
}

// --- Private functions ---

inline fn tmpBufPrint(comptime fmt: []const u8, args: anytype) []const u8 {
    const err_txt = "<#! not enough space in temp buffer for formatted string: " ++ fmt ++ " !#>";

    const g = getCurrentContext().?.ptr;

    const buf = g.TempBuffer.Data[0..@as(usize, @intCast(g.TempBuffer.Size))];
    return std.fmt.bufPrint(buf, fmt, args) catch err_txt;
}

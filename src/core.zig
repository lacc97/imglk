const std = @import("std");

pub const c_glk = @import("c.zig");

// --- Globals ---

pub var blorb_resource_map: ?*giblorb_map_t = null;

pub var interrupt_handler: ?GlkInterruptHandler = null;

// --- Public types ---

pub const GlkInterruptHandler = *const fn () callconv(.C) void;

pub const FileMode = enum(u3) {
    write = c_glk.filemode_Write,
    read = c_glk.filemode_Read,
    read_write = c_glk.filemode_ReadWrite,
    write_append = c_glk.filemode_WriteAppend,
};

const GestaltSelector = enum(u32) {
    version = c_glk.gestalt_Version,
    char_input = c_glk.gestalt_CharInput,
    line_input = c_glk.gestalt_LineInput,
    char_output = c_glk.gestalt_CharOutput,
    mouse_input = c_glk.gestalt_MouseInput,
    timer = c_glk.gestalt_Timer,
    graphics = c_glk.gestalt_Graphics,
    draw_image = c_glk.gestalt_DrawImage,
    sound = c_glk.gestalt_Sound,
    sound_volume = c_glk.gestalt_SoundVolume,
    sound_notify = c_glk.gestalt_SoundNotify,
    hyperlinks = c_glk.gestalt_Hyperlinks,
    hyperlink_input = c_glk.gestalt_HyperlinkInput,
    sound_music = c_glk.gestalt_SoundMusic,
    graphics_transparency = c_glk.gestalt_GraphicsTransparency,
    unicode = c_glk.gestalt_Unicode,
    unicode_normalisation = c_glk.gestalt_UnicodeNorm,
    line_input_echo = c_glk.gestalt_LineInputEcho,
    line_terminators = c_glk.gestalt_LineTerminators,
    line_terminator_key = c_glk.gestalt_LineTerminatorKey,
    date_time = c_glk.gestalt_DateTime,
    sound2 = c_glk.gestalt_Sound2,
    resource_stream = c_glk.gestalt_ResourceStream,
    graphics_char_input = c_glk.gestalt_GraphicsCharInput,

    _,
};

const CharOutputResult = enum(u32) {
    cannot_print = c_glk.gestalt_CharOutput_CannotPrint,
    approx_print = c_glk.gestalt_CharOutput_ApproxPrint,
    exact_print = c_glk.gestalt_CharOutput_ExactPrint,
};

// --- Private types ---

// -- Blorb

const giblorb_err_t = c_glk.giblorb_err_t;
const giblorb_map_t = c_glk.giblorb_map_t;

const strid_t = @import("StreamSubsystem.zig").strid_t;

// --- Private functions ---

fn gestalt(sel: GestaltSelector, val: u32, arr: []u32) u32 {
    _ = arr;
    switch (sel) {
        .version => return version(0, 7, 5),
        .unicode => return 1,
        .char_output => {
            // For now
            if (val < 0x100 and std.ascii.isPrint(@truncate(val))) return @intFromEnum(CharOutputResult.exact_print);
            return @intFromEnum(CharOutputResult.cannot_print);
        },
        .line_input => {
            if (val < 0x100 and std.ascii.isPrint(@truncate(val))) return 1;
            return 0;
        },
        .date_time => return 1,

        else => return 0,
    }
}

fn version(major: u16, minor: u8, patch: u8) u32 {
    return (@as(u32, major) << 16) | (@as(u32, minor) << 8) | @as(u32, patch);
}

// --- Exported ---

pub export fn glk_set_interrupt_handler(handler: GlkInterruptHandler) void {
    interrupt_handler = handler;
}

pub export fn glk_tick() void {}

pub export fn glk_gestalt(
    sel: u32,
    val: u32,
) u32 {
    return glk_gestalt_ext(sel, val, null, 0);
}

pub export fn glk_gestalt_ext(
    sel: u32,
    val: u32,
    arr: ?[*]u32,
    arrlen: u32,
) u32 {
    return gestalt(
        @enumFromInt(sel),
        val,
        if (arr) |a| a[0..arrlen] else &.{},
    );
}

// -- Blorb

export fn giblorb_set_resource_map(
    file: strid_t,
) giblorb_err_t {
    const err = c_glk.giblorb_create_map(@ptrCast(file), &blorb_resource_map);
    if (err != c_glk.giblorb_err_None) blorb_resource_map = null;
    return err;
}

export fn giblorb_get_resource_map() ?*giblorb_map_t {
    return blorb_resource_map;
}

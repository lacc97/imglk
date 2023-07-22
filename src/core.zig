const std = @import("std");

pub const c_glk = @cImport({
    @cInclude("glk.h");
});

// --- Globals ---

pub var interrupt_handler: ?GlkInterruptHandler = null;

// --- Public types ---

pub const GlkInterruptHandler = *const fn () callconv(.C) void;

pub const FileMode = enum(u3) {
    write = c_glk.filemode_Write,
    read = c_glk.filemode_Read,
    read_write = c_glk.filemode_ReadWrite,
    write_append = c_glk.filemode_WriteAppend,
};

// --- Exported ---

pub export fn glk_exit() void {}

pub export fn glk_set_interrupt_handler(handler: GlkInterruptHandler) void {
    interrupt_handler = handler;
}

pub export fn glk_tick() void {}

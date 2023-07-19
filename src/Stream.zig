const std = @import("std");

const ObjectPool = @import("object_pool.zig").ObjectPool;

const glk_log = std.log.scoped(.glk);

const Stream = @This();
// comptime {
//     @compileLog(@sizeOf(Stream));
// }

// --- Globals ---

const static_buffer_size: usize = 2048;
const static_buffer_size_uni: usize = 512;

var pool = ObjectPool(Stream).init(std.heap.c_allocator);

var current_stream: ?*Stream = null;

// --- Fields ---

rock: u32,
flags: packed struct(u32) {
    unicode: bool,
    read: bool,
    write: bool,

    // padding
    _: u29 = 0,
},
r_count: u32 = 0,
w_count: u32 = 0,

data: union(enum) {
    memory: struct {
        stream: std.io.FixedBufferStream([]u8),
    },
},

// --- Public types ---

pub const Error = error{
    EOF,
    NotAvailable,
};

// --- Public functions ---

pub fn deinit(
    self: *@This(),
) void {
    if (current_stream == self) current_stream = null;
    // TODO: deallocate
}

// -- Seeking

// -- Narrow char

pub fn getChar(
    self: *@This(),
) Error!u8 {
    var chs: [1]u8 = undefined;
    _ = try self.getChars(&chs);
    return chs[0];
}
pub fn getChars(
    self: *@This(),
    buf: []u8,
) Error!u32 {
    if (!self.flags.read) return Error.NotAvailable;

    switch (self.data) {
        .memory => |*m| {
            const readcount = m.stream.read(buf) catch unreachable;
            if (readcount == 0) return Error.EOF;
            return @intCast(readcount);
        },
    }
}
pub fn getLine(
    self: *@This(),
    buf: []u8,
) Error!u32 {
    if (!self.flags.read) return Error.NotAvailable;

    // Must have at least some space for the null terminator.
    std.debug.assert(buf.len > 0);

    switch (self.data) {
        .memory => |*m| {
            _ = m;
        },
    }
}

pub fn putChar(
    self: *@This(),
    ch: u8,
) Error!void {
    return self.putChars(&.{ch});
}
pub fn putChars(
    self: *@This(),
    buf: []const u8,
) Error!void {
    if (!self.flags.write) return Error.NotAvailable;

    if (!self.flags.unicode) {
        switch (self.data) {
            .memory => |*m| {
                _ = m.stream.write(buf) catch |err| {
                    switch (err) {
                        error.NoSpaceLeft => return Error.EOF,
                        else => unreachable,
                    }
                };
            },
        }
    } else {
        var buf_uni: [static_buffer_size_uni]u32 = undefined;

        var i: usize = 0;
        while (i < buf.len) {
            var j: usize = 0;
            while (i < buf.len and j < buf_uni.len) : ({
                j += 1;
                i += 1;
            }) {
                buf_uni[j] = buf[i];
            }
            try self.putUniChars(buf_uni[0..j]);
        }
    }
}

// -- Wide char

pub fn getUniChar(
    self: *@This(),
) Error!u32 {
    _ = self;
}

pub fn getUniChars(
    self: *@This(),
    buf: []u32,
) Error!u32 {
    _ = buf;
    _ = self;
}

pub fn putUniChar(
    self: *@This(),
    ch: u32,
) Error!void {
    return self.putUniChars(&.{ch});
}
pub fn putUniChars(
    self: *@This(),
    buf_uni: []const u32,
) Error!void {
    if (!self.flags.write) return Error.NotAvailable;

    if (self.flags.unicode) {
        switch (self.data) {
            .memory => |*m| {
                _ = m.stream.write(std.mem.sliceAsBytes(buf_uni)) catch |err| {
                    switch (err) {
                        error.NoSpaceLeft => return Error.EOF,
                        else => unreachable,
                    }
                };
            },
        }
    } else {
        var buf: [static_buffer_size]u8 = undefined;

        var i: usize = 0;
        while (i < buf_uni.len) {
            var j: usize = 0;
            while (i < buf_uni.len and j < buf.len) : ({
                j += 1;
                i += 1;
            }) {
                buf[j] = if (buf_uni[i] <= 0xff) @truncate(buf_uni[j]) else '?';
            }
            try self.putChars(buf[0..j]);
        }
    }
}

// --- Private types ---

// --- Public functions ---

// --- Private functions ---

// --- Exported ---

pub const strid_t = ?*Stream;

pub const stream_result_t = extern struct {
    readcount: u32,
    writecount: u32,
};

pub export fn glk_stream_get_rock(
    str: strid_t,
) callconv(.C) u32 {
    return str.?.rock;
}

pub export fn glk_stream_iterate(
    str: strid_t,
    rockptr: ?*u32,
) callconv(.C) strid_t {
    const next_str = pool.next(str) orelse return null;
    if (rockptr) |r| r.* = next_str.rock;
    return next_str;
}

pub export fn glk_stream_get_current() callconv(.C) strid_t {
    return current_stream;
}

pub export fn glk_stream_set_current(
    str: strid_t,
) callconv(.C) void {
    current_stream = str;
}

pub export fn glk_stream_close(
    str: strid_t,
    result: ?*stream_result_t,
) callconv(.C) void {
    const s = str.?;

    if (result) |r| {
        r.readcount = s.r_count;
        r.writecount = s.w_count;
    }

    s.deinit();
    pool.dealloc(s);
}

pub export fn glk_put_char_stream(
    str: strid_t,
    ch: u8,
) callconv(.C) void {
    str.?.putChar(ch) catch |err| {
        glk_log.warn("failed to put char: {}", .{err});
    };
}

pub export fn glk_put_string_stream(
    str: strid_t,
    s: ?[*:0]const u8,
) callconv(.C) void {
    str.?.putChars(std.mem.span(s.?)) catch |err| {
        glk_log.warn("failed to put chars: {}", .{err});
    };
}

pub export fn glk_put_buffer_stream(
    str: strid_t,
    buf: [*]const u8,
    len: u32,
) callconv(.C) void {
    str.?.putChars(buf[0..len]) catch |err| {
        glk_log.warn("failed to put char: {}", .{err});
    };
}

pub export fn glk_put_char(
    ch: u8,
) callconv(.C) void {
    glk_put_char_stream(current_stream, ch);
}

pub export fn glk_put_string(
    s: ?[*:0]const u8,
) callconv(.C) void {
    glk_put_string_stream(current_stream, s);
}

pub export fn glk_put_buffer(
    buf: [*]const u8,
    len: u32,
) callconv(.C) void {
    glk_put_buffer_stream(current_stream, buf, len);
}

pub export fn glk_put_char_stream_uni(
    str: strid_t,
    ch: u32,
) callconv(.C) void {
    str.?.putUniChar(ch) catch |err| {
        glk_log.warn("failed to put char: {}", .{err});
    };
}

pub export fn glk_put_string_stream_uni(
    str: strid_t,
    s: ?[*:0]const u32,
) callconv(.C) void {
    str.?.putUniChars(std.mem.span(s.?)) catch |err| {
        glk_log.warn("failed to put chars: {}", .{err});
    };
}

pub export fn glk_put_buffer_stream_uni(
    str: strid_t,
    buf: [*]const u32,
    len: u32,
) callconv(.C) void {
    str.?.putUniChars(buf[0..len]) catch |err| {
        glk_log.warn("failed to put char: {}", .{err});
    };
}

pub export fn glk_put_char_uni(
    ch: u32,
) callconv(.C) void {
    glk_put_char_stream_uni(current_stream, ch);
}

pub export fn glk_put_string_uni(
    s: ?[*:0]const u32,
) callconv(.C) void {
    glk_put_string_stream_uni(current_stream, s);
}

pub export fn glk_put_buffer_uni(
    buf: [*]const u32,
    len: u32,
) callconv(.C) void {
    glk_put_buffer_stream_uni(current_stream, buf, len);
}

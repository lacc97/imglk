const std = @import("std");
const core = @import("core.zig");

const ObjectPool = @import("object_pool.zig").ObjectPool;

const glk_log = std.log.scoped(.glk);

const StreamSubsystem = @This();

// --- Globals ---

const static_buffer_size: usize = 2048;
const static_buffer_size_uni: usize = 512;

var sys_stream: StreamSubsystem = undefined;

// --- Fields ---

pool: ObjectPool(Stream),
current: strid_t = null,

// --- Public types ---

pub const Error = error{
    EOF,
    NotAvailable,
    InvalidArgument,
};

const Stream = struct {
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

    // --- Private types ---

    // --- Public functions ---

    pub fn deinit(
        self: *@This(),
    ) void {
        _ = self;
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

        if (!self.flags.unicode) {
            return self.getCharsRaw(buf);
        } else {
            var buf_uni: [static_buffer_size_uni]u32 = undefined;

            var i: usize = 0;
            read_loop: while (i < buf.len) {
                const read_buf_len: usize = @min(static_buffer_size, buf.len);
                const read_count = self.getUniCharsRaw(buf_uni[0..read_buf_len]) catch |err| {
                    if (err == Error.EOF and i > 0) break :read_loop;
                    return err;
                };

                for (buf_uni[0..read_count]) |ch| {
                    buf[i] = if (ch >= 0x100) '?' else @truncate(ch);
                    i += 1;
                }
            }

            return @intCast(i);
        }
    }
    pub fn getLine(
        self: *@This(),
        buf: []u8,
    ) Error!u32 {
        if (!self.flags.read) return Error.NotAvailable;

        // Must have at least some space for the null terminator.
        std.debug.assert(buf.len > 0);

        var i: usize = 0;
        read_loop: while (i < (buf.len - 1)) : (i += 1) {
            const ch = self.getChar() catch |err| {
                if (err == Error.EOF) break :read_loop;
                return err;
            };
            buf[i] = ch;
            if (ch == '\n') break;
        }
        buf[i] = 0;

        return @intCast(i);
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
            return self.putCharsRaw(buf);
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
                try self.putUniCharsRaw(buf_uni[0..j]);
            }
        }
    }

    // -- Wide char

    pub fn getUniChar(
        self: *@This(),
    ) Error!u32 {
        var ch: [1]u32 = undefined;
        _ = try self.getUniChars(&ch);
        return ch[0];
    }
    pub fn getUniChars(
        self: *@This(),
        buf_uni: []u32,
    ) Error!u32 {
        if (!self.flags.read) return Error.NotAvailable;

        if (self.flags.unicode) {
            return self.getUniCharsRaw(buf_uni);
        } else {
            var buf: [static_buffer_size_uni]u8 = undefined;

            var i: usize = 0;
            read_loop: while (i < buf_uni.len) {
                const read_buf_len: usize = @min(static_buffer_size, buf_uni.len);
                const read_count = self.getCharsRaw(buf[0..read_buf_len]) catch |err| {
                    if (err == Error.EOF and i > 0) break :read_loop;
                    return err;
                };

                for (buf[0..read_count]) |ch| {
                    buf_uni[i] = ch;
                    i += 1;
                }
            }

            return @intCast(i);
        }
    }
    pub fn getUniLine(
        self: *@This(),
        buf_uni: []u32,
    ) Error!u32 {
        if (!self.flags.read) return Error.NotAvailable;

        // Must have at least some space for the null terminator.
        std.debug.assert(buf_uni.len > 0);

        var i: usize = 0;
        while (i < (buf_uni.len - 1)) : (i += 1) {
            const ch = self.getUniChar() catch |err| {
                if (err == Error.EOF) break;
                return err;
            };
            buf_uni[i] = ch;
            if (ch == '\n') break;
        }
        buf_uni[i] = 0;

        return @intCast(i);
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
            return self.putUniCharsRaw(buf_uni);
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
                try self.putCharsRaw(buf[0..j]);
            }
        }
    }

    // --- Private functions ---

    fn getCharsRaw(
        self: *@This(),
        buf: []u8,
    ) Error!u32 {
        std.debug.assert(!self.flags.unicode);

        switch (self.data) {
            .memory => |*m| {
                const rc = m.stream.read(buf) catch unreachable;
                if (rc == 0) return Error.EOF;

                const readcount: u32 = @intCast(rc);
                self.r_count += readcount;
                return @intCast(readcount);
            },
        }
    }

    fn putCharsRaw(
        self: *@This(),
        buf: []const u8,
    ) Error!void {
        std.debug.assert(!self.flags.unicode);

        switch (self.data) {
            .memory => |*m| {
                const wc = m.stream.write(buf) catch |err| {
                    switch (err) {
                        error.NoSpaceLeft => return Error.EOF,
                        else => unreachable,
                    }
                };

                const writecount: u32 = @intCast(wc);
                self.w_count += writecount;
            },
        }
    }

    fn getUniCharsRaw(
        self: *@This(),
        buf_uni: []u32,
    ) Error!u32 {
        std.debug.assert(self.flags.unicode);

        switch (self.data) {
            .memory => |*m| {
                var rc = m.stream.read(std.mem.sliceAsBytes(buf_uni)) catch unreachable;
                rc /= 4;
                if (rc == 0) return Error.EOF;

                const readcount: u32 = @intCast(rc);
                self.r_count += readcount;
                return readcount;
            },
        }
    }

    fn putUniCharsRaw(
        self: *@This(),
        buf_uni: []const u32,
    ) Error!void {
        std.debug.assert(self.flags.unicode);

        switch (self.data) {
            .memory => |*m| {
                var wc = m.stream.write(std.mem.sliceAsBytes(buf_uni)) catch |err| {
                    switch (err) {
                        error.NoSpaceLeft => return Error.EOF,
                        else => unreachable,
                    }
                };
                wc /= 4;
                if (wc == 0) return Error.EOF;

                const writecount: u32 = @intCast(wc);
                self.w_count += writecount;
            },
        }
    }
};

// --- Public functions ---

pub fn initSubsystem(alloc: std.mem.Allocator) !void {
    sys_stream = init(alloc);
}
pub fn deinitSubsystem() void {
    sys_stream.deinit();
}

// --- Private functions

fn init(
    alloc: std.mem.Allocator,
) StreamSubsystem {
    return .{ .pool = ObjectPool(Stream).init(alloc) };
}
fn deinit(
    self: *@This(),
) void {
    self.pool.deinit();
}

fn getNextStream(
    self: *@This(),
    str: ?*Stream,
    rockptr: ?*u32,
) ?*Stream {
    const next_str = self.pool.next(str) orelse return null;
    if (rockptr) |r| r.* = next_str.rock;
    return next_str;
}

fn openMemoryStream(self: *@This(), unicode: bool, buf: []u8, fmode: core.FileMode, rock: u32) !*Stream {
    if (unicode and buf.len % 4 != 0) return Error.InvalidArgument;
    if (fmode == .write_append) return Error.InvalidArgument;

    const str = try self.pool.alloc();
    errdefer self.pool.dealloc(str);

    str.* = .{
        .rock = rock,
        .flags = .{
            .unicode = unicode,
            .read = fmode == .read or fmode == .read_write,
            .write = fmode == .write or fmode == .read_write,
        },
        .data = .{
            .memory = .{
                .stream = std.io.fixedBufferStream(buf),
            },
        },
    };

    return str;
}
fn closeStream(self: *@This(), str: ?*Stream, resultptr: ?*stream_result_t) void {
    const s = str.?;

    if (resultptr) |r| {
        r.readcount = s.r_count;
        r.writecount = s.w_count;
    }

    if (self.current == s) self.current = null;
    s.deinit();
    self.pool.dealloc(s);
}

// --- Exported ---

pub const strid_t = ?*Stream;

const stream_result_t = core.c_glk.stream_result_t;

pub export fn glk_stream_get_rock(
    str: strid_t,
) callconv(.C) u32 {
    return str.?.rock;
}

pub export fn glk_stream_iterate(
    str: strid_t,
    rockptr: ?*u32,
) callconv(.C) strid_t {
    return sys_stream.getNextStream(str, rockptr);
}

pub export fn glk_stream_get_current() callconv(.C) strid_t {
    return sys_stream.current;
}

pub export fn glk_stream_set_current(
    str: strid_t,
) callconv(.C) void {
    sys_stream.current = str;
}

pub export fn glk_stream_open_memory(
    buf: ?[*]u8,
    len: u32,
    fmode: u32,
    rock: u32,
) strid_t {
    return sys_stream.openMemoryStream(
        false,
        buf.?[0..len],
        @enumFromInt(@as(u3, @intCast(fmode))),
        rock,
    ) catch |err| {
        glk_log.warn("failed to open memory stream: {}", .{err});
        return null;
    };
}

pub export fn glk_stream_open_memory_uni(
    buf: ?[*]u8,
    len: u32,
    fmode: u32,
    rock: u32,
) strid_t {
    return sys_stream.openMemoryStream(
        true,
        buf.?[0..len],
        @enumFromInt(@as(u3, @intCast(fmode))),
        rock,
    ) catch |err| {
        glk_log.warn("failed to open unicode memory stream: {}", .{err});
        return null;
    };
}

// test "Memory stream" {
//     try initSubsystem(std.heap.c_allocator);
//     defer deinitSubsystem();

//     const buf_len: usize = 128;

//     {
//         var buf1: [buf_len]u8 = undefined;
//         const str1 = glk_stream_open_memory(
//             &buf1,
//             buf1.len,
//             core.c_glk.filemode_Write,
//             1,
//         );
//         try std.testing.expect(str1 != null);
//         errdefer glk_stream_close(str1, null);

//         for (0..(buf_len - 1)) |i| glk_put_char_stream(str1, @truncate(i));

//         var result1: stream_result_t = undefined;
//         glk_stream_close(str1, &result1);

//         try std.testing.expectEqual(buf_len - 1, result1.readcount);
//         try std.testing.expectEqual(@as(usize, 0), result1.writecount);

//         for (0..(buf_len - 1)) |i| try std.testing.expectEqual(@as(u8, @truncate(i)), buf1[i]);
//     }
// }

pub export fn glk_stream_close(
    str: strid_t,
    result: ?*stream_result_t,
) callconv(.C) void {
    sys_stream.closeStream(str, result);
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

pub export fn glk_get_char_stream(
    str: strid_t,
) i32 {
    return str.?.getChar() catch |err| {
        if (err == Error.EOF) return -1;
        glk_log.warn("failed to get char: {}", .{err});
        return -1;
    };
}

pub export fn glk_get_line_stream(
    str: strid_t,
    buf: [*]u8,
    len: u32,
) u32 {
    return str.?.getLine(buf[0..len]) catch |err| {
        glk_log.warn("failed to get line: {}", .{err});
        return 0;
    };
}

pub export fn glk_get_buffer_stream(
    str: strid_t,
    buf: [*]u8,
    len: u32,
) u32 {
    return str.?.getChars(buf[0..len]) catch |err| {
        glk_log.warn("failed to get buffer: {}", .{err});
        return 0;
    };
}

pub export fn glk_put_char(
    ch: u8,
) callconv(.C) void {
    glk_put_char_stream(sys_stream.current, ch);
}

pub export fn glk_put_string(
    s: ?[*:0]const u8,
) callconv(.C) void {
    glk_put_string_stream(sys_stream.current, s);
}

pub export fn glk_put_buffer(
    buf: [*]const u8,
    len: u32,
) callconv(.C) void {
    glk_put_buffer_stream(sys_stream.current, buf, len);
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

pub export fn glk_get_char_stream_uni(
    str: strid_t,
) i32 {
    return @bitCast(str.?.getUniChar() catch |err| {
        if (err == Error.EOF) return -1;
        glk_log.warn("failed to get unicode char: {}", .{err});
        return -1;
    });
}

pub export fn glk_get_line_stream_uni(
    str: strid_t,
    buf_uni: [*]u32,
    len: u32,
) u32 {
    return str.?.getUniLine(buf_uni[0..len]) catch |err| {
        glk_log.warn("failed to get unicode line: {}", .{err});
        return 0;
    };
}

pub export fn glk_get_buffer_stream_uni(
    str: strid_t,
    buf_uni: [*]u32,
    len: u32,
) u32 {
    return str.?.getUniChars(buf_uni[0..len]) catch |err| {
        glk_log.warn("failed to get unicode buffer: {}", .{err});
        return 0;
    };
}

pub export fn glk_put_char_uni(
    ch: u32,
) callconv(.C) void {
    glk_put_char_stream_uni(sys_stream.current, ch);
}

pub export fn glk_put_string_uni(
    s: ?[*:0]const u32,
) callconv(.C) void {
    glk_put_string_stream_uni(sys_stream.current, s);
}

pub export fn glk_put_buffer_uni(
    buf: [*]const u32,
    len: u32,
) callconv(.C) void {
    glk_put_buffer_stream_uni(sys_stream.current, buf, len);
}

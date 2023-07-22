const std = @import("std");

const ObjectPool = @import("object_pool.zig").ObjectPool;

const glk_log = std.log.scoped(.glk);

const FileRefSubsystem = @This();

// --- Globals ---

var sys_fileref: FileRefSubsystem = undefined;

// --- Fields ---

pool: ObjectPool(FileRef),

// --- Public types ---

pub const FileRef = struct {
    // --- Fields ---

    rock: u32,
    usage: packed struct(u8) {
        kind: Kind,
        mode: Mode,
        _: u5 = 0,
    },
    path: []const u8,

    // --- Public types ---

    pub const Kind = enum(u2) {
        saved_game,
        transcript,
        input_record,
        data,
    };

    pub const Mode = enum(u1) {
        binary,
        text,
    };

    // --- Public functions ---

    pub fn init() FileRef {
        return undefined;
    }
    pub fn deinit(self: *@This()) void {
        _ = self;
    }
};

pub const OpenMode = enum(u2) {
    read,
    write,
    read_write,
    write_append,
};

// --- Public functions ---

pub fn initSubsystem(alloc: std.mem.Allocator) !void {
    sys_fileref = init(alloc);
}
pub fn deinitSubsystem() void {
    sys_fileref.deinit();
}

// --- Private functions ---

fn init(
    alloc: std.mem.Allocator,
) @This() {
    return .{ .pool = ObjectPool(FileRef).init(alloc) };
}
fn deinit(
    self: *@This(),
) void {
    self.pool.deinit();
}

fn getNextFileRef(
    self: *@This(),
    fr: ?*FileRef,
    rockptr: ?*u32,
) ?*FileRef {
    const next_fr = self.pool.next(fr) orelse return null;
    if (rockptr) |r| r.* = next_fr.rock;
    return next_fr;
}

fn destroyFileRef(self: *@This(), fr: ?*FileRef) void {
    const f = fr.?;
    f.deinit();
    self.pool.dealloc(f);
}

// --- Exported ---

pub const frefid_t = ?*FileRef;

pub export fn glk_fileref_get_rock(
    fr: frefid_t,
) u32 {
    return fr.?.rock;
}

pub export fn glk_fileref_iterate(
    fr: frefid_t,
    rockptr: ?*u32,
) frefid_t {
    return sys_fileref.getNextFileRef(fr, rockptr);
}

pub export fn glk_fileref_create_temp(
    usage: u32,
    rock: u32,
) frefid_t {
    _ = rock;
    _ = usage;
    return null;
}

pub export fn glk_fileref_create_by_prompt(
    usage: u32,
    rock: u32,
) frefid_t {
    _ = rock;
    _ = usage;
    return null;
}

pub export fn glk_fileref_destroy(
    fr: frefid_t,
) void {
    sys_fileref.destroyFileRef(fr);
}

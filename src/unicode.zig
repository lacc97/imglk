const std = @import("std");
const builtin = @import("builtin");

// --- Public functions ---

pub const codepoint = struct {
    // --- Constants ---
    const max_codepoint: u32 = 0x10FFFF;

    const max_utf8_codepoint_1byte: u32 = 0x00007F;
    const max_utf8_codepoint_2byte: u32 = 0x0007FF;
    const max_utf8_codepoint_3byte: u32 = 0x00FFFF;
    const max_utf8_codepoint_4byte: u32 = 0x10FFFF;

    const min_invalid_utf8_codepoint_surrogate: u32 = 0x00D800;
    const max_invalid_utf8_codepoint_surrogate: u32 = 0x00DFFF;

    // --- Functions ---

    // -- Codepoint validity

    pub inline fn isValid(cp: u32) bool {
        return cp <= max_codepoint;
    }

    inline fn isValidVec(
        comptime n: comptime_int,
        cps: @Vector(n, u32),
    ) @Vector(n, bool) {
        return cps <= @as(@Vector(n, u32), @splat(max_codepoint));
    }

    pub fn isValidSlice(cps: []const u32) bool {
        var c: []const u32 = cps;
        if (comptime std.simd.suggestVectorSize(u32)) |vec_size| {
            while (c.len >= vec_size) : (c = c[vec_size..]) {
                const is_valid_vec = isValidVec(vec_size, c[0..vec_size].*);
                if (!@reduce(.And, is_valid_vec)) return false;
            }
        }
        while (c.len > 0) : (c = c[1..]) {
            if (!isValid(c[0])) return false;
        }
        return true;
    }

    // -- UTF-8 encoded length

    pub inline fn utf8EncodedLen(cp: u32) u3 {
        var len: u3 = 0;
        if (cp <= max_utf8_codepoint_4byte) len += 1;
        if (cp <= max_utf8_codepoint_3byte) len += 1;
        if (cp <= max_utf8_codepoint_2byte) len += 1;
        if (cp <= max_utf8_codepoint_1byte) len += 1;
        if (cp >= min_invalid_utf8_codepoint_surrogate and cp <= max_invalid_utf8_codepoint_surrogate) len = 0;
        return len;
    }

    inline fn utf8EncodedLenVec(
        comptime n: comptime_int,
        cps: @Vector(n, u32),
    ) @Vector(n, u32) {
        const Vec = @Vector(n, u32);
        const Mask = @Vector(n, bool);

        const len_vec = blk: {
            var len: Vec = @splat(0);
            len += @select(
                u32,
                cps <= @as(Vec, @splat(max_utf8_codepoint_4byte)),
                @as(Vec, @splat(1)),
                @as(Vec, @splat(0)),
            );
            len += @select(
                u32,
                cps <= @as(Vec, @splat(max_utf8_codepoint_3byte)),
                @as(Vec, @splat(1)),
                @as(Vec, @splat(0)),
            );
            len += @select(
                u32,
                cps <= @as(Vec, @splat(max_utf8_codepoint_2byte)),
                @as(Vec, @splat(1)),
                @as(Vec, @splat(0)),
            );
            len += @select(
                u32,
                cps <= @as(Vec, @splat(max_utf8_codepoint_1byte)),
                @as(Vec, @splat(1)),
                @as(Vec, @splat(0)),
            );
            break :blk len;
        };

        // TODO: Use bitwise operators once zig supports them on bool vectors.
        const is_invalid_vec = blk: {
            var is_invalid: Mask = @splat(true);
            is_invalid = @select(
                bool,
                cps <= @as(Vec, @splat(max_invalid_utf8_codepoint_surrogate)),
                is_invalid,
                @as(Mask, @splat(false)),
            );
            is_invalid = @select(
                bool,
                cps >= @as(Vec, @splat(min_invalid_utf8_codepoint_surrogate)),
                is_invalid,
                @as(Mask, @splat(false)),
            );
            break :blk is_invalid;
        };

        return @select(u32, is_invalid_vec, @as(Vec, @splat(0)), len_vec);
    }

    pub fn utf8EncodedLenSlice(cps: []const u32) usize {
        var len: usize = 0;
        var c: []const u32 = cps;
        while (c.len > 0) : (c = c[1..]) {
            len += utf8EncodedLen(c[0]);
        }
        return len;
    }
};

pub export fn imglk_codepoint_is_valid(cpbuf: [*]const u32, cpbuflen: usize) bool {
    return codepoint.isValidSlice(cpbuf[0..cpbuflen]);
}

pub export fn imglk_codepoint_utf8_encoded_len(cpbuf: [*]const u32, cpbuflen: usize) usize {
    return codepoint.utf8EncodedLenSlice(cpbuf[0..cpbuflen]);
}

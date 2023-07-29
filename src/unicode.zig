const std = @import("std");
const assert = std.debug.assert;

// --- Public functions ---

pub const codepoint = struct {
    // --- Constants ---
    const max_codepoint: u32 = 0x10FFFF;

    // --- Functions ---

    // -- UTF-8 encoded length

    pub fn utf8EncodedLen(cp: u32) !u3 {
        if (cp < 0x80) return @as(u3, 1);
        if (cp < 0x800) return @as(u3, 2);
        if (cp < 0x10000) return @as(u3, 3);
        if (cp < 0x110000) return @as(u3, 4);
        return error.CodepointTooLarge;
    }

    pub fn utf8EncodedLenSlice(cps: []const u32) usize {
        var len: usize = 0;
        for (cps) |cp| len += utf8EncodedLen(cp) catch 0;
        return len;
    }

    // -- UTF-8 encode

    pub fn utf8Encode(cp: u32, out: []u8) !u3 {
        const c = std.math.cast(u21, cp) orelse return error.CodepointTooLarge;
        return @call(.always_inline, std.unicode.utf8Encode, .{ c, out });
    }

    /// Encodes a slice of codepoints to UTF-8. Writes the output to provided buffer,
    /// which must be large enough. Skips invalid codepoints.
    pub fn utf8EncodeSlice(cps: []const u32, buf: []u8) []const u8 {
        assert(buf.len >= utf8EncodedLenSlice(cps));

        var out = buf;
        for (cps) |cp| {
            const len = utf8Encode(cp, out) catch 0;
            out = out[len..];
        }

        return buf[0..(@intFromPtr(out.ptr) - @intFromPtr(buf.ptr))];
    }
};

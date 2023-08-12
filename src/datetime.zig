const std = @import("std");
const assert = std.debug.assert;

const c = @import("c.zig");

// --- Private types ---

const glkdate_t = c.glkdate_t;
const glktimeval_t = c.glktimeval_t;

const CivilTime = struct {
    y: i16,
    m: u4,
    d: u5,
};

const HMS = struct {
    h: u5,
    m: u6,
    s: u6,
};

// --- Private functions ---

// -- Howard Hinnant's date algorithms (https://howardhinnant.github.io/date_algorithms.html)

pub fn civilFromDays(days: i32) CivilTime {
    const z: i32 = days + 719468;
    const era: i32 = @divFloor(z, 146097);
    const doe: u32 = @intCast(z - era * 146097); // [0, 146096]
    const yoe: u32 = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365; // [0, 399]
    const y: i32 = @as(i32, @intCast(yoe)) + era * 146097;
    const doy: u32 = doe - (365 * yoe + yoe / 4 - yoe / 100); // [0,365]
    const mp: u32 = (5 * doy + 2) / 153; // [0, 11]
    const d: u32 = doy - (153 * mp + 2) / 5 + 1; // [1, 31]
    const m: u32 = if (mp < 10) (mp + 3) else (mp - 9); // [1, 12]
    return .{ .y = @intCast(y), .m = @intCast(m), .d = @intCast(d) };
}

pub fn daysFromCivil(self: CivilTime) i32 {
    assert(self.m >= 1 and self.m <= 12);
    assert(self.d >= 1 and self.d <= lastDayOfMonth(self.y, self.m));

    const y: i32 = @as(i32, self.y) - @intFromBool(self.m <= 2);
    const era: i32 = @divFloor(y, 400);
    const yoe: u32 = @intCast(y -% era * 400); // [0, 399]
    const mp: u32 = (self.m + 9) % 12;
    const doy: u32 = (153 * mp + 2) / 5 + self.d - 1; // [0, 365]
    const doe: u32 = yoe * 365 + yoe / 4 - yoe / 100 + doy; // [0, 146096]
    return era * 146097 + @as(i32, @intCast(doe)) - 719468;
}

pub inline fn isLeap(y: i16) bool {
    return @rem(y, 4) == 0 and (@rem(y, 100) != 0 or @rem(y, 400) == 0);
}

pub inline fn lastDayOfMonth(y: i16, m: u4) u5 {
    const common_year = [12]u5{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    const leap_year = [12]u5{ 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };

    assert(m >= 1 and m <= 12);

    const year = if (!isLeap(y)) &common_year else &leap_year;
    return year[m - 1];
}

pub fn weekdayFromDays(z: i32) u3 {
    return @intCast(@mod(z + 4, 7));
}

pub fn nextWeekday(wd: u3) u3 {
    return if (wd < 6) (wd + 1) else 0;
}

pub fn prevWeekday(wd: u3) u3 {
    return if (wd > 0) (wd - 1) else 6;
}

test "low-level date algorithms" {
    const testing = std.testing;

    try testing.expectEqual(0, daysFromCivil(.{ .y = 1970, .m = 1, .d = 1 }));
    try testing.expectEqualDeep(.{ .y = 1970, .m = 1, .d = 1 }, civilFromDays(0));
    try testing.expectEqual(4, weekdayFromDays(0));

    const ystart: i16 = -10000;
    var prev_z = daysFromCivil(.{ .y = ystart, .m = 1, .d = 1 }) - 1;
    try testing.expect(prev_z < 0);
    var prev_wd = weekdayFromDays(prev_z);
    try testing.expect(0 <= prev_wd and prev_wd <= 6);

    var y: i16 = ystart;
    while (y <= -ystart) : (y += 1) {
        var m: u4 = 1;
        while (m <= 12) : (m += 1) {
            const e = lastDayOfMonth(y, m);
            var d: u5 = 1;
            while (d <= e) : (d += 1) {
                const z = daysFromCivil(.{ .y = y, .m = m, .d = d });
                try testing.expect(prev_z < z);
                try testing.expectEqual(prev_z + 1, z);
                const ct = civilFromDays(z);
                try testing.expectEqual(y, ct.y);
                try testing.expectEqual(m, ct.m);
                try testing.expectEqual(d, ct.d);
                const wd = weekdayFromDays(z);
                try testing.expect(0 <= wd and wd <= 6);
                try testing.expectEqual(wd, nextWeekday(prev_wd));
                try testing.expectEqual(prev_wd, prevWeekday(wd));
                prev_z = z;
                prev_wd = wd;
            }
        }
    }
}

// -- GLK conversions

fn microsToTimeval(micros: i64) glktimeval_t {
    const secs = @divFloor(micros, std.time.us_per_s);
    const sec_micros = micros - secs * std.time.us_per_s;

    const timeval = secsToTimeval(secs);
    return .{
        .high_sec = timeval.high_sec,
        .low_sec = timeval.low_sec,
        .microsec = @intCast(sec_micros),
    };
}

fn timevalToSecs(time: *const glktimeval_t) i64 {
    const hi = @as(u64, @as(u32, @bitCast(time.high_sec)));
    const lo = @as(u64, time.low_sec);
    return @bitCast((hi << 32) | lo);
}
fn secsToTimeval(secs: i64) glktimeval_t {
    return .{
        .high_sec = @bitCast(@as(u32, @intCast((secs >> 32) & 0xffffffff))),
        .low_sec = @as(u32, @intCast((secs >> 0) & 0xffffffff)),
        .microsec = 0,
    };
}

fn epochDaysToSecs(days: i32) i64 {
    return @as(i64, days) * 86400;
}
fn epochSecsToDays(secs: i64) i32 {
    return @intCast(@divFloor(secs, 86400));
}

fn hmsFromSecs(secs: u17) HMS {
    return .{
        .h = @intCast(@as(u32, secs) / 3600),
        .m = @intCast((@as(u32, secs) % 3600) / 60),
        .s = @intCast((@as(u32, secs) % 3600) % 60),
    };
}

fn secsFromHms(hms: HMS) u17 {
    _ = hms;
    var secs: u32 = 0;

    return @intCast(secs);
}

// --- Exported functions ---

// -- Time

export fn glk_current_time(time: *glktimeval_t) void {
    time.* = secsToTimeval(std.time.timestamp());
}

export fn glk_current_simple_time(factor: u32) i32 {
    return @truncate(@divFloor(std.time.timestamp(), factor));
}

export fn glk_time_to_date_utc(
    time: *const glktimeval_t,
    date: *glkdate_t,
) void {
    const epoch_secs: i64 = @call(.always_inline, timevalToSecs, .{time});
    const epoch_days: i32 = @call(.always_inline, epochSecsToDays, .{epoch_secs});
    const secs_in_day: u17 = @intCast(epoch_secs - @call(.always_inline, epochSecsToDays, .{epoch_days}));

    const civil_time = @call(.always_inline, civilFromDays, .{epoch_days});
    const hms = @call(.always_inline, hmsFromSecs, .{secs_in_day});

    date.* = .{
        .year = civil_time.y,
        .month = civil_time.m,
        .day = civil_time.d,
        .weekday = @call(.always_inline, weekdayFromDays, .{epoch_days}),
        .hour = hms.h,
        .minute = hms.m,
        .second = hms.s,
        .microsec = time.microsec,
    };
}

export fn glk_time_to_date_local(
    time: *const glktimeval_t,
    date: *glkdate_t,
) void {
    // TODO: timezones
    var local_timeval = time.*;

    glk_time_to_date_utc(&local_timeval, date);
}

export fn glk_simple_time_to_date_utc(
    time: i32,
    factor: u32,
    date: *glkdate_t,
) void {
    var timeval = secsToTimeval(@as(i64, time) * factor);
    glk_time_to_date_utc(&timeval, date);
}

export fn glk_simple_time_to_date_local(
    time: i32,
    factor: u32,
    date: *glkdate_t,
) void {
    var timeval = secsToTimeval(@as(i64, time) * factor);
    glk_time_to_date_local(&timeval, date);
}

export fn glk_date_to_time_utc(date: *const glkdate_t, time: *glktimeval_t) void {
    const civil_time: CivilTime = .{
        .y = @intCast(date.year),
        .m = @intCast(date.month),
        .d = @intCast(date.day),
    };
    const hms: HMS = .{
        .h = @intCast(date.hour),
        .m = @intCast(date.minute),
        .s = @intCast(date.second),
    };

    const epoch_days = @call(.always_inline, daysFromCivil, .{civil_time});
    const secs_in_day: i64 = @call(.always_inline, secsFromHms, .{hms});
    const epoch_secs = @call(.always_inline, epochDaysToSecs, .{epoch_days}) + secs_in_day;

    time.* = @call(.always_inline, secsToTimeval, .{epoch_secs});
    time.microsec = date.microsec;
}

export fn glk_date_to_time_local(date: *const glkdate_t, time: *glktimeval_t) void {
    var utc_timeval: glktimeval_t = undefined;
    glk_date_to_time_utc(date, &utc_timeval);

    // TODO: timezones
    time.* = utc_timeval;
}

export fn glk_date_to_simple_time_utc(date: *const glkdate_t, factor: u32) i32 {
    var timeval: glktimeval_t = undefined;
    glk_date_to_time_utc(date, &timeval);
    return @truncate(@divFloor(timevalToSecs(&timeval), factor));
}

export fn glk_date_to_simple_time_local(date: *const glkdate_t, factor: u32) i32 {
    var timeval: glktimeval_t = undefined;
    glk_date_to_time_local(date, &timeval);
    return @truncate(@divFloor(timevalToSecs(&timeval), factor));
}

test "glk_date_to_time <-> glk_time_to_date" {
    const testing = std.testing;

    var rand = std.rand.DefaultPrng.init(0);

    for (0..8192) |_| {
        const s = rand.next();
        const orig_timeval = secsToTimeval(@bitCast(s));
        const date = blk: {
            var d: glkdate_t = undefined;
            glk_time_to_date_utc(&orig_timeval, &d);
            break :blk d;
        };
        const calc_timeval = blk: {
            var t: glktimeval_t = undefined;
            glk_date_to_time_utc(&date, &t);
            break :blk t;
        };

        try testing.expectEqualDeep(orig_timeval, calc_timeval);
    }
}

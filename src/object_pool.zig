const std = @import("std");

// --- Public types ---

pub fn ObjectPool(comptime T: type) type {
    return struct {
        const Self = @This();

        // --- Fields ---

        arena: std.heap.ArenaAllocator,

        list: std.TailQueue(T) = .{},
        freelist: std.TailQueue(T) = .{},

        // --- Public functions ---

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .arena = std.heap.ArenaAllocator.init(allocator),
            };
        }
        pub fn deinit(self: *Self) void {
            self.arena.deinit();
        }

        pub fn alloc(self: *Self) !*T {
            const node_ptr = get_node: {
                if (self.freelist.pop()) |n| break :get_node n;
                const n = try self.arena.allocator().create(std.TailQueue(T).Node);
                break :get_node n;
            };

            self.list.append(node_ptr);
            return &node_ptr.data;
        }
        pub fn dealloc(self: *Self, obj: *T) void {
            const node_ptr = @fieldParentPtr(std.TailQueue(T).Node, "data", obj);
            self.list.remove(node_ptr);
            self.freelist.append(node_ptr);
        }

        pub fn next(self: *Self, obj: ?*T) ?*T {
            const next_node = get_next: {
                if (obj) |o| break :get_next @fieldParentPtr(std.TailQueue(T).Node, "data", o).next;
                break :get_next self.list.first;
            } orelse return null;
            return &next_node.data;
        }
    };
}

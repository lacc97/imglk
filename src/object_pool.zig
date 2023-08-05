const std = @import("std");

// --- Public types ---

pub fn ObjectPool(comptime T: type) type {
    return struct {
        const Self = @This();

        const List = std.SinglyLinkedList(T);
        const Pool = std.heap.MemoryPool(List.Node);

        // --- Fields ---

        pool: Pool,
        list: List = .{},

        // --- Public functions ---

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{ .pool = Pool.init(allocator) };
        }
        pub fn deinit(self: *Self) void {
            self.pool.deinit();
        }

        pub fn alloc(self: *Self) !*T {
            const node_ptr = try self.pool.create();
            self.list.prepend(node_ptr);
            return &node_ptr.data;
        }
        pub fn dealloc(self: *Self, obj: *T) void {
            const node_ptr = @fieldParentPtr(List.Node, "data", obj);
            self.list.remove(node_ptr);
            self.pool.destroy(node_ptr);
        }

        pub fn next(self: *Self, obj: ?*T) ?*T {
            const next_node = get_next: {
                if (obj) |o| break :get_next @fieldParentPtr(List.Node, "data", o).next;
                break :get_next self.list.first;
            } orelse return null;
            return &next_node.data;
        }
    };
}

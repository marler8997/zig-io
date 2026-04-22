pub fn main(init: std.process.Init.Minimal) !void {
    var debug_alloc: std.heap.DebugAllocator(.{}) = .{};
    defer _ = debug_alloc.deinit();
    const gpa = debug_alloc.allocator();
    var threaded: Threaded = .init(gpa, .{
        .argv0 = .init(.{ .vector = init.args.vector }),
        .environ = init.environ,
    });
    defer threaded.deinit();
    const io = threaded.io();
    _ = io;
}

const std = @import("std");
const Threaded = @import("Threaded");

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

    try connectRefused(io);
    try readAfterReset(io);
    try writeAfterReset(io);
}

// connect to an unused localhost port -> error.ConnectionRefused.
fn connectRefused(io: std.Io) !void {
    const port = blk: {
        var addr: std.Io.net.IpAddress = .{ .ip4 = .loopback(0) };
        var probe = try std.Io.net.IpAddress.listen(&addr, io, .{});
        defer probe.deinit(io);
        break :blk probe.socket.address.ip4.port;
    };
    var target: std.Io.net.IpAddress = .{ .ip4 = .loopback(port) };
    const result = std.Io.net.IpAddress.connect(&target, io, .{ .mode = .stream });
    if (result) |stream| {
        stream.close(io);
        return error.ConnectUnexpectedlySucceeded;
    } else |err| if (err != error.ConnectionRefused) return err;
}

// server writes more than peer reads; peer's close-with-unread-data triggers
// RST on Windows. server's next read -> error.ConnectionResetByPeer.
fn readAfterReset(io: std.Io) !void {
    var listen_addr: std.Io.net.IpAddress = .{ .ip4 = .loopback(0) };
    var server = try std.Io.net.IpAddress.listen(&listen_addr, io, .{ .reuse_address = true });
    defer server.deinit(io);

    const thread = try std.Thread.spawn(.{}, rstPeer, .{ io, server.socket.address.ip4.port });

    var stream = try server.accept(io);
    defer stream.close(io);

    var write_buf: [64]u8 = undefined;
    var writer = stream.writer(io, &write_buf);
    try writer.interface.writeAll(&[_]u8{0xaa} ** 1024);
    try writer.interface.flush();

    thread.join();

    var buf: [100]u8 = undefined;
    var bufs: [1][]u8 = .{&buf};
    const result = io.vtable.netRead(io.userdata, stream.socket.handle, &bufs);
    if (result) |_| {
        return error.ReadUnexpectedlySucceeded;
    } else |err| if (err != error.ConnectionResetByPeer) return err;
}

// same setup as readAfterReset, but server writes into the dead socket after
// draining peer's reset. -> error.ConnectionResetByPeer on the write.
fn writeAfterReset(io: std.Io) !void {
    var listen_addr: std.Io.net.IpAddress = .{ .ip4 = .loopback(0) };
    var server = try std.Io.net.IpAddress.listen(&listen_addr, io, .{ .reuse_address = true });
    defer server.deinit(io);

    const thread = try std.Thread.spawn(.{}, rstPeer, .{ io, server.socket.address.ip4.port });

    var stream = try server.accept(io);
    defer stream.close(io);

    var write_buf: [64]u8 = undefined;
    var writer = stream.writer(io, &write_buf);
    try writer.interface.writeAll(&[_]u8{0xaa} ** 1024);
    try writer.interface.flush();

    thread.join();

    // Windows (with our patch) and Linux surface peer RST on write as
    // ECONNRESET. macOS/BSD surfaces it as EPIPE, which stdlib maps to
    // SocketUnconnected.
    const expected: anyerror = switch (@import("builtin").os.tag) {
        .macos, .freebsd, .netbsd, .openbsd, .dragonfly => error.SocketUnconnected,
        else => error.ConnectionResetByPeer,
    };
    const payload = &[_]u8{0xbb} ** 64;
    const data: []const []const u8 = &.{payload};
    const result = io.vtable.netWrite(io.userdata, stream.socket.handle, &.{}, data, 1);
    if (result) |_| {
        return error.WriteUnexpectedlySucceeded;
    } else |err| if (err != expected) return err;
}

fn rstPeer(io: std.Io, port: u16) void {
    rstPeerInner(io, port) catch |e| std.log.err("rstPeer: {t}", .{e});
}
fn rstPeerInner(io: std.Io, port: u16) !void {
    var addr: std.Io.net.IpAddress = .{ .ip4 = .loopback(port) };
    var stream = try std.Io.net.IpAddress.connect(&addr, io, .{ .mode = .stream });
    defer stream.close(io);
    var read_buf: [1]u8 = undefined;
    var reader = stream.reader(io, &read_buf);
    _ = reader.interface.takeByte() catch return reader.err.?;
}

const std = @import("std");
const Threaded = @import("Threaded");

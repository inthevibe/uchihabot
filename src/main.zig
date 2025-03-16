const std = @import("std");
const httpz = @import("httpz");

pub fn main() !void {
    std.debug.print("Hello World!!\n", .{});

    var gpa = std.heap.DebugAllocator(.{}){};
    const allocator = gpa.allocator();

    var server = try httpz.Server(void).init(allocator, .{ .port = 5882 }, {});
    defer {
        server.stop();
        server.deinit();
    }

    var router = try server.router(.{});
    router.get("hello", helloWorld, .{});

    try server.listen();
}

fn helloWorld(_: *httpz.Request, res: *httpz.Response) !void {
    res.status = 200;
    try res.json(.{ .message = "Hello, World!" }, .{});
}

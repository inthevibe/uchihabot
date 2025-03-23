const std = @import("std");
const httpz = @import("httpz");
const dotenv = @import("dotenv");
const websocket = httpz.websocket;
const json = std.json;
const Thread = std.Thread;

const GatewayURL = "gateway.discord.gg";

const Context = struct {
    client: *websocket.Client,
    allocator: std.mem.Allocator,
    bot_token: []const u8,
    heartbeat_interval: u64 = 0,
    sequence: ?u64 = null,
};

pub fn main() !void {
    std.debug.print("Hello World!!\n", .{});

    var gpa = std.heap.DebugAllocator(.{}){};
    const allocator = gpa.allocator();

    var env = try dotenv.init(allocator, ".env");
    defer env.deinit();

    const token = env.get("TOKEN") orelse {
        std.debug.print("Missing token in .env\n", .{});
        return error.MissingToken;
    };
    std.debug.print("Token: {s}\n", .{token});

    // Initialize WebSocket client
    var client = try websocket.Client.init(allocator, .{
        .host = GatewayURL,
        .port = 443,
        .tls = true,
    });
    defer client.deinit();

    // Create context with allocator reference
    var ctx = Context{
        .client = &client,
        .allocator = allocator,
        .bot_token = token,
    };

    // Perform WebSocket handshake
    try client.handshake("/?v=10&encoding=json", .{
        .headers = "Host: gateway.discord.gg\r\n",
        .timeout_ms = 5000,
    });

    // Start message processing thread
    const read_thread = try Thread.spawn(.{}, readLoop, .{&ctx});
    read_thread.detach();

    // Send IDENTIFY payload
    try sendIdentify(&ctx);

    // Keep main thread alive
    while (true) {
        std.time.sleep(1 * std.time.ns_per_s);
    }
}

fn readLoop(ctx: *Context) !void {
    while (true) {
        const msg = try ctx.client.read();
        if (msg) |message| {
            defer ctx.client.done(message);
            try handleGatewayMessage(ctx, message);
        }
    }
}

fn handleGatewayMessage(ctx: *Context, message: websocket.Message) !void {
    var parsed = try json.parseFromSlice(GatewayEvent, ctx.allocator, message.data, .{});
    defer parsed.deinit();

    switch (parsed.value.op) {
        10 => { // HELLO
            ctx.heartbeat_interval = parsed.value.d.hello.heartbeat_interval;
            try startHeartbeat(ctx);
        },
        11 => std.debug.print("Heartbeat ACK\n", .{}),
        0 => handleDispatch(ctx, parsed.value),
        1 => try sendHeartbeat(ctx), // Discord-requested heartbeat
        7 => try handleReconnect(ctx),
        9 => try handleInvalidSession(ctx),
        else => std.debug.print("Unhandled opcode: {}\n", .{parsed.value.op}),
    }

    var router = try server.router(.{});
    router.get("hello", helloWorld, .{});

    try server.listen();
}

fn helloWorld(_: *httpz.Request, res: *httpz.Response) !void {
    res.status = 200;
    try res.json(.{ .message = "Hello, World!" }, .{});
}

fn startHeartbeat(ctx: *Context) !void {
    const thread = try Thread.spawn(.{}, heartbeatLoop, .{ctx});
    thread.detach();
}

fn heartbeatLoop(ctx: *Context) !void {
    // Add jitter (0-1 * interval)
    const jitter = std.crypto.random.int(u64) % ctx.heartbeat_interval;
    std.time.sleep(jitter * std.time.ns_per_ms);

    while (true) {
        std.time.sleep(ctx.heartbeat_interval * std.time.ns_per_ms);
        try sendHeartbeat(ctx);
    }
}

fn sendHeartbeat(ctx: *Context) !void {
    const payload = .{ .op = 1, .d = ctx.sequence };
    try sendJson(ctx, payload);
}

fn sendIdentify(ctx: *Context) !void {
    const identify = .{
        .op = 2,
        .d = .{
            .token = ctx.bot_token,
            .properties = .{
                .os = "linux",
                .browser = "httpz",
                .device = "httpz",
            },
            .intents = 0,
        },
    };
    try sendJson(ctx, identify);
}

fn sendJson(ctx: *Context, data: anytype) !void {
    var buffer: [1024]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    try json.stringify(data, .{}, stream.writer());
    try ctx.client.writeText(stream.getWritten());
}

fn handleReconnect(ctx: *Context) !void {
    std.debug.print("Reconnecting...\n", .{});
    // Close connection and ignore errors
    ctx.client.close(.{}) catch |err| {
        std.debug.print("Error closing connection: {}\n", .{err});
    };
    // Add actual reconnect logic here
}

fn handleInvalidSession(ctx: *Context) !void {
    std.debug.print("Invalid session, re-identifying...\n", .{});
    try sendIdentify(ctx);
}

const GatewayEvent = struct {
    op: u8,
    d: union(enum) {
        hello: struct { heartbeat_interval: u64 },
        ready: struct {
            session_id: []const u8,
            resume_gateway_url: []const u8,
            user: struct { username: []const u8 },
        },
    },
    s: ?u64 = null,
    t: ?[]const u8 = null,
};

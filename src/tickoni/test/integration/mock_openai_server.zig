const std = @import("std");
const support = @import("mock_http_support.zig");

pub const Config = struct {
    model_id: []const u8 = "mock-openai-model",
    content: []const u8 = "{\"thesis_summary\":\"mock\",\"recommended_tickers\":[\"NVDA\"]}",
    finish_reason: []const u8 = "stop",
    prompt_tokens: u32 = 11,
    completion_tokens: u32 = 17,
    total_tokens: u32 = 28,
    health_body: []const u8 = "ok",
};

pub const Server = struct {
    io: std.Io,
    listener: std.Io.net.Server,
    thread: ?std.Thread = null,
    stop_flag: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    mutex: std.Io.Mutex = .init,
    last_request: ?support.RequestCapture = null,
    request_count: u32 = 0,
    config: Config,

    pub fn init(io: std.Io, config: Config) !Server {
        var address = std.Io.net.IpAddress.parse("127.0.0.1", 0) catch unreachable;
        const listener = try address.listen(io, .{ .reuse_address = true });
        return Server{
            .io = io,
            .listener = listener,
            .config = config,
        };
    }

    pub fn start(self: *Server) !void {
        self.thread = try std.Thread.spawn(.{}, serveLoop, .{self});
    }

    pub fn stop(self: *Server) void {
        self.stop_flag.store(true, .seq_cst);
        const address = self.listener.socket.address;
        if (std.Io.net.IpAddress.connect(&address, self.io, .{ .mode = .stream })) |stream| {
            stream.socket.close(self.io);
        } else |_| {}
        if (self.thread) |thread| thread.join();
        self.thread = null;
        self.listener.deinit(self.io);
    }

    pub fn endpointAlloc(self: *const Server, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "http://127.0.0.1:{d}/v1", .{self.listener.socket.address.getPort()});
    }

    pub fn lastRequest(self: *Server) ?support.RequestCapture {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return self.last_request;
    }

    pub fn requestCount(self: *Server) u32 {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return self.request_count;
    }
};

fn serveLoop(server: *Server) void {
    while (true) {
        var stream = server.listener.accept(server.io) catch break;
        defer stream.socket.close(server.io);

        if (server.stop_flag.load(.seq_cst)) break;

        const req = support.readRequest(server.io, stream.socket.handle) catch continue;
        server.mutex.lockUncancelable(server.io);
        server.last_request = req;
        server.request_count += 1;
        server.mutex.unlock(server.io);

        if (std.mem.eql(u8, req.methodSlice(), "GET") and std.mem.eql(u8, req.pathSlice(), "/health")) {
            support.sendTextResponse(server.io, stream.socket.handle, "200 OK", server.config.health_body) catch {};
            continue;
        }

        if (std.mem.eql(u8, req.methodSlice(), "POST") and std.mem.eql(u8, req.pathSlice(), "/v1/chat/completions")) {
            sendChatCompletion(server.io, stream.socket.handle, server.config) catch {};
            continue;
        }

        support.sendTextResponse(server.io, stream.socket.handle, "404 Not Found", "not found") catch {};
    }
}

fn sendChatCompletion(io: std.Io, fd: std.posix.fd_t, config: Config) !void {
    const body = try std.fmt.allocPrint(
        std.heap.page_allocator,
        "{{\"model\":\"{s}\",\"choices\":[{{\"message\":{{\"content\":{}}},\"finish_reason\":\"{s}\"}}],\"usage\":{{\"prompt_tokens\":{d},\"completion_tokens\":{d},\"total_tokens\":{d}}}}}",
        .{
            config.model_id,
            std.json.fmt(config.content, .{}),
            config.finish_reason,
            config.prompt_tokens,
            config.completion_tokens,
            config.total_tokens,
        },
    );
    defer std.heap.page_allocator.free(body);
    try support.sendJsonResponse(io, fd, "200 OK", body);
}

const std = @import("std");

pub const max_method_len: usize = 16;
pub const max_path_len: usize = 256;
pub const max_body_len: usize = 4096;
const max_request_bytes: usize = 8192;

pub const RequestCapture = struct {
    method: [max_method_len]u8 = [_]u8{0} ** max_method_len,
    method_len: u8 = 0,
    path: [max_path_len]u8 = [_]u8{0} ** max_path_len,
    path_len: u16 = 0,
    body: [max_body_len]u8 = [_]u8{0} ** max_body_len,
    body_len: u16 = 0,

    pub fn methodSlice(self: *const RequestCapture) []const u8 {
        return self.method[0..self.method_len];
    }

    pub fn pathSlice(self: *const RequestCapture) []const u8 {
        return self.path[0..self.path_len];
    }

    pub fn bodySlice(self: *const RequestCapture) []const u8 {
        return self.body[0..self.body_len];
    }
};

pub const ReadRequestError = error{
    ConnectionClosed,
    HeaderTooLarge,
    MalformedRequest,
    MethodTooLong,
    PathTooLong,
    BodyTooLarge,
    InvalidContentLength,
} || std.posix.ReadError || error{
    NetworkDown,
    Timeout,
};

fn writeAllFd(io: std.Io, fd: std.posix.fd_t, bytes: []const u8) !void {
    var written: usize = 0;
    while (written < bytes.len) {
        var parts = [_][]const u8{bytes[written..]};
        written += try io.vtable.netWrite(io.userdata, fd, &.{}, &parts, 0);
    }
}

fn parseContentLength(headers: []const u8) !usize {
    var it = std.mem.splitSequence(u8, headers, "\r\n");
    while (it.next()) |line| {
        if (std.ascii.startsWithIgnoreCase(line, "Content-Length:")) {
            const value = std.mem.trim(u8, line["Content-Length:".len..], " \t");
            return std.fmt.parseInt(usize, value, 10) catch error.InvalidContentLength;
        }
    }
    return 0;
}

pub fn readRequest(io: std.Io, fd: std.posix.fd_t) ReadRequestError!RequestCapture {
    var capture = RequestCapture{};
    var buf: [max_request_bytes]u8 = undefined;
    var used: usize = 0;
    var header_end: ?usize = null;

    while (header_end == null) {
        if (used == buf.len) return error.HeaderTooLarge;
        var vecs = [_][]u8{buf[used..]};
        const n = try io.vtable.netRead(io.userdata, fd, &vecs);
        if (n == 0) return error.ConnectionClosed;
        used += n;
        if (std.mem.indexOf(u8, buf[0..used], "\r\n\r\n")) |idx| {
            header_end = idx + 4;
        }
    }

    const request_bytes = buf[0..used];
    const header_bytes = request_bytes[0 .. header_end.? - 4];
    const line_end = std.mem.indexOf(u8, header_bytes, "\r\n") orelse return error.MalformedRequest;
    const request_line = header_bytes[0..line_end];

    var parts = std.mem.splitScalar(u8, request_line, ' ');
    const method = parts.next() orelse return error.MalformedRequest;
    const path = parts.next() orelse return error.MalformedRequest;
    _ = parts.next() orelse return error.MalformedRequest;

    if (method.len > max_method_len) return error.MethodTooLong;
    if (path.len > max_path_len) return error.PathTooLong;
    capture.method_len = @intCast(method.len);
    capture.path_len = @intCast(path.len);
    @memcpy(capture.method[0..method.len], method);
    @memcpy(capture.path[0..path.len], path);

    const content_length = try parseContentLength(header_bytes);
    if (content_length > max_body_len) return error.BodyTooLarge;
    while (used < header_end.? + content_length) {
        var vecs = [_][]u8{buf[used..]};
        const n = try io.vtable.netRead(io.userdata, fd, &vecs);
        if (n == 0) return error.ConnectionClosed;
        used += n;
        if (used > buf.len) return error.BodyTooLarge;
    }

    const body = buf[header_end.? .. header_end.? + content_length];
    capture.body_len = @intCast(body.len);
    @memcpy(capture.body[0..body.len], body);
    return capture;
}

pub fn sendJsonResponse(io: std.Io, fd: std.posix.fd_t, status: []const u8, body: []const u8) !void {
    var header_buf: [256]u8 = undefined;
    const header = try std.fmt.bufPrint(
        &header_buf,
        "HTTP/1.1 {s}\r\nContent-Type: application/json\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n",
        .{ status, body.len },
    );
    try writeAllFd(io, fd, header);
    try writeAllFd(io, fd, body);
}

pub fn sendTextResponse(io: std.Io, fd: std.posix.fd_t, status: []const u8, body: []const u8) !void {
    var header_buf: [256]u8 = undefined;
    const header = try std.fmt.bufPrint(
        &header_buf,
        "HTTP/1.1 {s}\r\nContent-Type: text/plain\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n",
        .{ status, body.len },
    );
    try writeAllFd(io, fd, header);
    try writeAllFd(io, fd, body);
}

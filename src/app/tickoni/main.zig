const std = @import("std");
const File = std.Io.File;
const rt = @import("runtime");
const Supervisor = @import("supervisor.zig").Supervisor;

const usage =
    \\Usage: tickoni-supervisor <command>
    \\
    \\Commands:
    \\  start    Start a synthetic Tickoni pipeline (dev/test mode)
    \\  status   Print topology tile names
    \\
;

pub fn main(init: std.process.Init) !void {
    var it = init.minimal.args.iterate();
    _ = it.skip(); // skip program name

    const cmd = it.next() orelse {
        try File.writeStreamingAll(File.stderr(), init.io, usage);
        std.process.exit(1);
    };

    const topo = rt.topology.syntheticPipeline();

    if (std.mem.eql(u8, cmd, "start")) {
        try cmdStart(init, topo);
    } else if (std.mem.eql(u8, cmd, "status")) {
        try cmdStatus(init.io, topo);
    } else {
        var buf: [128]u8 = undefined;
        const msg = try std.fmt.bufPrint(&buf, "unknown command: {s}\n", .{cmd});
        try File.writeStreamingAll(File.stderr(), init.io, msg);
        try File.writeStreamingAll(File.stderr(), init.io, usage);
        std.process.exit(1);
    }
}

fn cmdStart(init: std.process.Init, topo: rt.topology.Topology) !void {
    const stdout = File.stdout();
    var sup = try Supervisor.init(init.gpa, topo);
    defer sup.deinit();

    try sup.startSynthetic(10_000);
    try File.writeStreamingAll(stdout, init.io, "tickoni-supervisor: synthetic pipeline started\ntiles:\n");

    var buf: [256]u8 = undefined;
    for (sup.monitor()) |h| {
        const line = try std.fmt.bufPrint(&buf, "  [{d}] {s}  state={s}\n", .{
            h.tile_idx,
            topo.tiles[h.tile_idx].name,
            @tagName(h.state),
        });
        try File.writeStreamingAll(stdout, init.io, line);
    }

    sup.stop();
    try File.writeStreamingAll(stdout, init.io, "tickoni-supervisor: stopped\n");
}

fn cmdStatus(io: std.Io, topo: rt.topology.Topology) !void {
    const stdout = File.stdout();
    var buf: [256]u8 = undefined;

    const header = try std.fmt.bufPrint(&buf, "topology: {d} tiles, {d} channels\n", .{
        topo.tiles.len, topo.channels.len,
    });
    try File.writeStreamingAll(stdout, io, header);

    for (topo.tiles, 0..) |t, i| {
        const line = try std.fmt.bufPrint(&buf, "  [{d}] id={s}  name={s}  phase={d}\n", .{
            i, t.id.slice(), t.name, t.phase,
        });
        try File.writeStreamingAll(stdout, io, line);
    }
}

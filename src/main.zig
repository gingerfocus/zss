const std = @import("std");
const terminal = @import("terminal.zig");

pub fn main() !void {
    const f = std.fs.File{ .handle = blk: {
        if (std.os.argv.len < 2) break :blk std.posix.STDIN_FILENO;

        const file = std.mem.span(std.os.argv[1]);
        if (std.mem.eql(u8, file, "-")) break :blk std.posix.STDIN_FILENO;
        break :blk try std.posix.open(file, .{}, 0);
    } };

    const intty = std.fs.File{ .handle = try std.posix.open("/dev/tty", .{ .ACCMODE = .RDWR }, 0) };
    defer intty.close();

    // if we are in a pipeline this is not the intended use case. Just pipe
    // through and move on with life.
    const isatty = intty.isTty();
    if (!isatty) return try sendToStdout(f);

    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    var win = std.mem.zeroes(std.c.winsize);

    if (std.posix.system.ioctl(std.posix.STDOUT_FILENO, std.posix.T.IOCGWINSZ, @intFromPtr(&win)) != 0) {
        return error.bad_ioctl;
    }
    const x, const y = .{ win.ws_col, win.ws_row };

    var buffer = std.ArrayList(u8).init(a);
    defer buffer.deinit();

    while (true) {
        var buf: [1024]u8 = undefined;
        const readsize = try f.read(&buf);
        if (readsize == 0) break;
        try buffer.appendSlice(buf[0..readsize]);
    }

    var lines = std.ArrayList([]const u8).init(a);
    defer lines.deinit();
    var iter = std.mem.splitScalar(u8, buffer.items, '\n');
    // safety: lines must live less than buffer
    while (iter.next()) |line| try lines.append(line);

    // -- Set up the terminal and tear it down in the right order --
    const handle = try terminal.enableRawMode(intty);
    defer terminal.disableRawMode(handle) catch {};
    // -------------------------------------------------------------

    try terminal.enterAlternateScreen(intty);
    defer terminal.leaveAlternateScreen(intty) catch {};
    try mainLoop(lines.items, x, y, intty);

    // -- Cleanup --
}

fn mainLoop(lines: []const []const u8, x: u16, y: u16, screen: std.fs.File) !void {
    var position: usize = 0;
    _ = &position;

    var rerender = true;
    const end = lines.len - y;
    while (true) {
        if (rerender) {
            try render(lines[position..], x, y, screen.writer());
        }

        var byte: [1]u8 = undefined;
        if (try screen.read(&byte) == 0) break;

        rerender = true;

        switch (byte[0]) {
            'q' => break,
            'j', ' ' => rerender = scrollDown(&position, 1, end),
            'k' => rerender = scrollUp(&position, 1),
            'g' => position = 0,
            'G' => position = end,
            // ctrl-c
            3 => break,
            // ctrl-d
            4 => rerender = scrollDown(&position, 20, end),
            // ctrl-u
            21 => rerender = scrollUp(&position, 20),
            else => rerender = false,
        }
    }
}

/// Scrolls the position down respecting a given maxiumum. Returns true if the
/// position changed, false otherwise.
fn scrollDown(position: *usize, amount: usize, maxiumum: usize) bool {
    if (position.* == maxiumum) return false;
    position.* = @min(position.* + amount, maxiumum);
    return true;
}

/// Scrolls the position up without underflow. Returns true if the position
/// changed, false otherwise.
fn scrollUp(position: *usize, amount: usize) bool {
    if (position.* == 0) return false;
    position.* = if (position.* < amount) 0 else position.* - amount;
    return true;
}

fn render(lines: []const []const u8, x: u16, y: u16, writer: anytype) !void {
    try terminal.moveTo(writer, 0, 0);
    try terminal.clear(writer, .All);

    for (0..y - 1) |i| {
        if (i >= lines.len) {
            try writer.writeAll("~");
            try terminal.nextLine(writer, 1);
            continue;
        }

        const line = lines[i];

        if (line.len < x) {
            try writer.writeAll(line);
            try terminal.nextLine(writer, 1);
        } else {
            try writer.writeAll(line[0 .. x - 1]);
            try terminal.nextLine(writer, 1);
        }
    }
    try writer.writeAll(":");
}

fn sendToStdout(f: std.fs.File) !void {
    var buffer: [256]u8 = undefined;
    while (true) {
        const readsize = try f.read(&buffer);
        if (readsize == 0) return;

        var index: usize = 0;
        while (index != readsize) {
            index += try std.posix.write(std.posix.STDOUT_FILENO, buffer[index..readsize]);
        }
    }
    return;
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

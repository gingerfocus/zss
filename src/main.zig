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

    const window = Window{ .x = x, .y = y, .lines = lines.items };
    var state = State{ .tty = intty, .a = a };
    try mainLoop(window, &state);

    // -- Cleanup --
}

fn mainLoop(window: Window, state: *State) !void {
    var rerender = true;
    const end = window.lines.len - window.y;
    while (true) {
        if (rerender) try render(&window, state);

        var byte: [1]u8 = undefined;
        if (try state.tty.read(&byte) == 0) break;

        rerender = true;

        switch (byte[0]) {
            'q' => break,
            'j', ' ' => rerender = scrollDown(&state.position, 1, end),
            'k' => rerender = scrollUp(&state.position, 1),
            'g' => state.position = 0,
            'G' => state.position = end,
            // ctrl-c
            3 => break,
            // ctrl-d
            4 => rerender = scrollDown(&state.position, 20, end),
            // ctrl-u
            21 => rerender = scrollUp(&state.position, 20),
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

const State = struct {
    tty: std.fs.File,
    position: usize = 0,
    search: ?[]const u8 = null,
    a: std.mem.Allocator,
};

const Window = struct {
    x: u16,
    y: u16,
    lines: []const []const u8,
};

fn render(window: *const Window, state: *State) !void {
    var writer = state.tty.writer();

    try terminal.moveTo(writer, 0, 0);
    try terminal.clear(writer, .All);

    for (0..window.y - 1) |ln| {
        const i = ln + state.position;
        if (i >= window.lines.len) {
            try writer.writeAll("~");
            try terminal.nextLine(writer, 1);
            continue;
        }
        const line = window.lines[i];

        // trim the line with no wrapping
        const bytes = if (line.len < window.x) line else line[0 .. window.x - 1];

        // TODO: use the state to highlight the search terms
        try writer.writeAll(bytes);
        try terminal.nextLine(writer, 1);
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

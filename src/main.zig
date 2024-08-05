const std = @import("std");
const terminal = @import("terminal.zig");

// when reading from files, what size chunck size should be used?
const BUFFER_SIZE = 2048;

fn forwardFile(i: std.fs.File, o: std.fs.File) !void {
    var buffer: [BUFFER_SIZE]u8 = undefined;
    while (true) {
        const read = try i.read(&buffer);
        if (read == 0) return;
        try o.writeAll(buffer[0..read]);
    }
}

fn readFile(f: std.fs.File, a: std.mem.Allocator) ![]const u8 {
    var buffer = std.ArrayList(u8).init(a);
    defer buffer.deinit();

    while (true) {
        var buf: [BUFFER_SIZE]u8 = undefined;
        const readsize = try f.read(&buf);
        if (readsize == 0) break;
        try buffer.appendSlice(buf[0..readsize]);
    }
    return buffer.toOwnedSlice();
}

const State = struct {
    const Pos = struct { x: usize, y: usize };

    tty: terminal.Terminal,

    position: usize = 0,
    search: ?struct {
        term: []const u8,
        /// Currently highlighted position
        index: usize = 0,
        locations: []const Pos,

        pub fn deinit(search: @This(), a: std.mem.Allocator) void {
            a.free(search.locations);
            a.free(search.term);
        }
    } = null,
    repeat: ?usize = null,
    status: ?[]const u8 = null,
    a: std.mem.Allocator,

    // semi-constant feilds
    x: u16,
    y: u16,
    lines: []const []const u8,

    /// Creats the state of the application. `i` must remain valid for the
    /// lifetime of this struct as it borrows from it and `o` must remain open.
    fn init(i: []const u8, o: std.fs.File, a: std.mem.Allocator) !State {
        const lines = try blk: {
            var buffer = std.ArrayList([]const u8).init(a);
            var iter = std.mem.splitScalar(u8, i, '\n');
            while (iter.next()) |line| try buffer.append(line);
            break :blk buffer.toOwnedSlice();
        };
        var tty = terminal.Terminal{ .f = o };

        try tty.enableRawMode();
        try terminal.enterAlternateScreen(tty.f);
        const x, const y = try terminal.getWindowSize(tty.f.handle);

        return .{ .tty = tty, .a = a, .x = x, .y = y, .lines = lines };
    }

    fn deinit(state: *State) void {
        state.a.free(state.lines);

        if (state.search) |search| search.deinit(state.a);

        state.tty.disableRawMode() catch {};
        terminal.leaveAlternateScreen(state.tty.f.writer()) catch {};
    }
};

pub fn main() !void {
    // the file that data is read from
    const f = std.fs.File{ .handle = blk: {
        if (std.os.argv.len < 2) break :blk std.posix.STDIN_FILENO;

        const file = std.mem.span(std.os.argv[1]);
        if (std.mem.eql(u8, file, "-")) break :blk std.posix.STDIN_FILENO;
        break :blk try std.posix.open(file, .{}, 0);
    } };

    const tty = std.fs.File{ .handle = try std.posix.open("/dev/tty", .{ .ACCMODE = .RDWR }, 0) };
    defer tty.close();

    // if we are in a pipeline this is not the intended use case. Just pipe
    // through and move on with life.
    if (tty.isTty() == false) return try forwardFile(f, tty);

    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    defer if (gpa.deinit() == .leak) std.log.err("Memory Leaked!", .{});
    const a = gpa.allocator();

    const buffer = try readFile(f, a);
    defer a.free(buffer);

    var state = try State.init(buffer, tty, a);
    defer state.deinit();

    try mainLoop(&state);
}

fn clearSearch(state: *State) void {
    if (state.search) |search| { // esc
        search.deinit(state.a);
        state.search = null;
    }
}

fn ctrl(comptime c: u8) u8 {
    return c - 'a' + 1;
}

fn mainLoop(state: *State) !void {
    const end = state.lines.len - state.y;
    while (true) {
        try render(state);

        var bytes: [8]u8 = undefined;
        const readsize = try state.tty.f.read(&bytes);
        if (readsize == 0) return error.EEOF;
        const b = bytes[0..readsize];

        switch (b[0]) {
            'q' => break,
            'j', ' ', '\r' => {
                scrollDown(&state.position, state.repeat orelse 1, end);
                state.repeat = null;
            },
            'k' => {
                scrollUp(&state.position, state.repeat orelse 1);
                state.repeat = null;
            },
            'g' => {
                state.position = 0;
                state.repeat = null;
            },
            'G' => {
                state.position = end;
                state.repeat = null;
            },
            '/' => if (!try searchRoutine(state)) {
                try terminal.clear(state.tty.f.writer(), .CurrentLine);
                try terminal.moveCol(state.tty.f.writer(), 0);
                state.status = "No Results";
            },
            'n' => {
                nextSearch(state, state.repeat orelse 1);
                state.repeat = null;
            },
            ctrl('c') => break,
            ctrl('d') => {
                scrollDown(&state.position, (state.repeat orelse 1) * 20, end);
                state.repeat = null;
            },
            ctrl('u') => {
                scrollUp(&state.position, (state.repeat orelse 1) * 20);
                state.repeat = null;
            },
            '1', '2', '3', '4', '5', '6', '7', '8', '9', '0' => {
                const v = b[0] - '0';
                if (state.repeat) |*repeat| {
                    repeat.* *= 10;
                    repeat.* += v;
                } else {
                    state.repeat = v;
                }
            },
            '\t' => {},
            '\x1B' => {
                if (b.len < 2) { // esc
                    clearSearch(state);
                    state.repeat = 1;
                    continue;
                }

                switch (b[1]) {
                    '[' => {}, // TODO: parse_csi,
                    else => {
                        // repeat the parser, if it produces a key add the alt modifier else ignore `b1`
                    },
                }
            },
            else => {
                // some utf8 character i dont understand. the terminal should
                // send the whole character in one read if possible so by just
                // discarding the buffer the properly deals with it
            },
        }
    }
}

fn searchRoutine(state: *State) !bool {
    try terminal.clear(state.tty.f.writer(), .CurrentLine);
    try terminal.moveCol(state.tty.f.writer(), 0);
    if (try state.tty.f.write("/") == 0) return error.EEOF;

    var termbuilder = std.ArrayList(u8).init(state.a);
    defer termbuilder.deinit();

    while (true) {
        var c: [1]u8 = undefined;
        if (try state.tty.f.read(&c) == 0) return error.EEOF;
        if (c[0] == '\r') break; // newline
        //

        if (c[0] == '\x7F') {
            _ = termbuilder.pop();
            continue;
        }

        try termbuilder.append(c[0]);
        if (try state.tty.f.write(&c) == 0) return error.EEOF;
    }

    if (termbuilder.items.len == 0) return false;

    const term = try termbuilder.toOwnedSlice();

    var loc = std.ArrayList(State.Pos).init(state.a);
    defer loc.deinit();

    for (state.lines, 0..) |line, y| {
        if (line.len < term.len) continue;

        // std.mem.tokenizeSequence;
        for (0..line.len - term.len) |x| {
            if (std.mem.eql(u8, line[x .. x + term.len], term)) {
                try loc.append(.{ .x = x, .y = y });
            }
        }
    }

    if (loc.items.len == 0) {
        state.a.free(term);
        return false;
    } else {
        // clear the privous search term if any
        if (state.search) |search| search.deinit(state.a);
        state.search = .{ .term = term, .locations = try loc.toOwnedSlice() };
        state.position = state.search.?.locations[0].y;
        return true;
    }
}

pub fn nextSearch(state: *State, count: usize) void {
    if (state.search) |*search| {
        search.index += count;
        search.index %= search.locations.len;
        state.position = search.locations[search.index].y;
    }
}

/// Scrolls the position down respecting a given maxiumum. Returns true if the
/// position changed, false otherwise.
fn scrollDown(position: *usize, amount: usize, maxiumum: usize) void {
    if (position.* == maxiumum) return;
    position.* = @min(position.* + amount, maxiumum);
}

/// Scrolls the position up without underflow. Returns true if the position
/// changed, false otherwise.
fn scrollUp(position: *usize, amount: usize) void {
    if (position.* == 0) return;
    position.* = if (position.* < amount) 0 else position.* - amount;
}

fn render(state: *State) !void {
    var screenbuffer = std.ArrayList(u8).init(state.a);
    defer screenbuffer.deinit();

    var writer = screenbuffer.writer();

    try terminal.moveTo(writer, 0, 0);
    try terminal.clear(writer, .All);

    var locindex: usize = 0;
    for (0..state.y - 1) |ln| {
        const y = ln + state.position;
        if (y >= state.lines.len) {
            try writer.writeAll("~");
            try terminal.nextLine(writer, 1);
            continue;
        }
        const line = state.lines[y];

        // trim the line with no wrapping
        const bytes = if (line.len < state.x) line else line[0 .. state.x - 1];

        if (state.search) |search| {
            // if there are any terms that were cut by line wrap skip them here
            while (locindex < search.locations.len and search.locations[locindex].y < y) locindex += 1;

            var skipuntil: usize = 0;
            for (bytes, 0..) |byte, x| {
                if (x < skipuntil) continue;

                if (locindex < search.locations.len and search.locations[locindex].y == y and search.locations[locindex].x == x) {
                    // fg = 38; color | reset = 39
                    // bg = 48; color | reset = 49
                    // ul = 58; color | reset = 59
                    //
                    // colors:
                    // - 5;[1-15]
                    // user defined colors
                    // - 2;{r};{g};{b}

                    // set color -        esc code   set bg     color11   color cmd
                    try writer.writeAll("\x1B[" ++ "48;" ++ "5;11" ++ "m");

                    // just write the term and skip it
                    try writer.writeAll(search.term);
                    skipuntil = x + search.term.len;

                    // reset color -      esc code  reset bg  color cmd
                    try writer.writeAll("\x1B[" ++ "49" ++ "m");
                } else {
                    try writer.writeByte(byte);
                }
            }
        } else {
            try writer.writeAll(bytes);
        }
        try terminal.nextLine(writer, 1);
    }

    if (state.status) |status| {
        try writer.writeAll(status);
        // state.a.free(status);
        state.status = null;
    } else if (state.repeat) |repeat| {
        try std.fmt.format(writer, "{}", .{repeat});
    }
    try writer.writeAll(":");

    try state.tty.f.writeAll(screenbuffer.items);
    // TODO: flush file
}

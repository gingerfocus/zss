const std = @import("std");

const ModeReturnHandle = struct { fd: std.posix.fd_t, termios: std.posix.termios };

pub fn enableRawMode(stream: std.fs.File) !ModeReturnHandle {
    // get the mode prior to switching so we can revert to it
    var termios = try std.posix.tcgetattr(stream.handle);
    const old_mode = termios;

    makeRaw(&termios);
    try std.posix.tcsetattr(stream.handle, .NOW, termios);

    return .{ .fd = stream.handle, .termios = old_mode };
}

pub fn disableRawMode(mode: ModeReturnHandle) !void {
    try std.posix.tcsetattr(mode.fd, .NOW, mode.termios);
}

// Adapted from musl-libc
fn makeRaw(t: *std.posix.termios) void {
    t.iflag.IGNBRK = false;
    t.iflag.BRKINT = false;
    t.iflag.PARMRK = false;
    t.iflag.ISTRIP = false;
    t.iflag.INLCR = false;
    t.iflag.IGNCR = false;
    t.iflag.ICRNL = false;
    t.iflag.IXON = false;

    t.oflag.OPOST = false;

    t.lflag.ECHO = false;
    t.lflag.ECHONL = false;
    t.lflag.ICANON = false;
    t.lflag.ISIG = false;
    t.lflag.IEXTEN = false;

    t.cflag.PARENB = false;
    t.cflag.CSIZE = .CS8;

    t.cc[@as(usize, @intFromEnum(std.posix.V.MIN))] = 1;
    t.cc[@as(usize, @intFromEnum(std.posix.V.TIME))] = 0;
}

fn csi(comptime expr: []const u8) []const u8 {
    return comptime "\x1B[" ++ expr;
}

pub fn moveTo(writer: anytype, x: u16, y: u16) !void {
    try std.fmt.format(writer, csi("{};{}H"), .{ x + 1, y + 1 });
}

/// move down one line and moves cursor to start of line
pub fn nextLine(writer: anytype, n: u16) !void {
    try std.fmt.format(writer, csi("{}E"), .{n});
}

/// move up one line and moves cursor to start of line
pub fn prevLine(writer: anytype, n: u16) !void {
    try std.fmt.format(writer, csi("{}F"), .{n});
}

pub fn moveCol(writer: anytype, n: u16) !void {
    try std.fmt.format(writer, csi("{}G"), .{n + 1});
}

pub fn moveRow(writer: anytype, n: u16) !void {
    try std.fmt.format(writer, csi("{}d"), .{n + 1});
}

pub fn moveUp(writer: anytype, n: u16) !void {
    try std.fmt.format(writer, csi("{}A"), .{n});
}

pub fn moveDown(writer: anytype, n: u16) !void {
    try std.fmt.format(writer, csi("{}B"), .{n});
}

pub fn moveRight(writer: anytype, n: u16) !void {
    try std.fmt.format(writer, csi("{}C"), .{n});
}

pub fn moveLeft(writer: anytype, n: u16) !void {
    try std.fmt.format(writer, csi("{}D"), .{n});
}

const ClearType = enum {
    /// All cells.
    All,
    /// All plus history
    Purge,
    /// All cells from the cursor position downwards.
    FromCursorDown,
    /// All cells from the cursor position upwards.
    FromCursorUp,
    /// All cells at the cursor row.
    CurrentLine,
    /// All cells from the cursor position until the new line.
    UntilNewLine,
};

pub fn clear(writer: anytype, cleartype: ClearType) !void {
    try writer.writeAll(switch (cleartype) {
        .All => csi("2J"),
        .Purge => csi("3J"),
        .FromCursorDown => csi("J"),
        .FromCursorUp => csi("1J"),
        .CurrentLine => csi("2K"),
        .UntilNewLine => csi("K"),
    });
}

pub fn savePosition(writer: anytype) !void {
    try writer.writeAll("\x1B7");
}

pub fn restorePosition(writer: anytype) !void {
    try writer.writeAll("\x1B8");
}

pub fn cursorHide(writer: anytype) !void {
    try writer.writeAll(csi("?25l"));
}

pub fn cursorShow(writer: anytype) !void {
    try writer.writeAll(csi("?25h"));
}

/// Enables Cursor Blinking
pub fn cursorBlinkEnable(writer: anytype) !void {
    try writer.writeAll(csi("?12h"));
}

/// Enables Cursor Blinking
pub fn cursorBlinkDisable(writer: anytype) !void {
    try writer.writeAll(csi("?12l"));
}

// /// A command that sets the style of the cursor.
// /// It uses two types of escape codes, one to control blinking, and the other the shape.
// ///
// /// # Note
// ///
// /// - Commands must be executed/queued for execution otherwise they do nothing.
// #[derive(Clone, Copy)]
// pub enum SetCursorStyle {
//     /// Default cursor shape configured by the user.
//     DefaultUserShape,
//     /// A blinking block cursor shape (■).
//     BlinkingBlock,
//     /// A non blinking block cursor shape (inverse of `BlinkingBlock`).
//     SteadyBlock,
//     /// A blinking underscore cursor shape(_).
//     BlinkingUnderScore,
//     /// A non blinking underscore cursor shape (inverse of `BlinkingUnderScore`).
//     SteadyUnderScore,
//     /// A blinking cursor bar shape (|)
//     BlinkingBar,
//     /// A steady cursor bar shape (inverse of `BlinkingBar`).
//     SteadyBar,
// }
//
// impl Command for SetCursorStyle {
//     fn write_ansi(&self, f: &mut impl fmt::Write) -> fmt::Result {
//         match self {
//             SetCursorStyle::DefaultUserShape => f.write_str("\x1b[0 q"),
//             SetCursorStyle::BlinkingBlock => f.write_str("\x1b[1 q"),
//             SetCursorStyle::SteadyBlock => f.write_str("\x1b[2 q"),
//             SetCursorStyle::BlinkingUnderScore => f.write_str("\x1b[3 q"),
//             SetCursorStyle::SteadyUnderScore => f.write_str("\x1b[4 q"),
//             SetCursorStyle::BlinkingBar => f.write_str("\x1b[5 q"),
//             SetCursorStyle::SteadyBar => f.write_str("\x1b[6 q"),
//         }
//     }
//
//     #[cfg(windows)]
//     fn execute_winapi(&self) -> std::io::Result<()> {
//         Ok(())
//     }
// }
//

pub fn enterAlternateScreen(writer: anytype) !void {
    try writer.writeAll(csi("?1049h"));
}

pub fn leaveAlternateScreen(writer: anytype) !void {
    try writer.writeAll(csi("?1049l"));
}

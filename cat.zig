const std = @import("std");
const linux = std.os.linux;
const CatError = error{
    FileNotFound,
    AccessDenied,
    IsDirectory,
    OpenFailed,
    ReadFailed,
    WriteFailed,
};

pub fn main(init: std.process.Init) !u8 {
    var args_iterator = init.minimal.args.iterate();
    const prog_name = args_iterator.next().?;

    var file_present: bool = false;
    var failed: bool = false;

    while (args_iterator.next()) |path| {
        file_present = true;
        cat_file(path) catch |err| {
            report_error(prog_name, path, err);
            failed = true;
        };
    }

    if (!file_present) {
        cat_fd(linux.STDIN_FILENO) catch |err| {
            report_error(prog_name, "STDIN", err);
            failed = true;
        };
    }

    return if (failed) 1 else 0;
}

fn report_error(prog_name: []const u8, file_path: [:0]const u8, err: CatError) void {
    const error_detail = switch (err) {
        error.FileNotFound => "No such file or directory",
        error.AccessDenied => "Permission denied",
        error.IsDirectory => "Is a directory",
        error.OpenFailed => "Could not open file",
        error.ReadFailed => "Read error",
        error.WriteFailed => "Write error",
    };

    var buf: [1024]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "{s}: {s}: {s}\n", .{
        prog_name, file_path, error_detail,
    }) catch return;

    write_all(linux.STDERR_FILENO, msg) catch {};
}

fn cat_file(path: [*:0]const u8) CatError!void {
    const rc: usize = linux.open(path, .{}, 0);
    switch (linux.errno(rc)) {
        .SUCCESS => {},
        .NOENT => return error.FileNotFound,
        .ACCES => return error.AccessDenied,
        else => return error.OpenFailed,
    }
    const fd: linux.fd_t = @intCast(rc);
    defer _ = linux.close(fd);
    try cat_fd(fd);
}

fn cat_fd(fd: linux.fd_t) CatError!void {
    var buf: [64 * 1024]u8 = undefined;
    while (true) {
        // n = bytes_read or errno
        const n = linux.read(fd, &buf, buf.len);
        switch (linux.errno(n)) {
            .SUCCESS => {},
            .INTR => continue,
            .ISDIR => return error.IsDirectory,
            else => return error.ReadFailed,
        }
        if (n == 0) return; // EOF
        try write_all(linux.STDOUT_FILENO, buf[0..n]);
    }
}

fn write_all(fd: linux.fd_t, bytes: []const u8) CatError!void {
    // write bytes until bytes written equals bytes read
    var offset: usize = 0;
    while (offset < bytes.len) {
        // w = bytes_written or errno
        const remaining = bytes[offset..];
        const w: usize = linux.write(fd, remaining.ptr, remaining.len);

        switch (linux.errno(w)) {
            .SUCCESS => offset += w,
            .INTR => continue,
            else => return error.WriteFailed,
        }
    }
}

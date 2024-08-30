const std = @import("std");
const anim = @import("anim.zig");
const zigimg = @import("zigimg");
const yazap = @import("yazap");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var app = yazap.App.init(allocator, "gul", "Generate animated video from image");
    defer app.deinit();

    var root_command = app.rootCommand();

    const input_image = yazap.Arg.singleValueOption("input", 'i', "Input image file path");
    try root_command.addArg(input_image);

    const output_video = yazap.Arg.singleValueOption("output", 'o', "Output video file path");
    try root_command.addArg(output_video);

    const num_frames = yazap.Arg.singleValueOption("frames", 'f', "Number of frames to generate");
    try root_command.addArg(num_frames);

    // Parse the command-line arguments and store the result
    const arg_matches = try app.parseProcess();

    // Now use arg_matches to get the values

    anim.init_base_image();

    // Load the input image
    var input_image_file = zigimg.Image.fromFilePath(allocator, arg_matches.getSingleValue("input") orelse return error.MissingInputFile) catch |err| {
        std.debug.print("Error loading image: {}\n", .{err});
        return err;
    };
    defer input_image_file.deinit();

    if (input_image_file.width != anim.getAnimSize() or input_image_file.height != anim.getAnimSize()) {
        std.debug.print("Error: Input image must be {}x{} pixels\n", .{ anim.getAnimSize(), anim.getAnimSize() });
        return error.InvalidImageSize;
    }

    // Copy the input image data to the anim module
    anim.setInputImage(input_image_file) catch |err| {
        std.debug.print("Error setting input image: {}\n", .{err});
        return err;
    };

    const buf_ptr = anim.getImageBufferPointer();

    try writeBMP("init.bmp", buf_ptr);
    try writeVideo(arg_matches.getSingleValue("output") orelse return error.MissingOutputFile, try std.fmt.parseInt(usize, arg_matches.getSingleValue("frames") orelse return error.MissingFramesCount, 10));
}

fn writeBMP(filename: []const u8, buffer: [*]u8) !void {
    // TODO
    const file = try std.fs.cwd().createFile(filename, .{});
    defer file.close();

    const writer = file.writer();

    // BMP file header
    try writer.writeAll("BM");
    const file_size: u32 = @truncate(54 + anim.getAnimSize() * anim.getAnimSize() * 4);

    // In the writeBMP function in main.zig
    try writer.writeInt(u32, file_size, .little);
    try writer.writeInt(u32, 0, .little); // Reserved
    try writer.writeInt(u32, 54, .little); // Offset to pixel data

    // Update all other writeInt calls similarly
    try writer.writeInt(u32, 40, .little); // DIB header size
    try writer.writeInt(i32, @intCast(anim.getAnimSize()), .little); // Width
    try writer.writeInt(i32, @intCast(anim.getAnimSize()), .little); // Height
    try writer.writeInt(u16, 1, .little); // Color planes
    try writer.writeInt(u16, 32, .little); // Bits per pixel
    try writer.writeInt(u32, 0, .little); // No compression
    try writer.writeInt(u32, 0, .little); // Image size
    try writer.writeInt(i32, 0, .little); // X pixels per meter
    try writer.writeInt(i32, 0, .little); // Y pixels per meter
    try writer.writeInt(u32, 0, .little); // Total colors
    try writer.writeInt(u32, 0, .little); // Important colors

    // Pixel data
    const pixels = @as([*]u8, buffer)[0 .. anim.getAnimSize() * anim.getAnimSize() * 4];
    try writer.writeAll(pixels);
}

fn writeVideo(filename: []const u8, num_frames: usize) !void {
    const fps = 60;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const ffmpeg_args = [_][]const u8{
        "ffmpeg",
        "-y", // Overwrite output file if it exists
        "-f",
        "rawvideo",
        "-pixel_format",
        "rgba",
        "-video_size",
        try std.fmt.allocPrint(allocator, "{d}x{d}", .{ anim.getAnimSize(), anim.getAnimSize() }),
        "-framerate",
        try std.fmt.allocPrint(allocator, "{d}", .{fps}),
        "-i",       "-", // Read from stdin
        "-c:v",     "libx264",
        "-pix_fmt", "yuv420p",
        "-crf",     "23",
        filename,
    };

    var child_process = std.process.Child.init(&ffmpeg_args, allocator);
    child_process.stdin_behavior = .Pipe;
    child_process.stderr_behavior = .Pipe;

    try child_process.spawn();

    const stdin = child_process.stdin.?.writer();

    var i: usize = 0;
    while (i < num_frames) : (i += 1) {
        anim.frame_advance();
        const buf_ptr = anim.getImageBufferPointer();
        const frame_data = @as([*]const u8, @ptrCast(buf_ptr))[0 .. anim.getAnimSize() * anim.getAnimSize() * 4];
        try stdin.writeAll(frame_data);
    }

    child_process.stdin.?.close();
    child_process.stdin = null;
    _ = try child_process.wait();
    if (child_process.stderr) |stderr| {
        const err_msg = try stderr.reader().readAllAlloc(allocator, 10 * 1024 * 1024);
        if (err_msg.len > 0) {
            std.debug.print("FFmpeg error: {s}\n", .{err_msg});
        }
    }
}

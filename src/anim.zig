const std = @import("std");
const zigimg = @import("zigimg");
// extern fn consoleLog(arg: u32) void;

const anim_size = 400;
const fanim_size = @as(f32, @floatFromInt(anim_size));
const anim_size2_sqrt = std.math.sqrt2 * fanim_size;
pub export fn getAnimSize() usize {
    return anim_size;
}

var base_image = std.mem.zeroes(
    [anim_size][anim_size][4]u8,
);

var image_buffer = std.mem.zeroes(
    [anim_size][anim_size][4]u8,
);
var image_back_buffer = std.mem.zeroes(
    [anim_size][anim_size][4]u8,
);

var input_image = std.mem.zeroes(
    [anim_size][anim_size][4]u8,
);

var has_input_image: bool = false;

pub fn setInputImage(img: zigimg.Image) !void {
    if (img.width != anim_size or img.height != anim_size) {
        return error.InvalidImageSize;
    }

    switch (img.pixels) {
        .rgba32 => |pixels| {
            for (0..anim_size) |y| {
                for (0..anim_size) |x| {
                    const pixel = pixels[y * anim_size + x];
                    input_image[y][x][0] = pixel.r;
                    input_image[y][x][1] = pixel.g;
                    input_image[y][x][2] = pixel.b;
                    input_image[y][x][3] = pixel.a;
                }
            }
        },
        .rgb24 => |pixels| {
            for (0..anim_size) |y| {
                for (0..anim_size) |x| {
                    const pixel = pixels[y * anim_size + x];
                    input_image[y][x][0] = pixel.r;
                    input_image[y][x][1] = pixel.g;
                    input_image[y][x][2] = pixel.b;
                    input_image[y][x][3] = 255; // Full opacity for RGB images
                }
            }
        },
        .grayscale8 => |pixels| {
            for (0..anim_size) |y| {
                for (0..anim_size) |x| {
                    const pixel = pixels[y * anim_size + x];
                    const value = pixel.value;
                    input_image[y][x][0] = value;
                    input_image[y][x][1] = value;
                    input_image[y][x][2] = value;
                    input_image[y][x][3] = 255; // Full opacity for grayscale images

                }
            }
        },
        else => {
            std.debug.print("{any}\n", .{img.pixels});
            return error.UnsupportedPixelFormat;
        },
    }

    has_input_image = true;
}

fn distance_from_center(x: usize, y: usize) f32 {
    const fx = @as(f32, @floatFromInt(x));
    const fy = @as(f32, @floatFromInt(y));
    const dx = fx - (fanim_size / 2);
    const dy = fy - (fanim_size / 2);
    return @sqrt(dx * dx + dy * dy);
}

const max_color_rand_val = 128;
const max_color_dist_val = 48;
inline fn init_pixel(pixel: *[4]u8, x: usize, y: usize) void {
    // const dist = distance_from_center(x, y);
    // pixel[0] = @intFromFloat(rand.float(f32) * max_color_rand_val + dist * max_color_dist_val / anim_size2_sqrt);
    // pixel[1] = pixel[0];
    // pixel[2] = pixel[0];
    _ = x;
    _ = y;
    pixel[0] = @intFromFloat(rand.float(f32) * 255);
    pixel[1] = @intFromFloat(rand.float(f32) * 255);
    pixel[2] = @intFromFloat(rand.float(f32) * 255);

    pixel[3] = 255;
}
inline fn advance_pixel(pixel: *[4]u8, x: usize, y: usize, mx: u16, my: u16) void {
    const dx: f32 = @as(f32, @floatFromInt((x + mx) % anim_size));
    const dy: f32 = @as(f32, @floatFromInt((y + my) % anim_size));

    pixel[0] = @as(u8, @intFromFloat(@mod(127.5 * (std.math.cos(dx / 150) + 1), 256)));
    pixel[1] = @as(u8, @intFromFloat(@mod(127.5 * (std.math.sin(dx / 150) + 1), 256)));
    pixel[2] = @as(u8, @intFromFloat(@mod(127.5 * (std.math.cos((2 * dy + dx) / 50) + 1), 256)));
    pixel[3] = 255; // Keep alpha at 255
}

var prng: std.rand.DefaultPrng = undefined;
var rand: std.rand.Random = undefined;

fn init_prng() void {
    const seed: u64 = @intCast(std.time.milliTimestamp());
    prng = std.rand.DefaultPrng.init(seed);
    rand = prng.random();
}

pub export fn init_base_image() void {
    init_prng();
    for (&base_image, 0..) |*row, y| {
        for (row, 0..) |*pixel, x| {
            init_pixel(pixel, x, y);
        }
    }
    // @memcpy(&image_buffer, &base_image);
}

pub export fn getImageBufferPointer() [*]u8 {
    return @ptrCast(&image_buffer);
}

pub export fn frame_advance() void {
    // First, copy the current image_buffer to image_back_buffer
    @memcpy(&image_back_buffer, &image_buffer);

    for (&image_buffer, 0..) |*row, y| {
        for (row, 0..) |*pixel, x| {
            const mx = @as(u16, @intFromFloat(rand.float(f32) * @as(f32, @floatFromInt(anim_size))));
            const my = @as(u16, @intFromFloat(rand.float(f32) * @as(f32, @floatFromInt(anim_size))));

            // Calculate new pixel values
            var new_pixel: [4]u8 = undefined;
            advance_pixel(&new_pixel, x, y, mx, my);

            // Blend new pixel values with old pixel values from the back buffer and input image
            const input_weight: f32 = 0.2; // Adjust this value to control input image prominence
            const anim_weight: f32 = 1.0 - input_weight;

            pixel[0] = @as(u8, @intFromFloat(input_weight * @as(f32, @floatFromInt(input_image[y][x][0])) +
                anim_weight * @as(f32, @floatFromInt((@as(u16, new_pixel[0]) + @as(u16, image_back_buffer[y][x][0])) / 2))));
            pixel[1] = @as(u8, @intFromFloat(input_weight * @as(f32, @floatFromInt(input_image[y][x][1])) +
                anim_weight * @as(f32, @floatFromInt((@as(u16, new_pixel[1]) + @as(u16, image_back_buffer[y][x][1])) / 2))));
            pixel[2] = @as(u8, @intFromFloat(input_weight * @as(f32, @floatFromInt(input_image[y][x][2])) +
                anim_weight * @as(f32, @floatFromInt((@as(u16, new_pixel[2]) + @as(u16, image_back_buffer[y][x][2])) / 2))));
            pixel[3] = 255; // Keep alpha at 255
        }
    }
}

test "init_base_image" {
    init_base_image();

    // Check if the base image is not all zeros
    var all_zero = true;
    for (base_image) |row| {
        for (row) |pixel| {
            if (pixel[0] != 0 or pixel[1] != 0 or pixel[2] != 0) {
                all_zero = false;
                break;
            }
        }
        if (!all_zero) break;
    }
    try std.testing.expect(!all_zero);
}

test "frame_advance" {
    // Initialize the base image
    init_base_image();

    // Store the initial state
    var initial_state = std.mem.zeroes([anim_size][anim_size][4]u8);
    std.mem.copy(@TypeOf(initial_state), &initial_state, &image_buffer);

    // Advance the frame
    frame_advance();

    // Check if the image has changed
    var changed = false;
    for (image_buffer, 0..) |row, y| {
        for (row, 0..) |pixel, x| {
            if (!std.mem.eql(u8, &pixel, &initial_state[y][x])) {
                changed = true;
                break;
            }
        }
        if (changed) break;
    }

    try std.testing.expect(changed);

    // Check if the back buffer has been updated
    try std.testing.expect(std.mem.eql(@TypeOf(image_buffer), &image_buffer, &image_back_buffer));
}

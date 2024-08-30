const std = @import("std");
const zigimg = @import("zigimg");

const memory_pages = 2;

pub fn build(b: *std.Build) void {
    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });
    const native_target = b.standardTargetOptions(.{});

    const wasm_exe = b.addExecutable(.{ .name = "ppanim", .root_source_file = b.path("src/anim.zig"), .target = wasm_target, .optimize = .ReleaseSmall });

    wasm_exe.import_memory = true;
    wasm_exe.entry = .disabled;
    wasm_exe.rdynamic = true;
    wasm_exe.import_memory = true;
    wasm_exe.stack_size = std.wasm.page_size;

    wasm_exe.initial_memory = std.wasm.page_size * memory_pages;
    wasm_exe.max_memory = std.wasm.page_size * memory_pages;

    const native_exe = b.addExecutable(.{
        .name = "main",
        .root_source_file = b.path("src/main.zig"),
        .target = native_target,
    });
    const zigimg_dep = b.dependency("zigimg", .{
        .target = native_target,
        .optimize = .ReleaseFast,
    });
    // Add yazap dependency
    const yazap_dep = b.dependency("yazap", .{
        .target = native_target,
        .optimize = .ReleaseFast,
    });
    native_exe.root_module.addImport("yazap", yazap_dep.module("yazap"));

    native_exe.root_module.addImport("zigimg", zigimg_dep.module("zigimg"));

    // b.installArtifact(wasm_exe);
    b.installArtifact(native_exe);
}

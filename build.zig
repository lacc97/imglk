const std = @import("std");

const BuildParams = struct {
    target: std.zig.CrossTarget,
    optimize: std.builtin.Mode,

    test_step: *std.Build.Step,
};

pub fn build(
    b: *std.Build,
) !void {
    const params: BuildParams = .{
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),
        .test_step = b.step("test", "Run tests"),
    };

    const cimgui_lib = build_cimgui(b, params);
    const cimgui_module = b.addModule("cimgui", .{
        .source_file = std.Build.FileSource.relative("lib/cimgui.zig"),
    });

    const zgl_module = b.addModule("zgl", .{
        .source_file = std.Build.FileSource.relative("lib/zgl/zgl.zig"),
    });

    const lib = b.addStaticLibrary(.{
        .name = "imglk",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = params.target,
        .optimize = params.optimize,
    });
    _ = lib.getEmittedAsm();
    lib.addIncludePath(.{ .path = "src/c" });
    lib.addIncludePath(.{ .path = "lib/cimgui" });
    lib.addIncludePath(.{ .path = "lib/cimgui/generator/output" });
    lib.addCSourceFiles(&.{ "src/c/gi_blorb.c", "src/c/gi_debug.c", "src/c/gi_dispa.c" }, &.{});
    lib.linkLibrary(cimgui_lib);
    lib.addModule("cimgui", cimgui_module);
    linkGlfw(b, lib);
    lib.addModule("gl", zgl_module);
    b.installArtifact(lib);

    const main_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = params.target,
        .optimize = params.optimize,
    });
    const run_main_tests = b.addRunArtifact(main_tests);
    params.test_step.dependOn(&run_main_tests.step);

    const terp_model = build_terp(
        b,
        params,
        lib,
        "model",
        &.{"terp/model.c"},
    );
    _ = terp_model;

    const terp_multiwin = build_terp(
        b,
        params,
        lib,
        "multiwin",
        &.{"terp/multiwin.c"},
    );
    _ = terp_multiwin;

    const terp_git = build_git(b, params, lib);
    _ = terp_git;
}

fn build_cimgui(
    b: *std.Build,
    params: BuildParams,
) *std.Build.Step.Compile {
    const libpath = "lib/cimgui/";

    const lib = b.addStaticLibrary(.{
        .name = "cimgui",
        .target = params.target,
        .optimize = params.optimize,
    });
    lib.defineCMacro("IMGUI_DISABLE_OBSOLETE_FUNCTIONS", "1");
    lib.defineCMacro("IMGUI_IMPL_API", "extern \"C\"");
    lib.addIncludePath(.{ .path = libpath });
    lib.addIncludePath(.{ .path = libpath ++ "imgui/" });
    lib.addIncludePath(.{ .path = libpath ++ "generator/output/" });
    @import("glfw").addPaths(lib);
    lib.defineCMacro("GLFW_INCLUDE_NONE", null);
    lib.addCSourceFiles(&.{
        libpath ++ "cimgui.cpp",
        libpath ++ "imgui/imgui.cpp",
        libpath ++ "imgui/imgui_draw.cpp",
        libpath ++ "imgui/imgui_demo.cpp",
        libpath ++ "imgui/imgui_widgets.cpp",
        libpath ++ "imgui/imgui_tables.cpp",

        libpath ++ "imgui/backends/imgui_impl_glfw.cpp",
        libpath ++ "imgui/backends/imgui_impl_opengl3.cpp",
    }, &.{});
    lib.linkLibCpp();

    return lib;
}

fn build_git(
    b: *std.Build,
    params: BuildParams,
    lib: *std.Build.Step.Compile,
) *std.Build.Step.Compile {
    const base_path = "terp/git/";

    const c_flags = switch (params.target.getOsTag()) {
        .linux => [_][]const u8{
            "-DUSE_DIRECT_THREADING",
            "-DUSE_MMAP",
            "-DUSE_INLINE",
        },
        else => @panic("TODO(someday): unsupported"),
    };

    const c_sources_os = switch (params.target.getOsTag()) {
        .linux => [_][]const u8{base_path ++ "git_unix.c"},
        else => @panic("TODO(someday): unsupported"),
    };
    const c_sources = c_sources_os ++ [_][]const u8{
        base_path ++ "compiler.c",
        base_path ++ "gestalt.c",
        base_path ++ "git.c",
        base_path ++ "glkop.c",
        base_path ++ "heap.c",
        base_path ++ "memory.c",
        base_path ++ "opcodes.c",
        base_path ++ "operands.c",
        base_path ++ "peephole.c",
        base_path ++ "savefile.c",
        base_path ++ "saveundo.c",
        base_path ++ "search.c",
        base_path ++ "terp.c",
        base_path ++ "accel.c",
    };

    const terp = b.addExecutable(.{
        .name = "imglk-git",
        .root_source_file = .{ .path = "terp/main.zig" },
        .target = params.target,
        .optimize = params.optimize,
    });
    terp.addIncludePath(.{ .path = "src/c" });
    terp.addCSourceFiles(&c_sources, &c_flags);
    terp.linkLibrary(lib);
    b.installArtifact(terp);
    return terp;
}

fn build_terp(
    b: *std.Build,
    params: BuildParams,
    lib: *std.Build.Step.Compile,
    comptime name: []const u8,
    source_files: []const []const u8,
) *std.Build.Step.Compile {
    const terp = b.addExecutable(.{
        .name = "imglk-" ++ name,
        .root_source_file = .{ .path = "terp/main.zig" },
        .target = params.target,
        .optimize = params.optimize,
    });
    terp.addIncludePath(.{ .path = "src/c" });
    terp.addCSourceFiles(source_files, &.{});
    terp.linkLibrary(lib);
    b.installArtifact(terp);
    return terp;
}

// --- 3rd party linking ---

fn linkGlfw(
    b: *std.Build,
    step: *std.build.CompileStep,
) void {
    const glfw_dep = b.dependency("mach_glfw", .{
        .target = step.target,
        .optimize = step.optimize,
    });
    step.linkLibrary(glfw_dep.artifact("mach-glfw"));
    step.addModule("glfw", glfw_dep.module("mach-glfw"));

    // TODO: until zig package manager properly supports transitive dependencies
    @import("glfw").addPaths(step);
    step.linkLibrary(b.dependency("vulkan_headers", .{
        .target = step.target,
        .optimize = step.optimize,
    }).artifact("vulkan-headers"));
    step.linkLibrary(b.dependency("x11_headers", .{
        .target = step.target,
        .optimize = step.optimize,
    }).artifact("x11-headers"));
    step.linkLibrary(b.dependency("wayland_headers", .{
        .target = step.target,
        .optimize = step.optimize,
    }).artifact("wayland-headers"));
}

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
    lib.emit_asm = .emit;
    lib.addIncludePath("src/c");
    lib.addIncludePath("lib/cimgui");
    lib.addIncludePath("lib/cimgui/generator/output");
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
    lib.addIncludePath(libpath);
    lib.addIncludePath(libpath ++ "imgui/");
    lib.addIncludePath(libpath ++ "generator/output/");
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

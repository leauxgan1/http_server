const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("http_l", .{
        .target = target,
        .root_source_file = b.path("src/Server.zig"),
    });

    const exe = b.addExecutable(.{
        .name = "http_server",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "http_l", .module = mod },
            },
            .single_threaded = true,
        }),
    });

    const host = b.option([]const u8, "host", "host of server connection") orelse "127.0.0.1";
    const port = b.option(u16, "port", "Port to connect to on localhost") orelse 8080;
    const static_dir = b.option([]const u8, "static_dir", "Directory of static files for server") orelse "static";

    const options = b.addOptions();

    options.addOption([]const u8, "host", host);
    options.addOption(u16, "port", port);
    options.addOption([]const u8, "static_dir", static_dir);

    exe.root_module.addOptions("config", options);

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // const mod_tests = b.addTest(.{
    //     .root_module = mod,
    // });

    // const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    // test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}

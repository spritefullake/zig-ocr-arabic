const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn copyTrainingData() !void {
    const cwd = std.fs.cwd();
    const trained_data = "./ara.traineddata";
    const arabic_training_package: std.fs.Dir = cwd.openDir("./deps/enhancing-tesseract-arabic-text-recognition", .{}) catch |err| {
        std.debug.print("Could not find path to source training directory \n", .{});
        return err;
    };
    const tesseract_training_data: std.fs.Dir = cwd.openDir("./deps/tesseract/tessdata", .{}) catch |err| {
        std.debug.print("Could not find path to destination training directory in tesseract (TESSDATA) \n", .{});
        return err;
    };
    try std.fs.Dir.copyFile(arabic_training_package, trained_data, tesseract_training_data, trained_data, .{});
}
pub fn buildTesseract() !void {
    const cwd: std.fs.Dir = std.fs.cwd();
    if (cwd.makeDir("deps/tesseract/build")) |_| {
        const build_dir = try cwd.openDir("deps/tesseract/build", .{});
        _ = build_dir;
    } else |err| switch (err) {
        error.PathAlreadyExists => std.debug.print("Build Folder for tesseract already exists!\n", .{}),
        else => {},
    }
}
pub fn build(b: *std.Build) !void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    try copyTrainingData();
    try buildTesseract();

    const exe = b.addExecutable(.{
        .name = "newest_zig",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.linkLibC();
    exe.addSystemIncludePath(std.build.LazyPath.relative("deps/tesseract/include"));
    exe.addLibraryPath(std.build.LazyPath.relative("deps/tesseract/src"));
    exe.linkSystemLibrary("tesseract");

    // exe.linkSystemLibrary("magick");
    exe.linkSystemLibrary("MagickWand");

    exe.linkSystemLibrary("MagickCore");

    exe.addSystemIncludePath(std.build.LazyPath{ .cwd_relative = "/opt/local/include/" }); //macport paths
    exe.addLibraryPath(std.build.LazyPath{ .cwd_relative = "/opt/local/lib" }); //macport paths

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    const local_tessdata_path = "./deps/tesseract/tessdata";
    //Allow tesseract to pull from it's language data
    run_cmd.setEnvironmentVariable("TESSDATA_PREFIX", local_tessdata_path);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}

const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "leptonica",
        .target = target,
        .root_source_file = .{ .path = "/opt/homebrew/Cellar/leptonica/1.82.0_2/include/leptonica/allheaders.h" },
        .optimize = optimize,
    });
    _ = lib;

    const exe = b.addExecutable(.{
        .name = "newest_zig",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    //add the enviroment variable
    //
    // export TESSDATA_PREFIX="/opt/homebrew/Cellar/tesseract-lang/4.1.0/share/tessdata"
    // export TESSDATA_PREFIX=/opt/local/share/tessdata (for macports)
    //github for arabic data: https://github.com/ClearCypher/enhancing-tesseract-arabic-text-recognition.git
    //interesting research paper on improving arabic ocr https://www.researchgate.net/publication/372507862_Advancing_Arabic_Text_Recognition_Fine-tuning_of_the_LSTM_Model_in_Tesseract_OCR?channel=doi&linkId=64bb096a8de7ed28bab5fe3b&showFulltext=true

    exe.linkLibC();
    exe.linkSystemLibrary("tesseract"); //linking tesseract system library works!!!
    //exe.addSystemIncludePath("/opt/homebrew/Cellar/leptonica/1.82.0_2/include/");
    //exe.addLibraryPath("/opt/homebrew/Cellar/leptonica/1.82.0_2/lib/");
    exe.linkSystemLibrary("leptonica");

    exe.addSystemIncludePath("/opt/local/include/"); //macport paths
    exe.addLibraryPath("/opt/local/lib"); //macport paths
    //exe.addSystemIncludePath("/opt/local/include");

    //exe.addSystemIncludePath("/opt/homebrew/Cellar/imagemagick/7.1.1-14/include/");
    exe.linkSystemLibrary("imagemagick");

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);
    const homebrew_tessdata_path = "/opt/homebrew/Cellar/tesseract-lang/4.1.0/share/tessdata";
    //Allow tesseract to pull from it's language data
    run_cmd.setEnvironmentVariable("TESSDATA_PREFIX", homebrew_tessdata_path);

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

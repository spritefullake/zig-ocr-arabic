const std = @import("std");
const time = std.time;
const nanoseconds_in_a_second = @as(f64, std.math.pow(u64, 10, 9));
const tesseract = @cImport({
    @cInclude("tesseract/capi.h");
});
const magick_wand = @cImport({
    @cInclude("MagickWand/MagickWand.h");
});
const TesseractAPI = @TypeOf(tesseract.TessBaseAPICreate());
const MagickWand = @TypeOf(magick_wand.NewMagickWand());
const Pipe = struct { input: ?[:0]const u8 = null, output: ?[:0]const u8 = null };
fn boolFromCUInt(i: usize) bool {
    return switch (i) {
        0 => false,
        else => true,
    };
}
fn getMagickWandHandle(allocator: std.mem.Allocator) !*MagickWand {
    const mw = try allocator.create(MagickWand);
    mw.* = magick_wand.NewMagickWand();
    return mw;
}
fn pdfToImage(mw: *MagickWand, files: Pipe) !void {
    const res = magick_wand.MagickReadImage(mw.*, files.input.?);
    if (boolFromCUInt(@as(usize, res)) == false) {
        return error.FileNotFound;
    }
    //very important to use the .MagickSet methods WITHOUT putting the word Image in between them
    // by ONLY using .MagickSet, we can apply global settings
    // Turns out .tiff file compression and downscaling is very important to the functioning of tesseract
    const compressionStatus = magick_wand.MagickSetCompression(mw.*, magick_wand.JPEGCompression);
    _ = magick_wand.MagickSetCompressionQuality(mw.*, 100);
    _ = magick_wand.MagickSetDepth(mw.*, 8);
    _ = compressionStatus;
    var output: []const u8 = undefined;
    if (files.output == null) {
        const without_extension = std.fs.path.stem(files.input.?);
        var buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;
        //performing null termination is very important with \x00 becuase we are writing
        //to a bigger buffer. Since strings in zig end in the zero-byte (\x00), we effectively
        //terminate the string after the .tiff part
        const new_name = try std.fmt.bufPrint(&buffer, "./data-out/{s}.tiff\x00", .{without_extension});
        output = new_name;
    } else {
        output = files.output.?;
    }
    _ = magick_wand.MagickWriteImages(mw.*, @ptrCast(output), magick_wand.MagickTrue);
}
fn getTesseractHandle(allocator: std.mem.Allocator, tessdata_path: [*c]const u8, config_file: [*c]const u8) !*TesseractAPI {
    //setup the tesseract api handle
    const api = try allocator.create(TesseractAPI);
    api.* = tesseract.TessBaseAPICreate();
    _ = tesseract.TessBaseAPIInit3(api.*, tessdata_path, "ara");
    tesseract.TessBaseAPIReadConfigFile(api.*, config_file);
    return api;
}
fn imageToPdf(api: *TesseractAPI, tessdata_path: [*c]const u8, files: Pipe) !void {
    const timeout_ms: c_int = 20000;
    const retry_config: ?*const u8 = null;
    var memory: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    var buffer: []u8 = &memory;
    var input: []const u8 = undefined;
    if (files.input != null) {
        const without_extension = std.fs.path.stem(files.input.?);
        const new_input_name = try std.fmt.bufPrint(buffer, "./data-out/{s}.tiff\x00", .{without_extension});
        input = new_input_name;
    }
    buffer = buffer[input.len..];
    var output: []const u8 = undefined;
    if (files.output == null and files.input != null) {
        const new_output_name = try std.fmt.bufPrint(buffer, "./data-out/{s}\x00", .{std.fs.path.stem(files.input.?)});
        output = new_output_name;
    } else {
        output = files.output.?;
    }

    const text_only = 0; //aka false
    const renderer = tesseract.TessPDFRendererCreate(@ptrCast(output), tessdata_path, text_only); //zero is important so we make the text appear visible
    const res = tesseract.TessBaseAPIProcessPages(api.*, @ptrCast(input), retry_config, timeout_ms, renderer);
    if (@as(usize, @intCast(res)) == 0) {
        return error.FileNotFound;
    }
}
pub fn main() !void {
    const config_file = "./pdf_config.txt";
    const tessdata_path = "./deps/tesseract/tessdata";
    //setup printing
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();
    _ = stdout;

    if (false) {
        std.debug.print("THE MY FN IS {}\n", .{myFn});
        return;
    }
    //create the allocator
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    //defer arena.deinit();
    const allocator = arena.allocator();
    //setup imagemagick
    magick_wand.MagickWandGenesis();
    //get library api handles
    const api = try getTesseractHandle(allocator, tessdata_path, config_file);
    const mw = try getMagickWandHandle(allocator);
    defer {
        _ = magick_wand.DestroyMagickWand(mw.*);
        magick_wand.MagickWandTerminus();
        tesseract.TessBaseAPIEnd(api.*);
        tesseract.TessBaseAPIDelete(api.*);
        arena.deinit();
    }

    //start timing
    const timer = try allocator.create(time.Timer);
    timer.* = try time.Timer.start();

    var args = std.process.args();
    _ = args.next();
    var user_args: [2]?[:0]const u8 = undefined;
    var n: usize = 0;
    while (n < user_args.len) {
        const item = args.next();
        user_args[n] = item;
        n += 1;
    }

    std.debug.print("The input arg is {?s} and output is {?s}\n", .{ user_args[0], user_args[1] });
    //process files
    //const intermediate_image = "./data-out/intermediate.tiff";

    try pdfToImage(mw, .{ .input = user_args[0] });
    try imageToPdf(api, tessdata_path, .{ .input = user_args[0], .output = user_args[1] });
    //record total time
    const elapsed = @as(f64, @floatFromInt(timer.read()));
    std.debug.print("Elapsed time is {d} seconds \n", .{elapsed / nanoseconds_in_a_second});
    try bw.flush(); // don't forget to flush!
}
fn addWithEffects(comptime T: type, a: T, b: T) T {
    return a + b;
}
const myFn = addWithEffects(i64, 12, 34);

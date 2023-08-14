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
const Pipe = struct { input: []const u8, output: []const u8 };
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
    _ = magick_wand.MagickSetResolution(mw.*, 200, 200);
    const res = magick_wand.MagickReadImage(mw.*, @ptrCast(files.input));
    if (boolFromCUInt(@as(usize, res)) == false) {
        return error.FileNotFound;
    }
    //very important to use the .MagickSet methods WITHOUT putting the word Image in between them
    // by ONLY using .MagickSet, we can apply global settings
    // Turns out .tiff file compression and downscaling is very important to the functioning of tesseract

    // = magick_wand.MagickSetResolution(mw.*, 500, 500);
    const compressionStatus = magick_wand.MagickSetCompression(mw.*, magick_wand.JPEGCompression);
    _ = magick_wand.MagickSetCompressionQuality(mw.*, 100);
    _ = magick_wand.MagickSetDepth(mw.*, 8);
    _ = compressionStatus;
    _ = magick_wand.MagickWriteImages(mw.*, @ptrCast(files.output), magick_wand.MagickTrue);
    std.debug.print("All done with pdf to image \n", .{});
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
    const text_only = 0; //aka false
    const renderer = tesseract.TessPDFRendererCreate(@ptrCast(files.output), tessdata_path, text_only); //zero is important so we make the text appear visible
    const res = tesseract.TessBaseAPIProcessPages(api.*, @ptrCast(files.input), retry_config, timeout_ms, renderer);
    if (@as(usize, @intCast(res)) == 0) {
        return error.FileNotFound;
    }
}
pub fn processArguments(allocator: std.mem.Allocator, input_file_arg1: ?[:0]const u8, output_file_arg2: ?[:0]const u8) ![2]*Pipe {
    const input_file_pdf = try allocator.create([]const u8);
    const output_file_image = try allocator.create([]const u8);
    const input_file_image = try allocator.create([]const u8);
    const output_file_pdf = try allocator.create([]const u8);

    if (input_file_arg1) |input_file| {
        const without_extension = std.fs.path.stem(input_file);
        input_file_pdf.* = input_file;
        output_file_image.* = try std.fmt.allocPrint(allocator, "./data-out/{s}.tiff\x00", .{without_extension});
        input_file_image.* = output_file_image.*;
        if (output_file_arg2) |output_file| {
            output_file_pdf.* = output_file;
        } else {
            //performing null termination is very important with \x00 becuase we are writing
            //to a bigger buffer. Since strings in zig end in the zero-byte (\x00), we effectively
            //terminate the string after the .tiff part

            input_file_image.* = output_file_image.*;
            output_file_pdf.* = try std.fmt.allocPrint(allocator, "./data-out/{s}\x00", .{without_extension});
        }
    } else {
        return error.NoInputFile;
    }

    const pdf_to_image: *Pipe = try allocator.create(Pipe);
    pdf_to_image.* = .{ .input = input_file_pdf.*, .output = output_file_image.* };
    const image_to_pdf: *Pipe = try allocator.create(Pipe);
    image_to_pdf.* = .{ .input = output_file_image.*, .output = output_file_pdf.* };
    std.debug.print("The output file image is {s}\n\n\n\n", .{output_file_image.*});
    return [_]*Pipe{ pdf_to_image, image_to_pdf };
}
pub fn main() !void {
    const config_file = "./pdf_config.txt";
    const tessdata_path = "./deps/tesseract/tessdata";
    //create the allocator
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();
    //setup printing
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();
    _ = stdout;
    var args = try std.process.argsWithAllocator(allocator);
    _ = args.skip(); //skip program name argument
    var input_file_arg1: ?[:0]const u8 = args.next();
    var output_file_arg2: ?[:0]const u8 = args.next();
    const pipes = try processArguments(allocator, input_file_arg1, output_file_arg2);
    if (false) {
        std.debug.print("THE MY FN IS {}\n", .{myFn});
        return;
    }
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
    //process files
    std.debug.print("\n\n\n The input file pdf is {s}. Output file image is: {s}\n\n\n", .{ pipes[0].input[0..], pipes[0].output[0..] });
    try pdfToImage(mw, pipes[0].*);
    try imageToPdf(api, tessdata_path, pipes[1].*);
    //record total time
    const elapsed = @as(f64, @floatFromInt(timer.read()));
    std.debug.print("Elapsed time is {d} seconds \n", .{elapsed / nanoseconds_in_a_second});
    try bw.flush(); // don't forget to flush!
}
fn addWithEffects(comptime T: type, a: T, b: T) T {
    return a + b;
}
const myFn = addWithEffects(i64, 12, 34);

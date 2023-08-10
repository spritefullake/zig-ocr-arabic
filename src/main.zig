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
fn getMagickWandHandle(allocator: std.mem.Allocator) !*MagickWand {
    const mw = try allocator.create(MagickWand);
    mw.* = magick_wand.NewMagickWand();
    return mw;
}
fn pdfToImage(mw: *MagickWand, input_pdf: [*c]const u8, output_image: [*c]const u8) void {
    _ = magick_wand.MagickReadImage(mw.*, input_pdf);
    //very important to use the .MagickSet methods WITHOUT putting the word Image in between them
    // by ONLY using .MagickSet, we can apply global settings
    // Turns out .tiff file compression and downscaling is very important to the functioning of tesseract
    const compressionStatus = magick_wand.MagickSetCompression(mw.*, magick_wand.JPEGCompression);
    _ = magick_wand.MagickSetCompressionQuality(mw.*, 50);
    _ = magick_wand.MagickSetDepth(mw.*, 8);
    _ = compressionStatus;
    _ = magick_wand.MagickWriteImages(mw.*, output_image, magick_wand.MagickTrue);
}
fn getTesseractHandle(allocator: std.mem.Allocator, tessdata_path: [*c]const u8, config_file: [*c]const u8) !*TesseractAPI {
    //setup the tesseract api handle
    const api = try allocator.create(TesseractAPI);
    api.* = tesseract.TessBaseAPICreate();
    _ = tesseract.TessBaseAPIInit3(api.*, tessdata_path, "ara");
    tesseract.TessBaseAPIReadConfigFile(api.*, config_file);
    return api;
}
fn imageToPdf(api: *TesseractAPI, tessdata_path: [*c]const u8, input_image: [*c]const u8, output_pdf_path: [*c]const u8) void {
    const timeout_ms: c_int = 20000;
    const retry_config: ?*const u8 = null;
    const output_path = output_pdf_path;
    const text_only = 0; //aka false
    const renderer = tesseract.TessPDFRendererCreate(output_path, tessdata_path, text_only); //zero is important so we make the text appear visible
    _ = tesseract.TessBaseAPIProcessPages(api.*, input_image, retry_config, timeout_ms, renderer);
}
pub fn main() !void {
    const config_file = "./pdf_config.txt";
    const tessdata_path = "./deps/tesseract/tessdata";
    //setup printing
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();
    _ = stdout;
    //create the allocator
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    //setup imagemagick
    magick_wand.MagickWandGenesis();
    defer magick_wand.MagickWandTerminus();
    //get library api handles
    const api = try getTesseractHandle(allocator, tessdata_path, config_file);
    defer {
        tesseract.TessBaseAPIDelete(api.*);
        tesseract.TessBaseAPIEnd(api.*);
    }
    const mw = try getMagickWandHandle(allocator);
    defer _ = magick_wand.DestroyMagickWand(mw.*);
    //start timing
    const timer = try allocator.create(time.Timer);
    timer.* = try time.Timer.start();
    //process files
    const input_pdf = "./test_pdf_arabic_short.pdf";
    const intermediate_image = "./data-out/second.tiff";
    const output_pdf_path = "./data-out/final";
    pdfToImage(mw, input_pdf, intermediate_image);
    imageToPdf(api, tessdata_path, intermediate_image, output_pdf_path);
    //record total time
    const elapsed = @as(f64, @floatFromInt(timer.read()));
    std.debug.print("Elapsed time is {d} seconds \n", .{elapsed / nanoseconds_in_a_second});
    try bw.flush(); // don't forget to flush!
}
test "detect leaks" {
    const config_file = "./pdf_config.txt";
    const tessdata_path = "./deps/tesseract/tessdata";
    //create the allocator
    const allocator = std.testing.allocator;
    //setup imagemagick
    magick_wand.MagickWandGenesis();
    defer magick_wand.MagickWandTerminus();

    //get library api handles
    const api = try getTesseractHandle(allocator, tessdata_path, config_file);
    defer {
        tesseract.TessBaseAPIDelete(api.*);
        tesseract.TessBaseAPIEnd(api.*);
        allocator.destroy(api);
    }
    const mw = try getMagickWandHandle(allocator);
    defer allocator.destroy(mw);
    defer _ = magick_wand.DestroyMagickWand(mw.*);

    const input_pdf = "./test_pdf_arabic_short.pdf";
    const intermediate_image = "./data-out/second.tiff";
    const output_pdf_path = "./data-out/final";
    pdfToImage(mw, input_pdf, intermediate_image);
    imageToPdf(api, tessdata_path, intermediate_image, output_pdf_path);
}

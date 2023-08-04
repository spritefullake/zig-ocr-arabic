const std = @import("std");
const time = std.time;
const nanoseconds_in_a_second = @as(f64, std.math.pow(u64, 10, 9));
const tesseract = @cImport({
    @cInclude("tesseract/capi.h");
});
const leptonica = @cImport({
    @cInclude("leptonica/allheaders.h");
});
const magick_wand = @cImport({
    @cInclude("MagickWand/MagickWand.h");
});
const ImageMagick = @cImport({
    @cInclude("MagickCore/MagickCore.h");
});
const LeptonicaErrors = error{FileNotRead};
const Box = extern struct {};
const PixColormap = extern struct {};
const Pix = extern struct { w: c_ulong, h: c_ulong, d: c_ulong, wpl: c_ulong, xres: c_long, yres: c_long, informat: c_long, text: [*c]const u8, colormap: *PixColormap, data: *c_ulong };
const Pixa = extern struct { n: c_long, nalloc: c_long, refcount: c_ulong, pix: [*]*Pix, boxa: *Box };

const TessBaseAPI = struct {}; //@TypeOf(tesseract.TessBaseAPICreate());
const LeptPixaPtr = leptonica.pixaReadMultipageTiff("example");
const Renderer = extern struct {};
extern fn pixaReadMultipageTiff(image_path: [*c]const u8) [*c]Pixa;
extern fn pixReadTiff(image_path: [*c]const u8, n: c_long) [*c]Pix;
extern fn pixRead(image_path: [*c]const u8) *Pix;
extern fn TessBaseAPISetImage2(api: [*c]TessBaseAPI, [*c]Pix) void;
extern fn TessBaseAPIProcessPage(handle: [*c]TessBaseAPI, pix: [*c]Pix, page_index: c_long, filename: [*c]const u8, retry_config: [*c]const u8, timeout_millisec: c_long, renderer: [*c]Renderer) c_uint;
extern fn TessBaseAPIProcessPages(handle: [*c]TessBaseAPI, filename: [*c]const u8, retry_config: [*c]const u8, timeout_millisec: c_long, renderer: [*c]Renderer) c_short;
extern fn TessBaseAPIGetUTF8Text(api: [*c]TessBaseAPI) [*c]const u8;
extern fn TessPDFRendererCreate(outputbase: [*c]const u8, datadir: [*c]const u8, text_only: c_short) [*c]Renderer;
extern fn TessAltoRendererCreate(outputbase: [*c]const u8) [*c]Renderer;
extern fn TessResultRendererAddImage(renderer: [*c]Renderer, api: [*c]TessBaseAPI) c_short;
extern fn TessBaseAPICreate() [*c]TessBaseAPI;
extern fn TessBaseAPIInit3(handle: [*c]TessBaseAPI, datapath: [*c]const u8, language: [*c]const u8) c_short;
extern fn TessBaseAPIReadConfigFile(handle: [*c]TessBaseAPI, config_file: [*c]const u8) void;
extern fn TessBaseAPIDelete(handle: [*c]TessBaseAPI) void;
extern fn TessBaseAPIEnd(handle: [*c]TessBaseAPI) void;
extern fn TessResultRendererEndDocument(renderer: [*c]Renderer) c_short;
extern fn TessDeleteResultRenderer(renderer: [*c]Renderer) void;
fn mypixaReadMultipageTiff(allocator: std.mem.Allocator, image_path: []const u8) !*Pixa {
    const result: *Pixa = pixaReadMultipageTiff(@ptrCast(image_path));
    const pixa_ptr: *Pixa = try allocator.create(Pixa);
    //defer allocator.destroy(pixa_ptr);
    pixa_ptr.* = result.*;
    const nalloc: usize = @intCast(result.nalloc);
    const n: usize = @intCast(result.n);
    const pixes_array_ptr = try allocator.alloc(*Pix, nalloc);
    _ = pixes_array_ptr;

    var i: usize = 0;
    while (i < n) {
        std.debug.print("The pixel at {} is {} width \n", .{ i, result.pix[i].w });
        pixa_ptr.pix[i] = result.pix[i];
        i += 1;
    }

    return pixa_ptr;
}
fn pdfToImageIntermediate(input_pdf: [*c]const u8, output_image: [*c]const u8) void {
    var mw: ?*magick_wand.MagickWand = null;
    magick_wand.MagickWandGenesis();
    defer magick_wand.MagickWandTerminus();
    mw = magick_wand.NewMagickWand();

    var i: i32 = 0;
    _ = magick_wand.MagickSetResolution(mw.?, 300, 300);
    _ = magick_wand.MagickReadImage(mw.?, input_pdf);

    var color = magick_wand.NewPixelWand();
    _ = magick_wand.PixelSetColor(color.?, "white");
    //very important to use the .MagickSet methods WITHOUT putting the word Image in between them
    // by ONLY using .MagickSet, we can apply global settings
    // Turns out .tiff file compression and downscaling is very important to the functioning of tesseract
    const compressionStatus = magick_wand.MagickSetCompression(mw, magick_wand.JPEGCompression);
    _ = magick_wand.MagickSetCompressionQuality(mw, 50);
    _ = magick_wand.MagickSetDepth(mw, 8);
    _ = compressionStatus;
    while (i < magick_wand.MagickGetNumberImages(mw)) {
        i += 1;
        _ = magick_wand.MagickSetIteratorIndex(mw, i);
        _ = magick_wand.MagickSetImageAlphaChannel(mw, magick_wand.RemoveAlphaChannel);
        _ = magick_wand.MagickSetImageBackgroundColor(mw, color);
    }
    _ = magick_wand.MagickResetIterator(mw);
    _ = magick_wand.MagickSetFormat(mw, "png");
    _ = magick_wand.MagickWriteImages(mw, output_image, magick_wand.MagickTrue);

    defer {
        _ = magick_wand.DestroyMagickWand(mw);
        _ = magick_wand.DestroyPixelWand(color.?);
    }
}
fn imageIntermediateToPdf(input_image: [*c]const u8, output_pdf_path: [*c]const u8) void {
    //setup the tesseract api handle
    const api = TessBaseAPICreate();
    const tessdata_path = "./deps/tesseract/tessdata";
    _ = TessBaseAPIInit3(api, tessdata_path, "ara");
    TessBaseAPIReadConfigFile(api, "./pdf_config.txt");
    defer {
        TessBaseAPIDelete(api);
        TessBaseAPIEnd(api);
    }

    const timeout_ms: c_int = 20000;
    const retry_config: ?*const u8 = null;

    const output_path = output_pdf_path;
    const text_only = 0; //aka false

    const renderer = TessPDFRendererCreate(output_path, tessdata_path, text_only); //zero is important so we make the text appear visible
    _ = TessBaseAPIProcessPages(api, input_image, retry_config, timeout_ms, renderer);
}
pub fn main() !void {

    //setup printing
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();
    _ = stdout;
    //create the allocator
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);

    defer arena.deinit();
    const allocator = arena.allocator();

    //start timing
    const timer = try allocator.create(time.Timer);
    timer.* = try time.Timer.start();

    const input_pdf = "./test_pdf_arabic_short.pdf";
    const intermediate_image = "./data-out/second.tiff";
    pdfToImageIntermediate(input_pdf, intermediate_image);
    imageIntermediateToPdf(intermediate_image, "./data-out/output");

    const elapsed = @as(f64, @floatFromInt(timer.read()));

    std.debug.print("Elapsed time is {d} seconds \n", .{elapsed / nanoseconds_in_a_second});

    try bw.flush(); // don't forget to flush!
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

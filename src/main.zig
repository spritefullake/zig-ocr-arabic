const std = @import("std");
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
fn pdfToImageIntermediate(input_pdf: [*c]const u8, output_image: [*c]const u8) i32 {
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
    return i;
}
pub fn main() !void {
    //setup printing
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();
    //create the allocator
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input_image = "./data-out/second.tiff";
    const input_pdf = "./test_pdf_arabic_short.pdf";

    const pages = pdfToImageIntermediate(input_pdf, "./data-out/second.tiff");

    //setup the tesseract api handle
    const api = TessBaseAPICreate();
    const tessdata_path = "./deps/tesseract/tessdata";
    _ = TessBaseAPIInit3(api, tessdata_path, "ara");
    //TessBaseAPIReadConfigFile(api, "./pdf_config.txt");
    defer {
        TessBaseAPIDelete(api);
        TessBaseAPIEnd(api);
    }

    const timeout_ms: c_int = 20000;
    const retry_config: ?*const u8 = null;

    const output_path = "./data-out/output";
    const text_only = 0; //aka false
    //TessAltoRendererCreate(output_path);
    const renderer = TessPDFRendererCreate(output_path, tessdata_path, text_only); //zero is important so we make the text appear visible
    _ = TessBaseAPIProcessPages(api, "data-out/second.tiff", retry_config, timeout_ms, renderer);
    //const renderer2 = TessPDFRendererCreate("data-out/output_renderer2", tessdata_path, text_only);
    //_ = TessBaseAPISetImage2(api, pixRead("./data-out/intermediate_output-7.png"));
    //_ = TessResultRendererAddImage(renderer, api);
    //_ = TessBaseAPISetImage2(api, pixRead("./data-out/intermediate_output-8.png"));
    //_ = TessResultRendererAddImage(renderer, api);
    //_ = TessResultRendererEndDocument(renderer);
    //_ = TessBaseAPIProcessPages(api, "data-out/second-9.png", retry_config, timeout_ms, renderer2);

    if (false) {
        var k: usize = 0;
        while (k < pages) {
            const image_file_name = try std.fmt.allocPrint(allocator, "data-out/second-{}.png", .{k});
            const output_file_name = try std.fmt.allocPrint(allocator, "data-out/final-{}", .{k});

            std.debug.print("output_file_name: {s}\n", .{output_file_name});
            std.debug.print("image_file_name: {s}\n\n", .{image_file_name});

            const i_renderer = TessPDFRendererCreate(@ptrCast(output_file_name), tessdata_path, text_only);
            _ = TessBaseAPIProcessPages(api, @ptrCast(image_file_name), retry_config, timeout_ms, i_renderer);
            //const out_text = TessBaseAPIGetUTF8Text(api.?);
            //try stdout.print("The out text is {s}\n", .{out_text});
            //_ = TessBaseAPIProcessPage(api, pixRead(@ptrCast(image_file_name)), @intCast(k), @ptrCast(output_file_name), retry_config, timeout_ms, @ptrCast(renderer));

            TessDeleteResultRenderer(i_renderer);
            k += 1;
        }
        //_ = TessBaseAPIProcessPages(@ptrCast(api), input_image, retry_config, timeout_ms, renderer);
    }

    if (false) {
        const mw = undefined;
        _ = magick_wand.MagickReadImage(mw.?, input_image);
        const i = 0;
        while (i < magick_wand.MagickGetNumberImages(mw)) {
            _ = TessBaseAPISetImage2(api.?, pixReadTiff(input_image, @intCast(i)));
            _ = tesseract.TessResultRendererAddImage(renderer, api.?);

            i += 1;
        }
        _ = tesseract.TessResultRendererEndDocument(renderer);
    }

    if (false) {
        const pixa = try mypixaReadMultipageTiff(allocator, input_image);
        //const pixa: *Pixa = try pixaReadMultipageTiff(allocator, input_image);
        const my_pixes: [*]*Pix = pixa.pix;
        const total_pixes: usize = @intCast(pixa.n);
        const slice: []*Pix = pixa.pix[0..total_pixes];
        _ = slice;
        std.debug.print("Pixa item number 1: {} \n", .{my_pixes[0].w});
    }

    //read in an image as pixel data
    //convert image to text data
    //TessBaseAPISetImage2(api.?, @as(?*Pix, image));

    //_ = tesseract.TessBaseAPIProcessPages(api, input_image, retry_config, timeout_ms, renderer);
    //_ = tesseract.TessBaseAPIProcessPages(api, input_image, retry_config, timeout_ms, renderer);
    if (false) {
        var j: i32 = 0;
        while (j < pages) {
            const page = pixReadTiff(input_image, @intCast(j));
            //std.debug.print("THe details of page number {} with width {}", .{ j, &page.w });
            _ = TessBaseAPISetImage2(api, page);
            //const out_text: [*c]const u8 = TessBaseAPIGetUTF8Text(api);
            //try stdout.print("The out text is {s}\n", .{out_text});
            const i_renderer = TessPDFRendererCreate("./data-out/alternate", tessdata_path, text_only);
            _ = TessBaseAPIProcessPage(api, page, j, input_image, retry_config, timeout_ms, i_renderer);
            j += 1;
            TessDeleteResultRenderer(i_renderer);
        }
    }

    //const out_text: [*c]const u8 = tesseract.TessBaseAPIGetUTF8Text(api.?);

    try stdout.print("Run `zig build test` to run the tests.\n", .{});
    //try stdout.print("The out text is {s}\n", .{out_text});

    try bw.flush(); // don't forget to flush!
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

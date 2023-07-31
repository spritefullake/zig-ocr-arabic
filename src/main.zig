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
const LeptonicaErrors = error{FileNotRead};
const Pix = @TypeOf(leptonica.pixRead("example string"));

pub fn pixRead(allocator: std.mem.Allocator, file_path: []const u8) !*Pix {
    const c_string: [*c]const u8 = @ptrCast(file_path);
    const result: Pix = leptonica.pixRead(c_string);
    if (result == null) {
        return LeptonicaErrors.FileNotRead;
    } else {
        const image: *Pix = try allocator.create(Pix);
        defer allocator.destroy(image);
        image.* = result.?;
        return image;
    }
}
pub fn TessBaseAPISetImage2(api: *tesseract.TessBaseAPI, image: ?*Pix) void {
    tesseract.TessBaseAPISetImage2(api, @ptrCast(image));
}
pub fn main() !void {
    //create the allocator
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    //var mw: ?*magick_wand.MagickWand = null;
    //magick_wand.MagickWandGenesis();
    //mw = magick_wand.NewMagickWand();

    //setup the tesseract api handle
    const api: ?*tesseract.TessBaseAPI = tesseract.TessBaseAPICreate();
    _ = tesseract.TessBaseAPIInit3(api.?, null, "ara");
    tesseract.TessBaseAPIReadConfigFile(api.?, "./pdf_config.txt");
    defer tesseract.TessBaseAPIDelete(api.?);
    defer tesseract.TessBaseAPIEnd(api.?);

    const input_image = "./test_image_arabic.png";
    const timeout_ms: c_int = 5000;
    const retry_config: ?*const u8 = null;
    const tessdata_path = "/opt/local/share/tessdata/";
    const output_path = "./data-out/output";
    const text_only = 0; //aka false
    //read in an image as pixel data
    const image: *Pix = try pixRead(allocator, input_image);
    //convert image to text data
    TessBaseAPISetImage2(api.?, @as(?*Pix, image));
    const renderer = tesseract.TessPDFRendererCreate(output_path, tessdata_path, text_only); //zero is important so we make the text appear visible

    _ = tesseract.TessBaseAPIProcessPages(api, input_image, retry_config, timeout_ms, renderer);

    //setup printing
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try stdout.print("Run `zig build test` to run the tests.\n", .{});

    try bw.flush(); // don't forget to flush!
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

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
const Pix = @TypeOf(leptonica.pixRead("example string").*);

pub fn pixRead(allocator: std.mem.Allocator, file_path: []const u8) !*Pix {
    const c_string: [*c]const u8 = @ptrCast(file_path);
    const result: [*c]Pix = leptonica.pixRead(c_string);
    if (result == null) {
        return LeptonicaErrors.FileNotRead;
    } else {
        const image: *Pix = try allocator.create(Pix);
        defer allocator.destroy(image);
        image.* = result.*;
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
    //std.debug.print("The wand is {} \n", .{@typeInfo(magick_wand)});
    //mw = magick_wand.NewMagickWand();

    //setup the tesseract api handle
    const api: ?*tesseract.TessBaseAPI = tesseract.TessBaseAPICreate();
    _ = tesseract.TessBaseAPIInit3(api.?, null, "ara");
    tesseract.TessBaseAPIReadConfigFile(api.?, "./pdf_config.txt");
    defer tesseract.TessBaseAPIDelete(api.?);
    defer tesseract.TessBaseAPIEnd(api.?);

    //read in an image as pixel data
    const image: *Pix = try pixRead(allocator, "./test_image_arabic.png");
    //convert image to text data
    TessBaseAPISetImage2(api.?, @as(?*Pix, image));
    const out_text: [*c]const u8 = tesseract.TessBaseAPIGetUTF8Text(api.?);
    const renderer = tesseract.TessPDFRendererCreate("./data-out/output", "/opt/local/share/tessdata/", 0); //zero is important so we make the text appear visible
    _ = tesseract.TessResultRendererBeginDocument(renderer, "my_doc");
    _ = tesseract.TessResultRendererAddImage(renderer, api.?);
    _ = tesseract.TessResultRendererEndDocument(renderer);

    //setup printing
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try stdout.print("The out text is {s}\n", .{out_text});

    try stdout.print("Run `zig build test` to run the tests.\n", .{});

    try bw.flush(); // don't forget to flush!
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

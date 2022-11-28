const std = @import("std");
const deflate = @import("deflate.zig");
const bstream = @import("bit-stream.zig");
const HuffDecoder = @import("huffman.zig").HuffDecoder;
const HuffEncoderDecoder = @import("huffman.zig").HuffEncoderDecoder;

fn profileBitStream(bitStreamStruct: anytype) !void {
    const seed = @truncate(u64, @bitCast(u128, std.time.nanoTimestamp()));
    var prng = std.rand.DefaultPrng.init(seed);

    var allocator = std.heap.page_allocator;

    const NUM_BYTES = 100000000;
    var bytes = try allocator.alloc(u8, NUM_BYTES);
    defer allocator.free(bytes);
    var i: u32 = 0;
    while (i < 64 * 200) : (i += 1) {
        bytes[i] = prng.random().int(u8);
    }

    var stream = bitStreamStruct.fromBytes(bytes);

    var before = std.time.milliTimestamp();
    var numBits: u6 = 0;
    var bitsLeft: u64 = NUM_BYTES;
    while (bitsLeft > 0) {
        numBits = prng.random().int(u4);
        if (numBits == 0) {
            numBits = 1;
        }

        if (numBits > bitsLeft) {
            numBits = @truncate(u6, bitsLeft);
        }

        bitsLeft -= numBits;

        var bits = stream.getNBits(numBits);
        _ = bits;
    }

    var after = std.time.milliTimestamp();
    std.log.debug("{}ms", .{after - before});
}

fn profileDeflate() !void {
    comptime var testData = [_]u8{ 0b00011110, 0b11111000, 0b10111100, 0b01100011, 0b10011100, 0b10001000, 0b00000000, 0b00000000, 0b00110000, 0b01000000, 0b00001100, 0b11010100, 0b10101101, 0b01001010, 0b01111000, 0b11111111, 0b01101001, 0b00011100, 0b01101000, 0b01101001, 0b00111010, 0b01111000, 0b00101001, 0b11010011, 0b10110110, 0b10000000 };

    comptime { // can't be asked rewriting the above array to have the bits in the right order
        for (testData[0..]) |*byte| {
            byte.* = @bitReverse(u8, byte.*);
        }
    }

    var allocator = std.heap.page_allocator;

    var before = std.time.milliTimestamp();
    var i: u64 = 0;
    while (i < 500000) : (i += 1) {
        var outputStream = try deflate.decompress(&allocator, testData[0..]);
        allocator.free(outputStream);
    }
    var after = std.time.milliTimestamp();
    std.log.debug("{}ms", .{after - before});
}

fn profileApartmentsPngDeflateSection() !void {
    // const file = try std.fs.cwd().openFile("deflate-test", .{.read = true});
    // defer file.close();
    var allocator = std.heap.page_allocator;
    const bytes = try std.fs.cwd().readFileAlloc(allocator, "deflate-test", 1024*1024*1024);
    defer allocator.free(bytes);

    var outputStream = try deflate.decompress(&allocator, bytes);
    allocator.free(outputStream);
}

fn profileHuffTreeDecode() !void {
    const N = 1000000;
    var allocator = std.heap.page_allocator;
    var codes = [19]u32{ 4, 3, 0, 2, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 2, 0 };
    var bytes = [_]u8{ 0b00001000, 0b00101101, 0b11011011, 0b00100100, 0b00101101 };

    var list = std.ArrayList(u8).init(allocator);
    defer list.deinit();

    var iteration: i64 = 0;
    while (iteration < N) : (iteration += 1) {
        try list.appendSlice(bytes[0..]);
    }

    var bitStream = &bstream.BitStream.fromBytes(list.items);
    var decoder = try HuffDecoder.initFromCodes(allocator, codes[0..]);
    defer decoder.deinit();

    //decoder.debugPrintMappingAsBinary(17);

    // var codesOld = std.ArrayList(u16).init(allocator);
    // defer codesOld.deinit();
    // var codesNew = std.ArrayList(u16).init(allocator);
    // defer codesNew.deinit();

    var before = std.time.milliTimestamp();

    iteration = 0;
    const NUM_CODE_POINTS_PER_ITERATION = 16;
    while (iteration < N * NUM_CODE_POINTS_PER_ITERATION) : (iteration += 1) {
        var code = decoder.decode(bitStream) orelse unreachable;
        //try codesNew.append(code);
        _ = code;
    }

    var after = std.time.milliTimestamp();
    std.log.debug("New Method : {}ms", .{after - before});

    bitStream = &bstream.BitStream.fromBytes(list.items);
    var huffTree = try HuffEncoderDecoder.generateFromCodes(allocator, codes[0..]);
    defer huffTree.deinit();

    before = std.time.milliTimestamp();

    iteration = 0;
    while (iteration < N * NUM_CODE_POINTS_PER_ITERATION) : (iteration += 1) {
        var code = try huffTree.getNextCode(bitStream);
        //try codesOld.append(code);
        _ = code;
    }

    after = std.time.milliTimestamp();
    std.log.debug("Old Method : {}ms", .{after - before});

    // std.debug.assert(codesNew.items.len == codesOld.items.len);
    // var counter : usize = 0;
    // while(counter < codesNew.items.len) : (counter += 1) {
    //     //std.log.debug("counter={}, new={}, old={}", .{counter, codesNew.items[counter], codesOld.items[counter]});
    //     std.debug.assert(codesNew.items[counter] == codesOld.items[counter]);
    // }
}

pub fn main() !void {
    // try profileBitStream(bstream.BitStream);
    //try profileDeflate();
    //try profileHuffTreeDecode();
    try profileApartmentsPngDeflateSection();
}

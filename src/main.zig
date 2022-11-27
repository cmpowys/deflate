const std = @import("std");
const deflate = @import("deflate.zig");
const bstream = @import("bit-stream.zig");
const HuffNode = @import("huffman.zig").HuffNode;

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

fn profileHuffTreeDecode() !void {
    const N = 5000000;
    var allocator = std.heap.page_allocator;
    var codes = [19]u32{ 4, 3, 0, 2, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 2, 0 };
    var bytes = [_]u8{ 0b00000000, 0b00000110, 0b00000111, 0b00001001, 0b00111100, 0b00100110, 0b01001100 };
    var tree = try HuffNode.generateFromCodes(allocator, codes[0..]);
    defer tree.deinit();

    var before = std.time.milliTimestamp();

    var iteration: i64 = 0;

    while (iteration < N) : (iteration += 1) {
        var bitStream = &bstream.BitStream.fromBytes(bytes[0..]);

        var count: i64 = 0;
        while (count < 15) : (count += 1) {
            var code = try tree.getNextCode(bitStream);
            _ = code;
        }
    }

    var after = std.time.milliTimestamp();
    std.log.debug("{}ms", .{after - before});
}

pub fn main() !void {
    // try profileBitStream(bstream.BitStream);
    // try profileDeflate();
    try profileHuffTreeDecode();
}

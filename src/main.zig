const std = @import("std");
const deflate = @import("deflate.zig");
const bstream = @import("bit-stream.zig");

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

fn sanity_check() !void {
    comptime var testData = [_]u8{ 0b00011110, 0b11111000, 0b10111100, 0b01100011, 0b10011100, 0b10001000, 0b00000000, 0b00000000, 0b00110000, 0b01000000, 0b00001100, 0b11010100, 0b10101101, 0b01001010, 0b01111000, 0b11111111, 0b01101001, 0b00011100, 0b01101000, 0b01101001, 0b00111010, 0b01111000, 0b00101001, 0b11010011, 0b10110110, 0b10000000 };

    comptime { // can't be asked rewriting the above array to have the bits in the right order
        for (testData[0..]) |*byte| {
            byte.* = @bitReverse(u8, byte.*);
        }
    }

    const expectedString = [_]u8{ 'A', 'B', 'C', 'D', 'E', 'A', 'B', 'C', 'D', ' ', 'A', 'B', 'C', 'D', 'E', 'A', 'B', 'C', 'D' };
    var allocator = std.heap.page_allocator;

    var outputStream = try deflate.decompress(&allocator, testData[0..]);
    defer allocator.free(outputStream);

    try std.testing.expect(outputStream.len == expectedString.len);
    try std.testing.expectEqualSlices(u8, outputStream, expectedString[0..]);
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

fn test3Bytes() !void {
    var data = [_]u8{ 0b01111000, 0b11001010, 0b10101010 };
    var stream = bstream.BitStream.fromBytes(data[0..]);
    var bits: u64 = stream.getNBits(12) orelse unreachable;

    bits = stream.getNBits(10) orelse try unreachable;
    var expected: u64 = 0b1010101100;
    try std.testing.expectEqual(expected, bits);

    bits = stream.getNBits(2) orelse try unreachable;
    expected = 0b00000010;
    try std.testing.expectEqual(expected, bits);

    var bitsOpt = stream.getNBits(1);
    if (bitsOpt != null) {
        try std.testing.expect(false);
    }
}

fn test8ByteBoundary() !void {
    var data = [_]u8{ 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b10100000, 0b00000011, 0b00000110, 0b00000000 };
    //01100000011101
    //01100000011
    var stream = bstream.BitStream.fromBytes(data[0..]);

    var bits = stream.getNBits(61) orelse try unreachable;
    var expected: u64 = 0;
    try std.testing.expectEqual(expected, bits);

    bits = stream.getNBits(14) orelse try unreachable;
    expected = 0b11000000011101;
    try std.testing.expectEqual(expected, bits);

    bits = stream.getNBits(13) orelse try unreachable;
    expected = 0;
    try std.testing.expectEqual(expected, bits);

    var bitsOpt = stream.getNBits(1);
    if (bitsOpt != null) {
        try std.testing.expect(false);
    }
}

pub fn main() !void {
    // try profileBitStream(bstream.BitStream);
    // try profileBitStream(bstream.BitStreamMiddleAged);
    // try profileBitStream(bstream.BitStreamOld);
    // try sanity_check();
    //try profileDeflate();
    // try test3Bytes();
    // try test8ByteBoundary();
}

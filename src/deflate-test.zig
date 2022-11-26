const std = @import("std");
const deflate = @import("deflate.zig");

test "sanity" {
    comptime var testData = [_]u8{ 0b00011110, 0b11111000, 0b10111100, 0b01100011, 0b10011100, 0b10001000, 0b00000000, 0b00000000, 0b00110000, 0b01000000, 0b00001100, 0b11010100, 0b10101101, 0b01001010, 0b01111000, 0b11111111, 0b01101001, 0b00011100, 0b01101000, 0b01101001, 0b00111010, 0b01111000, 0b00101001, 0b11010011, 0b10110110, 0b10000000 };

    comptime { // can't be asked rewriting the above array to have the bits in the right order
        for (testData[0..]) |*byte| {
            byte.* = @bitReverse(u8, byte.*);
        }
    }

    const expectedString = [_]u8{ 'A', 'B', 'C', 'D', 'E', 'A', 'B', 'C', 'D', ' ', 'A', 'B', 'C', 'D', 'E', 'A', 'B', 'C', 'D' };
    var allocator = std.testing.allocator;

    var outputStream = try deflate.decompress(&allocator, testData[0..]);
    defer allocator.free(outputStream);

    try std.testing.expect(outputStream.len == expectedString.len);
    try std.testing.expectEqualSlices(u8, outputStream, expectedString[0..]);
}

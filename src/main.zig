const std = @import("std");
const deflate = @import("deflate.zig");
const bstream = @import("bit-stream.zig");

pub fn main() !void {
    // comptime var testData = [_]u8{ 0b00011110, 0b11111000, 0b10111100, 0b01100011, 0b10011100, 0b10001000, 0b00000000, 0b00000000, 0b00110000, 0b01000000, 0b00001100, 0b11010100, 0b10101101, 0b01001010, 0b01111000, 0b11111111, 0b01101001, 0b00011100, 0b01101000, 0b01101001, 0b00111010, 0b01111000, 0b00101001, 0b11010011, 0b10110110, 0b10000000 };

    // comptime { // can't be asked rewriting the above array to have the bits in the right order
    //     for (testData[0..]) |*byte| {
    //         byte.* = @bitReverse(u8, byte.*);
    //     }
    // }

    // var allocator = std.heap.page_allocator;

    // var before = std.time.milliTimestamp();
    // var i: u64 = 0;
    // while (i < 500000) : (i += 1) {
    //     var outputStream = try deflate.decompress(&allocator, testData[0..]);
    //     defer allocator.free(outputStream);
    // }
    // var after = std.time.milliTimestamp();
    // std.log.debug("{}ms", .{after - before});
}

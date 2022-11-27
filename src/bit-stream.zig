const std = @import("std");

pub const BitStream = struct {
    const Self = @This();

    bytes: []u8,
    bitPosition: u32,
    bitsInByte: u32,
    currentBytes: ?u64,

    pub fn fromBytes(bytes: []u8) BitStream {
        return BitStream{ .bytes = bytes, .bitPosition = 0, .currentBytes = null, .bitsInByte = 0 };
    }

    pub fn getNBits(self: *Self, numBits: u32) ?u64 {
        if (numBits == 0) return 0;

        if (self.currentBytes == null) {
            if (!self.getNextBytes()) return null;
        }

        const bytes = self.currentBytes orelse unreachable;
        const bitsRemaining = self.bitsInByte - self.bitPosition;
        const numBitsLocal = @minimum(@minimum(self.bitsInByte, numBits), bitsRemaining);

        var mask: u64 = std.math.maxInt(u64);
        mask <<= @truncate(u6, self.bitPosition);
        var zero_mask: u64 = std.math.maxInt(u64);
        zero_mask >>= @truncate(u6, (64 - self.bitPosition - numBitsLocal));
        mask &= zero_mask;
        var result: u64 = bytes & mask;
        result >>= @truncate(u6, self.bitPosition);

        self.bitPosition += numBitsLocal;

        if (self.bitPosition == self.bitsInByte) {
            self.currentBytes = null;
            self.bitPosition = 0;
        }

        //TODO(cpowys) don't make recursive
        if (numBits > numBitsLocal) {
            var secondResult = self.getNBits(numBits - numBitsLocal) orelse return null;
            result += secondResult << @truncate(u6, numBitsLocal);
        }

        return result;
    }

    fn getNextBytes(self: *Self) bool {
        const bytesRemaining = self.bytes.len;

        if (bytesRemaining == 0) {
            return false;
        }

        var bytesToCache = [_]u8{0} ** 8;

        const bytesToAdd = @minimum(8, bytesRemaining);

        std.mem.copy(u8, &bytesToCache, self.bytes[0..bytesToAdd]);
        self.currentBytes = std.mem.bytesToValue(u64, &bytesToCache);
        self.bytes = self.bytes[bytesToAdd..];

        self.bitsInByte = @truncate(u32, 8 * bytesToAdd);

        return true;
    }
};

test "correct results returned for specific byte stream using new method" {
    var data = [_]u8{0b01111000};
    var stream = BitStream.fromBytes(data[0..]);
    var bits = stream.getNBits(4) orelse unreachable;
    var expected: u64 = 0b00001000;
    try std.testing.expectEqual(expected, bits);

    bits = stream.getNBits(3) orelse try unreachable;
    expected = 0b00000111;
    try std.testing.expectEqual(expected, bits);

    bits = stream.getNBits(1) orelse try unreachable;
    expected = 0b00000000;
    try std.testing.expectEqual(expected, bits);

    var bitsOpt = stream.getNBits(1);
    if (bitsOpt != null) {
        try std.testing.expect(false);
    }
}

test "correct results returned for specific byte stream using new method on 2 bytes" {
    var data = [_]u8{ 0b01111000, 0b11001010 };
    var stream = BitStream.fromBytes(data[0..]);
    var bits: u64 = stream.getNBits(4) orelse unreachable;
    bits = stream.getNBits(3) orelse try unreachable;
    bits = stream.getNBits(5) orelse try unreachable;
    var expected: u64 = 0b00010100;
    try std.testing.expectEqual(expected, bits);

    bits = stream.getNBits(4) orelse try unreachable;
    expected = 0b00001100;
    try std.testing.expectEqual(expected, bits);

    var bitsOpt = stream.getNBits(1);
    if (bitsOpt != null) {
        try std.testing.expect(false);
    }
}

test "correct results returned for specific byte stream using new method on 3 bytes where we cross two byte boundaries" {
    var data = [_]u8{ 0b01111000, 0b11001010, 0b10101010 };
    var stream = BitStream.fromBytes(data[0..]);
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

test "nothing returned for empty byte stream" {
    var bytes: []u8 = &.{};
    var bitStream = BitStream.fromBytes(bytes);
    var returned = bitStream.getNBits(3);
    if (returned != null) {
        try std.testing.expect(false);
    }
}

test "0 returned when 0 bits requested" {
    var data = [_]u8{ 0b01111000, 0b11001010, 0b10101010 };
    var bitStream = BitStream.fromBytes(data[0..]);
    var returned = bitStream.getNBits(0) orelse unreachable;
    var expected: u64 = 0;
    try std.testing.expectEqual(expected, returned);
}

test "test8ByteBoundary" {
    var data = [_]u8{ 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b00000000, 0b10100000, 0b00000011, 0b00000110, 0b00000000 };
    //01100000011101
    //01100000011
    var stream = BitStream.fromBytes(data[0..]);

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

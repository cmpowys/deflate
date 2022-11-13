const std = @import("std");

pub const BitStream = struct {
    const Self = @This();

    bytes: []u8,
    bitPosition: u32,
    currentByte: ?u8, // TODO(cpowys) get working with more cached bytes?

    pub fn fromBytes(bytes: []u8) BitStream {
        return BitStream{ .bytes = bytes, .bitPosition = 0, .currentByte = null };
    }

    pub fn getNBits(self: *Self, numBits: u32) ?u64 {
        _ = self;
        _ = numBits;

        if (numBits == 0) return null;

        if (self.currentByte == null) {
            self.currentByte = self.getNextByte() orelse return null;
            self.bitPosition = 0;
        }

        var byte = self.currentByte orelse unreachable;
        var bitsRemainingInByte = 8 - self.bitPosition;
        var numBitsLocal = @minimum(@minimum(8, numBits), bitsRemainingInByte);

        var mask: u8 = 0b11111111;
        mask <<= @truncate(u3, self.bitPosition);
        var zero_mask: u8 = 0b11111111;
        zero_mask >>= @truncate(u3, (8 - self.bitPosition - numBitsLocal));
        mask &= zero_mask;
        var result: u64 = byte & mask;
        result >>= @truncate(u3, self.bitPosition);

        //01111000 -> mask wanted for bitpos=0,numbits=4 = 00001111
        // mask1 = 11111111 = max << bitPosition
        // mask2 = 00001111 =     max >> 4 (numBitsLocal)

        //01111000 -> bitPosition = 4, numBits = 3 want 01110000
        // mask1 = 11110000
        // mask2 = 01111111
        // 11111111 >> 3 = 00011111 = zm >> (1) (8 - 4 - 3)
        // so total mask would be 01110000 so we want to shift >> 4 times (bitPosition)?

        self.bitPosition += numBitsLocal;

        if (self.bitPosition == 8) {
            self.currentByte = null;
        }

        //TODO(cpowys) don't make recursive
        if (numBits > numBitsLocal) {
            var secondResult = self.getNBits(numBits - numBitsLocal) orelse return null;
            result += secondResult << @truncate(u6, numBitsLocal);
        }

        return result;
    }

    fn getNextByte(self: *Self) ?u8 {
        if (self.bytes.len == 0) {
            return null;
        }
        const byte = self.bytes[0];
        self.bytes = self.bytes[1..];
        return byte;
    }
};

pub const BitStreamOld = struct {
    const Self = @This();

    bytes: []u8,
    bitPosition: u8,
    currentByte: ?u8,

    pub fn fromBytes(bytes: []u8) BitStreamOld {
        return BitStreamOld{ .bytes = bytes, .bitPosition = 0, .currentByte = null };
    }

    fn getNextByte(self: *Self) ?u8 {
        if (self.bytes.len == 0) {
            return null;
        }
        const byte = self.bytes[0];
        self.bytes = self.bytes[1..];
        return byte;
    }

    pub fn getNBits(self: *Self, n: u6) ?u64 {
        // TODO make performant
        // TODO need to err if you try to get bytes whilst in the "middle" of a byte
        var result: u64 = 0;
        var bitNumber: u64 = 0;
        const one: u64 = 1;

        if (self.currentByte == null) {
            self.currentByte = self.getNextByte() orelse return null;
            self.bitPosition = 0;
        }

        while (bitNumber < n) : (bitNumber += 1) {
            const byte = self.currentByte orelse return null;

            const nextBit: u16 = if ((byte & (one << @intCast(u6, self.bitPosition))) != 0) 1 else 0;
            self.bitPosition += 1;

            result |= (nextBit << @intCast(u4, bitNumber));

            if (self.bitPosition == 8) {
                self.currentByte = self.getNextByte();
                self.bitPosition = 0;
            }
        }

        return result;
    }
};

// test "compare random results between old and new methods" {
//     const seed = @truncate(u64, @bitCast(u128, std.time.nanoTimestamp()));
//     var prng = std.rand.DefaultPrng.init(seed);

//     const NUM_BYTES = 64 * 200;
//     var bytesArr: [NUM_BYTES]u8 = undefined;
//     var i: u32 = 0;
//     while (i < 64 * 200) : (i += 1) {
//         bytesArr[i] = prng.random().int(u8);
//     }
//     var bytes = bytesArr[0..];

//     var bitStreamOld = BitStreamOld.fromBytes(bytes);
//     var bitStream = BitStream.fromBytes(bytes);

//     var numBits: u6 = 0;
//     var bitsLeft: u64 = NUM_BYTES;
//     while (bitsLeft > 0) {
//         numBits = prng.random().int(u4);
//         if (numBits == 0) {
//             numBits = 1;
//         }

//         if (numBits > bitsLeft) {
//             numBits = @truncate(u6, bitsLeft);
//         }

//         bitsLeft -= numBits;

//         var bitsFromOld = bitStreamOld.getNBits(numBits);
//         var bitsFromNew = bitStream.getNBits(numBits);

//         try std.testing.expectEqual(bitsFromOld, bitsFromNew);
//     }
// }

test "correct results returned for specific byte stream using old method" {
    var data = [_]u8{0b01111000};
    var stream = BitStreamOld.fromBytes(data[0..]);
    var bits = stream.getNBits(4) orelse 0;
    var expected: u64 = 0b00001000;
    try std.testing.expectEqual(expected, bits);
}

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
    var bitStream = BitStreamOld.fromBytes(bytes);
    var returned = bitStream.getNBits(3);
    if (returned != null) {
        try std.testing.expect(false);
    }
}

const std = @import("std");
const BitStream = @import("bit-stream.zig").BitStream;

pub const Error = error{ UnexpectedErrorAddingHuffNode, InvalidUnderlyingBitStream };

const MappingVal = struct { value: u16, depth: u16 };

pub const HuffDecoder = struct {
    const Self = @This();

    mapping: []MappingVal,
    allocator: std.mem.Allocator,
    maxDepth: usize, //TODO(cpowys) get datatype here right 16 should be way more than enough

    fn init(huff: *HuffEncoderDecoder) !*Self {
        var maxDepth = huff.getMaxDepth();
        var allocator = huff.allocator;

        std.debug.assert(maxDepth <= 16 and maxDepth > 0); // TODO(cpowys) can we expect this to get too big?
        var sizeOfMappings = std.math.pow(u32, 2, maxDepth);
        var mapping = try allocator.alloc(MappingVal, sizeOfMappings);
        errdefer allocator.free(mapping);

        var decoder = try allocator.create(Self);
        decoder.mapping = mapping;
        decoder.allocator = allocator;
        decoder.maxDepth = @truncate(u16, maxDepth);
        errdefer (allocator.destroy(decoder));
        try huff.populateDecoderMaps(decoder);

        return decoder;
    }

    pub fn debugPrintMappingAsBinary(self: *Self, requiredValue: i32) void {
        var counter: usize = 0;
        while (counter < self.mapping.len) : (counter += 1) {
            var mappingVal = self.mapping[counter];
            var depth = mappingVal.depth;
            var value = mappingVal.value;

            if (requiredValue < 0 or requiredValue == value) {
                std.log.debug("{b}, counter={}, depth={}, value={}", .{ counter, counter, depth, value });
            }
        }
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.mapping);
        self.allocator.destroy(self);
    }

    pub fn initFromCodes(allocator: std.mem.Allocator, codes: []u32) !*Self {
        var huffEncoderDecoder = try HuffEncoderDecoder.generateFromCodes(allocator, codes);
        defer huffEncoderDecoder.deinit();

        return HuffDecoder.init(huffEncoderDecoder);
    }

    pub fn decode(self: *Self, bits: *BitStream) ?u16 {
        var bitsOld = bits.copy();
        var maxDepth = @truncate(u16, @minimum(self.maxDepth, bits.getTotalBitsRemainingInStream()));

        if (maxDepth == 0) {
            return null;
        }

        var bitValue = bits.getNBits(maxDepth) orelse unreachable;
        var val = self.mapping[bitValue];
        bits.* = bitsOld;
        var b = bits.getNBits(val.depth) orelse unreachable;
        _ = b;
        return val.value;
    }
};

const HuffEncoderDecoder = struct {
    const Self = @This();

    value: ?u16,
    left: ?*Self,
    right: ?*Self,
    allocator: std.mem.Allocator,

    fn generateFromCodes(allocator: std.mem.Allocator, codes: []u32) !*Self {
        std.debug.assert(codes.len > 0);

        var codeCounts = try CodeCounts.getCodeCounts(allocator, codes);
        defer codeCounts.deinit(allocator);

        var huffTree = try Self.init(allocator);
        errdefer huffTree.deinit();

        var codeLength: u32 = 0;
        while (codeLength < codeCounts.maxCodeLength + 1) : (codeLength += 1) {
            if (codeCounts.codeCount[codeLength] == 0)
                continue;

            for (codes) |code, codeIndex| {
                if (code != codeLength)
                    continue;

                try huffTree.addCodePoint(codeLength, codeCounts.nextCode[codeLength], @intCast(u16, codeIndex));
                codeCounts.nextCode[codeLength] += 1;
            }
        }

        return huffTree;
    }

    fn init(allocator: std.mem.Allocator) !*Self {
        var result = try allocator.create(Self);
        result.left = null;
        result.right = null;
        result.value = null;
        result.allocator = allocator;
        return result;
    }

    fn deinit(self: *Self) void {
        // TODO(cpowys) need a better representation so we don't have to recursively delete all this
        if (self.left != null) {
            (self.left orelse unreachable).deinit();
        }

        if (self.right != null) {
            (self.right orelse unreachable).deinit();
        }

        self.allocator.destroy(self);
    }

    fn addCodePoint(self: *Self, codeLength: u32, code: u32, value: u16) !void {
        std.debug.assert(codeLength > 0);

        var depth: u64 = 0;
        var root = self;
        while (depth < codeLength) {
            if (root.value != null) {
                return Error.UnexpectedErrorAddingHuffNode;
            }

            const one: u64 = 1;
            const isZero = (code & (one << (@intCast(u6, codeLength - depth - 1)))) == 0; // TODO clean up these integer widths and messy casts

            if (isZero) {
                if (root.left == null) {
                    root.left = try Self.init(self.allocator);
                }
                root = root.left orelse unreachable;
            } else {
                if (root.right == null) {
                    root.right = try Self.init(self.allocator);
                }
                root = root.right orelse unreachable;
            }

            depth += 1;
        }

        if (root.left != null or root.right != null or root.value != null) {
            return Error.UnexpectedErrorAddingHuffNode;
        }

        root.value = value;
    }

    fn getNextCode(self: *Self, bits: *BitStream) !u16 {
        var root = self;

        while (true) {
            if (root.value != null) {
                return root.value orelse unreachable;
            } else if (root.right == null and root.left == null) {
                return Error.InvalidUnderlyingBitStream;
            }

            const nextBit = bits.getNBits(1) orelse {
                return Error.InvalidUnderlyingBitStream;
            };

            std.debug.assert(nextBit < 2);
            const isZero = nextBit == 0;

            if (isZero) {
                root = root.left orelse {
                    return Error.InvalidUnderlyingBitStream;
                };
            } else {
                root = root.right orelse {
                    return Error.InvalidUnderlyingBitStream;
                };
            }
        }
    }

    fn getMaxDepth(self: Self) u32 {
        var root = self;
        var depth: u32 = 0;

        if (root.value == null) {
            if (root.left != null) {
                depth += (root.left orelse unreachable).getMaxDepth();
            }

            if (root.right != null) {
                depth += (root.right orelse unreachable).getMaxDepth();
            }

            depth += 1;
        }

        return depth;
    }

    //TODO(cpowys) perf and cleanup
    fn populateDecoderMaps(self: *Self, decoder: *HuffDecoder) std.mem.Allocator.Error!void {
        try self.populateDecoderMapsWithDepth(decoder, 0, 0);
    }

    fn populateDecoderMapsWithDepth(self: *Self, decoder: *HuffDecoder, depth: u64, codePoint: u64) std.mem.Allocator.Error!void {
        if (self.value) |v| {
            var maxDepth: usize = decoder.maxDepth;
            std.debug.assert(maxDepth >= depth);

            var remainingDepth: u16 = @truncate(u16, maxDepth - depth);
            std.debug.assert(remainingDepth >= 0);

            var start: usize = 0;
            var end: usize = std.math.pow(usize, 2, remainingDepth) - 1;
            std.debug.assert(start <= end);

            while (start <= end) : (start += 1) {
                var key = (start << @truncate(u6, depth)) + codePoint;
                decoder.mapping[key] = MappingVal{ .value = v, .depth = @truncate(u16, depth) };
            }
        } else {
            std.debug.assert(self.left != null or self.right != null);

            if (self.left) |node| {
                try node.populateDecoderMapsWithDepth(decoder, depth + 1, codePoint);
            }

            if (self.right) |node| {
                var mask: u64 = 1;
                mask <<= @truncate(u5, depth);
                try node.populateDecoderMapsWithDepth(decoder, depth + 1, mask | codePoint);
            }
        }
    }
};

const CodeCounts = struct {
    const Self = @This();

    codeCount: []u32,
    nextCode: []u32,
    maxCodeLength: u32,

    fn getCodeCounts(allocator: std.mem.Allocator, codes: []u32) !CodeCounts {
        var maxCodeLength: u32 = codes[0];

        for (codes) |encodingLength| {
            maxCodeLength = @maximum(maxCodeLength, encodingLength);
        }

        var codeCount = try allocator.alloc(u32, maxCodeLength + 1);
        errdefer allocator.free(codeCount);

        for (codeCount) |*count| {
            count.* = 0;
        }

        for (codes) |encodingLength| {
            if (encodingLength > 0) {
                codeCount[encodingLength] += 1;
            }
        }

        var nextCode = try allocator.alloc(u32, maxCodeLength + 1);
        errdefer allocator.free(nextCode);

        for (nextCode) |*code| {
            code.* = 0;
        }

        var codeLength: usize = 1;
        var code: u32 = 0;
        while (codeLength < maxCodeLength + 1) : (codeLength += 1) {
            code = (code + codeCount[codeLength - 1]) << 1;
            nextCode[codeLength] = code;
        }

        return CodeCounts{ .codeCount = codeCount, .nextCode = nextCode, .maxCodeLength = maxCodeLength };
    }

    fn deinit(self: Self, allocator: std.mem.Allocator) void {
        allocator.free(self.codeCount);
        allocator.free(self.nextCode);
    }
};

test "can construct and destroy a hufftree" {
    var allocator = std.testing.allocator;
    var tree = try HuffEncoderDecoder.init(allocator);
    defer tree.deinit();
}

test "Test simple huff tree usage with example from sanity check" {
    var codes = [19]u32{ 4, 3, 0, 2, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 2, 0 };
    var bytes = [5]u8{ 0b00001000, 0b00101101, 0b11011011, 0b00100100, 0b00101101 };
    var bitStream = &BitStream.fromBytes(bytes[0..]);
    var decoder = try HuffDecoder.initFromCodes(std.testing.allocator, codes[0..]);
    defer decoder.deinit();

    var count: i64 = 0;
    while (count < 16) : (count += 1) {
        var code = decoder.decode(bitStream) orelse unreachable;
        _ = code;
    }
}

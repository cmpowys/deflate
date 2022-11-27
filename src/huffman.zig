const std = @import("std");
const BitStream = @import("bit-stream.zig").BitStream;

pub const Error = error{ UnexpectedErrorAddingHuffNode, InvalidUnderlyingBitStream };

pub const HuffNode = struct {
    const Self = @This();

    value: ?u16,
    left: ?*HuffNode,
    right: ?*HuffNode,
    allocator: std.mem.Allocator,

    pub fn generateFromCodes(allocator: std.mem.Allocator, codes: []u32) !*Self {
        std.debug.assert(codes.len > 0);

        var codeCounts = try CodeCounts.getCodeCounts(allocator, codes);
        defer codeCounts.deinit(allocator);

        var huffTree = try HuffNode.init(allocator);
        errdefer huffTree.deinit();

        var codeLength: u32 = 0;
        while (codeLength < codeCounts.maxCodeLength + 1) : (codeLength += 1) {
            if (codeCounts.codeCount[codeLength] == 0)
                continue;

            for (codes) |code, codeIndex| {
                if (code != codeLength)
                    continue;

                try huffTree.addHuffNode(codeLength, codeCounts.nextCode[codeLength], @intCast(u16, codeIndex));
                codeCounts.nextCode[codeLength] += 1;
            }
        }

        return huffTree;
    }

    pub fn init(allocator: std.mem.Allocator) !*HuffNode {
        var result = try allocator.create(HuffNode);
        result.left = null;
        result.right = null;
        result.value = null;
        result.allocator = allocator;
        return result;
    }

    pub fn deinit(self: *Self) void {
        // TODO(cpowys) need a better representation so we don't have to recursively delete all this
        if (self.left != null) {
            (self.left orelse unreachable).deinit();
        }

        if (self.right != null) {
            (self.right orelse unreachable).deinit();
        }

        self.allocator.destroy(self);
    }

    pub fn addHuffNode(self: *Self, codeLength: u32, code: u32, value: u16) !void {
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
                    root.left = try HuffNode.init(self.allocator);
                }
                root = root.left orelse unreachable;
            } else {
                if (root.right == null) {
                    root.right = try HuffNode.init(self.allocator);
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

    pub fn getNextCode(self: *HuffNode, bits: *BitStream) !u16 {
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
    var tree = try HuffNode.init(allocator);
    defer tree.deinit();
}

test "Test simple huff tree usage with example from sanity check" {
    var codes = [19]u32{ 4, 3, 0, 2, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 2, 0 };
    var bytes = [5]u8{ 0b00001000, 0b00101101, 0b11011011, 0b00100100, 0b00101101 };
    var bitStream = &BitStream.fromBytes(bytes[0..]);
    var tree = try HuffNode.generateFromCodes(std.testing.allocator, codes[0..]);
    defer tree.deinit();

    var count : i64  = 0;
    while (count < 16)  : (count += 1) {
        var code = try tree.getNextCode(bitStream);
        _ = code;
    }
}

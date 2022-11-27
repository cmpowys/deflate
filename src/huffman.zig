const std = @import("std");
const BitStream = @import("bit-stream.zig").BitStream;

pub const Error = error{ UnexpectedErrorAddingHuffNode, InvalidUnderlyingBitStream };

pub const HuffNode = struct {
    const Self = @This();

    value: ?u16,
    left: ?*HuffNode,
    right: ?*HuffNode,
    allocator: std.mem.Allocator,

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

test "can construct and destroy a hufftree" {
    var allocator = std.testing.allocator;
    var tree = try HuffNode.init(allocator);
    defer tree.deinit();
}

test "simple test" {
    //TODO
}

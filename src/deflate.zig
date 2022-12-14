const std = @import("std");
const Allocator = std.mem.Allocator;
const BitStream = @import("bit-stream.zig").BitStream;
const HuffDecoder = @import("huffman.zig").HuffDecoder;

pub const Error = error{ InvalidDeflateStream, Unsupported };

pub fn decompress(allocator: *Allocator, bytes: []u8) ![]u8 { // TODO make output a stream?
    var arena = std.heap.ArenaAllocator.init(allocator.*);
    defer arena.deinit();

    var bits = BitStream.fromBytes(bytes);

    const header = try getDeflateHeader(&bits);

    if (header.compressionMethod != 8) {
        std.log.err("Compression method = {}, expected 8", .{header.compressionMethod});
        return Error.Unsupported;
    }

    if (header.fDict == 1) {
        std.log.err("FDict flag = 1, not supported", .{});
        return Error.Unsupported;
    }

    // TODO check the other header fields

    var output = std.ArrayList(u8).init(allocator.*);
    errdefer output.clearAndFree();

    while (try processBlock(&bits, &output, &arena)) {}

    return output.toOwnedSlice();
}

const BlockType = enum(u8) { UnCompressed = 0, Fixed = 1, Dynamic = 2, Err = 3 };

const BlockHeader = struct { isFinal: bool, blockType: BlockType };

const DeflateHeader = struct { compressionMethod: u8, log2WindowSize: u8, fCheck: u8, fDict: u8, fLevel: u8 };

const HuffEncoderDecoderPair = struct { litCodes: *HuffDecoder, distCodes: *HuffDecoder };

const max_code_length_table_length = 19;
const max_lit_length_table_length = 286;
const max_dist_length_table_length = 32;

fn getDeflateHeader(bits: *BitStream) !DeflateHeader { // TODO could just make the DeflateHeader a packed struct and cast it to the first two bytes of the byte stream
    var compressionMethod = try getNextBitsWithError(bits, 4, "Compression Method");
    var log2WindowSize = try getNextBitsWithError(bits, 4, "Log 2 Window Size");
    var fCheck = try getNextBitsWithError(bits, 5, "fCheck");
    var fDict = try getNextBitsWithError(bits, 1, "fDict");
    var fLevel = try getNextBitsWithError(bits, 2, "fLevel");

    return DeflateHeader{ .compressionMethod = @intCast(u8, compressionMethod), .log2WindowSize = @intCast(u8, log2WindowSize), .fCheck = @intCast(u8, fCheck), .fDict = @intCast(u8, fDict), .fLevel = @intCast(u8, fLevel) };
}

fn getBlockHeader(bits: *BitStream) !BlockHeader {
    var isFinal = try getNextBitsWithError(bits, 1, "IsFinalBlock");
    var blockType = try getNextBitsWithError(bits, 2, "BlockType");
    return BlockHeader{ .isFinal = isFinal == 1, .blockType = @intToEnum(BlockType, blockType) };
}

fn processBlock(bits: *BitStream, output: *std.ArrayList(u8), arena: *std.heap.ArenaAllocator) !bool {
    _ = output;
    const blockHeader = try getBlockHeader(bits);

    switch (blockHeader.blockType) {
        BlockType.UnCompressed => {},
        BlockType.Fixed => {
            const huffPair = try getFixedHuffEncoderDecoderPair(arena);
            try decompressRestOfBlock(bits, output, huffPair);
        },
        BlockType.Dynamic => {
            const huffPair = try getDynamicHuffPairs(arena, bits);
            try decompressRestOfBlock(bits, output, huffPair);
        },
        else => {
            std.log.err("Deflate block header has block type : 3, which is an error", .{});
            return Error.InvalidDeflateStream;
        },
    }

    return !blockHeader.isFinal;
}

fn decompressRestOfBlock(bits: *BitStream, output: *std.ArrayList(u8), huffPair: HuffEncoderDecoderPair) !void {

    // TODO simplify table with a 2d array
    const baseLengthsForDistanceCodes = [_]u16{ 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258 };
    const extraLengthsForDistanceCodes = [_]u8{ 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 };
    const baseDistanceForDistanceCodes = [_]u16{ 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577 };
    const extraDistanceForDistanceCodes = [_]u8{ 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13 };

    while (true) {
        const litCode = huffPair.litCodes.decode(bits) orelse return Error.InvalidDeflateStream;

        if (litCode < 256) {
            try output.append(@intCast(u8, litCode));
        } else if (litCode == 256) {
            return;
        } else {
            const litIndex = litCode - 257;
            const baseLength = baseLengthsForDistanceCodes[litIndex];
            const numExtraLengthBits = extraLengthsForDistanceCodes[litIndex];
            const extraLength = try getNextBitsWithError(bits, numExtraLengthBits, "LitCode Extra Length Bits");
            const length = baseLength + extraLength;

            const distCode = huffPair.distCodes.decode(bits) orelse return Error.InvalidDeflateStream;
            const baseDistance = baseDistanceForDistanceCodes[distCode];
            const numExtraDistanceBits = extraDistanceForDistanceCodes[distCode];
            const extraDistance = try getNextBitsWithError(bits, numExtraDistanceBits, "DistCode Extra Distance Bits");
            const distance = baseDistance + extraDistance;

            const outputSize = output.items.len;
            if (outputSize - distance < 0) {
                std.log.err("Unexpected ditance calculated decompressing block, current output size is {}, distance calculated is {}", .{ outputSize, distance });
                return Error.InvalidDeflateStream;
            }

            var outputPosition: usize = 0;
            while (outputPosition < length) : (outputPosition += 1) {
                const literal: u8 = output.items[outputSize - distance + outputPosition];
                try output.append(literal);
            }
        }
    }
}

fn getDynamicHuffPairs(arena: *std.heap.ArenaAllocator, bits: *BitStream) !HuffEncoderDecoderPair {
    const numberOfLiteralLengthCodes = (try getNextBitsWithError(bits, 5, "Number Of Literal Length Codes")) + 257;
    const numberOfDistanceCodes = (try getNextBitsWithError(bits, 5, "Number Of Distance Codes")) + 1;
    const numberOfCodeLengthCodes = (try getNextBitsWithError(bits, 4, "Number Of Code Length Codes")) + 4;

    const codeLengthEncoding = try getCodeLengthCodes(arena, bits, numberOfCodeLengthCodes);
    const codeHuffEncoderDecoder = try HuffDecoder.initFromCodes(arena.allocator(), codeLengthEncoding);

    const encodedLitCodes = try getEncodedHuffCodes(bits, arena, codeHuffEncoderDecoder, numberOfLiteralLengthCodes);
    const litCodeHuffEncoderDecoder = try HuffDecoder.initFromCodes(arena.allocator(), encodedLitCodes);

    const encodedDistCodes = try getEncodedHuffCodes(bits, arena, codeHuffEncoderDecoder, numberOfDistanceCodes);
    const distCodeEncoderDecoder = try HuffDecoder.initFromCodes(arena.allocator(), encodedDistCodes);

    return HuffEncoderDecoderPair{
        .litCodes = litCodeHuffEncoderDecoder,
        .distCodes = distCodeEncoderDecoder,
    };
}

fn getCodeLengthCodes(arena: *std.heap.ArenaAllocator, bits: *BitStream, numberOfCodeLengthCodes: usize) ![]u32 {
    const codeLengthTableOrdering = [_]usize{ 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 };

    var codeLengthEncoding = try arena.allocator().alloc(u32, max_code_length_table_length);
    for (codeLengthEncoding) |*code| {
        code.* = 0;
    }

    var codeLengthIndex: usize = 0;
    while (codeLengthIndex < numberOfCodeLengthCodes) : (codeLengthIndex += 1) {
        const actualCodeLengthIndex = codeLengthTableOrdering[codeLengthIndex];
        const codeLength = @intCast(u32, try getNextBitsWithError(bits, 3, "Code Length"));
        codeLengthEncoding[actualCodeLengthIndex] = codeLength;
    }

    return codeLengthEncoding;
}

fn getEncodedHuffCodes(bits: *BitStream, arena: *std.heap.ArenaAllocator, huff: *HuffDecoder, numCodesExpected: usize) ![]u32 {
    std.debug.assert(numCodesExpected > 0);

    var codes = try std.ArrayList(u32).initCapacity(arena.allocator(), numCodesExpected);
    var prevCode: u32 = 0;

    while (codes.items.len < numCodesExpected) {
        var code: u32 = huff.decode(bits) orelse return Error.InvalidDeflateStream;
        var repeats: u64 = 1;

        if (code > 15) {
            switch (code) {
                16 => {
                    code = prevCode;
                    repeats = (try getNextBitsWithError(bits, 2, "HuffMan Repeats")) + 3;
                },
                17 => {
                    code = 0;
                    repeats = (try getNextBitsWithError(bits, 3, "HuffMan Repeats")) + 3;
                },
                18 => {
                    code = 0;
                    repeats = (try getNextBitsWithError(bits, 7, "HuffMan Repeats")) + 11;
                },
                else => {
                    std.log.debug("Unexpected code generated from huffman tree {}, should be < 19", .{code});
                    return Error.InvalidDeflateStream;
                },
            }
        }
        try codes.appendNTimes(code, repeats);
        prevCode = code;
    }

    if (codes.items.len > numCodesExpected) {
        std.log.err("When trying to decode a dynamic huffman tree, we processed {} codes but expected {}", .{ codes.items.len, numCodesExpected });
        return Error.InvalidDeflateStream;
    }

    return codes.toOwnedSlice();
}

fn getFixedHuffEncoderDecoderPair(arena: *std.heap.ArenaAllocator) !HuffEncoderDecoderPair {
    var huffPair: HuffEncoderDecoderPair = undefined;
    comptime var encodedLitCodes: [max_lit_length_table_length]u32 = undefined;
    comptime var encodedDistCodes: [max_dist_length_table_length]u32 = undefined;

    comptime {
        for (encodedLitCodes[0..144]) |*val| {
            val.* = 8;
        }

        for (encodedLitCodes[144..256]) |*val| {
            val.* = 9;
        }

        for (encodedLitCodes[256..280]) |*val| {
            val.* = 7;
        }

        for (encodedLitCodes[280..]) |*val| {
            val.* = 8;
        }

        for (encodedDistCodes[0..]) |*val| {
            val.* = 5;
        }
    }

    // TODO need a comptime allocator so this can all be done in comptime
    huffPair.litCodes = try HuffDecoder.initFromCodes(arena.allocator(), encodedLitCodes[0..]);
    huffPair.distCodes = try HuffDecoder.initFromCodes(arena.allocator(), encodedDistCodes[0..]);

    return huffPair;
}

fn getNextBitsWithError(self: *BitStream, numBits: u32, fieldName: []const u8) !u64 {
    return self.getNBits(numBits) orelse {
        std.log.err("Invalid deflate header, not enough bits for '{s}'", .{fieldName});
        return Error.InvalidDeflateStream;
    };
}

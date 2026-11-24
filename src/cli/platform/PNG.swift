// src/cli/platform/PNG.swift
//
// PNG in Swift, for the app icon: decoding icon.png, resampling it to each
// size a platform asks for, and encoding the result. No sips, no ImageMagick:
// the CLI builds icons the same way on macOS, Linux and Windows, with nothing
// to install first.
//
// Decodes every PNG a designer exports: greyscale, RGB, palette, with or
// without alpha, 1 to 16 bits, interlaced or not. Encodes RGBA, 8 bits, with
// per-row filters and deflate (LZ77 with fixed Huffman codes), which is within
// a few percent of zlib's output for icons.

import Foundation

struct PNGError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// An image as 8-bit RGBA, straight (not premultiplied) alpha, rows top down.
struct RGBAImage {
    let width: Int
    let height: Int
    var pixels: [UInt8]

    init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }
}

enum PNG {
    static let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    // MARK: Decoding

    static func decode(_ data: Data) throws -> RGBAImage {
        let bytes = [UInt8](data)
        guard bytes.count > 8, Array(bytes[0..<8]) == signature else { throw PNGError("not a PNG file") }
        var offset = 8
        var width = 0, height = 0, depth = 0, colour = 0, interlace = 0
        var palette: [UInt8] = []
        var transparency: [UInt8] = []
        var compressed: [UInt8] = []
        func u32(_ at: Int) -> Int {
            Int(bytes[at]) << 24 | Int(bytes[at + 1]) << 16 | Int(bytes[at + 2]) << 8 | Int(bytes[at + 3])
        }
        while offset + 8 <= bytes.count {
            let length = u32(offset)
            let type = String(decoding: bytes[offset + 4..<offset + 8], as: UTF8.self)
            let start = offset + 8
            guard start + length + 4 <= bytes.count else { throw PNGError("truncated \(type) chunk") }
            let body = bytes[start..<start + length]
            switch type {
            case "IHDR":
                width = u32(start)
                height = u32(start + 4)
                depth = Int(bytes[start + 8])
                colour = Int(bytes[start + 9])
                interlace = Int(bytes[start + 12])
            case "PLTE": palette = Array(body)
            case "tRNS": transparency = Array(body)
            case "IDAT": compressed += body
            case "IEND": offset = bytes.count
            default: break
            }
            offset = start + length + 4
        }
        guard width > 0, height > 0 else { throw PNGError("no image header") }
        let channels: Int
        switch colour {
        case 0: channels = 1      // greyscale
        case 2: channels = 3      // RGB
        case 3: channels = 1      // palette
        case 4: channels = 2      // greyscale and alpha
        case 6: channels = 4      // RGBA
        default: throw PNGError("unknown colour type \(colour)")
        }
        let raw = try Inflate.zlib(compressed)
        let bitsPerPixel = channels * depth
        let bpp = max(1, bitsPerPixel / 8)

        var out = [UInt8](repeating: 0, count: width * height * 4)
        var cursor = 0

        // One pass of the image (all of it, or one of Adam7's seven), unfiltered
        // and written into `out` at its pixels' places.
        func pass(_ pw: Int, _ ph: Int, place: (Int, Int) -> (Int, Int)) throws {
            guard pw > 0, ph > 0 else { return }
            let stride = (pw * bitsPerPixel + 7) / 8
            var previous = [UInt8](repeating: 0, count: stride)
            var row = [UInt8](repeating: 0, count: stride)
            for y in 0..<ph {
                guard cursor + 1 + stride <= raw.count else { throw PNGError("image data ends early") }
                let filter = raw[cursor]
                cursor += 1
                for i in 0..<stride {
                    let x = raw[cursor + i]
                    let a = i >= bpp ? Int(row[i - bpp]) : 0
                    let b = Int(previous[i])
                    let c = i >= bpp ? Int(previous[i - bpp]) : 0
                    let predicted: Int
                    switch filter {
                    case 0: predicted = 0
                    case 1: predicted = a
                    case 2: predicted = b
                    case 3: predicted = (a + b) / 2
                    case 4: predicted = paeth(a, b, c)
                    default: throw PNGError("unknown row filter \(filter)")
                    }
                    row[i] = UInt8(truncatingIfNeeded: Int(x) + predicted)
                }
                cursor += stride
                for x in 0..<pw {
                    let (ox, oy) = place(x, y)
                    let rgba = sample(row, x, depth: depth, colour: colour, channels: channels,
                                      palette: palette, transparency: transparency)
                    let o = (oy * width + ox) * 4
                    out[o] = rgba.0; out[o + 1] = rgba.1; out[o + 2] = rgba.2; out[o + 3] = rgba.3
                }
                swap(&previous, &row)
            }
        }

        if interlace == 1 {
            let passes = [(0, 0, 8, 8), (4, 0, 8, 8), (0, 4, 4, 8), (2, 0, 4, 4), (0, 2, 2, 4), (1, 0, 2, 2), (0, 1, 1, 2)]
            for (x0, y0, dx, dy) in passes {
                let pw = (width - x0 + dx - 1) / dx, ph = (height - y0 + dy - 1) / dy
                try pass(pw, ph) { x, y in (x0 + x * dx, y0 + y * dy) }
            }
        } else {
            try pass(width, height) { x, y in (x, y) }
        }
        return RGBAImage(width: width, height: height, pixels: out)
    }

    private static func paeth(_ a: Int, _ b: Int, _ c: Int) -> Int {
        let p = a + b - c
        let pa = abs(p - a), pb = abs(p - b), pc = abs(p - c)
        if pa <= pb && pa <= pc { return a }
        return pb <= pc ? b : c
    }

    /// Pixel `x` of an unfiltered row, as 8-bit RGBA.
    private static func sample(_ row: [UInt8], _ x: Int, depth: Int, colour: Int, channels: Int,
                               palette: [UInt8], transparency: [UInt8]) -> (UInt8, UInt8, UInt8, UInt8) {
        // Channel `c` scaled to 8 bits, and as stored (for tRNS's comparison).
        func value(_ c: Int) -> (UInt8, Int) {
            switch depth {
            case 16:
                let i = (x * channels + c) * 2
                let v = Int(row[i]) << 8 | Int(row[i + 1])
                return (row[i], v)
            case 8:
                let v = row[x * channels + c]
                return (v, Int(v))
            default:
                // 1, 2 or 4 bits: one channel, packed from the high bits down.
                let bit = x * depth
                let v = Int(row[bit / 8] >> UInt8(8 - depth - bit % 8)) & ((1 << depth) - 1)
                let scaled = colour == 3 ? v : v * 255 / ((1 << depth) - 1)
                return (UInt8(scaled), v)
            }
        }
        func tRNS16(_ index: Int) -> Int {
            guard transparency.count >= index * 2 + 2 else { return -1 }
            return Int(transparency[index * 2]) << 8 | Int(transparency[index * 2 + 1])
        }
        switch colour {
        case 0:
            let (g, stored) = value(0)
            return (g, g, g, stored == tRNS16(0) ? 0 : 255)
        case 2:
            let (r, sr) = value(0), (g, sg) = value(1), (b, sb) = value(2)
            let clear = sr == tRNS16(0) && sg == tRNS16(1) && sb == tRNS16(2)
            return (r, g, b, clear ? 0 : 255)
        case 3:
            let (_, index) = value(0)
            guard palette.count >= index * 3 + 3 else { return (0, 0, 0, 0) }
            let a = index < transparency.count ? transparency[index] : 255
            return (palette[index * 3], palette[index * 3 + 1], palette[index * 3 + 2], a)
        case 4:
            let (g, _) = value(0), (a, _) = value(1)
            return (g, g, g, a)
        default:
            let (r, _) = value(0), (g, _) = value(1), (b, _) = value(2), (a, _) = value(3)
            return (r, g, b, a)
        }
    }

    // MARK: Encoding

    static func encode(_ image: RGBAImage) -> Data {
        let stride = image.width * 4
        var raw = [UInt8]()
        raw.reserveCapacity((stride + 1) * image.height)
        var previous = [UInt8](repeating: 0, count: stride)
        var candidates = [[UInt8]](repeating: [UInt8](repeating: 0, count: stride), count: 5)
        for y in 0..<image.height {
            let row = Array(image.pixels[y * stride..<(y + 1) * stride])
            // Each filter tried; the one whose bytes are smallest as signed
            // values kept, as libpng's heuristic does.
            var best = 0, bestScore = Int.max
            for filter in 0..<5 {
                var score = 0
                for i in 0..<stride {
                    let a = i >= 4 ? Int(row[i - 4]) : 0
                    let b = Int(previous[i])
                    let c = i >= 4 ? Int(previous[i - 4]) : 0
                    let predicted: Int
                    switch filter {
                    case 1: predicted = a
                    case 2: predicted = b
                    case 3: predicted = (a + b) / 2
                    case 4: predicted = paeth(a, b, c)
                    default: predicted = 0
                    }
                    let v = UInt8(truncatingIfNeeded: Int(row[i]) - predicted)
                    candidates[filter][i] = v
                    score += v < 128 ? Int(v) : 256 - Int(v)
                }
                if score < bestScore { bestScore = score; best = filter }
            }
            raw.append(UInt8(best))
            raw += candidates[best]
            previous = row
        }

        var out = Data(signature)
        var header = Data()
        header.append(bigEndian(UInt32(image.width)))
        header.append(bigEndian(UInt32(image.height)))
        header.append(contentsOf: [8, 6, 0, 0, 0]) // 8 bits, RGBA, deflate, adaptive filters, not interlaced
        out.append(chunk("IHDR", header))
        out.append(chunk("IDAT", Data(Deflate.zlib(raw))))
        out.append(chunk("IEND", Data()))
        return out
    }

    static func bigEndian(_ value: UInt32) -> Data {
        Data([UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)])
    }

    static func chunk(_ type: String, _ payload: Data) -> Data {
        var body = Data(type.utf8)
        body.append(payload)
        var out = bigEndian(UInt32(payload.count))
        out.append(body)
        out.append(bigEndian(crc32(body)))
        return out
    }

    private static let crcTable: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data { crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFF_FFFF
    }

    static func adler32(_ data: [UInt8]) -> UInt32 {
        var a: UInt32 = 1, b: UInt32 = 0
        var index = 0
        while index < data.count {
            // 5552 bytes is the most that can be summed before the modulo is needed.
            let end = min(index + 5552, data.count)
            while index < end {
                a += UInt32(data[index])
                b += a
                index += 1
            }
            a %= 65_521
            b %= 65_521
        }
        return b << 16 | a
    }
}

// MARK: - Resampling

extension RGBAImage {
    /// Resized to exactly `width` × `height`. Shrinking averages every source
    /// pixel each output pixel covers (an area filter, as sips and
    /// ImageMagick's box filter do), in premultiplied alpha so transparent
    /// pixels lend no colour to the edges. Enlarging is bilinear.
    func resized(width newWidth: Int, height newHeight: Int) -> RGBAImage {
        guard newWidth > 0, newHeight > 0 else { return RGBAImage(width: 0, height: 0, pixels: []) }
        if newWidth == width && newHeight == height { return self }
        // Premultiplied, linear in [0, 1].
        var source = [Double](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) {
            let a = Double(pixels[i * 4 + 3]) / 255
            source[i * 4] = Double(pixels[i * 4]) / 255 * a
            source[i * 4 + 1] = Double(pixels[i * 4 + 1]) / 255 * a
            source[i * 4 + 2] = Double(pixels[i * 4 + 2]) / 255 * a
            source[i * 4 + 3] = a
        }
        // Across, then down: each a 1-D resample.
        let across = RGBAImage.resample(source, count: width, lines: height, stride: 1, lineStride: width,
                                        to: newWidth)
        let down = RGBAImage.resample(across, count: height, lines: newWidth, stride: newWidth, lineStride: 1,
                                      to: newHeight)
        var out = [UInt8](repeating: 0, count: newWidth * newHeight * 4)
        for i in 0..<(newWidth * newHeight) {
            let a = down[i * 4 + 3]
            func byte(_ v: Double) -> UInt8 { UInt8(max(0, min(255, (v * 255).rounded()))) }
            if a > 0 {
                out[i * 4] = byte(down[i * 4] / a)
                out[i * 4 + 1] = byte(down[i * 4 + 1] / a)
                out[i * 4 + 2] = byte(down[i * 4 + 2] / a)
            }
            out[i * 4 + 3] = byte(a)
        }
        return RGBAImage(width: newWidth, height: newHeight, pixels: out)
    }

    /// One axis: `lines` lines of `count` pixels each (pixel `i` of line `l`
    /// at index (l * lineStride + i * stride) * 4) to `newCount` pixels. The
    /// result is laid out the same way with `newCount` along the axis.
    private static func resample(_ input: [Double], count: Int, lines: Int, stride: Int, lineStride: Int,
                                 to newCount: Int) -> [Double] {
        // Output index for (line, pixel), in the same orientation as the input.
        let outStride = stride == 1 ? 1 : lines
        let outLineStride = stride == 1 ? newCount : 1
        var output = [Double](repeating: 0, count: newCount * lines * 4)
        let scale = Double(count) / Double(newCount)
        for line in 0..<lines {
            for o in 0..<newCount {
                var r = 0.0, g = 0.0, b = 0.0, a = 0.0
                if scale >= 1 {
                    // The source span this output pixel covers, partial pixels weighted.
                    let start = Double(o) * scale, end = start + scale
                    var i = Int(start)
                    var weight = 0.0
                    while Double(i) < end, i < count {
                        let w = min(end, Double(i + 1)) - max(start, Double(i))
                        let s = (line * lineStride + i * stride) * 4
                        r += input[s] * w; g += input[s + 1] * w; b += input[s + 2] * w; a += input[s + 3] * w
                        weight += w
                        i += 1
                    }
                    if weight > 0 { r /= weight; g /= weight; b /= weight; a /= weight }
                } else {
                    let centre = (Double(o) + 0.5) * scale - 0.5
                    let i0 = max(0, min(count - 1, Int(centre.rounded(.down))))
                    let i1 = min(count - 1, i0 + 1)
                    let t = max(0, min(1, centre - Double(i0)))
                    let s0 = (line * lineStride + i0 * stride) * 4, s1 = (line * lineStride + i1 * stride) * 4
                    r = input[s0] * (1 - t) + input[s1] * t
                    g = input[s0 + 1] * (1 - t) + input[s1 + 1] * t
                    b = input[s0 + 2] * (1 - t) + input[s1 + 2] * t
                    a = input[s0 + 3] * (1 - t) + input[s1 + 3] * t
                }
                let d = (line * outLineStride + o * outStride) * 4
                output[d] = r; output[d + 1] = g; output[d + 2] = b; output[d + 3] = a
            }
        }
        return output
    }
}

// MARK: - Inflate

/// RFC 1950/1951 decompression: stored, fixed and dynamic Huffman blocks.
enum Inflate {
    static func zlib(_ data: [UInt8]) throws -> [UInt8] {
        guard data.count >= 2, data[0] & 0x0F == 8, (Int(data[0]) << 8 | Int(data[1])) % 31 == 0 else {
            throw PNGError("image data isn't a zlib stream")
        }
        return try raw(data, from: 2)
    }

    private struct Huffman {
        /// Codes by length (counts) and the symbols in canonical order.
        var counts = [Int](repeating: 0, count: 16)
        var symbols: [Int] = []

        init(lengths: [Int]) {
            for length in lengths { counts[length] += 1 }
            counts[0] = 0
            var offsets = [Int](repeating: 0, count: 16)
            for i in 1..<16 { offsets[i] = offsets[i - 1] + counts[i - 1] }
            symbols = [Int](repeating: 0, count: lengths.count)
            for (symbol, length) in lengths.enumerated() where length != 0 {
                symbols[offsets[length]] = symbol
                offsets[length] += 1
            }
        }
    }

    private struct Bits {
        let data: [UInt8]
        var position: Int
        var bitBuffer = 0
        var bitCount = 0

        mutating func bits(_ n: Int) throws -> Int {
            while bitCount < n {
                guard position < data.count else { throw PNGError("image data ends early") }
                bitBuffer |= Int(data[position]) << bitCount
                position += 1
                bitCount += 8
            }
            let value = bitBuffer & ((1 << n) - 1)
            bitBuffer >>= n
            bitCount -= n
            return value
        }

        /// A symbol, a bit at a time down the canonical code (puff's decode).
        mutating func decode(_ h: Huffman) throws -> Int {
            var code = 0, first = 0, index = 0
            for length in 1..<16 {
                code |= try bits(1)
                let count = h.counts[length]
                if code - count < first { return h.symbols[index + (code - first)] }
                index += count
                first += count
                first <<= 1
                code <<= 1
            }
            throw PNGError("bad Huffman code in image data")
        }

        mutating func alignToByte() { bitBuffer = 0; bitCount = 0 }
    }

    static let lengthBase = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115,
                             131, 163, 195, 227, 258]
    static let lengthExtra = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
    static let distanceBase = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025,
                               1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]
    static let distanceExtra = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12,
                                12, 13, 13]

    private static let fixedLiterals = Huffman(lengths: (0..<288).map { $0 < 144 ? 8 : $0 < 256 ? 9 : $0 < 280 ? 7 : 8 })
    private static let fixedDistances = Huffman(lengths: [Int](repeating: 5, count: 30))

    static func raw(_ data: [UInt8], from start: Int) throws -> [UInt8] {
        var input = Bits(data: data, position: start)
        var out: [UInt8] = []
        out.reserveCapacity(data.count * 4)
        var last = 0
        repeat {
            last = try input.bits(1)
            let type = try input.bits(2)
            switch type {
            case 0:
                input.alignToByte()
                let p = input.position
                guard p + 4 <= data.count else { throw PNGError("image data ends early") }
                let length = Int(data[p]) | Int(data[p + 1]) << 8
                guard p + 4 + length <= data.count else { throw PNGError("image data ends early") }
                out += data[(p + 4)..<(p + 4 + length)]
                input.position = p + 4 + length
            case 1:
                try block(&input, &out, fixedLiterals, fixedDistances)
            case 2:
                let literalCount = try input.bits(5) + 257
                let distanceCount = try input.bits(5) + 1
                let codeCount = try input.bits(4) + 4
                let order = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]
                var codeLengths = [Int](repeating: 0, count: 19)
                for i in 0..<codeCount { codeLengths[order[i]] = try input.bits(3) }
                let codes = Huffman(lengths: codeLengths)
                var lengths: [Int] = []
                while lengths.count < literalCount + distanceCount {
                    let symbol = try input.decode(codes)
                    switch symbol {
                    case 0..<16: lengths.append(symbol)
                    case 16:
                        guard let previous = lengths.last else { throw PNGError("bad code lengths in image data") }
                        lengths += [Int](repeating: previous, count: 3 + (try input.bits(2)))
                    case 17: lengths += [Int](repeating: 0, count: 3 + (try input.bits(3)))
                    default: lengths += [Int](repeating: 0, count: 11 + (try input.bits(7)))
                    }
                }
                try block(&input, &out, Huffman(lengths: Array(lengths[0..<literalCount])),
                          Huffman(lengths: Array(lengths[literalCount..<literalCount + distanceCount])))
            default:
                throw PNGError("bad block type in image data")
            }
        } while last == 0
        return out
    }

    private static func block(_ input: inout Bits, _ out: inout [UInt8], _ literals: Huffman, _ distances: Huffman) throws {
        while true {
            let symbol = try input.decode(literals)
            if symbol < 256 { out.append(UInt8(symbol)); continue }
            if symbol == 256 { return }
            let lengthIndex = symbol - 257
            guard lengthIndex < lengthBase.count else { throw PNGError("bad length in image data") }
            let length = lengthBase[lengthIndex] + (try input.bits(lengthExtra[lengthIndex]))
            let distanceIndex = try input.decode(distances)
            guard distanceIndex < distanceBase.count else { throw PNGError("bad distance in image data") }
            let distance = distanceBase[distanceIndex] + (try input.bits(distanceExtra[distanceIndex]))
            guard distance <= out.count else { throw PNGError("bad distance in image data") }
            let from = out.count - distance
            for i in 0..<length { out.append(out[from + i]) }
        }
    }
}

// MARK: - Deflate

/// RFC 1951 compression for PNG's IDAT: greedy LZ77 over a 32 KB window with
/// hash chains, coded with the fixed Huffman tables. Not zlib's best, but
/// close to it on images, and a fraction of the code.
enum Deflate {
    static func zlib(_ data: [UInt8]) -> [UInt8] {
        var out: [UInt8] = [0x78, 0x01]
        var writer = BitWriter()
        writer.write(1, 1)   // the last block
        writer.write(1, 2)   // fixed Huffman codes
        let windowSize = 32_768, maxChain = 64
        var head = [Int](repeating: -1, count: 1 << 15)
        var previous = [Int](repeating: -1, count: windowSize)
        func hash(_ i: Int) -> Int {
            (Int(data[i]) << 10 ^ Int(data[i + 1]) << 5 ^ Int(data[i + 2])) & 0x7FFF
        }
        func insert(_ i: Int) {
            guard i + 2 < data.count else { return }
            let h = hash(i)
            previous[i % windowSize] = head[h]
            head[h] = i
        }
        var i = 0
        while i < data.count {
            var bestLength = 0, bestDistance = 0
            if i + 2 < data.count {
                var candidate = head[hash(i)]
                var chain = 0
                let limit = min(258, data.count - i)
                while candidate >= 0, i - candidate <= windowSize, chain < maxChain {
                    var length = 0
                    while length < limit && data[candidate + length] == data[i + length] { length += 1 }
                    if length > bestLength {
                        bestLength = length
                        bestDistance = i - candidate
                        if length == limit { break }
                    }
                    let next = previous[candidate % windowSize]
                    if next >= candidate { break }
                    candidate = next
                    chain += 1
                }
            }
            if bestLength >= 3 {
                writer.length(bestLength)
                writer.distance(bestDistance)
                for j in i..<(i + bestLength) { insert(j) }
                i += bestLength
            } else {
                writer.literal(Int(data[i]))
                insert(i)
                i += 1
            }
        }
        writer.literal(256)
        out += writer.finish()
        let check = PNG.adler32(data)
        out += [UInt8(check >> 24 & 0xFF), UInt8(check >> 16 & 0xFF), UInt8(check >> 8 & 0xFF), UInt8(check & 0xFF)]
        return out
    }

    private struct BitWriter {
        var bytes: [UInt8] = []
        var buffer = 0
        var count = 0

        /// `n` bits of `value`, least significant first, as deflate packs them.
        mutating func write(_ value: Int, _ n: Int) {
            buffer |= value << count
            count += n
            while count >= 8 {
                bytes.append(UInt8(buffer & 0xFF))
                buffer >>= 8
                count -= 8
            }
        }

        /// A Huffman code, which deflate stores most significant bit first.
        mutating func code(_ value: Int, _ n: Int) {
            var reversed = 0
            for k in 0..<n where value & (1 << k) != 0 { reversed |= 1 << (n - 1 - k) }
            write(reversed, n)
        }

        mutating func literal(_ symbol: Int) {
            switch symbol {
            case 0..<144: code(0x30 + symbol, 8)
            case 144..<256: code(0x190 + symbol - 144, 9)
            case 256..<280: code(symbol - 256, 7)
            default: code(0xC0 + symbol - 280, 8)
            }
        }

        mutating func length(_ length: Int) {
            var index = Inflate.lengthBase.count - 1
            while Inflate.lengthBase[index] > length { index -= 1 }
            literal(257 + index)
            let extra = Inflate.lengthExtra[index]
            if extra > 0 { write(length - Inflate.lengthBase[index], extra) }
        }

        mutating func distance(_ distance: Int) {
            var index = Inflate.distanceBase.count - 1
            while Inflate.distanceBase[index] > distance { index -= 1 }
            code(index, 5)
            let extra = Inflate.distanceExtra[index]
            if extra > 0 { write(distance - Inflate.distanceBase[index], extra) }
        }

        mutating func finish() -> [UInt8] {
            if count > 0 { bytes.append(UInt8(buffer & 0xFF)) }
            buffer = 0
            count = 0
            return bytes
        }
    }
}

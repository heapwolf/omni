
import Foundation

// MARK: - Drawing

enum IconArt {

    // Cool slate, dark to pale.
    private static let deep = (r: 0.302, g: 0.341, b: 0.447)
    private static let mid = (r: 0.447, g: 0.490, b: 0.561)
    private static let pale = (r: 0.855, g: 0.875, b: 0.890)

    /// PNG bytes, size × size. `letter` is drawn white inside the circle; nil
    /// or an unmapped character leaves it empty.
    static func placeholder(size: Int, letter: Character? = nil) -> Data {
        var canvas = Canvas(size: size)
        let s = Double(size)

        // Fractal value noise, biased heavier at the top.
        canvas.eachPixel { x, y in
            let cloud = Noise.fbm(x / s * 2.0, y / s * 2.0)
            let height = y / (s - 1)
            let t = min(max(cloud * 0.78 + height * 0.42, 0), 1)
            return t < 0.5
                ? mix(deep, mid, t * 2)
                : mix(mid, pale, (t - 0.5) * 2)
        }

        // One width for every line, hairline at any size.
        let line = max(1.0, s / 256)
        let ink = (r: 1.0, g: 1.0, b: 1.0)

        for step in 1..<4 {
            let at = (s * Double(step) / 4).rounded()
            canvas.segment(from: (at, 0), to: (at, s), width: line, colour: ink, alpha: 0.26)
            canvas.segment(from: (0, at), to: (s, at), width: line, colour: ink, alpha: 0.26)
        }

        let centre = (s / 2, s / 2)
        let circle = s * 0.32
        canvas.ring(centre: centre, radius: circle, width: line, colour: ink, alpha: 0.34)

        // The initial, drawn last so it sits on top.
        if let letter, let strokes = glyph(for: letter) {
            // Stem is a seventh of cap height. Cap height is larger below
            // 96pt, where the 512pt proportions leave the letter unreadable.
            let capHeight = s * (size < 96 ? 0.46 : 0.34)
            let pen = max(1.0, capHeight / 7)
            canvas.draw(strokes, centre: centre, capHeight: capHeight,
                        width: pen, colour: ink, alpha: 0.95)
        }

        return canvas.png()
    }

    /// One stroke of a letter. The alphabet is single-stroke skeletons, not
    /// outlines: outlines would need a fill rule.
    enum Stroke {
        /// Polyline in a unit box: x and y 0...1, y downward.
        case line([(Double, Double)])
        /// Centre, radius, start and end angle in degrees. 0° east, angles
        /// increase clockwise (y is down). Swept from `from` toward `to`.
        case arc(Double, Double, Double, Double, Double)
    }

    static func glyph(for character: Character) -> [Stroke]? {
        glyphs[Character(character.uppercased())]
    }

    private static let glyphs: [Character: [Stroke]] = [
        "0": [.arc(0.5, 0.5, 0.42, 0, 360)],
        "1": [.line([(0.3, 0.18), (0.5, 0.02), (0.5, 1)])],
        "2": [.arc(0.5, 0.32, 0.3, 180, 380), .line([(0.8, 0.4), (0.14, 1)]), .line([(0.14, 1), (0.88, 1)])],
        "3": [.arc(0.5, 0.28, 0.26, 180, 450), .arc(0.5, 0.77, 0.23, 270, 540)],
        "4": [.line([(0.7, 0.02), (0.12, 0.7), (0.92, 0.7)]), .line([(0.7, 0.02), (0.7, 1)])],
        "5": [.line([(0.78, 0.02), (0.24, 0.02), (0.24, 0.42), (0.52, 0.42)]), .arc(0.52, 0.71, 0.29, 270, 520)],
        "6": [.arc(0.5, 0.66, 0.33, 0, 360), .line([(0.78, 0), (0.27, 0.43)])],
        "7": [.line([(0.12, 0), (0.88, 0), (0.38, 1)])],
        "8": [.arc(0.5, 0.27, 0.26, 0, 360), .arc(0.5, 0.73, 0.28, 0, 360)],
        "9": [.arc(0.5, 0.34, 0.33, 0, 360), .line([(0.73, 0.55), (0.28, 0.95)])],
        "A": [.line([(0.05, 1), (0.5, 0), (0.95, 1)]), .line([(0.22, 0.66), (0.78, 0.66)])],
        "B": [.line([(0.14, 0), (0.14, 1)]), .line([(0.14, 0), (0.48, 0)]), .arc(0.48, 0.25, 0.25, -90, 90), .line([(0.48, 0.5), (0.14, 0.5)]), .line([(0.14, 0.5), (0.52, 0.5)]), .arc(0.52, 0.75, 0.25, -90, 90), .line([(0.52, 1), (0.14, 1)])],
        "C": [.arc(0.5, 0.5, 0.45, 60, 300)],
        "D": [.line([(0.14, 0), (0.14, 1)]), .line([(0.14, 0), (0.42, 0)]), .arc(0.42, 0.5, 0.5, -90, 90), .line([(0.42, 1), (0.14, 1)])],
        "E": [.line([(0.85, 0), (0.15, 0)]), .line([(0.15, 0), (0.15, 1)]), .line([(0.15, 1), (0.85, 1)]), .line([(0.15, 0.5), (0.7, 0.5)])],
        "F": [.line([(0.85, 0), (0.15, 0)]), .line([(0.15, 0), (0.15, 1)]), .line([(0.15, 0.5), (0.7, 0.5)])],
        "G": [.arc(0.5, 0.5, 0.45, 45, 315), .line([(0.82, 0.82), (0.82, 0.5), (0.55, 0.5)])],
        "H": [.line([(0.15, 0), (0.15, 1)]), .line([(0.85, 0), (0.85, 1)]), .line([(0.15, 0.5), (0.85, 0.5)])],
        "I": [.line([(0.5, 0), (0.5, 1)])],
        "J": [.line([(0.72, 0), (0.72, 0.72)]), .arc(0.45, 0.72, 0.27, 0, 180)],
        "K": [.line([(0.16, 0), (0.16, 1)]), .line([(0.88, 0), (0.16, 0.58)]), .line([(0.4, 0.4), (0.9, 1)])],
        "L": [.line([(0.2, 0), (0.2, 1)]), .line([(0.2, 1), (0.85, 1)])],
        "M": [.line([(0.08, 1), (0.08, 0), (0.5, 0.74), (0.92, 0), (0.92, 1)])],
        "N": [.line([(0.15, 1), (0.15, 0), (0.85, 1), (0.85, 0)])],
        "O": [.arc(0.5, 0.5, 0.45, 0, 360)],
        "P": [.line([(0.15, 1), (0.15, 0)]), .line([(0.15, 0), (0.5, 0)]), .arc(0.5, 0.27, 0.27, -90, 90), .line([(0.5, 0.54), (0.15, 0.54)])],
        "Q": [.arc(0.5, 0.5, 0.45, 0, 360), .line([(0.62, 0.66), (0.95, 1)])],
        "R": [.line([(0.15, 1), (0.15, 0)]), .line([(0.15, 0), (0.5, 0)]), .arc(0.5, 0.27, 0.27, -90, 90), .line([(0.5, 0.54), (0.15, 0.54)]), .line([(0.45, 0.54), (0.85, 1)])],
        "S": [.arc(0.5, 0.25, 0.25, -20, -270), .arc(0.5, 0.75, 0.25, 270, 520)],
        "T": [.line([(0.1, 0), (0.9, 0)]), .line([(0.5, 0), (0.5, 1)])],
        "U": [.line([(0.15, 0), (0.15, 0.65)]), .arc(0.5, 0.65, 0.35, 180, 0), .line([(0.85, 0.65), (0.85, 0)])],
        "V": [.line([(0.1, 0), (0.5, 1), (0.9, 0)])],
        "W": [.line([(0.05, 0), (0.28, 1), (0.5, 0.35), (0.72, 1), (0.95, 0)])],
        "X": [.line([(0.12, 0), (0.88, 1)]), .line([(0.88, 0), (0.12, 1)])],
        "Y": [.line([(0.12, 0), (0.5, 0.5)]), .line([(0.88, 0), (0.5, 0.5)]), .line([(0.5, 0.5), (0.5, 1)])],
        "Z": [.line([(0.12, 0), (0.88, 0), (0.12, 1), (0.88, 1)])],
    ]

    private static func mix(_ a: (r: Double, g: Double, b: Double),
                            _ b: (r: Double, g: Double, b: Double),
                            _ t: Double) -> (r: Double, g: Double, b: Double) {
        (r: a.r + (b.r - a.r) * t, g: a.g + (b.g - a.g) * t, b: a.b + (b.b - a.b) * t)
    }
}

/// Value noise over octaves. Deterministic from the integer lattice.
private enum Noise {
    private static func hash(_ x: Int, _ y: Int) -> Double {
        var h = UInt64(bitPattern: Int64(x &* 374_761_393 &+ y &* 668_265_263))
        h = (h ^ (h >> 13)) &* 1_274_126_177
        return Double((h ^ (h >> 16)) & 0xFFFFFF) / Double(0xFFFFFF)
    }

    /// Bilinear between lattice points, smoothstepped.
    private static func value(_ x: Double, _ y: Double) -> Double {
        let x0 = Int(x.rounded(.down)), y0 = Int(y.rounded(.down))
        let fx = x - Double(x0), fy = y - Double(y0)
        let sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy)

        let top = hash(x0, y0) + (hash(x0 + 1, y0) - hash(x0, y0)) * sx
        let bottom = hash(x0, y0 + 1) + (hash(x0 + 1, y0 + 1) - hash(x0, y0 + 1)) * sx
        return top + (bottom - top) * sy
    }

    /// Three octaves at a low base frequency; more reads as noise at icon sizes.
    static func fbm(_ x: Double, _ y: Double) -> Double {
        var total = 0.0, amplitude = 0.5, frequency = 1.0, weight = 0.0
        for _ in 0..<3 {
            total += value(x * frequency, y * frequency) * amplitude
            weight += amplitude
            amplitude *= 0.5
            frequency *= 2
        }
        return total / weight
    }
}

// MARK: - A very small rasteriser

/// RGB, no alpha: iOS rejects an app icon with one. Coverage is analytic
/// (distance to shape, softened across one pixel), not supersampled.
private struct Canvas {
    let size: Int
    private var pixels: [Double]   // r,g,b per pixel, 0...1

    init(size: Int) {
        self.size = size
        self.pixels = Array(repeating: 0, count: size * size * 3)
    }

    mutating func eachPixel(_ colour: (Double, Double) -> (r: Double, g: Double, b: Double)) {
        for y in 0..<size {
            for x in 0..<size {
                let c = colour(Double(x), Double(y))
                let i = (y * size + x) * 3
                pixels[i] = c.r; pixels[i + 1] = c.g; pixels[i + 2] = c.b
            }
        }
    }

    /// One pixel of feathering either side of the edge.
    private func coverage(_ distance: Double, _ halfWidth: Double) -> Double {
        let d = halfWidth - distance
        if d <= -0.5 { return 0 }
        if d >= 0.5 { return 1 }
        return d + 0.5
    }

    private mutating func blend(x: Int, y: Int, colour: (r: Double, g: Double, b: Double), alpha: Double) {
        guard alpha > 0, x >= 0, y >= 0, x < size, y < size else { return }
        let a = min(1, alpha)
        let i = (y * size + x) * 3
        pixels[i] += (colour.r - pixels[i]) * a
        pixels[i + 1] += (colour.g - pixels[i + 1]) * a
        pixels[i + 2] += (colour.b - pixels[i + 2]) * a
    }

    /// Stroked line segment. Letters use flat caps; grid and circles round.
    mutating func segment(from a: (Double, Double), to b: (Double, Double),
                          width: Double, colour: (r: Double, g: Double, b: Double), alpha: Double,
                          roundCaps: Bool = true) {
        let half = width / 2
        let minX = Int((min(a.0, b.0) - half - 1).rounded(.down))
        let maxX = Int((max(a.0, b.0) + half + 1).rounded(.up))
        let minY = Int((min(a.1, b.1) - half - 1).rounded(.down))
        let maxY = Int((max(a.1, b.1) + half + 1).rounded(.up))

        let dx = b.0 - a.0, dy = b.1 - a.1
        let lengthSquared = dx * dx + dy * dy

        for y in max(0, minY)...max(0, min(size - 1, maxY)) {
            for x in max(0, minX)...max(0, min(size - 1, maxX)) {
                let px = Double(x) + 0.5, py = Double(y) + 0.5
                // Distance from the pixel centre to the segment.
                let raw = lengthSquared > 0 ? ((px - a.0) * dx + (py - a.1) * dy) / lengthSquared : 0
                if !roundCaps && (raw < 0 || raw > 1) { continue }
                let t = max(0, min(1, raw))
                let cx = a.0 + dx * t, cy = a.1 + dy * t
                let distance = ((px - cx) * (px - cx) + (py - cy) * (py - cy)).squareRoot()
                blend(x: x, y: y, colour: colour, alpha: coverage(distance, half) * alpha)
            }
        }
    }

    /// Glyph strokes scaled to `capHeight`, centred. The unit box is square.
    mutating func draw(_ strokes: [IconArt.Stroke], centre: (Double, Double), capHeight: Double,
                       width: Double, colour: (r: Double, g: Double, b: Double), alpha: Double) {
        let originX = centre.0 - capHeight / 2, originY = centre.1 - capHeight / 2
        func place(_ x: Double, _ y: Double) -> (Double, Double) {
            (originX + x * capHeight, originY + y * capHeight)
        }

        for stroke in strokes {
            switch stroke {
            case .line(let points):
                guard points.count > 1 else { continue }
                for index in 0..<(points.count - 1) {
                    segment(from: place(points[index].0, points[index].1),
                            to: place(points[index + 1].0, points[index + 1].1),
                            width: width, colour: colour, alpha: alpha, roundCaps: false)
                }
                // Flat ends notch the outside of a corner; a zero-length
                // round-capped segment is a disc that fills it.
                for index in 1..<(points.count - 1) {
                    let joint = place(points[index].0, points[index].1)
                    segment(from: joint, to: joint, width: width, colour: colour, alpha: alpha)
                }

            case .arc(let cx, let cy, let r, let from, let to):
                // Chorded at roughly four degrees.
                let sweep = to - from
                let steps = max(2, Int(abs(sweep) / 4))
                var previous: (Double, Double)?
                for step in 0...steps {
                    let angle = (from + sweep * Double(step) / Double(steps)) * .pi / 180
                    let point = place(cx + r * cos(angle), cy + r * sin(angle))
                    if let previous {
                        segment(from: previous, to: point, width: width, colour: colour, alpha: alpha)
                    }
                    previous = point
                }
            }
        }
    }

    mutating func ring(centre: (Double, Double), radius: Double, width: Double,
                       colour: (r: Double, g: Double, b: Double), alpha: Double) {
        let half = width / 2
        let bound = radius + half + 1
        let minX = max(0, Int((centre.0 - bound).rounded(.down)))
        let maxX = min(size - 1, Int((centre.0 + bound).rounded(.up)))
        let minY = max(0, Int((centre.1 - bound).rounded(.down)))
        let maxY = min(size - 1, Int((centre.1 + bound).rounded(.up)))
        guard minX <= maxX, minY <= maxY else { return }

        for y in minY...maxY {
            for x in minX...maxX {
                let px = Double(x) + 0.5 - centre.0, py = Double(y) + 0.5 - centre.1
                // Distance to the circle's outline, not to its centre.
                let distance = abs((px * px + py * py).squareRoot() - radius)
                blend(x: x, y: y, colour: colour, alpha: coverage(distance, half) * alpha)
            }
        }
    }

    // MARK: PNG

    func png() -> Data {
        var raw = Data(capacity: size * (size * 3 + 1))
        for y in 0..<size {
            raw.append(0)  // filter type 0, none
            for x in 0..<size {
                let i = (y * size + x) * 3
                raw.append(UInt8(max(0, min(255, (pixels[i] * 255).rounded()))))
                raw.append(UInt8(max(0, min(255, (pixels[i + 1] * 255).rounded()))))
                raw.append(UInt8(max(0, min(255, (pixels[i + 2] * 255).rounded()))))
            }
        }

        var out = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

        var header = Data()
        header.append(bigEndian(UInt32(size)))
        header.append(bigEndian(UInt32(size)))
        header.append(contentsOf: [8, 2, 0, 0, 0])   // 8 bits, truecolour RGB
        out.append(chunk("IHDR", header))
        out.append(chunk("IDAT", zlibStored(raw)))
        out.append(chunk("IEND", Data()))
        return out
    }

    private func bigEndian(_ value: UInt32) -> Data {
        Data([UInt8(value >> 24 & 0xFF), UInt8(value >> 16 & 0xFF),
              UInt8(value >> 8 & 0xFF), UInt8(value & 0xFF)])
    }

    private func chunk(_ type: String, _ payload: Data) -> Data {
        var body = Data(type.utf8)
        body.append(payload)
        var out = bigEndian(UInt32(payload.count))
        out.append(body)
        out.append(bigEndian(crc32(body)))
        return out
    }

    /// A zlib stream of stored (uncompressed) deflate blocks. 0x78 0x01 is the
    /// usual header and satisfies zlib's own (CMF << 8 | FLG) % 31 == 0 check.
    private func zlibStored(_ raw: Data) -> Data {
        var out = Data([0x78, 0x01])
        let blockSize = 65_535
        var index = raw.startIndex
        repeat {
            let end = raw.index(index, offsetBy: min(blockSize, raw.distance(from: index, to: raw.endIndex)))
            let block = raw[index..<end]
            let isLast = end == raw.endIndex
            out.append(isLast ? 1 : 0)
            let length = UInt16(block.count)
            out.append(UInt8(length & 0xFF))
            out.append(UInt8(length >> 8))
            out.append(UInt8(~length & 0xFF))
            out.append(UInt8(~length >> 8 & 0xFF))
            out.append(contentsOf: block)
            index = end
        } while index < raw.endIndex
        out.append(bigEndian(adler32(raw)))
        return out
    }

    private func adler32(_ data: Data) -> UInt32 {
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in data {
            a = (a + UInt32(byte)) % 65_521
            b = (b + a) % 65_521
        }
        return b << 16 | a
    }

    private func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1
            }
        }
        return crc ^ 0xFFFF_FFFF
    }
}

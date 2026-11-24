// src/cli/platform/Digest.swift
//
// SHA-1 and SHA-256 in Swift, so the CLI hashes the same way everywhere with
// nothing to install: no shasum or sha256sum, and no CryptoKit, which Linux
// and Windows don't have. SHA-1 is only for certificate fingerprints, which
// is how Apple's tools name a signing identity; nothing here relies on it
// resisting collisions.

import Foundation

enum Digest {
    static func sha1(_ data: Data) -> [UInt8] { sha1([UInt8](data)) }
    static func sha256(_ data: Data) -> [UInt8] { sha256([UInt8](data)) }

    static func hex(_ digest: [UInt8], uppercase: Bool = false) -> String {
        digest.map { String(format: uppercase ? "%02X" : "%02x", $0) }.joined()
    }

    /// The message padded to whole 64-byte blocks: a 1 bit, zeros, its bit length.
    private static func padded(_ message: [UInt8]) -> [UInt8] {
        var out = message
        let bits = UInt64(message.count) * 8
        out.append(0x80)
        while out.count % 64 != 56 { out.append(0) }
        for shift in stride(from: 56, through: 0, by: -8) { out.append(UInt8(truncatingIfNeeded: bits >> UInt64(shift))) }
        return out
    }

    private static func word(_ bytes: [UInt8], _ at: Int) -> UInt32 {
        UInt32(bytes[at]) << 24 | UInt32(bytes[at + 1]) << 16 | UInt32(bytes[at + 2]) << 8 | UInt32(bytes[at + 3])
    }

    private static func bytes(_ words: [UInt32]) -> [UInt8] {
        words.flatMap { w in [UInt8(w >> 24), UInt8(w >> 16 & 0xFF), UInt8(w >> 8 & 0xFF), UInt8(w & 0xFF)] }
    }

    private static func rotl(_ x: UInt32, _ n: UInt32) -> UInt32 { x << n | x >> (32 - n) }
    private static func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 { x >> n | x << (32 - n) }

    // MARK: SHA-1 (FIPS 180-4, 6.1)

    static func sha1(_ message: [UInt8]) -> [UInt8] {
        var h: [UInt32] = [0x6745_2301, 0xEFCD_AB89, 0x98BA_DCFE, 0x1032_5476, 0xC3D2_E1F0]
        let m = padded(message)
        var w = [UInt32](repeating: 0, count: 80)
        for block in stride(from: 0, to: m.count, by: 64) {
            for t in 0..<16 { w[t] = word(m, block + t * 4) }
            for t in 16..<80 { w[t] = rotl(w[t - 3] ^ w[t - 8] ^ w[t - 14] ^ w[t - 16], 1) }
            var (a, b, c, d, e) = (h[0], h[1], h[2], h[3], h[4])
            for t in 0..<80 {
                let f: UInt32, k: UInt32
                switch t {
                case 0..<20: f = (b & c) | (~b & d); k = 0x5A82_7999
                case 20..<40: f = b ^ c ^ d; k = 0x6ED9_EBA1
                case 40..<60: f = (b & c) | (b & d) | (c & d); k = 0x8F1B_BCDC
                default: f = b ^ c ^ d; k = 0xCA62_C1D6
                }
                let temp = rotl(a, 5) &+ f &+ e &+ k &+ w[t]
                (e, d, c, b, a) = (d, c, rotl(b, 30), a, temp)
            }
            h[0] = h[0] &+ a; h[1] = h[1] &+ b; h[2] = h[2] &+ c; h[3] = h[3] &+ d; h[4] = h[4] &+ e
        }
        return bytes(h)
    }

    // MARK: SHA-256 (FIPS 180-4, 6.2)

    private static let k256: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]

    static func sha256(_ message: [UInt8]) -> [UInt8] {
        var h: [UInt32] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
        let m = padded(message)
        var w = [UInt32](repeating: 0, count: 64)
        for block in stride(from: 0, to: m.count, by: 64) {
            for t in 0..<16 { w[t] = word(m, block + t * 4) }
            for t in 16..<64 {
                let s0 = rotr(w[t - 15], 7) ^ rotr(w[t - 15], 18) ^ (w[t - 15] >> 3)
                let s1 = rotr(w[t - 2], 17) ^ rotr(w[t - 2], 19) ^ (w[t - 2] >> 10)
                w[t] = w[t - 16] &+ s0 &+ w[t - 7] &+ s1
            }
            var (a, b, c, d, e, f, g, hh) = (h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7])
            for t in 0..<64 {
                let s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
                let ch = (e & f) ^ (~e & g)
                let t1 = hh &+ s1 &+ ch &+ k256[t] &+ w[t]
                let s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let t2 = s0 &+ maj
                (hh, g, f, e, d, c, b, a) = (g, f, e, d &+ t1, c, b, a, t1 &+ t2)
            }
            h[0] = h[0] &+ a; h[1] = h[1] &+ b; h[2] = h[2] &+ c; h[3] = h[3] &+ d
            h[4] = h[4] &+ e; h[5] = h[5] &+ f; h[6] = h[6] &+ g; h[7] = h[7] &+ hh
        }
        return bytes(h)
    }
}

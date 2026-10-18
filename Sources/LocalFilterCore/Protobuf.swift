import Foundation

enum DecodeError: Error { case malformed, ambiguous, oversized, crypto, compression }

struct WireField {
    let number: UInt32
    let kind: UInt8
    let bytes: Data
    let integer: UInt64?
    let raw: Data
}

enum Wire {
    static let limit = 4 * 1024 * 1024

    static func parse(_ data: Data) throws -> [WireField] {
        guard data.count <= limit else { throw DecodeError.oversized }
        let input = [UInt8](data)
        var cursor = 0
        func varint() throws -> UInt64 {
            var value: UInt64 = 0
            for i in 0..<10 {
                guard cursor < input.count else { throw DecodeError.malformed }
                let byte = input[cursor]; cursor += 1
                if i == 9 && byte > 1 { throw DecodeError.malformed }
                value |= UInt64(byte & 127) << (i * 7)
                if byte < 128 { return value }
            }
            throw DecodeError.malformed
        }
        var fields = [WireField]()
        while cursor < input.count {
            guard fields.count < 100_000 else { throw DecodeError.oversized }
            let start = cursor
            let tag = try varint()
            let number = tag >> 3, kind = UInt8(tag & 7)
            guard number > 0 && number < (1 << 29) else { throw DecodeError.malformed }
            var bytes = Data(), integer: UInt64?
            switch kind {
            case 0: integer = try varint()
            case 1, 2, 5:
                let length = kind == 2 ? try varint() : (kind == 1 ? 8 : 4)
                guard length <= input.count - cursor else { throw DecodeError.malformed }
                bytes = Data(input[cursor..<(cursor + Int(length))]); cursor += Int(length)
            default: throw DecodeError.malformed
            }
            fields.append(WireField(number: UInt32(number), kind: kind, bytes: bytes,
                                    integer: integer, raw: Data(input[start..<cursor])))
        }
        return fields
    }

    static func one(_ fields: [WireField], _ number: UInt32, _ kind: UInt8) throws -> WireField? {
        let matches = fields.filter { $0.number == number }
        guard matches.count <= 1, matches.first.map({ $0.kind == kind }) ?? true else {
            throw DecodeError.ambiguous
        }
        return matches.first
    }

    static func child(_ data: Data?, _ number: UInt32) throws -> Data? {
        guard let data else { return nil }
        return try one(parse(data), number, 2)?.bytes
    }

    static func varint(_ n: UInt64) -> Data {
        var n = n, result = Data()
        while n > 127 { result.append(UInt8(n & 127) | 128); n >>= 7 }
        result.append(UInt8(n)); return result
    }

    static func field(_ number: UInt32, _ data: Data) -> Data {
        varint(UInt64(number) << 3 | 2) + varint(UInt64(data.count)) + data
    }

    static func integer(_ number: UInt32, _ value: UInt64) -> Data {
        varint(UInt64(number) << 3) + varint(value)
    }

    static func transform(_ data: Data, field number: UInt32,
                          _ rewrite: (Data) throws -> Data) throws -> Data {
        var output = Data()
        for field in try parse(data) {
            if field.number == number && field.kind == 2 {
                let replacement = try rewrite(field.bytes)
                output += replacement == field.bytes ? field.raw : self.field(number, replacement)
            } else { output += field.raw }
        }
        return output
    }
}

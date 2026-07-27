import Testing
import Foundation
@testable import VaporUtilities

// MARK: - Data

@Test("Data encoding empty data returns empty string")
func dataEncodingEmpty() {
    let data = Data()
    #expect(data.base64URLEncodedString() == "")
}

@Test("Data encoding single byte")
func dataEncodingSingleByte() {
    let data = Data([0x66])
    #expect(data.base64URLEncodedString() == "Zg")
}

@Test("Data encoding hello")
func dataEncodingHello() {
    #expect(Data("hello".utf8).base64URLEncodedString() == "aGVsbG8")
}

@Test("Data encoding uses URL alphabet")
func dataEncodingURLAlphabet() {
    let data = Data([0xFB])
    #expect(data.base64URLEncodedString() == "-w")
    #expect(data.base64EncodedString() == "+w==")

    let data2 = Data([0xFC])
    #expect(data2.base64URLEncodedString() == "_A")
    #expect(data2.base64EncodedString() == "/A==")
}

@Test("Data encoding RFC 4648 vectors")
func dataEncodingRFC4648() {
    let vectors: [(String, String)] = [
        ("", ""), ("f", "Zg"), ("fo", "Zm8"),
        ("foo", "Zm9v"), ("foob", "Zm9vYg"),
        ("fooba", "Zm9vYmE"), ("foobar", "Zm9vYmFy"),
    ]
    for (plain, expected) in vectors {
        #expect(Data(plain.utf8).base64URLEncodedString() == expected)
    }
}

@Test("Data decoding empty string")
func dataDecodingEmpty() {
    #expect(Data(base64URLEncoded: "") == Data())
}

@Test("Data decoding unpadded")
func dataDecodingUnpadded() {
    let data = Data(base64URLEncoded: "aGVsbG8")
    #expect(data != nil)
    #expect(String(data: data!, encoding: .utf8) == "hello")
}

@Test("Data decoding padded")
func dataDecodingPadded() {
    let data = Data(base64URLEncoded: "aGVsbG8=")
    #expect(data != nil)
    #expect(String(data: data!, encoding: .utf8) == "hello")
}

@Test("Data decoding standard base64 with plus")
func dataDecodingStandardPlus() {
    #expect(Data(base64URLEncoded: "+w==") == Data([0xFB]))
}

@Test("Data decoding standard base64 with slash")
func dataDecodingStandardSlash() {
    #expect(Data(base64URLEncoded: "/A==") == Data([0xFC]))
}

@Test("Data decoding URL-safe base64 with minus")
func dataDecodingURLMinus() {
    #expect(Data(base64URLEncoded: "-w") == Data([0xFB]))
}

@Test("Data decoding URL-safe base64 with underscore")
func dataDecodingURLUnderscore() {
    #expect(Data(base64URLEncoded: "_A") == Data([0xFC]))
}

@Test("Data decoding invalid input")
func dataDecodingInvalid() {
    #expect(Data(base64URLEncoded: "!!!invalid!!!") == nil)
    #expect(Data(base64URLEncoded: "a") == nil)
}

@Test("Data decoding RFC 4648 vectors")
func dataDecodingRFC4648() {
    let vectors: [(String, String)] = [
        ("", ""), ("Zg", "f"), ("Zm8", "fo"),
        ("Zm9v", "foo"), ("Zm9vYg", "foob"),
        ("Zm9vYmE", "fooba"), ("Zm9vYmFy", "foobar"),
    ]
    for (encoded, expected) in vectors {
        let data = Data(base64URLEncoded: encoded)
        #expect(data != nil)
        #expect(String(data: data!, encoding: .utf8) == expected)
    }
}

@Test("Data round-trip random data")
func dataRoundTripRandom() {
    for _ in 0..<50 {
        let count = Int.random(in: 0...256)
        let bytes = (0..<count).map { _ in UInt8.random(in: 0...255) }
        let original = Data(bytes)
        let encoded = original.base64URLEncodedString()
        let decoded = Data(base64URLEncoded: encoded)
        #expect(original == decoded)
    }
}

@Test("Data round-trip odd lengths")
func dataRoundTripOddLengths() {
    for length in [1, 2, 3, 4, 5, 6, 7] {
        let data = Data([UInt8](repeating: 0x41, count: length))
        #expect(Data(base64URLEncoded: data.base64URLEncodedString()) == data)
    }
}

// MARK: - RandomAccessCollection

@Test("RAC encoding bytes via RandomAccessCollection")
func racEncodingBytes() {
    let bytes: [UInt8] = [0x66, 0x6f, 0x6f]
    let expected: [UInt8] = [90, 109, 57, 118] // "Zm9v" as ASCII bytes
    #expect(bytes.base64URLEncodedBytes() == expected)
}

@Test("RAC encoding string via RandomAccessCollection")
func racEncodingString() {
    let bytes: [UInt8] = [0x66, 0x6f, 0x6f]
    #expect(bytes.base64URLEncodedString() == "Zm9v")
}

@Test("RAC encoding empty via RandomAccessCollection")
func racEncodingEmpty() {
    let bytes: [UInt8] = []
    #expect(bytes.base64URLEncodedBytes() == [])
    #expect(bytes.base64URLEncodedString() == "")
}

// MARK: - Array

@Test("Array decoding base64 URL string")
func arrayDecodingString() {
    let bytes = [UInt8](decodingBase64URL: "aGVsbG8")
    #expect(bytes != nil)
    #expect(bytes! == [UInt8]("hello".utf8))
}

@Test("Array decoding base64 URL bytes")
func arrayDecodingBytes() {
    let encoded: [UInt8] = [97, 71, 86, 115, 98, 71, 56] // "aGVsbG8" as ASCII
    let bytes = [UInt8](decodingBase64URL: encoded)
    #expect(bytes != nil)
    #expect(bytes! == [UInt8]("hello".utf8))
}

@Test("Array decoding invalid input")
func arrayDecodingInvalid() {
    #expect([UInt8](decodingBase64URL: "!!!invalid!!!") == nil)
}

// MARK: - String

@Test("String encoding via base64URLEncodedString")
func stringEncoding() {
    #expect("hello".base64URLEncodedString() == "aGVsbG8")
}

@Test("String encoding via base64URLEncodedBytes")
func stringEncodingBytes() {
    let expected: [UInt8] = [97, 71, 86, 115, 98, 71, 56] // "aGVsbG8" as ASCII
    #expect("hello".base64URLEncodedBytes() == expected)
}

@Test("String encoding empty")
func stringEncodingEmpty() {
    #expect("".base64URLEncodedString() == "")
    #expect("".base64URLEncodedBytes() == [])
}

@Test("String decoding via base64URLDecodedData")
func stringDecoding() {
    let data = "aGVsbG8".base64URLDecodedData
    #expect(data != nil)
    #expect(String(data: data!, encoding: .utf8) == "hello")
}

@Test("String decoding invalid")
func stringDecodingInvalid() {
    #expect("!!!invalid!!!".base64URLDecodedData == nil)
}

// MARK: - Substring

@Test("Substring encoding")
func substringEncoding() {
    let full = "hello world"
    let sub = full.prefix(5) // "hello"
    #expect(sub.base64URLEncodedString() == "aGVsbG8")
}

@Test("Substring encoding bytes")
func substringEncodingBytes() {
    let sub = "hello".prefix(0)
    #expect(sub.base64URLEncodedBytes() == [])
    #expect(sub.base64URLEncodedString() == "")
}

// MARK: - Cross-type consistency

@Test("all encoding methods produce same output for same input")
func crossTypeConsistency() {
    let input: [UInt8] = [0x66, 0x6f, 0x6f]
    let data = Data(input)
    let string = "foo"
    let substring = string[string.startIndex...]

    let expected = "Zm9v"
    #expect(data.base64URLEncodedString() == expected)
    #expect(input.base64URLEncodedString() == expected)
    #expect(string.base64URLEncodedString() == expected)
    #expect(substring.base64URLEncodedString() == expected)
}

@Test("all decoding methods round-trip with encoding")
func crossTypeRoundTrip() {
    let original = "The quick brown fox jumps over the lazy dog."

    let encoded = original.base64URLEncodedString()
    let decoded = Data(base64URLEncoded: encoded)
    #expect(decoded != nil)
    #expect(String(data: decoded!, encoding: .utf8) == original)

    let arrayDecoded = [UInt8](decodingBase64URL: encoded)
    #expect(arrayDecoded != nil)
    #expect(arrayDecoded! == [UInt8](original.utf8))
}
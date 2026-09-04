#!/usr/bin/env swift

import Foundation

private struct IconEntry {
    let type: String
    let fileName: String
}

private let entries = [
    IconEntry(type: "icp4", fileName: "icon_16x16.png"),
    IconEntry(type: "icp5", fileName: "icon_32x32.png"),
    IconEntry(type: "icp6", fileName: "icon_32x32@2x.png"),
    IconEntry(type: "ic07", fileName: "icon_128x128.png"),
    IconEntry(type: "ic08", fileName: "icon_256x256.png"),
    IconEntry(type: "ic09", fileName: "icon_512x512.png"),
    IconEntry(type: "ic10", fileName: "icon_512x512@2x.png"),
]

private func fourCharacterCode(_ value: String) throws -> Data {
    let data = Data(value.utf8)
    guard data.count == 4 else {
        throw CocoaError(.fileReadCorruptFile)
    }
    return data
}

private func bigEndianData(_ value: UInt32) -> Data {
    var value = value.bigEndian
    return withUnsafeBytes(of: &value) { Data($0) }
}

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: make-icns.swift ICONSET_DIRECTORY OUTPUT.icns\n".utf8))
    exit(EXIT_FAILURE)
}

let iconsetURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
var chunks = Data()

do {
    for entry in entries {
        let data = try Data(contentsOf: iconsetURL.appendingPathComponent(entry.fileName))
        guard data.starts(with: pngSignature) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        chunks.append(try fourCharacterCode(entry.type))
        chunks.append(bigEndianData(UInt32(data.count + 8)))
        chunks.append(data)
    }
    var output = try fourCharacterCode("icns")
    output.append(bigEndianData(UInt32(chunks.count + 8)))
    output.append(chunks)
    try output.write(to: outputURL, options: .atomic)
} catch {
    FileHandle.standardError.write(Data("Unable to create ICNS: \(error)\n".utf8))
    exit(EXIT_FAILURE)
}

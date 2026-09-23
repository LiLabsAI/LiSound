import Foundation
import CoreAudio

enum AudioChainError: LocalizedError {
    case osStatus(OSStatus, String)
    case invalidState(String)

    var errorDescription: String? {
        switch self {
        case let .osStatus(status, what): "Core Audio error \(status) in \(what)"
        case let .invalidState(what): what
        }
    }
}

/// `AudioBufferList.mBuffers` is a variable-length C array of 8-byte-aligned
/// `AudioBuffer` elements: it starts at offset 8 (after pointer-alignment padding),
/// not at 4. Access the list only through these raw-pointer helpers — Swift's
/// `pointee` access on this struct returns garbage on current SDKs.
enum AudioBufferListAccess {
    static var buffersOffset: Int {
        MemoryLayout<AudioBufferList>.stride - MemoryLayout<AudioBuffer>.stride
    }

    static func bufferCount(_ list: UnsafePointer<AudioBufferList>) -> Int {
        Int(UnsafeRawPointer(list).load(as: UInt32.self))
    }

    static func buffers(_ list: UnsafePointer<AudioBufferList>) -> UnsafePointer<AudioBuffer> {
        UnsafeRawPointer(list)
            .advanced(by: buffersOffset)
            .assumingMemoryBound(to: AudioBuffer.self)
    }

    static func mutableBuffers(_ list: UnsafeMutablePointer<AudioBufferList>) -> UnsafeMutablePointer<AudioBuffer> {
        UnsafeMutableRawPointer(list)
            .advanced(by: buffersOffset)
            .assumingMemoryBound(to: AudioBuffer.self)
    }
}

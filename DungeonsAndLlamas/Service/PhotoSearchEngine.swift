//
//  PhotoSearchEngine.swift
//  DungeonsAndLlamas
//

import Foundation
import Metal

enum PhotoSearchError: LocalizedError {
    case metalUnavailable
    case metalExecutionFailed(String)

    var errorDescription: String? {
        switch self {
        case .metalUnavailable:
            return "Semantic photo search is unavailable on this device."
        case .metalExecutionFailed(let message):
            return "Semantic photo search failed: \(message)"
        }
    }
}

protocol PhotoDistanceEngine {
    func distances(query: [Float], flattenedCandidates: [Float], candidateCount: Int) throws -> [Float]
    func distances(query: [Float], candidateBuffer: MTLBuffer, dimension: Int, candidateCount: Int) throws -> [Float]
}

final class PhotoEmbeddingBufferCache {
    private let device: MTLDevice?
    private(set) var buffer: MTLBuffer?
    private(set) var dimension = 0
    private var offsets = [String: Int]()

    init(device: MTLDevice? = MTLCreateSystemDefaultDevice()) {
        self.device = device
    }

    var isReady: Bool {
        buffer != nil && !offsets.isEmpty
    }

    func contains(_ id: String) -> Bool {
        offsets[id] != nil
    }

    func replace(with records: [(id: String, embedding: [Float])]) {
        invalidate()
        guard let device, let first = records.first, !first.embedding.isEmpty else { return }
        let embeddingDimension = first.embedding.count
        guard records.allSatisfy({ $0.embedding.count == embeddingDimension }) else { return }

        let flattened = records.flatMap(\.embedding)
        let newBuffer: MTLBuffer? = flattened.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return nil }
            return device.makeBuffer(bytes: baseAddress, length: bytes.count, options: .storageModeShared)
        }
        guard let newBuffer else { return }

        self.buffer = newBuffer
        dimension = embeddingDimension
        offsets = Dictionary(uniqueKeysWithValues: records.enumerated().map { ($0.element.id, $0.offset) })
    }

    func candidateBuffer(for ids: [String]) -> MTLBuffer? {
        guard let buffer, let device, !ids.isEmpty else { return nil }
        guard ids.allSatisfy({ offsets[$0] != nil }) else { return nil }

        let byteCount = ids.count * dimension * MemoryLayout<Float>.stride
        guard let candidateBuffer = device.makeBuffer(length: byteCount, options: .storageModeShared) else { return nil }
        let destination = candidateBuffer.contents()
        let source = buffer.contents()
        let embeddingByteCount = dimension * MemoryLayout<Float>.stride
        for (index, id) in ids.enumerated() {
            guard let offset = offsets[id] else { return nil }
            destination.advanced(by: index * embeddingByteCount)
                .copyMemory(from: source.advanced(by: offset * embeddingByteCount), byteCount: embeddingByteCount)
        }
        return candidateBuffer
    }

    func invalidate() {
        buffer = nil
        dimension = 0
        offsets.removeAll(keepingCapacity: true)
    }
}

final class MetalPhotoDistanceEngine: PhotoDistanceEngine {
    private let commandQueue: MTLCommandQueue?
    private let pipeline: MTLComputePipelineState?

    init() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let library = device.makeDefaultLibrary(),
              let function = library.makeFunction(name: "photoCosineDistance"),
              let pipeline = try? device.makeComputePipelineState(function: function) else {
            commandQueue = nil
            self.pipeline = nil
            return
        }
        commandQueue = device.makeCommandQueue()
        self.pipeline = pipeline
    }

    func distances(query: [Float], flattenedCandidates: [Float], candidateCount: Int) throws -> [Float] {
        guard let candidateBuffer = deviceBuffer(values: flattenedCandidates) else {
            throw PhotoSearchError.metalExecutionFailed("Unable to allocate Metal search buffers.")
        }
        return try distances(query: query, candidateBuffer: candidateBuffer, dimension: query.count, candidateCount: candidateCount)
    }

    func distances(query: [Float], candidateBuffer: MTLBuffer, dimension: Int, candidateCount: Int) throws -> [Float] {
        guard let commandQueue, let pipeline else {
            throw PhotoSearchError.metalUnavailable
        }
        guard !query.isEmpty, candidateCount > 0 else { return [] }

        guard dimension == query.count else {
            throw PhotoSearchError.metalExecutionFailed("Search embeddings have incompatible dimensions.")
        }

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw PhotoSearchError.metalExecutionFailed("Unable to create a Metal command buffer.")
        }

        guard let queryBuffer = deviceBuffer(commandQueue: commandQueue, values: query),
              let outputBuffer = commandQueue.device.makeBuffer(
                length: candidateCount * MemoryLayout<Float>.stride,
                options: .storageModeShared
              ) else {
            throw PhotoSearchError.metalExecutionFailed("Unable to allocate Metal search buffers.")
        }

        var dimensionValue = UInt32(dimension)
        var candidateCountValue = UInt32(candidateCount)
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(queryBuffer, offset: 0, index: 0)
        encoder.setBuffer(candidateBuffer, offset: 0, index: 1)
        encoder.setBuffer(outputBuffer, offset: 0, index: 2)
        encoder.setBytes(&dimensionValue, length: MemoryLayout<UInt32>.size, index: 3)
        encoder.setBytes(&candidateCountValue, length: MemoryLayout<UInt32>.size, index: 4)

        let width = min(pipeline.threadExecutionWidth, pipeline.maxTotalThreadsPerThreadgroup)
        encoder.dispatchThreads(
            MTLSize(width: candidateCount, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: max(1, width), height: 1, depth: 1)
        )
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        if let error = commandBuffer.error {
            throw PhotoSearchError.metalExecutionFailed(error.localizedDescription)
        }

        return outputBuffer.contents()
            .bindMemory(to: Float.self, capacity: candidateCount)
            .toArray(count: candidateCount)
    }

    private func deviceBuffer(commandQueue: MTLCommandQueue, values: [Float]) -> MTLBuffer? {
        values.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return nil }
            return commandQueue.device.makeBuffer(
                bytes: baseAddress,
                length: bytes.count,
                options: .storageModeShared
            )
        }
    }

    private func deviceBuffer(values: [Float]) -> MTLBuffer? {
        guard let commandQueue else { return nil }
        return deviceBuffer(commandQueue: commandQueue, values: values)
    }
}

private extension UnsafeMutablePointer where Pointee == Float {
    func toArray(count: Int) -> [Float] {
        Array(UnsafeBufferPointer(start: self, count: count))
    }
}

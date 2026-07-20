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
    func distances(query: [Float], candidates: [[Float]]) throws -> [Float]
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

    func distances(query: [Float], candidates: [[Float]]) throws -> [Float] {
        guard let commandQueue, let pipeline else {
            throw PhotoSearchError.metalUnavailable
        }
        guard !query.isEmpty, !candidates.isEmpty else { return [] }

        let dimension = query.count
        let flattened = candidates.flatMap { $0 }
        guard flattened.count == dimension * candidates.count,
              candidates.allSatisfy({ $0.count == dimension }) else {
            throw PhotoSearchError.metalExecutionFailed("Search embeddings have incompatible dimensions.")
        }

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw PhotoSearchError.metalExecutionFailed("Unable to create a Metal command buffer.")
        }

        guard let queryBuffer = deviceBuffer(commandQueue: commandQueue, values: query),
              let candidateBuffer = deviceBuffer(commandQueue: commandQueue, values: flattened),
              let outputBuffer = commandQueue.device.makeBuffer(
                length: candidates.count * MemoryLayout<Float>.stride,
                options: .storageModeShared
              ) else {
            throw PhotoSearchError.metalExecutionFailed("Unable to allocate Metal search buffers.")
        }

        var dimensionValue = UInt32(dimension)
        var candidateCount = UInt32(candidates.count)
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(queryBuffer, offset: 0, index: 0)
        encoder.setBuffer(candidateBuffer, offset: 0, index: 1)
        encoder.setBuffer(outputBuffer, offset: 0, index: 2)
        encoder.setBytes(&dimensionValue, length: MemoryLayout<UInt32>.size, index: 3)
        encoder.setBytes(&candidateCount, length: MemoryLayout<UInt32>.size, index: 4)

        let width = min(pipeline.threadExecutionWidth, pipeline.maxTotalThreadsPerThreadgroup)
        encoder.dispatchThreads(
            MTLSize(width: candidates.count, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: max(1, width), height: 1, depth: 1)
        )
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        if let error = commandBuffer.error {
            throw PhotoSearchError.metalExecutionFailed(error.localizedDescription)
        }

        return outputBuffer.contents()
            .bindMemory(to: Float.self, capacity: candidates.count)
            .toArray(count: candidates.count)
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
}

private extension UnsafeMutablePointer where Pointee == Float {
    func toArray(count: Int) -> [Float] {
        Array(UnsafeBufferPointer(start: self, count: count))
    }
}

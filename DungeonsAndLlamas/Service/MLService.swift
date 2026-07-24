//
//  MLService.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2025-05-05.
//

import CoreML
import CoreImage
import CoreAI
import UIKit

private let mlLogger = LoggingService.shared.ml

// adapted from https://github.com/huggingface/coreml-examples/tree/main/depth-anything-example
actor MLService {
    
    struct PredictionResult: Hashable, Identifiable {
        var id: String {
            label
        }
        let label: String
        let probability: Double
    }
    
    enum EmbeddingError: Error {
        case modelNotLoaded
        case functionNotFound(String)
        case outputNotFound(String)
        case outputTypeMismatch(String)
        case invalidImage
        case invalidEmbeddingDimensions(Int, Int)
    }
    
    let context = CIContext()
    let tokenizer = CLIPTokenizer()
    static let targetDepthSize = CGSize(width: 518, height: 392)
    static let targetClassifierSize = CGSize(width: 256, height: 256)
    static let targetClipImageSize = CGSize(width: 256, height: 256)
    static let clipImageMean: [Float] = [0, 0, 0]
    static let clipImageStandardDeviation: [Float] = [1, 1, 1]

    /// The depth model.
    var depthModel: DepthAnythingV2SmallF16?
//    var classifierModel: FastViTT8F16?
    var classifierModel: FastViTMA36F16?
    var clipModel: AIModel?
    var clipTextFunction: InferenceFunction?
    var clipImageFunction: InferenceFunction?
    
    /// A pixel buffer used as input to the model.
    let inputDepthPixelBuffer: CVPixelBuffer
    let inputClassifierPixelBuffer: CVPixelBuffer

    
    init() {
        // Create a reusable buffer to avoid allocating memory for every model invocation
        var buffer: CVPixelBuffer!
        var status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(MLService.targetDepthSize.width),
            Int(MLService.targetDepthSize.height),
            kCVPixelFormatType_32ARGB,
            nil,
            &buffer
        )
        guard status == kCVReturnSuccess else {
            fatalError("Failed to create pixel buffer")
        }
        inputDepthPixelBuffer = buffer
        
        status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(MLService.targetClassifierSize.width),
            Int(MLService.targetClassifierSize.height),
            kCVPixelFormatType_32ARGB,
            nil,
            &buffer
        )
        guard status == kCVReturnSuccess else {
            fatalError("Failed to create pixel buffer")
        }
        inputClassifierPixelBuffer = buffer
        
    }

    /// Explicit warm-up hook. Normal callers load only the model they need.
    func loadModel() async throws {
        try loadDepthModelIfNeeded()
        try loadClassifierModelIfNeeded()
        try await loadClipModelIfNeeded()
    }

    /// Compatibility warm-up for existing embedding migrations. It intentionally
    /// initializes only CLIP, not the depth or classification models.
    func waitUntilLoaded() async throws {
        try await loadClipModelIfNeeded()
    }

    // TODO: this takes about 13s on an iPad Air M1 - convert depth model to .aimodel for faster loading
    private func loadDepthModelIfNeeded() throws {
        guard depthModel == nil else { return }
        depthModel = try DepthAnythingV2SmallF16()
    }

    private func loadClassifierModelIfNeeded() throws {
        guard classifierModel == nil else { return }
        classifierModel = try FastViTMA36F16()
    }

    private func loadClipModelIfNeeded() async throws {
        guard clipModel == nil else { return }
        let compiledURL = Bundle.main.url(forResource: "mobileclip2_s2.h13g", withExtension: "aimodelc")
        let sourceURL = Bundle.main.url(forResource: "mobileclip2_s2", withExtension: "aimodel")
        guard let url = compiledURL ?? sourceURL else {
            throw EmbeddingError.modelNotLoaded
        }
        let clipModel = try await AIModel(contentsOf: url)
        self.clipModel = clipModel
        
        guard let textFunction = try clipModel.loadFunction(named: "encode_text") else {
            throw EmbeddingError.functionNotFound("encode_text")
        }
        guard let imageFunction = try clipModel.loadFunction(named: "encode_image") else {
            throw EmbeddingError.functionNotFound("encode_image")
        }
        clipTextFunction = textFunction
        clipImageFunction = imageFunction
    }
    
    func performDepthInference(_ image: UIImage) async throws -> UIImage? {
        
        try loadDepthModelIfNeeded()
        guard let depthModel else { return nil }
        
        let clock = ContinuousClock()
        let start = clock.now
        
        guard let pixelBuffer = image.convertToBuffer() else {
            return nil
        }
        let originalSize = CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
        
        
        var cIImage = CIImage(cvPixelBuffer: pixelBuffer)
        cIImage = cIImage.resized(to: MLService.targetDepthSize)
        context.render(cIImage, to: inputDepthPixelBuffer)
        let result = try depthModel.prediction(image: inputDepthPixelBuffer)
        let outputImage = CIImage(cvPixelBuffer: result.depth).resized(to: originalSize)
       
        let temporaryContext = CIContext()
        guard let videoImage = temporaryContext.createCGImage(outputImage, from: CGRectMake(0, 0, CGFloat(CVPixelBufferGetWidth(pixelBuffer)), CGFloat(CVPixelBufferGetHeight(pixelBuffer)))) else {
            return nil
        }

        let duration = clock.now - start
        mlLogger.debug("Depth inference took \(duration.formatted(.units(allowed: [.seconds, .milliseconds])), privacy: .public)")
        
        return UIImage(cgImage: videoImage)
    }
    
    func performClassifierInference(_ image: UIImage) async throws -> [PredictionResult]? {
        
        try loadClassifierModelIfNeeded()
        guard let classifierModel else { return nil }
        
        let clock = ContinuousClock()
        let start = clock.now
        
        guard let pixelBuffer = image.convertToBuffer() else {
            return nil
        }

        let inputImage = CIImage(cvPixelBuffer: pixelBuffer).resized(to: MLService.targetClassifierSize)
        context.render(inputImage, to: inputClassifierPixelBuffer)
        let result = try classifierModel.prediction(image: inputClassifierPixelBuffer)
        let classifications = result.classLabel_probs.sorted { $0.value > $1.value }.map { (label, prob) in
            PredictionResult(label: label, probability: prob)
        }
        
        let duration = clock.now - start
        mlLogger.debug("Classification inference took \(duration.formatted(.units(allowed: [.seconds, .milliseconds])), privacy: .public)")
        
        return classifications
    }
    
    func textEmbedding(for text: String) async throws -> [Float] {
        try await loadClipModelIfNeeded()
        guard let clipTextFunction else {
            throw EmbeddingError.modelNotLoaded
        }
        
        let clock = ContinuousClock()
        let start = clock.now
        defer {
            let duration = clock.now - start
            mlLogger.debug("Text embedding took \(duration.formatted(.units(allowed: [.seconds, .milliseconds])), privacy: .public)")
        }
        
        let tokens = tokenizer.encode_full(text: text).map(Int32.init)
        let input = NDArray(scalars: tokens, shape: [1, tokenizer.contextLength])
        return try await embedding(function: clipTextFunction, inputName: "text", outputName: "text_features", input: input)
    }
    
    func imageEmbedding(for image: UIImage) async throws -> [Float] {
        try await loadClipModelIfNeeded()
        guard let clipImageFunction else {
            throw EmbeddingError.modelNotLoaded
        }
        
        let clock = ContinuousClock()
        let start = clock.now
        defer {
            let duration = clock.now - start
            mlLogger.debug("Image embedding took \(duration.formatted(.units(allowed: [.seconds, .milliseconds])), privacy: .public)")
        }
        
        let input = try clipImageArray(from: image)
        return try await embedding(function: clipImageFunction, inputName: "image", outputName: "image_features", input: input)
    }

    func combinedImageEmbedding(for images: [UIImage]) async throws -> [Float] {
        guard !images.isEmpty else {
            throw EmbeddingError.invalidImage
        }
        var embeddings = [[Float]]()
        embeddings.reserveCapacity(images.count)
        for image in images {
            embeddings.append(try await imageEmbedding(for: image))
        }
        guard let first = embeddings.first, embeddings.allSatisfy({ $0.count == first.count }) else {
            throw EmbeddingError.invalidEmbeddingDimensions(0, 0)
        }
        let normalized = embeddings.map { embedding in
            let magnitude = sqrt(embedding.reduce(Float.zero) { $0 + $1 * $1 })
            return magnitude == 0 ? embedding : embedding.map { $0 / magnitude }
        }
        let count = first.count
        let average = (0..<count).map { index in
            normalized.reduce(Float.zero) { $0 + $1[index] } / Float(normalized.count)
        }
        let magnitude = sqrt(average.reduce(Float.zero) { $0 + $1 * $1 })
        return magnitude == 0 ? average : average.map { $0 / magnitude }
    }
    
    func similarity(text: String, image: UIImage) async throws -> Float {
        let textEmbedding = try await textEmbedding(for: text)
        let imageEmbedding = try await imageEmbedding(for: image)
        return try Self.cosineSimilarity(textEmbedding, imageEmbedding)
    }
    
    static func cosineSimilarity(_ embedding1: [Float], _ embedding2: [Float]) throws -> Float {
        guard embedding1.count == embedding2.count else {
            throw EmbeddingError.invalidEmbeddingDimensions(embedding1.count, embedding2.count)
        }
        
        let dotProduct = zip(embedding1, embedding2).reduce(Float.zero) { $0 + $1.0 * $1.1 }
        let magnitude1 = sqrt(embedding1.reduce(Float.zero) { $0 + $1 * $1 })
        let magnitude2 = sqrt(embedding2.reduce(Float.zero) { $0 + $1 * $1 })
        return dotProduct / (magnitude1 * magnitude2)
    }
    
    private func embedding(function: InferenceFunction, inputName: String, outputName: String, input: NDArray) async throws -> [Float] {
        var outputs = try await function.run(inputs: [inputName: input])
        guard let outputValue = outputs.remove(outputName) else {
            throw EmbeddingError.outputNotFound(outputName)
        }
        guard let outputArray = outputValue.ndArray else {
            throw EmbeddingError.outputTypeMismatch(outputName)
        }
        guard outputArray.scalarType == .float32 else {
            throw EmbeddingError.outputTypeMismatch(outputName)
        }
        
        return floats(from: outputArray)
    }
    
    private func clipImageArray(from image: UIImage) throws -> NDArray {
        guard let pixelBuffer = image.convertToBuffer() else {
            throw EmbeddingError.invalidImage
        }
        
        let resizedImage = CIImage(cvPixelBuffer: pixelBuffer).resized(to: Self.targetClipImageSize)
        guard let rgbaPixelBuffer = context.render(resizedImage, pixelFormat: kCVPixelFormatType_32BGRA) else {
            throw EmbeddingError.invalidImage
        }
        
        CVPixelBufferLockBaseAddress(rgbaPixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(rgbaPixelBuffer, .readOnly) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(rgbaPixelBuffer) else {
            throw EmbeddingError.invalidImage
        }
        
        let width = Int(Self.targetClipImageSize.width)
        let height = Int(Self.targetClipImageSize.height)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(rgbaPixelBuffer)
        let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
        var values = Array(repeating: Float.zero, count: 3 * width * height)
        
        for y in 0..<height {
            for x in 0..<width {
                let sourceOffset = y * bytesPerRow + x * 4
                let pixelIndex = y * width + x
                let red = Float(bytes[sourceOffset + 2]) / 255.0
                let green = Float(bytes[sourceOffset + 1]) / 255.0
                let blue = Float(bytes[sourceOffset]) / 255.0
                values[pixelIndex] = (red - Self.clipImageMean[0]) / Self.clipImageStandardDeviation[0]
                values[width * height + pixelIndex] = (green - Self.clipImageMean[1]) / Self.clipImageStandardDeviation[1]
                values[2 * width * height + pixelIndex] = (blue - Self.clipImageMean[2]) / Self.clipImageStandardDeviation[2]
            }
        }
        
        return NDArray(scalars: values, shape: [1, 3, height, width])
    }
    
    private func floats(from array: NDArray) -> [Float] {
        let view = array.view(as: Float.self)
        let count = array.shape.reduce(1, *)
        var values = [Float]()
        values.reserveCapacity(count)
        
        if let elements = view.contiguousElements {
            for index in 0..<count {
                values.append(elements[index])
            }
            return values
        }
        
        view.withUnsafePointer { pointer, shape, strides in
            for linearIndex in 0..<count {
                var remainder = linearIndex
                var offset = 0
                for dimension in stride(from: shape.count - 1, through: 0, by: -1) {
                    let index = remainder % shape[dimension]
                    remainder /= shape[dimension]
                    offset += index * strides[dimension]
                }
                values.append(pointer[offset])
            }
        }
        
        return values
    }
    
    // https://stackoverflow.com/a/44475334
    func buffer(from image: UIImage) -> CVPixelBuffer? {
        let attrs = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue, kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue] as CFDictionary
        var pixelBuffer : CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, Int(image.size.width), Int(image.size.height), kCVPixelFormatType_32ARGB, attrs, &pixelBuffer)
        guard (status == kCVReturnSuccess) else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))
        let pixelData = CVPixelBufferGetBaseAddress(pixelBuffer!)
        
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: pixelData, width: Int(image.size.width), height: Int(image.size.height), bitsPerComponent: image.cgImage?.bitsPerComponent ?? 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer!), space: rgbColorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)
        
        context?.translateBy(x: 0, y: image.size.height)
        context?.scaleBy(x: 1.0, y: -1.0)
        
        UIGraphicsPushContext(context!)
        image.draw(in: CGRect(x: 0, y: 0, width: image.size.width, height: image.size.height))
        UIGraphicsPopContext()
        CVPixelBufferUnlockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))
        
        return pixelBuffer
    }
    
}



extension UIImage {
        
    func convertToBuffer() -> CVPixelBuffer? {
        
        let attributes = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue
        ] as CFDictionary
        
        var pixelBuffer: CVPixelBuffer?
        
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, Int(self.size.width),
            Int(self.size.height),
            kCVPixelFormatType_32ARGB,
            attributes,
            &pixelBuffer)
        
        guard (status == kCVReturnSuccess) else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))
        
        let pixelData = CVPixelBufferGetBaseAddress(pixelBuffer!)
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        
        let context = CGContext(
            data: pixelData,
            width: Int(self.size.width),
            height: Int(self.size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer!),
            space: rgbColorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)
        
        context?.translateBy(x: 0, y: self.size.height)
        context?.scaleBy(x: 1.0, y: -1.0)
        
        UIGraphicsPushContext(context!)
        self.draw(in: CGRect(x: 0, y: 0, width: self.size.width, height: self.size.height))
        UIGraphicsPopContext()
        
        CVPixelBufferUnlockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: 0))
        
        return pixelBuffer
    }
    
    // https://programmer.group/ios-picture-rotation-method.html
    func rotateImage(withAngle angle: Double) -> UIImage? {
        if angle.truncatingRemainder(dividingBy: 360) == 0 { return self }
        
        let imageRect = CGRect(origin: .zero, size: self.size)
        let radian = CGFloat(angle / 180 * Double.pi)
        let rotatedTransform = CGAffineTransform.identity.rotated(by: radian)
        var rotatedRect = imageRect.applying(rotatedTransform)
        rotatedRect.origin.x = 0
        rotatedRect.origin.y = 0
        
        UIGraphicsBeginImageContext(rotatedRect.size)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        context.translateBy(x: rotatedRect.width / 2, y: rotatedRect.height / 2)
        context.rotate(by: radian)
        context.translateBy(x: -self.size.width / 2, y: -self.size.height / 2)
        self.draw(at: .zero)
        let rotatedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return rotatedImage
    }
}


extension CIImage {
    /// Returns a resized image.
    func resized(to size: CGSize) -> CIImage {
        let outputScaleX = size.width / extent.width
        let outputScaleY = size.height / extent.height
        var outputImage = self.transformed(by: CGAffineTransform(scaleX: outputScaleX, y: outputScaleY))
        outputImage = outputImage.transformed(
            by: CGAffineTransform(translationX: -outputImage.extent.origin.x, y: -outputImage.extent.origin.y)
        )
        return outputImage
    }
}

extension CIContext {
    /// Renders an image to a new pixel buffer.
    func render(_ image: CIImage, pixelFormat: OSType) -> CVPixelBuffer? {
        var output: CVPixelBuffer!
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(image.extent.width),
            Int(image.extent.height),
            pixelFormat,
            nil,
            &output
        )
        guard status == kCVReturnSuccess else {
            return nil
        }
        render(image, to: output)
        return output
    }
    
    /// Writes the image as a PNG.
    //    func writePNG(_ image: CIImage, to url: URL) {
    //        let outputCGImage = createCGImage(image, from: image.extent)!
    //        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    //            fatalError("Failed to create an image destination.")
    //        }
    //        CGImageDestinationAddImage(destination, outputCGImage, nil)
    //        CGImageDestinationFinalize(destination)
    //    }
}

//
//  MLService.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2025-05-05.
//

import CoreML
import CoreImage
import UIKit

// adapted from https://github.com/huggingface/coreml-examples/tree/main/depth-anything-example
actor MLService {
    let context = CIContext()
    static let targetSize = CGSize(width: 518, height: 392)
    
    /// The depth model.
    var model: DepthAnythingV2SmallF16?
    
    /// A pixel buffer used as input to the model.
    let inputPixelBuffer: CVPixelBuffer
    
    
    init() {
        // Create a reusable buffer to avoid allocating memory for every model invocation
        var buffer: CVPixelBuffer!
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(MLService.targetSize.width),
            Int(MLService.targetSize.height),
            kCVPixelFormatType_32ARGB,
            nil,
            &buffer
        )
        guard status == kCVReturnSuccess else {
            fatalError("Failed to create pixel buffer")
        }
        inputPixelBuffer = buffer
        
        Task.detached(priority: .userInitiated) {
            try await self.loadModel()
        }
    }
    
    // TODO: this takes about 13s on an iPad Air M1
    // skip this somehow for swiftUI previews
    func loadModel() async throws {
        print("Loading model...")
        
        let clock = ContinuousClock()
        let start = clock.now
        
        model = try DepthAnythingV2SmallF16()
        
        let duration = clock.now - start
        print("Model loaded (took \(duration.formatted(.units(allowed: [.seconds, .milliseconds]))))")
    }
    
    func performInference(_ image: UIImage) async throws -> UIImage? {
        
        guard let model else {
            return nil
        }
        
        guard let pixelBuffer = image.convertToBuffer() else {
            return nil
        }
        let originalSize = CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
        
        
        var cIImage = CIImage(cvPixelBuffer: pixelBuffer)
        cIImage = cIImage.resized(to: MLService.targetSize)
        context.render(cIImage, to: inputPixelBuffer)
        let result = try model.prediction(image: inputPixelBuffer)
        let outputImage = CIImage(cvPixelBuffer: result.depth).resized(to: originalSize)
       
        let temporaryContext = CIContext()
        guard let videoImage = temporaryContext.createCGImage(outputImage, from: CGRectMake(0, 0, CGFloat(CVPixelBufferGetWidth(pixelBuffer)), CGFloat(CVPixelBufferGetHeight(pixelBuffer)))) else {
            return nil
        }

        return UIImage(cgImage: videoImage)

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

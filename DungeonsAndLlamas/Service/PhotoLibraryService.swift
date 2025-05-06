//
//  PhotoLibraryService.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2025-04-14.
//

import Photos
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

@MainActor
class PhotoLibraryService {
    var status: PHAuthorizationStatus?
    
    var ml = MLService() // TODO: inject this

    var canAccess: Bool {
        return status == .authorized || status == .limited
    }
    
    let defaultImage = UIImage(named: "lighthouse")!
    
    func checkAuthStatus() {
        status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status! {
            
        case .notDetermined:
            print("not determined")
            Task.init {
                self.status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            }
        case .restricted:
            print("restricted")
            return
        case .denied:
            print("denied")
            return
        case .authorized:
            print("authorized")
            return
        case .limited:
            print("limited")
            return
        @unknown default:
            fatalError()
        }
    }
    
    struct PhotoLibraryImage: Identifiable, Equatable, Hashable {
        var id: String
        var image: UIImage
        var depth: UIImage? = nil
        var estimatedDepth: UIImage? = nil
        var canny: UIImage? = nil
    }
    
    func getImages(limit: Int = 10, size: CGSize = CGSize(width: 512, height: 512)) -> AsyncStream<PhotoLibraryImage> {
        
        guard canAccess else {
            print("no access")
            fatalError()
        }
        
        let manager = PHImageManager.default()
        let fetch = PHFetchOptions()
        fetch.fetchLimit = limit
        fetch.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: .image, options: fetch)

        let request = PHImageRequestOptions()
        request.isSynchronous = false
        request.isNetworkAccessAllowed = true
        request.resizeMode = .exact
        request.deliveryMode = .highQualityFormat
        
        return AsyncStream { continuation in
            var count = 0
            result.enumerateObjects { asset, i, pointer in
                manager.requestImage(for: asset,
                                     targetSize: size,
                                     contentMode: .aspectFill,
                                     options: request) { image, info in
                    
                    if let image {
                        continuation.yield(
                            PhotoLibraryImage(id: asset.localIdentifier, image: image, depth: nil, canny: nil)
                        )
                    }
                    
                    count += 1
                    if count >= fetch.fetchLimit {
                        print("finished")
                        continuation.finish()
                    }
                }
            }
        }
    }
    
    func getDepth(identifier: String) async -> PhotoLibraryImage? {
        return await withCheckedContinuation { continuation in
            let manager = PHImageManager.default()
            
            let fetch = PHFetchOptions()
            fetch.fetchLimit = 1
            let result = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: fetch)
            
            guard let asset = result.firstObject else {
                continuation.resume(returning: .none)
                return
            }
            
            let request = PHImageRequestOptions()
            request.isSynchronous = false
            request.isNetworkAccessAllowed = true
            request.resizeMode = .exact
            request.deliveryMode = .highQualityFormat
            
            manager.requestImageDataAndOrientation(for: asset, options: request) { data, dataUTI, orientation, info in
                
                manager.requestImage(for: asset,
                                     targetSize: CGSize(width: 512, height: 512),
                                     contentMode: .aspectFill,
                                     options: request) { image, info in
                    
                    guard let image else {
                        continuation.resume(returning: nil)
                        return
                    }
                    let canny = self.canny(image: image)
                    var result = PhotoLibraryImage(id: identifier, image: image, canny: canny)
                    
                    
                    if let data,
                        let depthData = self.depth(imageData: data),
                        let depthImage = self.image(depth: depthData)?.resizeAndCrop() {
                        
                        result.depth = depthImage
                    }
                    
//                    manager.requestImage(for: asset,
//                                         targetSize: MLService.targetSize,
//                                         contentMode: .aspectFill,
//                                         options: request) { image, info in
                        Task {
                            
//                            guard let image else {
//                                continuation.resume(returning: result)
//                                return
//                            }
                            
                            var estimatedDepth: UIImage?
                            do {
                                estimatedDepth = try await self.ml.performInference(image)
                            } catch {
                                print(error)
                            }
                            result.estimatedDepth = estimatedDepth
                            continuation.resume(returning: result)

                        }
//                    }
                    
                }
            }
        }
    }
    
    
    // TODO: fix code crimes and make this follow PHPhotoLibrary best practices
    @available(*, deprecated, renamed: "getImages", message: "this method sucks don't use it")
    func getImagesWithDepth(limit: Int = 10) -> AsyncStream<PhotoLibraryImage> {
        
        guard canAccess else {
            print("no access")
            fatalError()
        }
        
        let manager = PHImageManager.default()
        
        let fetch = PHFetchOptions()
        fetch.fetchLimit = limit
        fetch.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let format = "(mediaSubtypes & %d) != 0"
        fetch.predicate = NSPredicate(format: format, argumentArray: [PHAssetMediaSubtype.photoDepthEffect.rawValue])
        
        let result = PHAsset.fetchAssets(with: .image, options: fetch)
        
        let request = PHImageRequestOptions()
        request.isSynchronous = false
        request.isNetworkAccessAllowed = true
        request.resizeMode = .exact
        request.deliveryMode = .highQualityFormat
        
        return AsyncStream { continuation in
            var count = 0
            result.enumerateObjects { asset, i, pointer in
                
                manager.requestImageDataAndOrientation(for: asset, options: request) { data, dataUTI, orientation, info in
                    
                    if let data {
                        if let depthData = self.depth(imageData: data) {
                            let depthImage = self.image(depth: depthData)?.resizeAndCrop()
                            manager.requestImage(for: asset,
                                                 targetSize: CGSize(width: 512, height: 512),
                                                 contentMode: .aspectFill,
                                                 options: request) { image, info in
                                if let image {                                    
                                    let canny = depthImage != nil ? self.canny(image: depthImage!) : self.canny(image: image)
                                    
                                    continuation.yield(
                                        PhotoLibraryImage(id: asset.localIdentifier, image: image, depth: depthImage, canny: canny)
                                    )
                                } else {
                                    print("no image \(count)")
                                    continuation.yield(PhotoLibraryImage(id: asset.localIdentifier, image: UIImage(data: data)!, depth: nil, canny: nil))
                                }
                                
                                count += 1
                                if count >= fetch.fetchLimit {
                                    print("finished")
                                    continuation.finish()
                                }
                            }
                        } else {
                            print("no depth \(count)")
                            count += 1
                            continuation.yield(PhotoLibraryImage(id: asset.localIdentifier, image: UIImage(data: data)!, depth: nil, canny: nil))
                        }
                        
                    } else {
                        print("no data \(count)")
                        count += 1
                        continuation.yield(PhotoLibraryImage(id: NSUUID().uuidString, image: self.defaultImage, depth: nil, canny: nil))
                    }
                    
                    if count >= fetch.fetchLimit {
                        print("finished")
                        continuation.finish()
                    }
                }
            }
        }
    }
    
    // from https://developer.apple.com/videos/play/wwdc2017/507/
    func depth(imageData: Data) -> AVDepthData? {
        guard let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil) else {
            return nil
        }
        
        guard let auxData = CGImageSourceCopyAuxiliaryDataInfoAtIndex(imageSource, 0, kCGImageAuxiliaryDataTypeDisparity) as? [AnyHashable : Any] else {
            return nil
        }
        
        do {
            let depthData = try AVDepthData(fromDictionaryRepresentation: auxData)
            return depthData.converting(toDepthDataType: kCVPixelFormatType_DisparityFloat32)
        } catch {
            return nil
        }
    }
    
    // from https://stackoverflow.com/questions/8072208/how-to-turn-a-cvpixelbuffer-into-a-uiimage
    func image(depth: AVDepthData) -> UIImage? {
        let buffer = depth.depthDataMap
        let ciImage = CIImage(cvPixelBuffer: buffer)
        let context = CIContext()
        guard let imageRef = context.createCGImage(ciImage, from: CGRect(x: 0, y: 0, width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))) else {
            return nil
        }
        
        return UIImage(cgImage: imageRef)
    }
    
    func canny(image: UIImage) -> UIImage {
        guard let cgimage = image.cgImage else {
            fatalError("no cgimage")
        }
        let ciimage = CIImage(cgImage: cgimage)
        let context = CIContext()
        let filteredImage = cannyEdgeDetector(inputImage: ciimage)
        guard let output = context.createCGImage(filteredImage, from: filteredImage.extent) else {
            fatalError("no output")
        }
        
        return UIImage(cgImage: output)
    }
    
    // from https://developer.apple.com/documentation/coreimage/cifilter/4401852-cannyedgedetector
    private func cannyEdgeDetector(inputImage: CIImage) -> CIImage {
        let filter = CIFilter.cannyEdgeDetector()
        filter.inputImage = inputImage
        filter.gaussianSigma = 5
        filter.perceptual = false
        filter.thresholdLow = 0.02
        filter.thresholdHigh = 0.05
        filter.hysteresisPasses = 1
        return filter.outputImage!
    }
    
}

public extension UIImage {
    
    // TODO: remove magic numbers for specific depth map sizes/orientations
    func resizeAndCrop() -> UIImage {
        
        let cropRect: CGRect
        let newSize: CGSize
        if self.size.width > self.size.height {
            cropRect = CGRect(x: 85, y: 0, width: 512, height: 512)
            newSize = CGSize(width: 682, height: 512)
        } else {
            cropRect = CGRect(x: 0, y: 85, width: 512, height: 512)
            newSize = CGSize(width: 512, height: 682)
        }
        
        return resize(toTargetSize: newSize, scale: 1.0).croppedImage(inRect: cropRect)
    }
    
    // https://stackoverflow.com/a/48110726
    func croppedImage(inRect rect: CGRect) -> UIImage {
        let rad: (Double) -> CGFloat = { deg in
            return CGFloat(deg / 180.0 * .pi)
        }
        var rectTransform: CGAffineTransform
        switch imageOrientation {
        case .left:
            let rotation = CGAffineTransform(rotationAngle: rad(90))
            rectTransform = rotation.translatedBy(x: 0, y: -size.height)
        case .right:
            let rotation = CGAffineTransform(rotationAngle: rad(-90))
            rectTransform = rotation.translatedBy(x: -size.width, y: 0)
        case .down:
            let rotation = CGAffineTransform(rotationAngle: rad(-180))
            rectTransform = rotation.translatedBy(x: -size.width, y: -size.height)
        default:
            rectTransform = .identity
        }
        rectTransform = rectTransform.scaledBy(x: scale, y: scale)
        let transformedRect = rect.applying(rectTransform)
        let imageRef = cgImage!.cropping(to: transformedRect)!
        let result = UIImage(cgImage: imageRef, scale: scale, orientation: imageOrientation)
        return result
    }
    
    // https://gist.github.com/licvido/55d12a8eb76a8103c753
    func resize(toTargetSize targetSize: CGSize, scale: CGFloat?) -> UIImage {

        let newScale = (scale != nil) ? self.scale : scale! // change this if you want the output image to have a different scale
        let originalSize = self.size

        let widthRatio = targetSize.width / originalSize.width
        let heightRatio = targetSize.height / originalSize.height

        // Figure out what our orientation is, and use that to form the rectangle
        let newSize: CGSize
        if widthRatio < heightRatio { // note: change here means it'll restrict to the min size instead
            newSize = CGSize(width: floor(originalSize.width * heightRatio), height: floor(originalSize.height * heightRatio))
        } else {
            newSize = CGSize(width: floor(originalSize.width * widthRatio), height: floor(originalSize.height * widthRatio))
        }

        // This is the rect that we've calculated out and this is what is actually used below
        let rect = CGRect(origin: .zero, size: newSize)

        // Actually do the resizing to the rect using the ImageContext stuff
        let format = UIGraphicsImageRendererFormat()
        format.scale = newScale
        format.opaque = true
        let newImage = UIGraphicsImageRenderer(bounds: rect, format: format).image() { _ in
            self.draw(in: rect)
        }

        return newImage
    }
}

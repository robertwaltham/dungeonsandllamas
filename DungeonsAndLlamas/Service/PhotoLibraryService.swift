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
    
    struct ImageResult {
        let image: UIImage
        let depth: UIImage?
        
        init(image: UIImage, depth: UIImage? = nil) {
            self.image = image
            self.depth = depth
        }
    }
    
    func getImages(limit: Int = 10) -> AsyncStream<ImageResult> {
        
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
                            let depthImage = self.image(depth: depthData)
//                            if let depthImage {
//                                print("\(depthImage.size) - \(UIImage(data: data)!.size)")
//                            }
                            continuation.yield(
                                ImageResult(image: UIImage(data: data)!, depth: depthImage)
                            )
                        } else {
                            continuation.yield(ImageResult(image: UIImage(data: data)!))
                        }
                        

                    } else {
                        continuation.yield(ImageResult(image: self.defaultImage))
                    }
                    
                    count += 1
                    if count == fetch.fetchLimit {
                        continuation.finish()
                    }
                }
            }
        }
    }
    
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

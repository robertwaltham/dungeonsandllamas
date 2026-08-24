//
//  HistoryThumbnailStore.swift
//  DungeonsAndLlamas
//

import Foundation
import ImageIO
import UIKit

actor HistoryThumbnailStore {
    private static let cacheCostLimit = 32 * 1_024 * 1_024

    private let cache = NSCache<NSString, UIImage>()
    private let imageDirectory = URL.documentsDirectory.appendingPathComponent("savedImages")

    init() {
        cache.totalCostLimit = Self.cacheCostLimit
    }

    func thumbnail(path: String, maxPixelSize: Int) -> UIImage? {
        guard !Task.isCancelled, !path.isEmpty, maxPixelSize > 0 else {
            return nil
        }

        let key = "\(path)|\(maxPixelSize)" as NSString
        if let cachedImage = cache.object(forKey: key) {
            return cachedImage
        }

        guard !Task.isCancelled else {
            return nil
        }

        let url = imageDirectory.appending(path: path)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let image = UIImage(cgImage: cgImage)
        let cost = max(1, cgImage.bytesPerRow * cgImage.height)
        cache.setObject(image, forKey: key, cost: cost)
        return image
    }
}

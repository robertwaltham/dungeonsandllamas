//
//  FileService.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2024-04-16.
//

import Foundation
import UIKit
import PencilKit
import ImageIO

private let storageLogger = LoggingService.shared.storage

class FileService {
    
    var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }
    
    var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .iso8601
        return e
    }
    
    
    init() {
        let urls = [imageDirectory(), sdHistoryDirectory(), llmHistoryDirectory(), pencilDrawingDirectory(), imageCacheDirectory()]
        let manager = FileManager.default

        for url in urls {
            if !manager.fileExists(atPath: url.absoluteString) {
                do {
                    try manager.createDirectory(at: url, withIntermediateDirectories: true)
                } catch {
                    storageLogger.error("Directory creation failed: \(error.localizedDescription, privacy: .private)")
                }
            }
        }
    }
    
    private func imageDirectory() -> URL {
        return URL.documentsDirectory.appendingPathComponent("savedImages")
    }
    
    private func sdHistoryDirectory() -> URL {
        return URL.documentsDirectory.appendingPathComponent("sdHistory")
    }
    
    private func pencilDrawingDirectory() -> URL {
        return URL.documentsDirectory.appendingPathComponent("pencil")
    }
    
    private func llmHistoryDirectory() -> URL {
        return URL.documentsDirectory.appendingPathComponent("llmHistory")
    }
    
    private func imageCacheDirectory() -> URL {
        return URL.documentsDirectory.appendingPathComponent("imageCache")
    }
    
    //MARK: - Images
    
    func save(image: UIImage) -> String {
        let filename = NSUUID().uuidString + ".png"
        let fileURL = imageDirectory().appending(component: filename)
        if let data = image.pngData() {
            do {
                try data.write(to: fileURL)
            } catch {
                storageLogger.error("Image write failed: \(error.localizedDescription, privacy: .private)")
            }
        } else {
            storageLogger.error("Could not encode image as PNG")
        }

        return filename
    }

    func save(imageData: Data) -> String? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              CGImageSourceGetCount(source) > 0 else {
            return nil
        }
        let filename = NSUUID().uuidString + imageFileExtension(for: CGImageSourceGetType(source) as String?)
        let fileURL = imageDirectory().appending(component: filename)
        do {
            try imageData.write(to: fileURL, options: .atomic)
            return filename
        } catch {
            storageLogger.error("Image-data save failed: \(error.localizedDescription, privacy: .private)")
            return nil
        }
    }

    private func imageFileExtension(for uti: String?) -> String {
        switch uti {
        case "public.jpeg": return ".jpg"
        case "public.heic": return ".heic"
        case "public.webp": return ".webp"
        default: return ".png"
        }
    }

    func imageExists(path: String?) -> Bool {
        guard let path, !path.isEmpty else {
            return false
        }
        let fileURL = imageDirectory().appending(path: path)
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else {
            return false
        }
        return CGImageSourceGetCount(source) > 0
    }
    
    func loadImage(path: String) -> UIImage {
        let url = imageDirectory().appending(path: path)
        return UIImage(contentsOfFile: url.path) ?? UIImage(named: "lighthouse")!
    }

    func loadImage(path: String, maxPixelSize: Int) -> UIImage {
        let url = imageDirectory().appending(path: path)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            return UIImage(cgImage: image)
        }
        return UIImage(named: "lighthouse")!
    }
    
    func save(drawing: PKDrawing) -> String {
        let filename = NSUUID().uuidString + ".drawing"
        let fileURL = pencilDrawingDirectory().appending(component: filename)
        let data = drawing.dataRepresentation()
        do {
            try data.write(to: fileURL)
        } catch {
            storageLogger.error("Drawing write failed: \(error.localizedDescription, privacy: .private)")
        }

        return filename
    }
    
    func load(path: String) -> PKDrawing {
        do {
            let data = try Data(contentsOf: pencilDrawingDirectory().appending(path: path))
            return try PKDrawing(data: data)
            
        } catch {
            storageLogger.error("Drawing load failed: \(error.localizedDescription, privacy: .private)")
        }
        return PKDrawing()
    }
    
    // expected identifier is a localIdentifier from a PHAsset which contains / characters
    func cache(image: UIImage, identifier: String) {
        let filename = identifier.replacingOccurrences(of: "/", with: "_") + ".png"
        let fileURL = imageCacheDirectory().appending(component: filename)
        if let data = image.pngData() {
            do {
                try data.write(to: fileURL)
            } catch {
                storageLogger.error("Cached image write failed: \(error.localizedDescription, privacy: .private)")
            }
        } else {
            storageLogger.error("Could not encode cached image as PNG")
        }
    }
    
    func loadCachedImage(identifier: String) -> UIImage? {
        let filename = identifier.replacingOccurrences(of: "/", with: "_") + ".png"
        let filepath = imageCacheDirectory().appending(path: filename)
        let manager = FileManager.default

        guard manager.fileExists(atPath: filepath.absoluteString) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: filepath)
            return UIImage(data: data)
        } catch {
            storageLogger.error("Cached image load failed: \(error.localizedDescription, privacy: .private)")
        }
        return nil
    }

    func imageCacheFileCount() -> Int {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: imageCacheDirectory(),
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        return entries.reduce(into: 0) { count, url in
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                count += 1
            }
        }
    }
}

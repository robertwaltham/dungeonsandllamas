//
//  FileService.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2024-04-16.
//

import Foundation
import UIKit
import PencilKit


final class FileService {
    
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
    
    let manager = FileManager.default
    
    init() {
        let urls = [imageDirectory(), sdHistoryDirectory(), llmHistoryDirectory(), pencilDrawingDirectory()]
        
        for url in urls {
            if !manager.fileExists(atPath: url.absoluteString) {
                do {
                    try manager.createDirectory(at: url, withIntermediateDirectories: true)
                } catch {
                    print(error.localizedDescription)
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
    
    //MARK: - SD History
    
    func save(history: GenerationService.SDHistoryEntry) {
        let filename = NSUUID().uuidString
        let fileURL = sdHistoryDirectory().appending(component: filename + ".history")
        
        do {
            try encoder.encode(history).write(to: fileURL)
        } catch {
            print(error)
        }
    }
    
    func loadSDHistory() -> [GenerationService.SDHistoryEntry] {
        var result = [GenerationService.SDHistoryEntry]()
        
        do {
            let directory = sdHistoryDirectory()
            let paths = try manager.contentsOfDirectory(atPath: directory.path())
            for path in paths {
                let data = try Data(contentsOf: directory.appending(path: path))
                
                result.append(try decoder.decode(GenerationService.SDHistoryEntry.self, from: data))
            }

        } catch {
            print(error.localizedDescription)
        }

        return result.sorted { a, b in
            a.start < b.start
        }
    }
    
    //MARK: - Images
    
    func save(image: UIImage) -> String {
        let filename = NSUUID().uuidString + ".png"
        let fileURL = imageDirectory().appending(component: filename)
        if let data = image.pngData() {
            do {
                try data.write(to: fileURL)
            } catch {
                print(error.localizedDescription)
            }
        } else {
            print("error getting png data")
        }

        return filename
    }
    
    func loadImage(path: String) -> UIImage {
        do {
            let data = try Data(contentsOf: imageDirectory().appending(path: path))
            return UIImage(data: data) ?? UIImage(named: "lighthouse")!
            
        } catch {
            print(error.localizedDescription)
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
            print(error.localizedDescription)
        }

        return filename
    }
    
    func load(path: String) -> PKDrawing {
        do {
            let data = try Data(contentsOf: pencilDrawingDirectory().appending(path: path))
            return try PKDrawing(data: data)
            
        } catch {
            print(error.localizedDescription)
        }
        return PKDrawing()
    }
}

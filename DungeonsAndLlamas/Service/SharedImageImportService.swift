//
//  SharedImageImportService.swift
//  DungeonsAndLlamas
//
//  Created by OpenAI on 2026-06-27.
//

import Foundation
import UIKit

@MainActor
struct SharedImageImportService {
    static let urlScheme = "dungeonsandllamas"
    static let importHost = "comfyui"
    static let importPath = "/shared-image"
    static let appGroupIdentifier = "group.com.leveltenpaladin.DungeonsAndLlamas"

    private static let sharedImageFilename = "SharedComfyUIInput.png"

    static func sharedImageURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent(sharedImageFilename, isDirectory: false)
    }

    static func canHandle(_ url: URL) -> Bool {
        url.scheme == urlScheme && url.host == importHost && url.path == importPath
    }

    static func loadSharedImage(for url: URL) -> UIImage? {
        guard canHandle(url),
              let sharedImageURL = sharedImageURL(),
              let data = try? Data(contentsOf: sharedImageURL),
              let image = UIImage(data: data) else {
            return nil
        }

        try? FileManager.default.removeItem(at: sharedImageURL)
        return image
    }
}

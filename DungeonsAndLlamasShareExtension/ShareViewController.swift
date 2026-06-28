//
//  ShareViewController.swift
//  DungeonsAndLlamasShareExtension
//
//  Created by OpenAI on 2026-06-27.
//

import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private enum Constants {
        static let appGroupIdentifier = "group.com.leveltenpaladin.DungeonsAndLlamas"
        static let sharedImageFilename = "SharedComfyUIInput.png"
        static let openURL = URL(string: "dungeonsandllamas://comfyui/shared-image")!
    }

    private var didStartImport = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        guard !didStartImport else {
            return
        }

        didStartImport = true
        importFirstSharedImage()
    }

    private func importFirstSharedImage() {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let provider = extensionItem.attachments?.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }) else {
            completeRequest()
            return
        }

        provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] data, _ in
            guard let self else {
                return
            }

            Task { @MainActor in
                guard let data,
                      self.writeSharedImageData(data) else {
                    self.completeRequest()
                    return
                }

                _ = await self.extensionContext?.open(Constants.openURL)
                self.completeRequest()
            }
        }
    }

    private func writeSharedImageData(_ data: Data) -> Bool {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Constants.appGroupIdentifier) else {
            return false
        }

        do {
            let imageURL = containerURL.appendingPathComponent(Constants.sharedImageFilename, isDirectory: false)
            try data.write(to: imageURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private func completeRequest() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}

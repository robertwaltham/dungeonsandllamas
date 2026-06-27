//
//  ComfyUITestView.swift
//  DungeonsAndLlamas
//
//  Created by OpenAI on 2026-06-21.
//

import SwiftUI
import Observation
import PencilKit
import UIKit

struct ComfyUITestView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var viewModel = ComfyUITestViewModel()
    @State var generationService: GenerationService

    private var isCompact: Bool {
        horizontalSizeClass == .compact
    }

    var body: some View {
        Group {
            if isCompact {
                GeometryReader { geometry in
                    compactLayout(canvasDimension: min(320, max(240, geometry.size.width - 32)))
                }
            } else {
                regularLayout
            }
        }
        .navigationTitle("ComfyUI Test")
    }

    private var regularLayout: some View {
        ScrollView {
            VStack(alignment: .center, spacing: 16) {
                controls

//                HStack(alignment: .top, spacing: 24) {
                    canvasSection(canvasDimension: 512)
                    outputSection(maxImageHeight: 512)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
//                }

//                detailsSection
            }
            .padding()
        }
    }

    private func compactLayout(canvasDimension: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .center, spacing: 16) {
                controls
                canvasSection(canvasDimension: canvasDimension)
                outputSection(maxImageHeight: canvasDimension)
//                detailsSection
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
//                    Text("Prompt")
//                        .font(.headline)
                    TextField("Prompt", text: $viewModel.prompt, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...6)
                }

                Button("Generate") {
                    viewModel.generate(using: generationService)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.loading)
//            }

//            HStack(spacing: 12) {
                Button("Clear Drawing") {
                    viewModel.clearDrawing()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.loading)

                Button("Random Seed") {
                    viewModel.randomizeSeed()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.loading)

//                TextField("Seed", value: $viewModel.seed, format: .number.grouping(.never))
//                    .textFieldStyle(.roundedBorder)
//                    .disabled(true)
            }
        }
    }

    private func canvasSection(canvasDimension: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
//            Text("Input Image")
//                .font(.headline)
            PencilCanvasView(
                drawing: $viewModel.drawing,
                showTooltip: $viewModel.showTooltip,
                contentSize: $viewModel.canvasSize
            )
            .frame(width: canvasDimension, height: canvasDimension)
            .border(.secondary)
        }
    }

    private func outputSection(maxImageHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.loading {
                LoadingView()
                    .frame(maxWidth: .infinity, minHeight: 120)
            }

            if let error = viewModel.error {
                Text(error)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            if let image = viewModel.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: maxImageHeight)
            }
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.inputImagePath != nil || viewModel.uploadedInputFilename != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Input Upload")
                        .font(.headline)
                    if let inputImagePath = viewModel.inputImagePath {
                        Text(inputImagePath)
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                    if let uploadedInputFilename = viewModel.uploadedInputFilename {
                        Text(uploadedInputFilename)
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                }
            }

            if !viewModel.imagePaths.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Output Files")
                        .font(.headline)
                    ForEach(viewModel.imagePaths, id: \.self) { path in
                        Text(path)
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }
}

private struct LoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Generating...")
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

@MainActor
@Observable
private class ComfyUITestViewModel {
    var prompt = "make realistic"
    var seed = randomSeed()
    var promptId = UUID().uuidString.lowercased()
    var drawing: PKDrawing?
    var showTooltip = true
    var canvasSize = 512
    var loading = false
    var image: UIImage?
    var imagePaths = [String]()
    var inputImagePath: String?
    var uploadedInputFilename: String?
    var error: String?

    func resetPromptId() {
        promptId = UUID().uuidString.lowercased()
    }

    func randomizeSeed() {
        seed = Self.randomSeed()
    }

    func clearDrawing() {
        drawing = nil
        inputImagePath = nil
        uploadedInputFilename = nil
    }

    func generate(using generationService: GenerationService) {
        guard !loading else {
            return
        }

        loading = true
        image = nil
        imagePaths = []
        inputImagePath = nil
        uploadedInputFilename = nil
        error = nil

        let inputImage: InputImage
        do {
            inputImage = try saveDrawingInputImage()
            inputImagePath = inputImage.path
        } catch {
            self.error = error.localizedDescription
            loading = false
            return
        }

        let prompt = prompt
        let seed = seed
        let clientId = generationService.comfyUIClientId
        let promptId = UUID().uuidString.lowercased()
        self.promptId = promptId

        Task {
            do {
                let upload = try await generationService.comfyUIClient.uploadImage(
                    inputImage.data,
                    filename: inputImage.filename,
                    type: .input,
                    overwrite: true
                )
                uploadedInputFilename = upload.name

                let messageStream = try await generationService.comfyUIClient.messages(clientId: clientId)
                _ = try await generationService.comfyUIClient.submitImageFlux2KleinImageEdit(
                    prompt: prompt,
                    seed: seed,
                    imageFilename: upload.name,
                    clientId: clientId,
                    promptId: promptId
                )
                try await waitForImageEditCompletion(promptId: promptId, messages: messageStream)

                let outputs = try await generationService.comfyUIClient.imageOutputPaths(promptId: promptId)
                let paths = outputs.keys.sorted().flatMap { outputs[$0] ?? [] }
                imagePaths = paths

                if let firstPath = paths.first, let loadedImage = UIImage(contentsOfFile: firstPath) {
                    image = loadedImage
                } else {
                    error = "No image output returned."
                }
            } catch {
                self.error = error.localizedDescription
            }

            randomizeSeed()
            loading = false
        }
    }

    private func waitForImageEditCompletion(promptId: String, messages: AsyncThrowingStream<ComfyUIClient.WebSocketMessage, Error>) async throws {
        for try await message in messages {
            guard case .event(let event) = message, event.isExecutionComplete(for: promptId) else {
                continue
            }
            return
        }
    }

    private func saveDrawingInputImage() throws -> InputImage {
        guard let drawing, !drawing.strokes.isEmpty else {
            throw APIError.requestError("Draw an input image before generating.")
        }

        let size = CGSize(width: canvasSize, height: canvasSize)
        let bounds = CGRect(origin: .zero, size: size)
        let drawingImage = drawing.image(from: bounds, scale: 1)
        let renderedImage = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill()
            context.cgContext.fill(bounds)
            drawingImage.draw(in: bounds)
        }
        guard let data = renderedImage.pngData() else {
            throw APIError.requestError("could not render drawing image")
        }

        let filename = "comfy-input-\(UUID().uuidString.lowercased()).png"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ComfyUIInputImages", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent(filename)
        try data.write(to: fileURL)
        return InputImage(data: data, filename: filename, path: fileURL.path())
    }

    private static func randomSeed() -> Int64 {
        Int64.random(in: 0...999_999_999_999_999)
    }

    private struct InputImage {
        let data: Data
        let filename: String
        let path: String
    }
}

#Preview {
    NavigationStack {
        ComfyUITestView(generationService: GenerationService())
    }
}

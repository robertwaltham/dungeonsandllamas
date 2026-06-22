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
    @State private var viewModel = ComfyUITestViewModel()
    @State var generationService: GenerationService

    var body: some View {
        ScrollView {
            VStack(alignment: .center, spacing: 16) {

                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Prompt")
                            .font(.headline)
                        TextField("Prompt", text: $viewModel.prompt, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(1...6)
                    }
                    
                    HStack {
                        Button("Generate") {
                            viewModel.generate(using: generationService)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(viewModel.loading)
                    }
                }
                
                HStack {
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
                    
                    TextField("Seed", value: $viewModel.seed, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                        .disabled(true)
                }

                PencilCanvasView(
                    drawing: $viewModel.drawing,
                    showTooltip: $viewModel.showTooltip,
                    contentSize: $viewModel.canvasSize
                )
                .frame(width: 512, height: 512)
                .border(.secondary)

//                HStack(alignment: .center, spacing: 4) {
//
//                    VStack {
//                        Text("Client UUID")
//                            .font(.headline)
//                        Text(generationService.comfyUIClientId)
//                            .font(.caption)
//                            .textSelection(.enabled)
//                    }
//                    VStack {
//                        Text("Prompt UUID")
//                            .font(.headline)
//                        Text(viewModel.promptId)
//                            .font(.caption)
//                            .textSelection(.enabled)
//                    }
//                }

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
                        .frame(maxHeight: 600)
                }

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
            .padding()
        }
        .navigationTitle("ComfyUI Test")
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

                let outputs = try await generationService.comfyUIClient.generateImageFlux2KleinImageEdit(
                    prompt: prompt,
                    seed: seed,
                    imageFilename: upload.name,
                    clientId: clientId,
                    promptId: promptId
                )
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

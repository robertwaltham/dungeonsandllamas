//
//  ComfyUITestView.swift
//  DungeonsAndLlamas
//
//  Created by OpenAI on 2026-06-21.
//

import SwiftUI
import Observation

struct ComfyUITestView: View {
    @State private var viewModel = ComfyUITestViewModel()
    @State var generationService: GenerationService

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("ComfyUI Flux2")
                    .font(.largeTitle)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Prompt")
                        .font(.headline)
                    TextField("Prompt", text: $viewModel.prompt, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...6)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Seed")
                        .font(.headline)
                    HStack {
                        TextField("Seed", value: $viewModel.seed, format: .number.grouping(.never))
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.numberPad)

                        Button("Random Seed") {
                            viewModel.randomizeSeed()
                        }
                        .buttonStyle(.bordered)
                        .disabled(viewModel.loading)
                    }

                    Text("Client UUID")
                        .font(.headline)
                    Text(generationService.comfyUIClientId)
                        .font(.caption)
                        .textSelection(.enabled)

                    Text("Prompt UUID")
                        .font(.headline)
                    Text(viewModel.promptId)
                        .font(.caption)
                        .textSelection(.enabled)
                }

                HStack {
                    Button("Generate") {
                        viewModel.generate(using: generationService)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.loading)
                }

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
    var loading = false
    var image: UIImage?
    var imagePaths = [String]()
    var error: String?

    func resetPromptId() {
        promptId = UUID().uuidString.lowercased()
    }

    func randomizeSeed() {
        seed = Self.randomSeed()
    }

    func generate(using generationService: GenerationService) {
        guard !loading else {
            return
        }

        loading = true
        image = nil
        imagePaths = []
        error = nil

        let prompt = prompt
        let seed = seed
        let clientId = generationService.comfyUIClientId
        let promptId = UUID().uuidString.lowercased()
        self.promptId = promptId

        Task {
            do {
                let outputs = try await generationService.comfyUIClient.generateImageFlux2KleinImageEdit(
                    prompt: prompt,
                    seed: seed,
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

    private static func randomSeed() -> Int64 {
        Int64.random(in: 0...999_999_999_999_999)
    }
}

#Preview {
    NavigationStack {
        ComfyUITestView(generationService: GenerationService())
    }
}

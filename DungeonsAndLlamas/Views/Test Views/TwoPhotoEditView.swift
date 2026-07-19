//
//  TwoPhotoEditView.swift
//  DungeonsAndLlamas
//

import SwiftUI
import Observation
import UIKit

struct TwoPhotoEditView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var viewModel: TwoPhotoEditViewModel
    @State private var activeSlot: TwoPhotoEditViewModel.ImageSlot?
    @FocusState private var promptFocused: Bool
    let generationService: GenerationService

    init(generationService: GenerationService, history: ImageHistoryModel? = nil) {
        self.generationService = generationService
        self._viewModel = State(initialValue: TwoPhotoEditViewModel(generationService: generationService, history: history))
    }

    var body: some View {
        ZStack {
            GradientView(type: .greyscale)

            ScrollView {
                VStack(spacing: 16) {
                    Text("Choose two photos and describe how they should be combined.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    TextField("Prompt", text: $viewModel.prompt, axis: .vertical)
                        .focused($promptFocused)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...6)

                    inputCards

                    Button {
                        promptFocused = false
                        viewModel.generate(using: generationService)
                    } label: {
                        Label(viewModel.loading ? "Generating…" : "Generate", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.canGenerate || viewModel.loading)

                    if let error = viewModel.error {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    outputSection
                }
                .padding()
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Flux2 Two-Photo Edit")
        .task {
            await viewModel.loadGallery(using: generationService.photos)
        }
        .sheet(item: $activeSlot) { slot in
            PhotoGalleryPicker(
                title: "Choose \(slot.title)",
                images: viewModel.photoLibraryImages,
                isLoading: viewModel.isLoadingPhotoLibraryImages,
                selectedID: viewModel.selectionID(for: slot),
                onSelect: { photo in
                    viewModel.select(photo, for: slot, using: generationService.photos)
                },
                onLoadMore: { photo in
                    viewModel.loadNextPhotoLibraryBatchIfNeeded(currentPhoto: photo, using: generationService.photos)
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private var inputCards: some View {
        if horizontalSizeClass == .compact {
            VStack(spacing: 12) {
                inputCard(for: .one)
                inputCard(for: .two)
            }
        } else {
            HStack(alignment: .top, spacing: 16) {
                inputCard(for: .one)
                inputCard(for: .two)
            }
        }
    }

    private func inputCard(for slot: TwoPhotoEditViewModel.ImageSlot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(slot.title)
                .font(.headline)

            Group {
                if let image = viewModel.image(for: slot) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 180, maxHeight: 360)
                        .background(.black.opacity(0.08))
                } else {
                    ContentUnavailableView("No photo selected", systemImage: "photo", description: Text("Choose an image from your photo library."))
                        .frame(maxWidth: .infinity, minHeight: 180)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .center) {
                if viewModel.isPreparing(slot: slot) {
                    ProgressView("Preparing…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                }
            }

            Button(viewModel.image(for: slot) == nil ? "Pick Image" : "Replace Image") {
                activeSlot = slot
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.loading || viewModel.isPreparing(slot: slot))
            .accessibilityLabel("Pick \(slot.title)")
        }
        .frame(maxWidth: .infinity)
    }

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(viewModel.hasPreviousOutput ? "Result" : "Generated Result")
                .font(.headline)

            if let output = viewModel.output {
                Image(uiImage: output)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .overlay {
                        if viewModel.loading {
                            ProgressView("Generating…")
                                .padding()
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
            } else {
                ContentUnavailableView("No result yet", systemImage: "sparkles", description: Text("Your generated image will appear here."))
                    .frame(maxWidth: .infinity, minHeight: 180)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PhotoGalleryPicker: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let images: [PhotoLibraryService.PhotoLibraryImage]
    let isLoading: Bool
    let selectedID: String?
    let onSelect: (PhotoLibraryService.PhotoLibraryImage) -> Void
    let onLoadMore: (PhotoLibraryService.PhotoLibraryImage) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.headline)
                    .padding(.horizontal)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 8) {
                    ForEach(images) { photo in
                        Button {
                            onSelect(photo)
                            dismiss()
                        } label: {
                            Image(uiImage: photo.image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 72, height: 72)
                                .clipped()
                                .overlay(alignment: .topTrailing) {
                                    selectedBadge(isSelected: photo.id == selectedID)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(photo.id == selectedID ? "Selected photo" : "Photo")
                        .onAppear {
                            onLoadMore(photo)
                        }
                    }

                    if isLoading {
                        ProgressView()
                            .frame(width: 72, height: 72)
                    }
                }
                .padding()
            }
        }
        .frame(minHeight: 360)
    }

    @ViewBuilder
    private func selectedBadge(isSelected: Bool) -> some View {
        if isSelected {
            Image(systemName: "checkmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Color.accentColor)
                .padding(3)
        }
    }
}

@MainActor
@Observable
private final class TwoPhotoEditViewModel {
    enum ImageSlot: String, Identifiable, Hashable {
        case one
        case two

        var id: String { rawValue }
        var title: String { rawValue == "one" ? "Image 1" : "Image 2" }
    }

    private struct SelectedImage {
        let id: String
        let image: UIImage
        let prepared: PreparedImage
    }

    private struct PreparedImage {
        let image: UIImage
        let data: Data
        let filename: String
    }

    private static let batchSize = 40
    private static let defaultPrompt = "stylize image 2 with the colors and theme of image 1"

    var prompt: String
    var photoLibraryImages = [PhotoLibraryService.PhotoLibraryImage]()
    var isLoadingPhotoLibraryImages = false
    var canLoadMorePhotoLibraryImages = true
    var loading = false
    var error: String?
    var output: UIImage?

    private var firstImage: SelectedImage?
    private var secondImage: SelectedImage?
    private var preparingSlots = Set<ImageSlot>()
    private var selectedIDs = [ImageSlot: String]()
    private var generationTask: Task<Void, Never>?
    private var seed = TwoPhotoEditViewModel.randomSeed()

    init(generationService: GenerationService, history: ImageHistoryModel?) {
        prompt = history?.prompt ?? Self.defaultPrompt

        guard let history else { return }
        seed = Self.randomSeed()
        if let firstPath = history.inputFilePaths.first {
            firstImage = Self.makeSelectedImage(id: "history-image-1", image: generationService.fileService.loadImage(path: firstPath), prefix: "comfy-history-image-1")
        }
        if history.inputFilePaths.indices.contains(1) {
            let secondPath = history.inputFilePaths[1]
            secondImage = Self.makeSelectedImage(id: "history-image-2", image: generationService.fileService.loadImage(path: secondPath), prefix: "comfy-history-image-2")
        }
        output = history.outputFilePath.map { generationService.fileService.loadImage(path: $0) }
        selectedIDs[.one] = firstImage?.id
        selectedIDs[.two] = secondImage?.id
    }

    var canGenerate: Bool {
        firstImage != nil && secondImage != nil && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasPreviousOutput: Bool { output != nil }

    func image(for slot: ImageSlot) -> UIImage? {
        slot == .one ? firstImage?.image : secondImage?.image
    }

    func isPreparing(slot: ImageSlot) -> Bool {
        preparingSlots.contains(slot)
    }

    func selectionID(for slot: ImageSlot) -> String? {
        selectedIDs[slot]
    }

    func loadGallery(using service: PhotoLibraryService) async {
        guard photoLibraryImages.isEmpty else { return }
        await service.requestAccessIfNeeded()
        guard service.canAccess else {
            error = "Photo library access is required to pick images."
            return
        }
        loadNextPhotoLibraryImages(using: service)
    }

    func loadNextPhotoLibraryBatchIfNeeded(currentPhoto photo: PhotoLibraryService.PhotoLibraryImage, using service: PhotoLibraryService) {
        guard photo.id == photoLibraryImages.last?.id else { return }
        loadNextPhotoLibraryImages(using: service)
    }

    private func loadNextPhotoLibraryImages(using service: PhotoLibraryService) {
        guard !isLoadingPhotoLibraryImages, canLoadMorePhotoLibraryImages else { return }
        isLoadingPhotoLibraryImages = true
        let offset = photoLibraryImages.count

        Task {
            var loadedCount = 0
            var loadedIDs = Set(photoLibraryImages.map(\.id))
            for await photo in service.getImages(limit: Self.batchSize, offset: offset, size: CGSize(width: 220, height: 220)) {
                guard !loadedIDs.contains(photo.id) else { continue }
                loadedIDs.insert(photo.id)
                photoLibraryImages.append(photo)
                loadedCount += 1
            }
            canLoadMorePhotoLibraryImages = loadedCount == Self.batchSize
            isLoadingPhotoLibraryImages = false
        }
    }

    func select(_ photo: PhotoLibraryService.PhotoLibraryImage, for slot: ImageSlot, using service: PhotoLibraryService) {
        selectedIDs[slot] = photo.id
        preparingSlots.insert(slot)
        error = nil

        Task {
            do {
                let image = try await service.getImage(identifier: photo.id, targetSize: CGSize(width: 1600, height: 1600))
                guard !Task.isCancelled else { return }
                let prepared = try Self.prepare(image: image, prefix: slot == .one ? "comfy-photo-1" : "comfy-photo-2")
                let selected = SelectedImage(id: photo.id, image: prepared.image, prepared: prepared)
                if slot == .one {
                    firstImage = selected
                } else {
                    secondImage = selected
                }
            } catch {
                self.error = error.localizedDescription
            }
            preparingSlots.remove(slot)
        }
    }

    func generate(using generationService: GenerationService) {
        guard canGenerate, !loading, let firstImage, let secondImage else { return }

        generationTask?.cancel()
        loading = true
        error = nil
        let prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let seed = seed
        let clientID = generationService.comfyUIClientId
        let promptID = UUID().uuidString.lowercased()
        let firstPath = generationService.fileService.save(image: firstImage.prepared.image)
        let secondPath = generationService.fileService.save(image: secondImage.prepared.image)
        var history = ImageHistoryModel(
            id: UUID().uuidString,
            start: .now,
            prompt: prompt,
            promptId: promptID,
            negativePrompt: "Flux2 Klein 2 image edit",
            model: "ComfyUI Flux2 Klein 4B",
            sampler: "euler",
            steps: 4,
            size: max(Int(firstImage.prepared.image.size.width), Int(firstImage.prepared.image.size.height)),
            seed: Int(seed),
            inputFilePaths: [firstPath, secondPath],
            drawingFilePath: nil,
            session: clientID,
            sequence: 0,
            loras: []
        )

        generationTask = Task { @MainActor in
            defer {
                loading = false
                self.seed = Self.randomSeed()
            }

            do {
                let firstUpload = try await generationService.comfyUIClient.uploadImage(firstImage.prepared.data, filename: firstImage.prepared.filename, type: .input, overwrite: false)
                let secondUpload = try await generationService.comfyUIClient.uploadImage(secondImage.prepared.data, filename: secondImage.prepared.filename, type: .input, overwrite: false)
                let messages = try await generationService.comfyUIClient.messages(clientId: clientID)
                _ = try await generationService.comfyUIClient.submitImageFlux2Klein2ImageEdit(
                    prompt: prompt,
                    seed: seed,
                    firstImageFilename: firstUpload.name,
                    secondImageFilename: secondUpload.name,
                    clientId: clientID,
                    promptId: promptID
                )

                for try await message in messages {
                    guard case .event(let event) = message, event.isExecutionComplete(for: promptID) else { continue }
                    break
                }

                let outputs = try await generationService.comfyUIClient.imageOutputPaths(promptId: promptID)
                let paths = outputs.keys.sorted().flatMap { outputs[$0] ?? [] }
                guard let firstPath = paths.first, let image = UIImage(contentsOfFile: firstPath) else {
                    throw APIError.requestError("No image output returned.")
                }

                output = image
                history.outputFilePath = generationService.fileService.save(image: image)
                history.outputEmbedding = try? await generationService.mlService.imageEmbedding(for: image)
                history.end = .now
            } catch is CancellationError {
                return
            } catch {
                self.error = error.localizedDescription
                history.errorDescription = error.localizedDescription
                history.end = .now
            }

            history.promptEmbedding = try? await generationService.mlService.textEmbedding(for: prompt)
            history.inputEmbedding = try? await generationService.mlService.combinedImageEmbedding(for: [firstImage.prepared.image, secondImage.prepared.image])
            generationService.db.save(history: history)
            generationService.imageHistory.append(history)
            generationService.lastHistory = history
        }
    }

    private static func makeSelectedImage(id: String, image: UIImage, prefix: String) -> SelectedImage? {
        guard let prepared = try? prepare(image: image, prefix: prefix) else { return nil }
        return SelectedImage(id: id, image: prepared.image, prepared: prepared)
    }

    private static func prepare(image: UIImage, prefix: String) throws -> PreparedImage {
        guard image.size.width > 0, image.size.height > 0 else {
            throw APIError.requestError("Could not prepare image")
        }
        let maxPixels: CGFloat = 1_000_000
        let scale = min(1, sqrt(maxPixels / (image.size.width * image.size.height)))
        let size = CGSize(width: max(1, round(image.size.width * scale)), height: max(1, round(image.size.height * scale)))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let processed = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let data = processed.pngData() else {
            throw APIError.requestError("Could not encode image")
        }
        return PreparedImage(image: processed, data: data, filename: "\(prefix)-\(UUID().uuidString.lowercased()).png")
    }

    private static func randomSeed() -> Int64 {
        Int64.random(in: 0...999_999_999_999_999)
    }
}

#Preview {
    NavigationStack {
        TwoPhotoEditView(generationService: GenerationService())
    }
}

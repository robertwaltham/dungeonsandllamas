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
    @State private var showingPhotoLibraryPopover = false
    let generationService: GenerationService

    init(generationService: GenerationService, workflow: ComfyUITestWorkflow = .one, history: ImageHistoryModel? = nil) {
        self.generationService = generationService
        self._viewModel = State(initialValue: ComfyUITestViewModel(workflow: workflow, history: history, generationService: generationService))
    }


    private var isCompact: Bool {
        horizontalSizeClass == .compact
    }

    var body: some View {
        Group {
            ZStack {
                GradientView(type: .greyscale)
                if isCompact {
                    GeometryReader { geometry in
                        compactLayout(canvasDimension: min(320, max(240, geometry.size.width - 32)))
                    }
                } else {
                    regularLayout
                }
            }
        }
        .navigationTitle("ComfyUI Test")
    }

    private var regularLayout: some View {
        ScrollView {
            VStack(alignment: .center, spacing: 16) {
                controls
                canvasSection(canvasDimension: 512)
                outputSection(maxImageHeight: 512)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
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
                Spacer().frame(height: 50)
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            
            TextField("Prompt", text: $viewModel.prompt, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...6)
            
            HStack(alignment: .bottom, spacing: 12) {

                Button("Generate") {
                    viewModel.generate(using: generationService)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.loading || (viewModel.useTwoImageWorkflow && viewModel.selectedPhotoLibraryDisplayImage == nil))

                Button("Clear Drawing") {
                    viewModel.clearDrawing()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.loading)
                
                photoLibrarySelectionView()


//                Button("Random Seed") {
//                    viewModel.randomizeSeed()
//                }
//                .buttonStyle(.bordered)
//                .disabled(viewModel.loading)

//                Toggle("2 Images", isOn: Binding(
//                    get: { viewModel.useTwoImageWorkflow },
//                    set: { viewModel.setTwoImageWorkflow($0, using: generationService) }
//                ))
//                .toggleStyle(.switch)
//                .disabled(viewModel.loading)

            }

            if viewModel.useTwoImageWorkflow {
                Toggle("Use Depth", isOn: Binding(
                    get: { viewModel.usePhotoLibraryDepthImage },
                    set: { viewModel.setUsePhotoLibraryDepthImage($0, using: generationService) }
                ))
                .toggleStyle(.switch)
                .disabled(viewModel.loading)

            }
        }
    }

    private var photoLibraryPopover: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 8) {
                ForEach(viewModel.photoLibraryImages) { photo in
                    Button {
                        viewModel.selectPhotoLibraryImage(photo, using: generationService)
                        showingPhotoLibraryPopover = false
                    } label: {
                        if let image = viewModel.photoLibraryDisplayImage(for: photo) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 72, height: 72)
                                .clipped()
                                .border(viewModel.selectedPhotoLibraryImageId == photo.id ? Color.accentColor : Color.secondary)
                        } else {
                            ProgressView()
                                .frame(width: 72, height: 72)
                                .border(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.loading || viewModel.photoLibraryDisplayImage(for: photo) == nil)
                    .onAppear {
                        viewModel.loadNextPhotoLibraryBatchIfNeeded(currentPhoto: photo, using: generationService.photos)
                    }
                }

                if viewModel.isLoadingPhotoLibraryImages {
                    ProgressView()
                        .frame(width: 72, height: 72)
                }
            }
            .padding()
        }
        .frame(width: 360, height: 360)
    }

    private func canvasSection(canvasDimension: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                Color.white

                if viewModel.useTwoImageWorkflow,
                   let selectedPhotoLibraryDisplayImage = viewModel.selectedPhotoLibraryDisplayImage {
                    Image(uiImage: selectedPhotoLibraryDisplayImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: canvasDimension, height: canvasDimension)
                        .clipped()
                }

                PencilCanvasView(
                    drawing: $viewModel.drawing,
                    showTooltip: $viewModel.showTooltip,
                    contentSize: $viewModel.canvasSize,
                    opaque: !viewModel.useTwoImageWorkflow
                )
                
                if viewModel.loading {
                    LoadingView()
                        .frame(maxWidth: .infinity, minHeight: 120)
                }
            }
            .frame(width: canvasDimension, height: canvasDimension)
            .border(.secondary)
            
        }
    }

    private func photoLibrarySelectionView() -> some View {
        Button("Pick Image") {
            viewModel.loadPhotoLibraryImages(using: generationService.photos)
            showingPhotoLibraryPopover = true
        }
        .buttonStyle(.bordered)
        .disabled(viewModel.loading)
        .popover(isPresented: $showingPhotoLibraryPopover) {
            photoLibraryPopover
        }
    }

    private func outputSection(maxImageHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {

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
        .background(
            RoundedRectangle(cornerRadius: 15)
                .fill(.white)
        )
    }
}

@MainActor
@Observable
private class ComfyUITestViewModel {
    private static let oneImageDefaultPrompt = "make realistic"
    private static let twoImageDefaultPrompt = "stylize image 2 with the colors and theme of image 1"
    private static let photoLibraryBatchSize = 40

    var prompt = oneImageDefaultPrompt
    var seed = randomSeed()
    var promptId = UUID().uuidString.lowercased()
    var drawing: PKDrawing?
    var showTooltip = true
    var canvasSize = 512
    var loading = false
    var useTwoImageWorkflow = false
    var usePhotoLibraryDepthImage = false
    var photoLibraryImages = [PhotoLibraryService.PhotoLibraryImage]()
    var isLoadingPhotoLibraryImages = false
    var canLoadMorePhotoLibraryImages = true
    var selectedPhotoLibraryImageId: String?
    var selectedPhotoLibraryDisplayImage: UIImage?
    private var selectedPhotoLibraryImage: PhotoLibraryService.PhotoLibraryImage?
    private var photoLibraryDepthImagesById = [String: UIImage]()
    private var pickedPhotoInputImage: InputImage?
    var image: UIImage?
    var imagePaths = [String]()
    var inputImagePath: String?
    var uploadedInputFilename: String?
    var error: String?

    init(workflow: ComfyUITestWorkflow = .one, history: ImageHistoryModel? = nil, generationService: GenerationService? = nil) {
        guard let history, let generationService else {
            if workflow == .two {
                prompt = Self.twoImageDefaultPrompt
                useTwoImageWorkflow = true
            }
            return
        }

        prompt = history.prompt
        seed = Int64(history.seed)
        useTwoImageWorkflow = history.inputFilePaths.count > 1
        usePhotoLibraryDepthImage = history.negativePrompt?.localizedCaseInsensitiveContains("depth") == true
        inputImagePath = history.inputFilePaths.first

        if let drawingFilePath = history.drawingFilePath {
            drawing = generationService.fileService.load(path: drawingFilePath)
        }

        if let outputFilePath = history.outputFilePath {
            image = generationService.fileService.loadImage(path: outputFilePath)
            imagePaths = [outputFilePath]
        }

        do {
            if history.inputFilePaths.indices.contains(1) {
                let secondInputImage = generationService.fileService.loadImage(path: history.inputFilePaths[1])
                pickedPhotoInputImage = try inputImage(from: secondInputImage, filenamePrefix: "comfy-history-input")
                selectedPhotoLibraryDisplayImage = secondInputImage
                selectedPhotoLibraryImageId = history.inputFilePaths[1]
            }
        } catch {
            self.error = error.localizedDescription
        }
    }


    func resetPromptId() {
        promptId = UUID().uuidString.lowercased()
    }

    func randomizeSeed() {
        seed = Self.randomSeed()
    }

    func setTwoImageWorkflow(_ enabled: Bool, using generationService: GenerationService) {
        useTwoImageWorkflow = enabled
        if enabled, prompt == Self.oneImageDefaultPrompt {
            prompt = Self.twoImageDefaultPrompt
        } else if !enabled, prompt == Self.twoImageDefaultPrompt {
            prompt = Self.oneImageDefaultPrompt
        }
    }

    func loadPhotoLibraryImages(using photoLibraryService: PhotoLibraryService) {
        guard photoLibraryImages.isEmpty else {
            return
        }

        canLoadMorePhotoLibraryImages = true
        loadNextPhotoLibraryImages(using: photoLibraryService)
    }

    func loadNextPhotoLibraryBatchIfNeeded(currentPhoto photo: PhotoLibraryService.PhotoLibraryImage, using photoLibraryService: PhotoLibraryService) {
        guard photo.id == photoLibraryImages.last?.id else {
            return
        }

        loadNextPhotoLibraryImages(using: photoLibraryService)
    }

    private func loadNextPhotoLibraryImages(using photoLibraryService: PhotoLibraryService) {
        guard !isLoadingPhotoLibraryImages, canLoadMorePhotoLibraryImages else {
            return
        }

        photoLibraryService.checkAuthStatus()
        guard photoLibraryService.canAccess else {
            error = "Photo library access is required to pick a second image."
            return
        }

        isLoadingPhotoLibraryImages = true
        let offset = photoLibraryImages.count

        Task {
            var loadedCount = 0
            var loadedPhotoIds = Set(photoLibraryImages.map(\.id))

            for await photo in photoLibraryService.getImages(limit: Self.photoLibraryBatchSize, offset: offset, size: CGSize(width: 512, height: 512)) {
                guard !loadedPhotoIds.contains(photo.id) else {
                    continue
                }

                loadedPhotoIds.insert(photo.id)
                photoLibraryImages.append(photo)
                loadedCount += 1

                if usePhotoLibraryDepthImage {
                    loadDepthImage(for: photo, using: photoLibraryService)
                }
            }

            canLoadMorePhotoLibraryImages = loadedCount == Self.photoLibraryBatchSize
            isLoadingPhotoLibraryImages = false
        }
    }

    func setUsePhotoLibraryDepthImage(_ enabled: Bool, using generationService: GenerationService) {
        usePhotoLibraryDepthImage = enabled
        if enabled {
            loadDepthImages(using: generationService.photos)
        }
        guard let selectedPhotoLibraryImage else {
            selectedPhotoLibraryDisplayImage = nil
            pickedPhotoInputImage = nil
            return
        }
        selectPhotoLibraryImage(selectedPhotoLibraryImage, using: generationService)
    }

    func photoLibraryDisplayImage(for photo: PhotoLibraryService.PhotoLibraryImage) -> UIImage? {
        if usePhotoLibraryDepthImage {
            return photoLibraryDepthImagesById[photo.id]
        }
        return photo.image
    }

    func selectPhotoLibraryImage(_ photo: PhotoLibraryService.PhotoLibraryImage, using generationService: GenerationService) {
        selectedPhotoLibraryImage = photo
        selectedPhotoLibraryImageId = photo.id
        error = nil

        if let displayImage = photoLibraryDisplayImage(for: photo) {
            prepareSelectedPhotoLibraryImage(displayImage)
        } else if usePhotoLibraryDepthImage {
            loadDepthImage(for: photo, using: generationService.photos, selectWhenLoaded: true)
        } else {
            selectedPhotoLibraryDisplayImage = nil
            pickedPhotoInputImage = nil
        }
    }

    private func loadDepthImages(using photoLibraryService: PhotoLibraryService) {
        for photo in photoLibraryImages {
            loadDepthImage(for: photo, using: photoLibraryService)
        }
    }

    private func loadDepthImage(for photo: PhotoLibraryService.PhotoLibraryImage, using photoLibraryService: PhotoLibraryService, selectWhenLoaded: Bool = false) {
        guard photoLibraryDepthImagesById[photo.id] == nil else {
            if selectWhenLoaded, let depthImage = photoLibraryDepthImagesById[photo.id] {
                prepareSelectedPhotoLibraryImage(depthImage)
            }
            return
        }

        Task {
            guard let imageWithDepth = await photoLibraryService.getDepth(identifier: photo.id),
                  let depthImage = imageWithDepth.depth ?? imageWithDepth.estimatedDepth else {
                if selectWhenLoaded {
                    error = "The selected photo does not have a depth image."
                    selectedPhotoLibraryDisplayImage = nil
                    pickedPhotoInputImage = nil
                }
                return
            }

            photoLibraryDepthImagesById[photo.id] = depthImage
            if selectWhenLoaded, selectedPhotoLibraryImageId == photo.id {
                prepareSelectedPhotoLibraryImage(depthImage)
            }
        }
    }

    private func prepareSelectedPhotoLibraryImage(_ image: UIImage) {
        do {
            let filenamePrefix = usePhotoLibraryDepthImage ? "comfy-depth" : "comfy-photo"
            pickedPhotoInputImage = try inputImage(from: image, filenamePrefix: filenamePrefix)
            selectedPhotoLibraryDisplayImage = image
        } catch {
            self.error = error.localizedDescription
            pickedPhotoInputImage = nil
            selectedPhotoLibraryDisplayImage = nil
            selectedPhotoLibraryImageId = nil
        }
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
        let useTwoImageWorkflow = useTwoImageWorkflow
        let pickedPhotoInputImage = pickedPhotoInputImage
        let drawing = drawing
        var inputFilePaths = [generationService.fileService.save(image: inputImage.image)]
        if let pickedPhotoInputImage {
            inputFilePaths.append(generationService.fileService.save(image: pickedPhotoInputImage.image))
        }
        let historyId = UUID().uuidString
        var history = ImageHistoryModel(
            id: historyId,
            start: Date.now,
            prompt: prompt,
            negativePrompt: useTwoImageWorkflow ? "Flux2 Klein 2 image edit" : "Flux2 Klein image edit",
            model: "ComfyUI Flux2 Klein 4B",
            sampler: "euler",
            steps: 4,
            size: 512,
            seed: Int(seed),
            inputFilePaths: inputFilePaths,
            drawingFilePath: drawing.map { generationService.fileService.save(drawing: $0) },
            session: clientId,
            sequence: 0,
            loras: []
        )
        self.promptId = promptId

        if useTwoImageWorkflow, pickedPhotoInputImage == nil {
            self.error = "Pick a second image before generating."
            loading = false
            return
        }

        Task {
            do {
                let drawingUpload = try await generationService.comfyUIClient.uploadImage(
                    inputImage.data,
                    filename: inputImage.filename,
                    type: .input,
                    overwrite: false
                )
                uploadedInputFilename = drawingUpload.name

                let messageStream = try await generationService.comfyUIClient.messages(clientId: clientId)
                if useTwoImageWorkflow, let pickedPhotoInputImage {
                    let pickedPhotoUpload = try await generationService.comfyUIClient.uploadImage(
                        pickedPhotoInputImage.data,
                        filename: pickedPhotoInputImage.filename,
                        type: .input,
                        overwrite: false
                    )
                    _ = try await generationService.comfyUIClient.submitImageFlux2Klein2ImageEdit(
                        prompt: prompt,
                        seed: seed,
                        firstImageFilename: drawingUpload.name,
                        secondImageFilename: pickedPhotoUpload.name,
                        clientId: clientId,
                        promptId: promptId
                    )
                } else {
                    _ = try await generationService.comfyUIClient.submitImageFlux2KleinImageEdit(
                        prompt: prompt,
                        seed: seed,
                        imageFilename: drawingUpload.name,
                        clientId: clientId,
                        promptId: promptId
                    )
                }
                try await waitForImageEditCompletion(promptId: promptId, messages: messageStream)

                let outputs = try await generationService.comfyUIClient.imageOutputPaths(promptId: promptId)
                let paths = outputs.keys.sorted().flatMap { outputs[$0] ?? [] }
                imagePaths = paths

                if let firstPath = paths.first, let loadedImage = UIImage(contentsOfFile: firstPath) {
                    image = loadedImage
                    history.outputFilePath = generationService.fileService.save(image: loadedImage)
                    history.end = Date.now
                } else {
                    error = "No image output returned."
                    history.errorDescription = "No image output returned."
                    history.end = Date.now
                }
            } catch {
                self.error = error.localizedDescription
                history.errorDescription = error.localizedDescription
                history.end = Date.now
            }

            generationService.db.save(history: history)
            generationService.imageHistory.append(history)
            generationService.lastHistory = history
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
        return try inputImage(from: renderedImage, filenamePrefix: "comfy-input")
    }

    private func inputImage(from image: UIImage, filenamePrefix: String) throws -> InputImage {
        guard let processedImage = Self.centerCroppedImage(image, sideLength: 512),
              let data = processedImage.pngData() else {
            throw APIError.requestError("could not prepare input image")
        }

        let filename = "\(filenamePrefix)-\(UUID().uuidString.lowercased()).png"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ComfyUIInputImages", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent(filename)
        try data.write(to: fileURL)
        return InputImage(image: processedImage, data: data, filename: filename, path: fileURL.path())
    }

    private static func centerCroppedImage(_ image: UIImage, sideLength: CGFloat) -> UIImage? {
        guard image.size.width > 0, image.size.height > 0 else {
            return nil
        }

        let outputSize = CGSize(width: sideLength, height: sideLength)
        let scale = max(sideLength / image.size.width, sideLength / image.size.height)
        let scaledSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let origin = CGPoint(x: (sideLength - scaledSize.width) / 2, y: (sideLength - scaledSize.height) / 2)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1

        return UIGraphicsImageRenderer(size: outputSize, format: format).image { _ in
            image.draw(in: CGRect(origin: origin, size: scaledSize))
        }
    }

    private static func randomSeed() -> Int64 {
        Int64.random(in: 0...999_999_999_999_999)
    }

    private struct InputImage {
        let image: UIImage
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

//
//  GenerationService.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2024-04-01.
//

import Foundation
import Observation
import SwiftUI
import PencilKit

private let generationLogger = LoggingService.shared.generation

@MainActor
@Observable
class GenerationService {
    
    var llmClient = LargeLangageModelClient()
    var stableDiffusionClient = StableDiffusionClient()
    var comfyUIClient = ComfyUIClient()
    var mlService = MLService()
    
    var fileService = FileService()
    var db = DatabaseService()
    var photos = PhotoLibraryService()
    
    static let statusCheckInterval = 2.0
    private static let comfyUIClientIdKey = "comfyUIClientId"
    
    public init() {}
    
    var comfyUIClientId: String {
        get {
            if let savedClientId = UserDefaults.standard.string(forKey: GenerationService.comfyUIClientIdKey) {
                let normalizedClientId = savedClientId.lowercased()
                if normalizedClientId != savedClientId {
                    UserDefaults.standard.set(normalizedClientId, forKey: GenerationService.comfyUIClientIdKey)
                }
                return normalizedClientId
            }
            let clientId = UUID().uuidString.lowercased()
            UserDefaults.standard.set(clientId, forKey: GenerationService.comfyUIClientIdKey)
            return clientId
        }
        set {
            UserDefaults.standard.set(newValue.lowercased(), forKey: GenerationService.comfyUIClientIdKey)
        }
    }
    
    struct ConnectionStatus {
        var connected: Bool
        var lastChecked: Date
        var service: Service
        var error: String?
    }
    
    struct LoraInvocation: Identifiable, Hashable, Sendable {
        var id: String {
            name
        }
        var name: String
        var weight: Double
        var activation: String?
        
        var bracketSteps: Int = 0
        var bracketMin: Double = 0
        var bracketMax: Double = 0
        
        var description: String {
            "\(name) \(weight.formatted(.number.precision(.fractionLength(0...2))))"
        }
        
        var increment: Double {
            guard bracketSteps > 0 else {
                return 0
            }
            
            return (bracketMax - bracketMin) / Double(bracketSteps - 1)
        }
        
        mutating func calculateWeight(step: Int) {
            weight = bracketMin + (increment * Double(step))
        }
    }
    
    enum Service {
        case stableDiffusion
        case largeLanguageModel
        case comfyUI
    }
    
    var llmStatus = ConnectionStatus(connected: false, lastChecked: .distantPast, service: .largeLanguageModel)
    var sdStatus = ConnectionStatus(connected: false, lastChecked: .distantPast, service: .stableDiffusion)
    var comfyUIStatus = ConnectionStatus(connected: false, lastChecked: .distantPast, service: .comfyUI)
    var comfyUIConnectionInfo: ComfyUIClient.ConnectionInfo?
    var comfyUISystemStatus: ComfyUIClient.SystemStatus?
    var comfyUIModels: [String: [String]] = [:]
    
    var sdModels: [StableDiffusionClient.Model] = []
    var llmModels: [LargeLangageModelClient.Model] = []
    var selectedSDModel: StableDiffusionClient.Model?
    var selectedLLMModel: LargeLangageModelClient.Model?
    var sdLoras: [StableDiffusionClient.Lora] = []
    var sdSamplers: [StableDiffusionClient.Sampler] = []
    var selectedSampler = StableDiffusionClient.defaultSampler // default
    var controlNetModels: [String] = []
    var controlNetModules: [String] = []
    
    var LLMHistory = [LLMHistoryEntry]()
    var imageHistory = [ImageHistoryModel]()
    var lastHistory: ImageHistoryModel?

    enum HistorySyncPhase: Equatable, Sendable {
        case fetching
        case processing(completed: Int, total: Int)
    }

    private(set) var historySyncPhase: HistorySyncPhase?
    
    var imageSize = 512
    var steps = 20
    
    private(set) var statusTask: Task<Void, Never>?
    private(set) var modelTask: Task<Void, Never>?
    private(set) var comfyUIModelsTask: Task<Void, Never>?
    private(set) var embeddingMigrationTask: Task<Void, Never>?
    private(set) var historySyncTask: Task<Void, Never>?
    
    private var storedPrompt: String?
    
    //MARK: - History
    
    func loadHistory() {
        imageHistory = db.loadHistory()
    }

    func logStartupSummary() {
        let inputFileCount = imageHistory.reduce(0) { $0 + $1.inputFilePaths.count }
        let outputFileCount = imageHistory.reduce(0) { $0 + ($1.outputFilePath == nil ? 0 : 1) }
        let progress = historySyncTask == nil ? "idle" : "scheduled"
        generationLogger.info("Startup summary historyRecords=\(self.imageHistory.count, privacy: .public) cachedImages=\(self.fileService.imageCacheFileCount(), privacy: .public) progress=\(progress, privacy: .public) inputFiles=\(inputFileCount, privacy: .public) outputFiles=\(outputFileCount, privacy: .public)")
    }

    func synchronizeComfyUIHistoryOnStartup() {
        guard historySyncTask == nil else {
            return
        }

        historySyncTask = Task { @MainActor [weak self] in
            guard let self else { return }
            historySyncPhase = .fetching
            defer {
                historySyncPhase = nil
                historySyncTask = nil
            }

            do {
                let serverHistory = try await comfyUIClient.typedHistory()
                let candidates = serverHistory.values
                    .compactMap { self.historyCandidate(from: $0) }
                    .sorted { $0.start < $1.start }

                historySyncPhase = .processing(completed: 0, total: candidates.count)
                generationLogger.debug("ComfyUI history sync progress 0/\(candidates.count, privacy: .public)")
                var completed = 0
                let assetCache = HistoryAssetCache()

                for candidate in candidates {
                    do {
                        try await synchronize(candidate: candidate, assetCache: assetCache)
                    } catch {
                        generationLogger.error("ComfyUI history sync failed for \(candidate.promptId, privacy: .private(mask: .hash)): \(String(describing: error), privacy: .private)")
                    }
                    completed += 1
                    historySyncPhase = .processing(completed: completed, total: candidates.count)
                    generationLogger.debug("ComfyUI history sync progress \(completed, privacy: .public)/\(candidates.count, privacy: .public)")
                }
            } catch {
                generationLogger.error("ComfyUI history sync failed: \(String(describing: error), privacy: .private)")
            }

            historySyncPhase = nil
            migrateHistoryEmbeddingsOnStartup()
        }
    }

    private struct HistoryCandidate: Sendable {
        let promptId: String
        let prompt: String
        let negativePrompt: String
        let model: String
        let sampler: String
        let steps: Int
        let seed: Int
        let start: Date
        let end: Date
        let session: String
        let inputReferences: [ImageReference]
        let outputReference: ImageReference

        struct ImageReference: Sendable {
            let filename: String
            let subfolder: String
            let type: ComfyUIClient.ViewImageType
        }
    }

    private final class HistoryAssetCache {
        var paths = [String: String]()
    }

    private enum HistoryWorkflowDefinition {
        case oneImage
        case twoImages

        var nodeTypes: [String: String] {
            switch self {
            case .oneImage:
                return ["76": "LoadImage", "9": "SaveImage", "75:74": "CLIPTextEncode", "75:73": "RandomNoise", "75:62": "Flux2Scheduler", "75:61": "KSamplerSelect", "75:70": "UNETLoader"]
            case .twoImages:
                return ["76": "LoadImage", "81": "LoadImage", "94": "SaveImage", "92:109": "CLIPTextEncode", "92:106": "RandomNoise", "92:102": "Flux2Scheduler", "92:101": "KSamplerSelect", "92:107": "UNETLoader"]
            }
        }

        var inputNodeIds: [String] {
            switch self {
            case .oneImage: return ["76"]
            case .twoImages: return ["76", "81"]
            }
        }

        var outputNodeId: String {
            switch self {
            case .oneImage: return "9"
            case .twoImages: return "94"
            }
        }

        var promptNodeId: String {
            switch self {
            case .oneImage: return "75:74"
            case .twoImages: return "92:109"
            }
        }

        var seedNodeId: String {
            switch self {
            case .oneImage: return "75:73"
            case .twoImages: return "92:106"
            }
        }

        var stepsNodeId: String {
            switch self {
            case .oneImage: return "75:62"
            case .twoImages: return "92:102"
            }
        }

        var samplerNodeId: String {
            switch self {
            case .oneImage: return "75:61"
            case .twoImages: return "92:101"
            }
        }

        var modelNodeId: String {
            switch self {
            case .oneImage: return "75:70"
            case .twoImages: return "92:107"
            }
        }

        var negativePrompt: String {
            switch self {
            case .oneImage: return "Flux2 Klein image edit"
            case .twoImages: return "Flux2 Klein 2 image edit"
            }
        }
    }

    private func historyCandidate(from record: ComfyUIClient.HistoryRecord) -> HistoryCandidate? {
        guard record.status.statusStr == "success",
              record.status.completed else {
            return nil
        }

        guard let definition = [HistoryWorkflowDefinition.oneImage, .twoImages].first(where: { definition in
            definition.nodeTypes.allSatisfy { nodeId, classType in
                record.prompt.workflow[nodeId]?.classType == classType
            }
        }) else {
            return nil
        }

        func scalar(_ nodeId: String, _ key: String) -> ComfyUIClient.HistoryRecord.JSONValue? {
            record.prompt.workflow[nodeId]?.inputs[key]
        }

        guard let prompt = scalar(definition.promptNodeId, "text")?.stringValue,
              let model = scalar(definition.modelNodeId, "unet_name")?.stringValue,
              let sampler = scalar(definition.samplerNodeId, "sampler_name")?.stringValue,
              let steps = scalar(definition.stepsNodeId, "steps")?.int64Value,
              let seed = scalar(definition.seedNodeId, "noise_seed")?.int64Value,
              let createTime = record.prompt.createTime,
              let output = record.outputs[definition.outputNodeId]?.images?.first,
              let start = date(milliseconds: createTime) else {
            return nil
        }

        let inputReferences = definition.inputNodeIds.compactMap { nodeId -> HistoryCandidate.ImageReference? in
            guard let reference = scalar(nodeId, "image")?.stringValue else { return nil }
            let components = reference.split(separator: "/", omittingEmptySubsequences: true)
            guard let filename = components.last else { return nil }
            return HistoryCandidate.ImageReference(
                filename: String(filename),
                subfolder: components.dropLast().joined(separator: "/"),
                type: .input
            )
        }

        guard inputReferences.count == definition.inputNodeIds.count,
              let end = executionSuccessDate(record) ?? date(milliseconds: createTime) else {
            return nil
        }

        return HistoryCandidate(
            promptId: record.prompt.promptId.lowercased(),
            prompt: prompt,
            negativePrompt: definition.negativePrompt,
            model: model,
            sampler: sampler,
            steps: Int(steps),
            seed: Int(seed),
            start: start,
            end: end,
            session: record.prompt.clientId ?? "comfyui-import",
            inputReferences: inputReferences,
            outputReference: HistoryCandidate.ImageReference(filename: output.filename, subfolder: output.subfolder, type: output.type)
        )
    }

    private func executionSuccessDate(_ record: ComfyUIClient.HistoryRecord) -> Date? {
        for message in record.status.messages {
            guard message.count > 1,
                  message[0].stringValue == "execution_success",
                  case .object(let data) = message[1],
                  data["timestamp"]?.int64Value != nil else {
                continue
            }
            return date(milliseconds: data["timestamp"]!.int64Value!)
        }
        return nil
    }

    private func date(milliseconds: Int64) -> Date? {
        guard milliseconds > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
    }

    private func synchronize(candidate: HistoryCandidate, assetCache: HistoryAssetCache) async throws {
        let local = imageHistory.first { $0.promptId?.lowercased() == candidate.promptId }
        var inputPaths = local?.inputFilePaths ?? []

        for (index, reference) in candidate.inputReferences.enumerated() {
            if inputPaths.indices.contains(index), fileService.imageExists(path: inputPaths[index]) {
                continue
            }
            let path = try await downloadAndSave(reference: reference, cache: assetCache)
            if inputPaths.indices.contains(index) {
                inputPaths[index] = path
            } else {
                inputPaths.append(path)
            }
        }

        var outputPath = local?.outputFilePath
        if !fileService.imageExists(path: outputPath) {
            outputPath = try await downloadAndSave(reference: candidate.outputReference, cache: assetCache)
        }

        if var local {
            guard local.inputFilePaths != inputPaths || local.outputFilePath != outputPath else { return }
            local.inputFilePaths = inputPaths
            local.outputFilePath = outputPath
            db.updateAssets(history: local)
            replaceHistory(local)
            return
        }

        guard let outputPath else { return }
        let size = imageSize(path: inputPaths.first)
        let promptEmbedding = try? await mlService.textEmbedding(for: candidate.prompt)
        let inputEmbedding: [Float]?
        if inputPaths.count > 1 {
            inputEmbedding = try? await mlService.combinedImageEmbedding(for: inputPaths.map { fileService.loadImage(path: $0) })
        } else if let inputPath = inputPaths.first {
            inputEmbedding = try? await mlService.imageEmbedding(for: fileService.loadImage(path: inputPath))
        } else {
            inputEmbedding = nil
        }
        let outputEmbedding = try? await mlService.imageEmbedding(for: fileService.loadImage(path: outputPath))
        let imported = ImageHistoryModel(
            id: UUID().uuidString,
            start: candidate.start,
            end: candidate.end,
            prompt: candidate.prompt,
            promptId: candidate.promptId,
            promptEmbedding: promptEmbedding,
            negativePrompt: candidate.negativePrompt,
            model: candidate.model,
            sampler: candidate.sampler,
            steps: candidate.steps,
            size: size,
            seed: candidate.seed,
            inputFilePaths: inputPaths,
            inputEmbedding: inputEmbedding,
            outputFilePath: outputPath,
            outputEmbedding: outputEmbedding,
            session: candidate.session,
            sequence: 0,
            loras: []
        )
        db.save(history: imported)
        imageHistory.append(imported)
    }

    private func downloadAndSave(reference: HistoryCandidate.ImageReference, cache: HistoryAssetCache) async throws -> String {
        let key = "\(reference.type.rawValue)|\(reference.subfolder)|\(reference.filename)"
        if let cached = cache.paths[key] {
            return cached
        }
        let data = try await comfyUIClient.imageData(named: reference.filename, subfolder: reference.subfolder, type: reference.type)
        guard let path = fileService.save(imageData: data) else {
            throw APIError.requestError("unable to save ComfyUI image \(reference.filename)")
        }
        cache.paths[key] = path
        return path
    }

    private func imageSize(path: String?) -> Int {
        guard let path else { return 512 }
        let image = fileService.loadImage(path: path)
        if let cgImage = image.cgImage {
            return max(cgImage.width, cgImage.height)
        }
        return max(Int(image.size.width), Int(image.size.height))
    }

    private func replaceHistory(_ history: ImageHistoryModel) {
        if let index = imageHistory.firstIndex(where: { $0.id == history.id }) {
            imageHistory[index] = history
        }
        if lastHistory?.id == history.id {
            lastHistory = history
        }
    }
    
    func migrateHistoryEmbeddingsOnStartup() {
        guard embeddingMigrationTask == nil else {
            return
        }
        
        embeddingMigrationTask = Task {
            do {
                try await mlService.waitUntilLoaded()
                await migrateHistoryEmbeddings()
            } catch {
                generationLogger.error("History embedding migration failed: \(String(describing: error), privacy: .private)")
            }
            embeddingMigrationTask = nil
        }
    }
    
    private func migrateHistoryEmbeddings() async {
        let combinedInputMigrationKey = "combined-two-photo-input-embedding-v1"
        let shouldMigrateCombinedInputs = !UserDefaults.standard.bool(forKey: combinedInputMigrationKey)
        for index in imageHistory.indices {
            var history = imageHistory[index]
            var didUpdate = false
            let forceUpdate = false
            
            if (history.promptEmbedding == nil || forceUpdate) {
                history.promptEmbedding = try? await mlService.textEmbedding(for: history.prompt)
                didUpdate = history.promptEmbedding != nil
            }
            
            if (history.inputEmbedding == nil || forceUpdate || (shouldMigrateCombinedInputs && isTwoPhotoHistory(history))) {
                if isTwoPhotoHistory(history) {
                    let inputImages = history.inputFilePaths.map { fileService.loadImage(path: $0) }
                    history.inputEmbedding = try? await mlService.combinedImageEmbedding(for: inputImages)
                } else if let inputImage = embeddingInputImage(for: history) {
                    history.inputEmbedding = try? await mlService.imageEmbedding(for: inputImage)
                }
                didUpdate = didUpdate || history.inputEmbedding != nil
            }
            
            if (history.outputEmbedding == nil || forceUpdate),
               let outputFilePath = history.outputFilePath {
                let outputImage = fileService.loadImage(path: outputFilePath)
                history.outputEmbedding = try? await mlService.imageEmbedding(for: outputImage)
                didUpdate = didUpdate || history.outputEmbedding != nil
            }
            
            guard didUpdate else {
                continue
            }
            
            db.updateEmbeddings(history: history)
            imageHistory[index] = history
            if lastHistory?.id == history.id {
                lastHistory = history
            }
        }
        UserDefaults.standard.set(true, forKey: "combined-two-photo-input-embedding-v1")
    }

    private func isTwoPhotoHistory(_ history: ImageHistoryModel) -> Bool {
        history.drawingFilePath == nil &&
        history.inputFilePaths.count >= 2 &&
        history.negativePrompt == "Flux2 Klein 2 image edit"
    }
    
    private func embeddingInputImage(for history: ImageHistoryModel) -> UIImage? {
        if history.inputFilePaths.indices.contains(1) {
            return fileService.loadImage(path: history.inputFilePaths[1])
        }
        guard let inputFilePath = history.inputFilePaths.first else {
            return nil
        }
        return fileService.loadImage(path: inputFilePath)
    }
    
    func searchHistory(query: String) async throws -> [ImageHistoryModel] {
        
        let clock = ContinuousClock()
        let start = clock.now
        defer {
            let duration = clock.now - start
            generationLogger.debug("Search took \(duration.formatted(.units(allowed: [.seconds, .milliseconds])), privacy: .public)")
        }
        
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return imageHistory.reversed()
        }
        
        let queryEmbedding = try await mlService.textEmbedding(for: trimmedQuery)
        let scores = imageHistory.compactMap { history -> (history: ImageHistoryModel, score: Float)? in
            let embeddings = [/*history.promptEmbedding,*/ history.inputEmbedding, history.outputEmbedding].compactMap { $0 }
            let score = embeddings.compactMap { embedding in
                try? MLService.cosineSimilarity(queryEmbedding, embedding)
            }.max()
            guard let score else {
                return nil
            }
            return (history, score)
        }
        .filter {
            $0.score > 0.2
        }
        .sorted { lhs, rhs in
            lhs.score > rhs.score
        }
        
        return scores.map(\.history)
    }
    
    func loadOutputImage(history: ImageHistoryModel) -> UIImage {
        return fileService.loadImage(path: history.outputFilePath ?? "") // TODO: error handling
    }
    
    func loadInputImage(history: ImageHistoryModel) -> UIImage {
        return fileService.loadImage(path: history.inputFilePaths.first ?? "") // TODO: error handling
    }

    func loadInputImages(history: ImageHistoryModel) -> [UIImage] {
        history.inputFilePaths.map { fileService.loadImage(path: $0) }
    }

    func loadDepthImage(history: ImageHistoryModel) -> UIImage {
        return fileService.loadImage(path: history.depthFilePath ?? "") // TODO: error handling
    }
    
    func loadDrawing(history: ImageHistoryModel) -> PKDrawing {
        return fileService.load(path: history.drawingFilePath ?? "") // TODO: error handling
    }
    
    func lastPrompt() -> String {
        // TODO: Persist last prompt
        return storedPrompt ?? "A cat with a fancy hat"
    }
    
    func promptsFromHistory() -> [String] {
        var result = Set<String>()
        for h in imageHistory {
            result.insert(h.prompt)
        }
        return result.sorted()
    }
    
    func modelsFromHistory() -> [String] {
        var result = Set<String>()
        for h in imageHistory {
            result.insert(h.model)
        }
        return result.sorted()
    }
    
    func lorasFromHistory() -> [String] {
        var result = Set<String>()
        for h in imageHistory {
            for lora in h.loras {
                result.insert(lora.name)
            }
        }
        return result.sorted()
    }
    
    //MARK: - Status & Models

    func checkStatus() {
        
        guard statusTask == nil else {
            return
        }
        
        statusTask = Task.init {
            
//            do {
//                llmStatus = ConnectionStatus(connected: try await llmClient.testConnection(), lastChecked: Date.now, service: .largeLanguageModel)
//            } catch {
//                llmStatus = ConnectionStatus(connected: false, lastChecked: Date.now, service: .largeLanguageModel, error: error.localizedDescription)
//            }
//            
//            do {
//                sdStatus = ConnectionStatus(connected: try await stableDiffusionClient.testConnection(), lastChecked: Date.now, service: .stableDiffusion)
//            } catch {
//                sdStatus = ConnectionStatus(connected: false, lastChecked: Date.now, service: .stableDiffusion, error: error.localizedDescription)
//            }
            
            do {
                let systemStats = try await comfyUIClient.systemStats()
                comfyUIConnectionInfo = systemStats.connection
                comfyUISystemStatus = systemStats.status
                comfyUIStatus = ConnectionStatus(connected: systemStats.connection.connected, lastChecked: Date.now, service: .comfyUI)
            } catch {
                comfyUIConnectionInfo = nil
                comfyUISystemStatus = nil
                comfyUIStatus = ConnectionStatus(connected: false, lastChecked: Date.now, service: .comfyUI, error: error.localizedDescription)
            }

            statusTask = nil
        }
    }
    
    func checkStatusIfNeeded() {
        
        guard abs(llmStatus.lastChecked.timeIntervalSinceNow) > GenerationService.statusCheckInterval &&
                abs(sdStatus.lastChecked.timeIntervalSinceNow) > GenerationService.statusCheckInterval &&
                abs(comfyUIStatus.lastChecked.timeIntervalSinceNow) > GenerationService.statusCheckInterval else {
            return
        }
        
        checkStatus()
    }
    
    func getComfyUIModels() {
        guard comfyUIModelsTask == nil else {
            return
        }
        
        comfyUIModelsTask = Task {
            do {
                let modelTypes = try await comfyUIClient.modelFolders()
                var modelsByType = [String: [String]]()
                
                for modelType in modelTypes {
                    let models = try await comfyUIClient.models(in: modelType)
                    if !models.isEmpty {
                        modelsByType[modelType] = models
                    }
                }
                
                comfyUIModels = modelsByType
            } catch {
                generationLogger.error("Model refresh failed: \(String(describing: error), privacy: .private)")
            }
            
            comfyUIModelsTask = nil
        }
    }
    
    func getModels() {
        
        guard modelTask == nil else {
            return
        }
        
//        modelTask = Task {
//            
//            do {
//                sdModels = try await stableDiffusionClient.imageGenerationModels()
//                let options = try await stableDiffusionClient.imageGenerationOptions()
//                
//                selectedSDModel = sdModels.first { model in
//                    model.sha256 == options.sdCheckpointHash
//                }
//                                
////                llmModels = try await llmClient.getLocalModels()
////                selectedLLMModel = llmModels.first
//                
//                sdSamplers = try await stableDiffusionClient.samplers()
//                
//                sdLoras = try await stableDiffusionClient.loras()
//                
////                try await stableDiffusionClient.scriptInfo()
//                controlNetModels = try await stableDiffusionClient.controlNetModels()
//                controlNetModules = try await stableDiffusionClient.controlNetModules()
//                
//            } catch {
//                print(error)
//            }
//            
//            modelTask = nil
//        }
    }
    
    func setSelectedModel() {
        
        guard modelTask == nil else {
            return
        }
        
        guard let selectedSDModel = selectedSDModel else {
            generationLogger.warning("No image-generation model selected")
            return
        }
        
        modelTask = Task {
            do {
                try await stableDiffusionClient.setImageGenerationModel(model: selectedSDModel)
            } catch {
                generationLogger.error("Image-generation model selection failed: \(String(describing: error), privacy: .private)")
            }
            
            modelTask = nil
        }
    }
    
    //MARK: - Generation
    
    func text(prompt: String, result: Binding<String>, loading: Binding<Bool>) {
        
        guard let selectedLLMModel = selectedLLMModel else {
            return
        }
        
        Task.init {
            loading.wrappedValue = true
            result.wrappedValue = ""
            var history = LLMHistoryEntry(prompt: prompt, model: selectedLLMModel.name)
            do {
                for try await obj in await self.llmClient.asyncStreamGenerate(prompt: prompt, model: selectedLLMModel) {
                    if !obj.done {
                        result.wrappedValue += obj.response
                        history.result += obj.response
                    }
                }
            } catch {
                history.errorDescription = error.localizedDescription
                generationLogger.error("Generation failed: \(String(describing: error), privacy: .private)")
            }
            history.end = Date.now
            loading.wrappedValue = false
            LLMHistory.append(history)
        }
    }
    
    func image(prompt: String,
               promptAddon: String?,
               negativePrompt: String,
               loras: [LoraInvocation] = [],
               seed: Int,
               session: String,
               sequence: Int,
               drawing: PKDrawing,
               drawingScale: CGFloat,
               output: Binding<UIImage?>,
               progress: Binding<StableDiffusionClient.Progress?>,
               loading: Binding<Bool>) {
        
        loading.wrappedValue = true
        
        var image = drawing.image(from: CGRect(x: 0, y: 0, width: drawingScale, height: drawingScale), scale: 1.0)
        
        if imageSize != 512 { // TODO: canvas size instead of resizing
            image = image.resized(to: CGSize(width: imageSize, height: imageSize))
        }
        guard let base64Image = image.pngData()?.base64EncodedString() else {
            return
        }
        
        var sdOptions = StableDiffusionClient.GenerationOptions(prompt: prompt,
                                                                negativePrompt: negativePrompt,
                                                                size: imageSize,
                                                                steps: steps,
                                                                sampler: selectedSampler,
                                                                initImages: [base64Image])
        
        sdOptions.seed = seed
        storedPrompt = prompt
        
        Task.init {
            
            if selectedSDModel == nil {
                if modelTask == nil {
                    getModels()
                }
                _ = await modelTask?.result // TODO: handle error case
            }
            
            var fullPrompt = prompt
            if let promptAddon {
                fullPrompt += promptAddon
            }
            
            let id = NSUUID().uuidString
            var history = ImageHistoryModel(id: id,
                                            start: Date.now,
                                            prompt: fullPrompt,
                                            model: selectedSDModel?.modelName ?? "none",
                                            sampler: selectedSampler.name,
                                            steps: steps,
                                            size: imageSize,
                                            seed: seed,
                                            inputFilePaths: [fileService.save(image: image)],
                                            drawingFilePath: fileService.save(drawing: drawing),
                                            session: session,
                                            sequence: sequence,
                                            loras: loras.map({ lora in
                LoraHistoryModel(id: NSUUID().uuidString,
                                 name: lora.name,
                                 weight: lora.weight,
                                 historyModelId: id)
            }))
                        
    
            
            if loras.count > 0 {
                fullPrompt += " "
                fullPrompt += loras.map { lora in
                    promptAdd(lora: lora)
                }.joined(separator: " ")
            }

            sdOptions.prompt = fullPrompt
            
            do {
                let strings = try await stableDiffusionClient.generateBase64EncodedImages(sdOptions)
                
                if let string = strings.first,
                   let data = Data(base64Encoded: string),
                   let image = UIImage(data: data) {
                    output.wrappedValue = image
                    history.end = Date.now
                    history.outputFilePath = fileService.save(image: image)
                }
            } catch {
                history.errorDescription = error.localizedDescription
                generationLogger.error("Generation request failed: \(String(describing: error), privacy: .private)")
            }
            loading.wrappedValue = false

            db.save(history: history)
            imageHistory.append(history)
            lastHistory = history
        }
        
        Task.init {
            // TODO: inherit known values from options
            progress.wrappedValue = StableDiffusionClient.Progress(progress: 0, etaRelative: 0, state: StableDiffusionClient.Progress.State.initial())
            do {
                while loading.wrappedValue == true {
                    progress.wrappedValue = try await self.stableDiffusionClient.imageGenerationProgress()
                    try await Task.sleep(nanoseconds: 200_000_000)
                }
            } catch {
                generationLogger.error("Generation history update failed: \(String(describing: error), privacy: .private)")
            }
        }
    }
    
    func depth(prompt: String,
               loras: [LoraInvocation] = [],
               seed: Int,
               input: UIImage,
               depth: UIImage,
               mode: StableDiffusionClient.ControlNetOptions.ControlMode = .balanced,
               session: String,
               sequence: Int,
               output: Binding<UIImage?>,
               progress: Binding<StableDiffusionClient.Progress?>,
               loading: Binding<Bool>
    ) {
        loading.wrappedValue = true

        guard let base64Depth = depth.pngData()?.base64EncodedString() else {
            return
        }
        
        guard let base64Image = input.pngData()?.base64EncodedString() else {
            return
        }
        
        var controlNetOptions = StableDiffusionClient.ControlNetOptions(image: base64Depth)
        controlNetOptions.controlMode = mode
        var sdOptions = StableDiffusionClient.GenerationOptions(prompt: prompt,
                                                                size: imageSize,
                                                                steps: steps,
                                                                sampler: selectedSampler,
                                                                initImages: [base64Image],
                                                                controlNetOptions: controlNetOptions)
        sdOptions.seed = seed
        
        Task.init {
            
            if selectedSDModel == nil {
                if modelTask == nil {
                    getModels()
                }
                _ = await modelTask?.result // TODO: handle error case
            }
            
            var fullPrompt = prompt
            
            if loras.count > 0 {
                fullPrompt += " "
                fullPrompt += loras.map { lora in
                    promptAdd(lora: lora)
                }.joined(separator: " ")
            }

            sdOptions.prompt = fullPrompt
            
            
            let id = NSUUID().uuidString
            var history = ImageHistoryModel(id: id,
                                            start: Date.now,
                                            prompt: prompt,
                                            model: selectedSDModel?.modelName ?? "none",
                                            sampler: selectedSampler.name,
                                            steps: steps,
                                            size: imageSize,
                                            seed: seed,
                                            inputFilePaths: [fileService.save(image: input)],
                                            depthFilePath: fileService.save(image: depth),
                                            session: session,
                                            sequence: sequence,
                                            loras: loras.map({ lora in
                LoraHistoryModel(id: NSUUID().uuidString,
                                 name: lora.name,
                                 weight: lora.weight,
                                 historyModelId: id)
            }))
            
            do {
                let strings = try await stableDiffusionClient.generateBase64EncodedImages(sdOptions)
                
                if let string = strings.first,
                   let data = Data(base64Encoded: string),
                   let image = UIImage(data: data) {
                    output.wrappedValue = image
                    
                    history.end = Date.now
                    history.outputFilePath = fileService.save(image: image)
                }
            } catch {
                generationLogger.error("Generation history save failed: \(String(describing: error), privacy: .private)")
                history.errorDescription = error.localizedDescription
            }
            loading.wrappedValue = false
            db.save(history: history)
            imageHistory.append(history)
            lastHistory = history
        }
        
        Task.init {
            // TODO: inherit known values from options
            progress.wrappedValue = StableDiffusionClient.Progress(progress: 0, etaRelative: 0, state: StableDiffusionClient.Progress.State.initial())
            do {
                while loading.wrappedValue == true {
                    progress.wrappedValue = try await self.stableDiffusionClient.imageGenerationProgress()
                    try await Task.sleep(nanoseconds: 200_000_000)
                }
            } catch {
                generationLogger.error("Generation preparation failed: \(String(describing: error), privacy: .private)")
            }
        }
        
    }
    
    func inpaint(prompt: String,
                 negativePrompt: String,
                 loras: [LoraInvocation] = [],
                 seed: Int,
                 session: String,
                 sequence: Int,
                 maskDrawing: PKDrawing,
                 input: UIImage,
                 drawingScale: CGFloat,
                 inpaintOptions: StableDiffusionClient.SoftInpaintingOptions,
                 output: Binding<UIImage?>,
                 progress: Binding<StableDiffusionClient.Progress?>,
                 loading: Binding<Bool>) {
        
        loading.wrappedValue = true

        var mask = maskDrawing.image(from: CGRect(x: 0, y: 0, width: drawingScale, height: drawingScale), scale: 1.0)
        
        if imageSize != 512 { // TODO: canvas size instead of resizing
            mask = mask.resized(to: CGSize(width: imageSize, height: imageSize))
        }
        guard let base64Mask = mask.pngData()?.base64EncodedString() else {
            return
        }
        
        guard let base64Image = input.pngData()?.base64EncodedString() else {
            return
        }
        
        var sdOptions = StableDiffusionClient.GenerationOptions(prompt: prompt,
                                                                negativePrompt: negativePrompt,
                                                                size: imageSize,
                                                                steps: steps,
                                                                sampler: selectedSampler,
                                                                initImages: [base64Image],
                                                                mask: base64Mask,
                                                                inPaintingOptions: inpaintOptions)

        sdOptions.seed = seed
        storedPrompt = prompt
        
        Task.init {
            
            if selectedSDModel == nil {
                if modelTask == nil {
                    getModels()
                }
                _ = await modelTask?.result // TODO: handle error case
            }
            
            var fullPrompt = prompt
            
//            let id = NSUUID().uuidString
//            var history = ImageHistoryModel(id: id,
//                                            start: Date.now,
//                                            prompt: fullPrompt,
//                                            model: selectedSDModel?.modelName ?? "none",
//                                            sampler: selectedSampler.name,
//                                            steps: steps,
//                                            size: imageSize,
//                                            seed: seed,
//                                            inputFilePath: fileService.save(image: image),
//                                            drawingFilePath: fileService.save(drawing: drawing),
//                                            session: session,
//                                            sequence: sequence,
//                                            loras: loras.map({ lora in
//                LoraHistoryModel(id: NSUUID().uuidString,
//                                 name: lora.name,
//                                 weight: lora.weight,
//                                 historyModelId: id)
//            }))
                        
    
            
            if loras.count > 0 {
                fullPrompt += " "
                fullPrompt += loras.map { lora in
                    promptAdd(lora: lora)
                }.joined(separator: " ")
            }

            sdOptions.prompt = fullPrompt
            
            do {
                let strings = try await stableDiffusionClient.generateBase64EncodedImages(sdOptions)
                
                if let string = strings.first,
                   let data = Data(base64Encoded: string),
                   let image = UIImage(data: data) {
                    output.wrappedValue = image
//                    history.end = Date.now
//                    history.outputFilePath = fileService.save(image: image)
                }
            } catch {
//                history.errorDescription = error.localizedDescription
                generationLogger.error("Image-generation response processing failed: \(String(describing: error), privacy: .private)")
            }
            loading.wrappedValue = false

//            db.save(history: history)
//            imageHistory.append(history)
//            lastHistory = history
        }
        
        Task.init {
            // TODO: inherit known values from options
            progress.wrappedValue = StableDiffusionClient.Progress(progress: 0, etaRelative: 0, state: StableDiffusionClient.Progress.State.initial())
            do {
                while loading.wrappedValue == true {
                    progress.wrappedValue = try await self.stableDiffusionClient.imageGenerationProgress()
                    try await Task.sleep(nanoseconds: 200_000_000)
                }
            } catch {
                generationLogger.error("Image-generation progress request failed: \(String(describing: error), privacy: .private)")
            }
        }
        
    }
    
    struct Bracket: Identifiable, Hashable {
        let id = NSUUID().uuidString
        let firstLora: LoraInvocation
        let secondLora: LoraInvocation
        let thirdLora: LoraInvocation?
        let start: Date
        let end: Date
        let result: UIImage
    }
    
    struct Step: Identifiable, Hashable {
        let id = NSUUID().uuidString
        let steps: Int
        let start: Date
        let end: Date
        let result: UIImage
        let sampler: String
        
        var formattedTime: String {
            start.distance(to: end).formatted(.number.precision(.fractionLength(0...2)))
        }
    }
    
    func stepImage(input: UIImage,
                   stepStart: Int,
                   stepEnd: Int,
                   history: ImageHistoryModel,
                   iterateSampers: Bool,
                   loading: Binding<Bool>,
                   progress: Binding<StableDiffusionClient.Progress?>,
                   cancel: Binding<Bool>) -> AsyncThrowingStream<Step, Error>  {
        
        guard let base64Image = input.pngData()?.base64EncodedString() else {
            fatalError("can't convert image")
        }
        
        var sdOptions = StableDiffusionClient.GenerationOptions(prompt: history.prompt,
                                                                negativePrompt: history.negativePrompt ?? "",
                                                                size: imageSize,
                                                                steps: steps,
                                                                sampler: selectedSampler,
                                                                initImages: [base64Image])
        sdOptions.seed = history.seed
        
        if history.loras.count > 0 {
            sdOptions.prompt += " "
            sdOptions.prompt += history.loras.map { lora in
                let activation = sdLoras.first(where: { loadedLora in
                    loadedLora.name == lora.name // TODO: fix this garbage
                })?.activation ?? ""
                return promptAdd(lora: LoraInvocation(name: lora.name, weight: lora.weight, activation: activation))
            }.joined(separator: " ")
        }
                
        loading.wrappedValue = true
        cancel.wrappedValue = false
        
        return AsyncThrowingStream<Step, Error> { continuation in
            
            Task.init {
                do {
                    if iterateSampers {
                    
                    for sampler in sdSamplers {
                        for j in stepStart...stepEnd {
                            let start = Date.now
                            sdOptions.steps = j
                            sdOptions.samplerName = sampler.name
                            let strings = try await self.stableDiffusionClient.generateBase64EncodedImages(sdOptions)
                            let end = Date.now
                            if let string = strings.first,
                               let data = Data(base64Encoded: string),
                               let image = UIImage(data: data) {
                                continuation.yield(
                                    Step(steps: j, start: start, end: end, result: image, sampler: sdOptions.samplerName)
                                )
                            }
                            
                            if cancel.wrappedValue {
                                generationLogger.debug("Generation stream cancelled")
                                continuation.finish()
                                return
                            }
                        }
                    }
                } else {
                    for i in stepStart...stepEnd {
                        
                        let start = Date.now
                        sdOptions.steps = i
                        let strings = try await self.stableDiffusionClient.generateBase64EncodedImages(sdOptions)
                        let end = Date.now
                        if let string = strings.first,
                           let data = Data(base64Encoded: string),
                           let image = UIImage(data: data) {
                            continuation.yield(
                                Step(steps: i, start: start, end: end, result: image, sampler: selectedSampler.name)
                            )
                        }
                        
                        if cancel.wrappedValue {
                            generationLogger.debug("Generation stream cancelled")
                            continuation.finish()
                            return
                        }
                    }
                }

                
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    func bracketImage(input: UIImage,
                      prompt: String,
                      negativePrompt: String,
                      seed: Int,
                      firstLora: LoraInvocation,
                      secondLora: LoraInvocation,
                      thirdLora: LoraInvocation,
                      loading: Binding<Bool>,
                      progress: Binding<StableDiffusionClient.Progress?>,
                      cancel: Binding<Bool>) -> AsyncThrowingStream<Bracket, Error> {

        guard let base64Image = input.pngData()?.base64EncodedString() else {
            fatalError("can't convert image")
        }
        
        var sdOptions = StableDiffusionClient.GenerationOptions(prompt: prompt, negativePrompt: negativePrompt, size: imageSize, steps: steps, sampler: selectedSampler, initImages: [base64Image])
        sdOptions.seed = seed
        
        loading.wrappedValue = true
        cancel.wrappedValue = false
        
        return AsyncThrowingStream<Bracket, Error> { continuation in
            
            Task.init {
                
                let target = firstLora.bracketSteps * secondLora.bracketSteps * (thirdLora.bracketSteps > 0 ? thirdLora.bracketSteps : 1)

                var count = 0
                var firstLoraInvocation = firstLora
                var secondLoraInvocation = secondLora
                for i in 0..<firstLora.bracketSteps {
                    firstLoraInvocation.calculateWeight(step: i)
                    for j in 0..<secondLora.bracketSteps {
                        secondLoraInvocation.calculateWeight(step: j)

                        var options = sdOptions
                        do {
                            let start = Date.now

                            if thirdLora.bracketSteps > 0 {
                                for k in 0..<thirdLora.bracketSteps {
                                    var thirdLoraInvocation = thirdLora
                                    thirdLoraInvocation.calculateWeight(step: k)

                                    options.prompt = "\(prompt) \(self.promptAdd(lora: firstLoraInvocation)) \(self.promptAdd(lora: secondLoraInvocation)) \(self.promptAdd(lora: thirdLoraInvocation)) "
                                    
                                    let strings = try await self.stableDiffusionClient.generateBase64EncodedImages(options)
                                    
                                    if let string = strings.first,
                                       let data = Data(base64Encoded: string),
                                       let image = UIImage(data: data) {
                                        continuation.yield(
                                            Bracket(firstLora: firstLoraInvocation,
                                                    secondLora: secondLoraInvocation,
                                                    thirdLora: thirdLoraInvocation,
                                                    start: start,
                                                    end: Date.now,
                                                    result: image)
                                        )
                                    }
                                    
                                    count += 1
                                    if count >= target {
                                        continuation.finish()
                                    }
                                    if cancel.wrappedValue {
                                        generationLogger.debug("Generation stream cancelled")
                                        continuation.finish()
                                        return
                                    }
                                }
                                
                            } else {
                                options.prompt = "\(prompt) \(self.promptAdd(lora: firstLoraInvocation)) \(self.promptAdd(lora: secondLoraInvocation))"
                                
                                let strings = try await self.stableDiffusionClient.generateBase64EncodedImages(options)
                                
                                if let string = strings.first,
                                   let data = Data(base64Encoded: string),
                                   let image = UIImage(data: data) {
                                    continuation.yield(
                                        Bracket(firstLora: firstLoraInvocation,
                                                secondLora: secondLoraInvocation,
                                                thirdLora: nil,
                                                start: start,
                                                end: Date.now,
                                                result: image))
                                }
                                
                                count += 1
                                if count >= target {
                                    continuation.finish()
                                }
                                if cancel.wrappedValue {
                                    generationLogger.debug("Generation stream cancelled")
                                    continuation.finish()
                                    return
                                }
                            }

                        } catch {
                            generationLogger.error("Generation stream failed: \(String(describing: error), privacy: .private)")
                            continuation.finish(throwing: error)
                        }
                    }
                }
            }
            
        }
        
    }
    
    private nonisolated func promptAdd(lora: LoraInvocation) -> String {
        return " <lora:\(lora.name):\(lora.weight.formatted(.number.precision(.fractionLength(0...2))))> \(lora.activation ?? "")"
    }
    
    func interrogate(image: UIImage, output: Binding<String?>) {
        
        guard let base64Image = image.pngData()?.base64EncodedString() else {
            generationLogger.error("Failed to generate image data")
            return
        }
        
        Task {
            do {
                output.wrappedValue = try await stableDiffusionClient.interrogate(base64EncodedImage: base64Image)
            } catch {
                generationLogger.error("Image interrogation failed: \(String(describing: error), privacy: .private)")
                output.wrappedValue = nil
            }    
        }
    }
    
    func suggestedPromptAdds() -> [String: String] {
        return [
            "Wizard": ", modelshoot style, extremely detailed CG unity 8k wallpaper, full shot body photo of the most beautiful artwork in the world, english medieval, nature magic, medieval era, painting by Ed Blinkey, Atey Ghailan, Studio Ghibli, by Jeremy Mann, Greg Manchess, Antonio Moro, trending on ArtStation, trending on CGSociety, Intricate, High Detail, Sharp focus, dramatic, painting art by midjourney and greg rutkowski, petals, countryside, action pose",
            "Wizard2": ", (painting, art: 1.5), (modelshoot: 1.1), (full shot body photo: 1.2), (extremely detailed: 1.2), (sharp focus: 1.2), (dramatic), (Ed Blinkey, Atey Ghailan, Studio Ghibli, Jeremy Mann, Greg Manchess, Antonio Moro)",
            "Film": ", cinematic film still, (shallow depth of field:0.24), (vignette:0.15), (highly detailed, high budget:1.2), (bokeh, cinemascope:0.3), (epic, gorgeous:1.2), film grain, (grainy:0.6), (detailed skin texture:1.1), subsurface scattering, (motion blur:0.7)"
        ]
    }
    
    //MARK: - Classes & Structs
    
    struct LLMHistoryEntry: Codable, Identifiable {
        var id: Date {
            start
        }
        
        var start: Date = Date.now
        var end: Date?
        var prompt: String
        var result: String = ""
        var model: String
        var errorDescription: String?
    }
    
    //MARK: - Testing
    
    func setupForTesting() {
        db.setupForTesting(fileService: fileService)
        loadHistory()
    }
}


extension UIImage {
    func resized(to size: CGSize) -> UIImage {
        return UIGraphicsImageRenderer(size: size).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

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

@MainActor
@Observable
class GenerationService {
    
    var apiClient = APIClient()
    var fileService = FileService()
    
    static let statusCheckInterval = 2.0
    
    public init() {}
    
    struct ConnectionStatus {
        var connected: Bool
        var lastChecked: Date
        var service: APIClient.Service
    }
    
    var llmStatus = ConnectionStatus(connected: false, lastChecked: .distantPast, service: .largeLanguageModel)
    var sdStatus = ConnectionStatus(connected: false, lastChecked: .distantPast, service: .stableDiffusion)
    
    var sdModels: [StableDiffusionModel] = []
    var llmModels: [LLMModel] = []
    var selectedSDModel: StableDiffusionModel?
    var selectedLLMModel: LLMModel?
    var sdLoras: [StableDiffusionLora] = []
    var sdSamplers: [StableDiffusionSampler] = []
    var selectedSampler = APIClient.defaultSampler // default
    
    var LLMHistory = [LLMHistoryEntry]()
    var SDHistory = [SDHistoryEntry]()
    
    var imageSize = 512
    var steps = 20
    
    private(set) var statusTask: Task<Void, Never>?
    private(set) var modelTask: Task<Void, Never>?
    
    private var storedPrompt: String?
    
    //MARK: - History
    
    func loadHistory() {
        SDHistory = fileService.loadSDHistory()
    }
    
    func loadOutputImage(history: SDHistoryEntry) -> UIImage {
        return fileService.loadImage(path: history.outputFilePaths.first ?? "") // TODO: error handling
    }
    
    func loadInputImage(history: SDHistoryEntry) -> UIImage {
        return fileService.loadImage(path: history.inputFilePath ?? "") // TODO: error handling
    }
    
    func loadDrawing(history: SDHistoryEntry) -> PKDrawing {
        return fileService.load(path: history.drawingPath ?? "") // TODO: error handling
    }
    
    func lastPrompt() -> String {
        // TODO: Persist last prompt
        return storedPrompt ?? "A cat with a fancy hat"
    }
    
    func promptsFromHistory() -> [String] {
        var result = Set<String>()
        for h in SDHistory {
            result.insert(h.prompt)
        }
        return result.sorted()
    }
    
    func modelsFromHistory() -> [String] {
        var result = Set<String>()
        for h in SDHistory {
            result.insert(h.model)
        }
        return result.sorted()
    }
    
    func lorasFromHistory() -> [String] {
        var result = Set<String>()
        for h in SDHistory {
            if let lora = h.lora {
                result.insert(lora)
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
            
            do {
                let success = try await apiClient.testConnection(service: .largeLanguageModel)
                llmStatus = ConnectionStatus(connected: success, lastChecked: Date.now, service: .largeLanguageModel)
            } catch {
                print(error.localizedDescription)
            }
            
            do {
                let success = try await apiClient.testConnection(service: .stableDiffusion)
                sdStatus = ConnectionStatus(connected: success, lastChecked: Date.now, service: .stableDiffusion)
            } catch {
                print(error.localizedDescription)
            }
            
            statusTask = nil
        }
    }
    
    func checkStatusIfNeeded() {
        
        guard abs(llmStatus.lastChecked.timeIntervalSinceNow) > GenerationService.statusCheckInterval &&
                abs(sdStatus.lastChecked.timeIntervalSinceNow) > GenerationService.statusCheckInterval else {
            return
        }
        
        checkStatus()
    }
    
    func getModels() {
        
        guard modelTask == nil else {
            return
        }
        
        modelTask = Task {
            
            do {
                sdModels = try await apiClient.imageGenerationModels()
                let options = try await apiClient.imageGenerationOptions()
                
                selectedSDModel = sdModels.first { model in
                    model.sha256 == options.sdCheckpointHash
                }
                                
                llmModels = try await apiClient.getLocalModels()
                selectedLLMModel = llmModels.first
                
                sdSamplers = try await apiClient.samplers()
                
//                if let selectedLLMModel = selectedLLMModel {
//                    let detail = try await apiClient.getDetail(model: selectedLLMModel)
//                    print(detail)
//                }
                
            sdLoras = try await apiClient.loras()
                
            } catch {
                print(error)
            }
            
            modelTask = nil
        }
    }
    
    func setSelectedModel() {
        
        guard modelTask == nil else {
            return
        }
        
        guard let selectedSDModel = selectedSDModel else {
            print("no model selected")
            return
        }
        
        modelTask = Task {
            do {
                try await apiClient.setImageGenerationModel(model: selectedSDModel)
            } catch {
                print(error)
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
                for try await obj in await self.apiClient.asyncStreamGenerate(prompt: prompt) {
                    if !obj.done {
                        result.wrappedValue += obj.response
                        history.result += obj.response
                    }
                }
            } catch {
                history.errorDescription = error.localizedDescription
                print(error)
            }
            history.end = Date.now
            loading.wrappedValue = false
            LLMHistory.append(history)
        }
    }
    
    func image(prompt: String, promptAddon: String?, negativePrompt: String, lora: StableDiffusionLora?, loraWeight: Double, seed: Int, drawing: PKDrawing, output: Binding<UIImage?>, progress: Binding<StableDiffusionProgress?>, loading: Binding<Bool>) {
        
        loading.wrappedValue = true
        
        var sdOptions = StableDiffusionGenerationOptions(prompt: prompt, negativePrompt: negativePrompt, size: imageSize, steps: steps, sampler: selectedSampler)
        let image = drawing.image(from: CGRect(x: 0, y: 0, width: imageSize, height: imageSize), scale: 1.0)
        guard let base64Image = image.pngData()?.base64EncodedString() else {
            return
        }
        
        sdOptions.seed = seed
        storedPrompt = prompt
        
        Task.init {
            
            if selectedSDModel == nil {
                if modelTask == nil {
                    getModels()
                }
                _ = await modelTask?.result // TODO: handle error case
                print("selected model: \(selectedSDModel?.modelName ?? "none")")
            }
            
            var history = SDHistoryEntry(prompt: prompt, promptAdd: promptAddon, negativePrompt: negativePrompt, model: selectedSDModel?.modelName ?? "none")
            history.inputFilePath = fileService.save(image: image)
            history.drawingPath = fileService.save(drawing: drawing)
            history.seed = seed
            history.sampler = selectedSampler.name
            
            var fullPrompt = prompt
            if let promptAddon {
                fullPrompt += promptAddon
            }
            
            if let lora {
                history.lora = lora.name
                history.loraWeight = loraWeight
                fullPrompt += promptAdd(lora: lora, weight: loraWeight)
            }

            sdOptions.prompt = fullPrompt
            
            do {
                let strings = try await apiClient.generateBase64EncodedImages(sdOptions, base64EncodedSourceImages: [base64Image])
                
                if let string = strings.first,
                   let data = Data(base64Encoded: string),
                   let image = UIImage(data: data) {
                    output.wrappedValue = image
                    history.end = Date.now
                    history.outputFilePaths = [fileService.save(image: image)]
                }
            } catch {
                history.errorDescription = error.localizedDescription
                print(error)
            }
            loading.wrappedValue = false
            
            fileService.save(history: history)
            SDHistory.append(history)
        }
        
        Task.init {
            // TODO: inherit known values from options
            progress.wrappedValue = StableDiffusionProgress(progress: 0, etaRelative: 0, state: StableDiffusionProgress.StableDiffusionState.initial())
            do {
                while loading.wrappedValue == true {
                    progress.wrappedValue = try await self.apiClient.imageGenerationProgress()
                    try await Task.sleep(nanoseconds: 200_000_000)
                }
            } catch {
                print(error)
            }
        }
    }
    
    private func promptAdd(lora: StableDiffusionLora, weight: Double) -> String {
        return " <lora:\(lora.name):\(weight.formatted(.number.precision(.fractionLength(0...1))))>"
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
    
    struct SDHistoryEntry: Codable, Identifiable, Hashable {
        var id: Date {
            start
        }
        
        var start: Date = Date.now
        var end: Date?
        var prompt: String
        var promptAdd: String?
        var negativePrompt: String
        var inputFilePath: String?
        var outputFilePaths = [String]()
        var model: String
        var errorDescription: String?
        var lora: String?
        var loraWeight: Double?
        var drawingPath: String?
        var seed: Int?
        var sampler: String?
    }
    
    //MARK: - Testing
    
    func generateHistoryForTesting() {
        
        var entry = SDHistoryEntry(prompt: "a cat in a fancy hat, with a really long prompt that doesn't fit on the page properly, best quality, realistic, etc etc", negativePrompt: "negative prompt", model: "model")
        entry.inputFilePath = fileService.save(image: UIImage(named: "lighthouse")!)
        entry.outputFilePaths = [fileService.save(image: UIImage(named: "lighthouse")!)]
        entry.end = Date.now
        
        for i in 0..<30 {
            var newEntry = entry
            newEntry.start = Date.now.addingTimeInterval(TimeInterval(i))
            if i > 5 {
                newEntry.loraWeight = 0.5
                newEntry.lora = "lora_name_0.015"
            }
            SDHistory.append(newEntry)
        }
    }
}

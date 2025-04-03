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
    
    var llmClient = LargeLangageModelClient()
    var stableDiffusionClient = StableDiffusionClient()
    
    var fileService = FileService()
    
    static let statusCheckInterval = 2.0
    
    public init() {}
    
    struct ConnectionStatus {
        var connected: Bool
        var lastChecked: Date
        var service: Service
        var error: String?
    }
    
    struct LoraInvocation: Identifiable, Hashable {
        var id: String {
            name
        }
        var name: String
        var weight: Double
        
        var description: String {
            "\(name) \(weight.formatted(.number.precision(.fractionLength(0...2))))"
        }
    }
    
    enum Service {
        case stableDiffusion
        case largeLanguageModel
    }
    
    var llmStatus = ConnectionStatus(connected: false, lastChecked: .distantPast, service: .largeLanguageModel)
    var sdStatus = ConnectionStatus(connected: false, lastChecked: .distantPast, service: .stableDiffusion)
    
    var sdModels: [StableDiffusionClient.Model] = []
    var llmModels: [LargeLangageModelClient.Model] = []
    var selectedSDModel: StableDiffusionClient.Model?
    var selectedLLMModel: LargeLangageModelClient.Model?
    var sdLoras: [StableDiffusionClient.Lora] = []
    var sdSamplers: [StableDiffusionClient.Sampler] = []
    var selectedSampler = StableDiffusionClient.defaultSampler // default
    
    var LLMHistory = [LLMHistoryEntry]()
    var SDHistory = [SDHistoryEntry]()
    
    var imageSize = 512
    var steps = 20
    
    private(set) var statusTask: Task<Void, Never>?
    private(set) var modelTask: Task<Void, Never>?
    
    private var storedPrompt: String?
    
    //MARK: - History
    
    func loadHistory() {
        // TODO: Migrate history properly
        SDHistory = fileService.loadSDHistory()
        
        for i in 0..<SDHistory.count {
            if let loraName = SDHistory[i].lora {
                let loraWeight = SDHistory[i].loraWeight ?? 0
                SDHistory[i].loras = [SDHistoryEntry.LoraHistoryEntry]()
                SDHistory[i].loras?.append(SDHistoryEntry.LoraHistoryEntry(name: loraName, weight: loraWeight))
            }
        }
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
            for lora in h.loras ?? [] {
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
            
            do {
                llmStatus = ConnectionStatus(connected: try await llmClient.testConnection(), lastChecked: Date.now, service: .largeLanguageModel)
            } catch {
                llmStatus = ConnectionStatus(connected: false, lastChecked: Date.now, service: .largeLanguageModel, error: error.localizedDescription)
            }
            
            do {
                sdStatus = ConnectionStatus(connected: try await stableDiffusionClient.testConnection(), lastChecked: Date.now, service: .stableDiffusion)
            }catch {
                sdStatus = ConnectionStatus(connected: false, lastChecked: Date.now, service: .stableDiffusion, error: error.localizedDescription)
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
                sdModels = try await stableDiffusionClient.imageGenerationModels()
                let options = try await stableDiffusionClient.imageGenerationOptions()
                
                selectedSDModel = sdModels.first { model in
                    model.sha256 == options.sdCheckpointHash
                }
                                
                llmModels = try await llmClient.getLocalModels()
                selectedLLMModel = llmModels.first
                
                sdSamplers = try await stableDiffusionClient.samplers()
                
                sdLoras = try await stableDiffusionClient.loras()
                
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
                try await stableDiffusionClient.setImageGenerationModel(model: selectedSDModel)
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
                for try await obj in await self.llmClient.asyncStreamGenerate(prompt: prompt, model: selectedLLMModel) {
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
    
    func image(prompt: String, promptAddon: String?, negativePrompt: String, loras: [LoraInvocation] = [], seed: Int, drawing: PKDrawing, output: Binding<UIImage?>, progress: Binding<StableDiffusionClient.Progress?>, loading: Binding<Bool>) {
        
        loading.wrappedValue = true
        
        var image = drawing.image(from: CGRect(x: 0, y: 0, width: 512, height: 512), scale: 1.0)
        
        if imageSize != 512 { // TODO: canvas size instead of resizing
            image = image.resized(to: CGSize(width: imageSize, height: imageSize))
        }
        guard let base64Image = image.pngData()?.base64EncodedString() else {
            return
        }
        
        var sdOptions = StableDiffusionClient.GenerationOptions(prompt: prompt, negativePrompt: negativePrompt, size: imageSize, steps: steps, sampler: selectedSampler, initImages: [base64Image])
        
        sdOptions.seed = seed
        storedPrompt = prompt
        
        Task.init {
            
            if selectedSDModel == nil {
                if modelTask == nil {
                    getModels()
                }
                _ = await modelTask?.result // TODO: handle error case
            }
            
            var history = SDHistoryEntry(prompt: prompt, promptAdd: promptAddon, negativePrompt: negativePrompt, model: selectedSDModel?.modelName ?? "none")
            history.inputFilePath = fileService.save(image: image)
            history.drawingPath = fileService.save(drawing: drawing)
            history.seed = seed
            history.sampler = selectedSampler.name
            history.steps = steps
            history.size = imageSize
            history.loras = loras.map { lora in
                SDHistoryEntry.LoraHistoryEntry(name: lora.name, weight: lora.weight)
            }
                        
            var fullPrompt = prompt
            if let promptAddon {
                fullPrompt += promptAddon
            }
            
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
            progress.wrappedValue = StableDiffusionClient.Progress(progress: 0, etaRelative: 0, state: StableDiffusionClient.Progress.State.initial())
            do {
                while loading.wrappedValue == true {
                    progress.wrappedValue = try await self.stableDiffusionClient.imageGenerationProgress()
                    try await Task.sleep(nanoseconds: 200_000_000)
                }
            } catch {
                print(error)
            }
        }
    }
    
    struct Bracket: Identifiable {
        let firstLora: LoraInvocation
        let secondLora: LoraInvocation
        let result: UIImage
        
        var id: String {
            return result.hash.description
        }
    }
    
    func bracketImage(input: UIImage, prompt: String, negativePrompt: String, seed: Int, firstLora: String, secondLora: String, bracketSteps: Int, maxWeight: Double, minWeight: Double, loading: Binding<Bool>, progress: Binding<StableDiffusionClient.Progress?>) -> AsyncThrowingStream<Bracket, Error> {

        guard let base64Image = input.pngData()?.base64EncodedString() else {
            fatalError("can't convert image")
        }
        
        guard bracketSteps > 0 else {
            fatalError("divide by zero")
        }
        
        var sdOptions = StableDiffusionClient.GenerationOptions(prompt: prompt, negativePrompt: negativePrompt, size: imageSize, steps: steps, sampler: selectedSampler, initImages: [base64Image])
        sdOptions.seed = seed
        
        loading.wrappedValue = true

        
        return AsyncThrowingStream<Bracket, Error> { continuation in
            
            Task.init {
                let loraIncrement: Double = (maxWeight - minWeight) / Double(bracketSteps - 1)
                var count = 0
                for i in 0..<bracketSteps {
                    for j in 0..<bracketSteps {
                        var options = sdOptions
                        do {
                            let firstLoraInvocation = LoraInvocation(name: firstLora, weight: minWeight + loraIncrement * Double(i))
                            let secondLoraInvocation = LoraInvocation(name: secondLora, weight: minWeight + loraIncrement * Double(j))
                            print("\(firstLoraInvocation) \(secondLoraInvocation)")
                            options.prompt = "\(prompt) \(self.promptAdd(lora: firstLoraInvocation)) \(self.promptAdd(lora: secondLoraInvocation))"
                            
                            let strings = try await self.stableDiffusionClient.generateBase64EncodedImages(options)
                            
                            if let string = strings.first,
                               let data = Data(base64Encoded: string),
                               let image = UIImage(data: data) {
                                continuation.yield(Bracket(firstLora: firstLoraInvocation, secondLora: secondLoraInvocation, result: image))
                            }
                            
                            count += 1
                            print("generated: \(count)")
                            if count >= bracketSteps * bracketSteps {
                                continuation.finish()
                            }
                        } catch {
                            continuation.finish(throwing: error)
                            print(error)
                        }
                    }
                }
            }
            
        }
        
    }
    
    private nonisolated func promptAdd(lora: LoraInvocation) -> String {
        return " <lora:\(lora.name):\(lora.weight.formatted(.number.precision(.fractionLength(0...1))))>"
    }
    
    func interrogate(image: UIImage, output: Binding<String?>) {
        
        guard let base64Image = image.pngData()?.base64EncodedString() else {
            print("failed to generate image data")
            return
        }
        
        Task {
            do {
                output.wrappedValue = try await stableDiffusionClient.interrogate(base64EncodedImage: base64Image)
            } catch {
                print(error)
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
    
    struct SDHistoryEntry: Codable, Identifiable, Hashable {
        var id: Date {
            start
        }
        
        struct LoraHistoryEntry: Codable, Equatable, Hashable, Identifiable {
            var id: String {
                name
            }
            var name: String
            var weight: Double
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
        var loras: [LoraHistoryEntry]?
        var drawingPath: String?
        var seed: Int?
        var sampler: String?
        var steps: Int?
        var size: Int?
    }
    
    //MARK: - Testing
    
    func generateHistoryForTesting() {
        
        var entry = SDHistoryEntry(prompt: "a cat in a fancy hat, with a really long prompt that doesn't fit on the page properly, best quality, realistic, etc etc", negativePrompt: "negative prompt", model: "model")
        entry.inputFilePath = fileService.save(image: UIImage(named: "lighthouse")!)
        entry.outputFilePaths = [fileService.save(image: UIImage(named: "lighthouse")!)]
        entry.end = Date.now
        entry.size = 512
        entry.steps = 21
        entry.seed = Int.random(in: 1...100)
        
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


extension UIImage {
    func resized(to size: CGSize) -> UIImage {
        return UIGraphicsImageRenderer(size: size).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

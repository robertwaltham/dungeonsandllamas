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
    var db = DatabaseService()
    
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
    fileprivate var SDHistory = [SDHistoryEntry]() // TODO: Remove
    var imageHistory = [ImageHistoryModel]()
    var lastHistory: ImageHistoryModel?
    
    var imageSize = 512
    var steps = 20
    
    private(set) var statusTask: Task<Void, Never>?
    private(set) var modelTask: Task<Void, Never>?
    
    private var storedPrompt: String?
    
    //MARK: - History
    
    func loadHistory() {
        imageHistory = db.loadHistory()
        if imageHistory.count == 0 {
            migrateHistory()
        }
    }
    
    func migrateHistory() { // TODO: remove
        SDHistory = fileService.loadSDHistory()
        
        for i in 0..<SDHistory.count {
            if let loraName = SDHistory[i].lora {
                let loraWeight = SDHistory[i].loraWeight ?? 0
                SDHistory[i].loras = [SDHistoryEntry.LoraHistoryEntry]()
                SDHistory[i].loras?.append(SDHistoryEntry.LoraHistoryEntry(name: loraName, weight: loraWeight))
            }
            let history = SDHistory[i]
            let id = NSUUID().uuidString
            let loras: [LoraHistoryModel] = (history.loras ?? []).map { entry in
                return LoraHistoryModel(id: NSUUID().uuidString,
                                 name: "",
                                 weight: 1,
                                 historyModelId: id)
            }
            let entry = ImageHistoryModel(id: id,
                                          start: history.start,
                                          end: history.end,
                                          prompt: history.prompt,
                                          model: history.model,
                                          sampler: history.sampler ?? "",
                                          steps: history.steps ?? 20,
                                          size: history.size ?? 512,
                                          seed: history.seed ?? -1,
                                          inputFilePath: history.inputFilePath,
                                          outputFilePath: history.outputFilePaths.first,
                                          drawingFilePath: history.drawingPath,
                                          errorDescription: history.errorDescription,
                                          session: NSUUID().uuidString,
                                          sequence: 0,
                                          loras: loras)
            db.save(history: entry)
        }
    }
    
    func loadOutputImage(history: ImageHistoryModel) -> UIImage {
        return fileService.loadImage(path: history.outputFilePath ?? "") // TODO: error handling
    }
    
    func loadInputImage(history: ImageHistoryModel) -> UIImage {
        return fileService.loadImage(path: history.inputFilePath ?? "") // TODO: error handling
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
                
//                try await stableDiffusionClient.scriptInfo()
                
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
                                            inputFilePath: fileService.save(image: image),
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
                print(error)
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
                print(error)
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
                print(error)
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
                print(error)
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
                                print("cancelled")
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
                            print("cancelled")
                            continuation.finish()
                            return
                        }
                    }
                }

                
                continuation.finish()
                
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
                                        print("cancelled")
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
                                    print("cancelled")
                                    continuation.finish()
                                    return
                                }
                            }

                        } catch {
                            print(error)
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
    
    struct SDHistoryEntry: Codable, Identifiable, Hashable { // TODO: remove
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

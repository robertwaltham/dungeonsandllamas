//
//  GenerationService.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2024-04-01.
//

import Foundation
import Observation
import SwiftUI

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
    
    var LLMHistory = [LLMHistoryEntry]()
    var SDHistory = [SDHistoryEntry]()
    
    private(set) var statusTask: Task<Void, Never>?
    private(set) var modelTask: Task<Void, Never>?
    
    //MARK: - History
    
    func loadHistory() {
        SDHistory = fileService.loadSDHistory()
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
                
//                if let selectedLLMModel = selectedLLMModel {
//                    let detail = try await apiClient.getDetail(model: selectedLLMModel)
//                    print(detail)
//                }
                
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
    
    func image(prompt: String, negativePrompt: String, image: UIImage, output: Binding<UIImage?>, progress: Binding<StableDiffusionProgress?>, loading: Binding<Bool>) {
        
        loading.wrappedValue = true
        
        let sdOptions = StableDiffusionGenerationOptions(prompt: prompt, negativePrompt: negativePrompt)
        guard let base64Image = image.pngData()?.base64EncodedString() else {
            return
        }
        
        
        Task.init {
            
            if selectedSDModel == nil {
                if modelTask == nil {
                    getModels()
                }
                _ = await modelTask?.result // TODO: handle error case
                print("selected model: \(selectedSDModel?.modelName ?? "none")")
            }
            
            var history = SDHistoryEntry(prompt: prompt, negativePrompt: negativePrompt, model: selectedSDModel?.modelName ?? "none")
            history.inputFilePath = fileService.save(image: image)

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
    
    struct SDHistoryEntry: Codable, Identifiable {
        var id: Date {
            start
        }
        
        var start: Date = Date.now
        var end: Date?
        var prompt: String
        var negativePrompt: String
        var inputFilePath: String?
        var outputFilePaths = [String]()
        var model: String
        var errorDescription: String?
    }
    
    //MARK: - Testing
    
    func generateHistoryForTesting() {
        
        var entry = SDHistoryEntry(prompt: "a cat in a fancy hat, with a really long prompt that doesn't fit on the page properly, best quality, realistic, etc etc", negativePrompt: "negative prompt", model: "model")
        entry.inputFilePath = fileService.save(image: UIImage(named: "lighthouse")!)
        entry.outputFilePaths = [fileService.save(image: UIImage(named: "lighthouse")!)]
        entry.end = Date.now
        SDHistory.append(entry)
    }
}

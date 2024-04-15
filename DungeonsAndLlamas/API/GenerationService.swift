//
//  GenerationService.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2024-04-01.
//

import Foundation
import Observation

@MainActor
@Observable
class GenerationService {
    
    var apiClient = APIClient()
    
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
    
    private(set) var statusTask: Task<Void, Never>?
    private(set) var modelTask: Task<Void, Never>?

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
            print("Status | SD - \(sdStatus.connected) | LLM - \(llmStatus.connected)")
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
}

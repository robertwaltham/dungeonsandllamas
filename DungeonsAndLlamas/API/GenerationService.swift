//
//  GenerationService.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2024-04-01.
//

import Foundation

class GenerationService {
    
    var sharedInstance = GenerationService()
    var apiClient = APIClient()
    
    public init() {}
    
    struct ConnectionStatus {
        var connected: Bool
        var lastChecked: Date
        var service: APIClient.Service
    }
    
    var llmStatus = ConnectionStatus(connected: false, lastChecked: .distantPast, service: .largeLanguageModel)
    var sdStatus = ConnectionStatus(connected: false, lastChecked: .distantPast, service: .stableDiffusion)

    func checkStatus() async {
        
        do {
            let success = try await apiClient.testConnection(service: .largeLanguageModel)
            llmStatus =  ConnectionStatus(connected: success, lastChecked: Date.now, service: .largeLanguageModel)
        } catch {
            print(error.localizedDescription)
        }
        
        do {
            let success = try await apiClient.testConnection(service: .stableDiffusion)
            sdStatus =  ConnectionStatus(connected: success, lastChecked: Date.now, service: .stableDiffusion)
        } catch {
            print(error.localizedDescription)
        }
    }
}

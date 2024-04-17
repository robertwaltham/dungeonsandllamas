//
//  ContentView.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2024-03-26.
//

import SwiftUI
import SwiftData
import Observation

struct ContentView: View {
    @State var flowState = ContentFlowState()
    @State var generationService: GenerationService
    
    var body: some View {
        ContentFlowCoordinator(flowState: flowState, generationService: generationService) {
            landing()
        }
    }
    
    @MainActor @ViewBuilder
    func landing() -> some View {
        if UIDevice.current.userInterfaceIdiom == .phone {
            LandingiPhoneView(flowState: flowState, generationService: generationService)
        } else {
            LandingView(flowState: flowState, generationService: generationService)
        }
    }
}

#Preview {
    ContentView(generationService: GenerationService())
}

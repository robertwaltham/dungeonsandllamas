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
    @Environment(GenerationService.self) private var generationService
    @State private var flowState = ContentFlowState()
    
    var body: some View {
        ContentFlowCoordinator(flowState: flowState) {
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
    ContentView()
        .environment(GenerationService())
}

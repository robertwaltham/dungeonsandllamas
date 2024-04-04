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
        ContentFlowCoordinator(flowState: flowState) {
           LandingView(flowState: flowState, generationService: generationService)
        }
    }
}

#Preview {
    ContentView(generationService: GenerationService())
}

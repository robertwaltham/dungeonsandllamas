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
        .onOpenURL(perform: handleOpenURL)
    }
    
    @MainActor @ViewBuilder
    func landing() -> some View {
        if UIDevice.current.userInterfaceIdiom == .phone {
            LandingiPhoneView(flowState: flowState, generationService: generationService)
        } else {
            LandingView(flowState: flowState, generationService: generationService)
        }
    }

    @MainActor
    private func handleOpenURL(_ url: URL) {
        guard let image = SharedImageImportService.loadSharedImage(for: url) else {
            return
        }

        flowState.path = NavigationPath()
        flowState.nextLink(.comfyUITestSharedImage(image))
    }
}

#Preview {
    ContentView()
        .environment(GenerationService())
}

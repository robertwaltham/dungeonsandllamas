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
        .safeAreaInset(edge: .top, spacing: 0) {
            if let phase = generationService.historySyncPhase {
                HistorySyncProgressView(phase: phase)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: generationService.historySyncPhase)
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

private struct HistorySyncProgressView: View {
    let phase: GenerationService.HistorySyncPhase

    var body: some View {
        HStack(spacing: 12) {
            switch phase {
            case .fetching:
                ProgressView()
                Text("Checking server history…")
            case .processing(let completed, let total):
                ProgressView(value: Double(completed), total: Double(max(total, 1)))
                    .frame(maxWidth: 180)
                Text("\(completed) of \(total)")
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }
}

#Preview {
    ContentView()
        .environment(GenerationService())
}

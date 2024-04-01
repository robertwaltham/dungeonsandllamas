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
    @State var viewModel = ContentViewModel()
    
    var body: some View {
        ContentFlowCoordinator(flowState: viewModel) {
           LandingView(viewModel: viewModel)
        }
    }
}

#Preview {
    ContentView()
}

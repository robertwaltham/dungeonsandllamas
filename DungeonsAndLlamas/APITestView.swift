//
//  APITestView.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2024-03-26.
//

import SwiftUI
import Observation

struct APITestView: View {
    @State var viewModel = ViewModel()
    @State var contentViewModel: ContentViewModel

    var body: some View {
        VStack {
            Text("Test")
            Button("Stream Generate") {
                viewModel.testStream()
            }.buttonStyle(.bordered)
            Text(viewModel.result)
        }
    }
}

@Observable
class ViewModel {
    let client = APIClient()
    
    var result = ""
    
    func testStream() {
        result = ""
        Task.init {
            do {
                for try await obj in client.asyncStreamGenerate(prompt: "What is the meaning of life in 30 words or less") {
                    if !obj.done {
                        result += obj.response
                    }
                }
            } catch {
                print(error)
            }
        }
    }
}

#Preview {
    let viewModel = ContentViewModel()
    return ContentFlowCoordinator(flowState: viewModel) {
        APITestView(contentViewModel: viewModel)
    }
}

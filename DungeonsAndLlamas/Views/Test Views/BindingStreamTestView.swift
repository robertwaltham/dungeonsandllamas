//
//  BindingStreamTestView.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2024-04-15.
//

import SwiftUI

struct BindingStreamTestView: View {
    @State var viewModel = BindingStreamTestViewModel()
    @State var flowState: ContentFlowState
    @State var generationService: GenerationService

    var body: some View {
        
        VStack {
            HStack {
                TextField("Prompt", text: $viewModel.prompt)
                    .frame(minHeight: 75)
                    .padding()
                    .background(Color(white: 0.8))
                    .clipShape(RoundedRectangle(cornerSize: CGSize(width: 20, height: 20)))
                .padding()
                
                HStack {
                    if !viewModel.loading {
                        Button("Generate") {
                            generationService.text(prompt: viewModel.prompt, result: $viewModel.result, loading: $viewModel.loading)
                        }
                        .buttonStyle(.bordered)
                    } else {
                        ProgressView()
                    }
                }
                .padding(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 20))
                .frame(minWidth: 120)
            }.frame(minHeight: 200)

            Text(viewModel.result)
            .onChange(of: viewModel.result) { oldValue, newValue in
                print(newValue)
            }
            .padding(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10))
            .frame(maxWidth: .infinity, minHeight: 75)
            .background(Color(white: 0.8))
            .clipShape(RoundedRectangle(cornerSize: CGSize(width: 20, height: 20)))
            .padding()
            
            VStack {
                ForEach(generationService.LLMHistory) { history in
                    HStack {
                        Text(history.prompt)
                        Text(history.result)
                    }
                }
            }
            
            Spacer()
            
        }.onAppear {
            generationService.getModels()
        }
    }
}

@Observable
class BindingStreamTestViewModel {
    var result = ""
    var prompt = "What is the meaning of life. In 30 words or less."
    var loading = false
}

#Preview {
    let flowState = ContentFlowState()
    return ContentFlowCoordinator(flowState: flowState) {
        BindingStreamTestView(flowState: flowState, generationService: GenerationService())
    }
}

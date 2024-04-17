//
//  PencilDrawingiPadView.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2024-04-15.
//

import SwiftUI
import PencilKit

struct PencilDrawingiPadView: View {
    @State var viewModel: PencilViewModel
    @State var flowState: ContentFlowState
    @State var generationService: GenerationService
    
    init(flowState: ContentFlowState, generationService: GenerationService) {
        self.viewModel = PencilViewModel(generationService: generationService)
        self.flowState = flowState
        self.generationService = generationService
    }
    
    var body: some View {
        ZStack {
            Color(white: 0.7)
            VStack {

                PencilCanvasView(image: $viewModel.drawing, showTooltip: $viewModel.showTooltip)
                    .frame(width: 512, height: 512)
                    .onChange(of: viewModel.drawing) { oldValue, newValue in
                        guard let drawing = newValue, !viewModel.loading else {
                            return
                        }
                        
                        generationService.image(prompt: viewModel.imagePrompt(), negativePrompt: viewModel.negative, image: drawing, output: $viewModel.output, progress: $viewModel.progress, loading: $viewModel.loading)
                    }
                
                TextField("Prompt", text: $viewModel.prompt)
                    .frame(width: 482)
                    .padding()
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerSize: CGSize(width: 10, height: 10)))
                
                ZStack {
                    if let image = viewModel.output {
                        Image(uiImage: image)
                            .frame(width: 512, height: 512)
                            .background(.white)
                    } else {
                        Rectangle()
                            .foregroundColor(.white)
                            .frame(width: 512, height: 512)
                    }
                    
                    if viewModel.loading {
                        VStack {
                            Spacer()
                            ProgressView(value: viewModel.progress?.progress ?? 0)
                                .frame(width: 500, height: 10)

                        }
                    }
                }.frame(height: 512)

            }
            HStack {
                Spacer()
                VStack {
                    Button("Clear") {
                        viewModel.drawing = nil
                    }
                    .buttonStyle(.bordered)
                    .padding()
                    .foregroundColor(.red)
                    
                    Button("History") {
                        viewModel.showTooltip = false
                        flowState.coverItem = .sdHistory
                    }
                    .buttonStyle(.bordered)
                    .padding()
                    
                    Toggle("Add", isOn: $viewModel.includePromptAdd)
                        .frame(maxWidth: 90)
                        .padding()
                    
                    Toggle("Tool", isOn: $viewModel.showTooltip)
                        .frame(maxWidth: 90)
                        .padding()
                }
                .background(Color(white: 0.9))
                .clipShape(RoundedRectangle(cornerSize: CGSize(width: 20, height: 20)))
            }
            .padding()
        }
    }
}



#Preview {
    let flowState = ContentFlowState()
    let service = GenerationService()
    service.generateHistoryForTesting()
    return ContentFlowCoordinator(flowState: flowState, generationService: service) {
        PencilDrawingiPadView(flowState: flowState, generationService: service)
    }
}

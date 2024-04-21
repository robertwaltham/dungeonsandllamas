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
    
    @MainActor
    init(flowState: ContentFlowState, generationService: GenerationService, history: GenerationService.SDHistoryEntry) {
        let viewModel = PencilViewModel(generationService: generationService)
        viewModel.load(history: history)
        self.viewModel = viewModel
        self.flowState = flowState
        self.generationService = generationService
    }
    
    var body: some View {
        ZStack {
            Color(white: 0.7)
            VStack {

                PencilCanvasView(drawing: $viewModel.drawing, showTooltip: $viewModel.showTooltip)
                    .frame(width: 512, height: 512)
                    .onChange(of: viewModel.drawing) { oldValue, newValue in
                        guard !viewModel.loading else {
                            return
                        }
                        viewModel.generate(output: $viewModel.output, progress: $viewModel.progress, loading: $viewModel.loading)
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
                    
                    Button("Go Again") {
                        guard !viewModel.loading else {
                            return
                        }
                        viewModel.generate(output: $viewModel.output, progress: $viewModel.progress, loading: $viewModel.loading)
                    }
                    .buttonStyle(.bordered)
                    .padding()
                    .foregroundColor(.green)

                    
                    let maxWidth: CGFloat = 100
                    Toggle("Add", isOn: $viewModel.includePromptAdd)
                        .frame(maxWidth: maxWidth)
                        .padding(EdgeInsets(top: 0, leading: 10, bottom: 10, trailing: 10))

                    Toggle("Tool", isOn: $viewModel.showTooltip)
                        .frame(maxWidth: maxWidth)
                        .padding(EdgeInsets(top: 0, leading: 10, bottom: 10, trailing: 10))

                    Text("Lora")
                    Picker("Lora", selection: $viewModel.selectedLora) {
                        Text("None").tag(nil as StableDiffusionLora?)
                        ForEach(generationService.SDLoras) { lora in
                            Text(lora.name).tag(lora as StableDiffusionLora?)
                        }
                    }
                    .frame(maxWidth: maxWidth)
                    .padding(EdgeInsets(top: 0, leading: 10, bottom: 10, trailing: 10))

                    Text("Weight \(viewModel.loraWeight, format: .number.precision(.fractionLength(0...1)))")
                    Slider(value: $viewModel.loraWeight, in: 0...1)
                        .frame(maxWidth: maxWidth)
                        .padding(EdgeInsets(top: 0, leading: 10, bottom: 10, trailing: 10))
                    
                    Text("Seed")
                    Text("\(viewModel.seed, format: .number.grouping(.never))")
                        .padding(EdgeInsets(top: 0, leading: 10, bottom: 10, trailing: 10))
                        .onTapGesture {
                            viewModel.newSeed()
                        }
                    
                    Button("History") {
                        viewModel.showTooltip = false
                        flowState.coverItem = .sdHistory
                    }
                    .buttonStyle(.bordered)
                    .padding()
                    
                }
                .background(Color(white: 0.9))
                .clipShape(RoundedRectangle(cornerSize: CGSize(width: 20, height: 20)))
            }
            .padding(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 10))
        }
    }
}



#Preview {
    let flowState = ContentFlowState()
    let service = GenerationService()
    service.generateHistoryForTesting()
    Task {
        service.getModels()
    }
    return ContentFlowCoordinator(flowState: flowState, generationService: service) {
        PencilDrawingiPadView(flowState: flowState, generationService: service)
    }
}

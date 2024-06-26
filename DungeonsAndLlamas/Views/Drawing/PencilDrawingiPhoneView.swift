//
//  PencilDrawingiPhoneView.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2024-04-17.
//

import SwiftUI

import SwiftUI
import PencilKit

struct PencilDrawingiPhoneView: View {
    @State var viewModel: PencilViewModel
    @State var flowState: ContentFlowState
    @State var generationService: GenerationService
    @State var showSettings = false
    
    let imageSize: CGFloat = 320
    
    @MainActor
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
            Color(white: 0.7).ignoresSafeArea()
            VStack {
                Spacer()
                PencilCanvasView(drawing: $viewModel.drawing, showTooltip: $viewModel.showTooltip, contentSize: $generationService.imageSize)
                    .frame(width: imageSize, height: imageSize)
                    .onChange(of: viewModel.drawing) { oldValue, newValue in
                        guard !viewModel.loading else {
                            return
                        }
                        viewModel.generate(output: $viewModel.output, progress: $viewModel.progress, loading: $viewModel.loading)
                    }
                
                HStack {
                    Text(viewModel.prompt)
                        .padding()
                        .frame(maxHeight: 50)
                    
                    Button("Settings") {
                        showSettings = true
                    }
                    .buttonStyle(.bordered)
                    .padding(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 10))
                    .popover(isPresented: $showSettings, content: {
                        VStack {
                            HStack {
                                Button("Clear Canvas") {
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
                            }
                            
                            Text("Prompt").font(.title2)
                            TextEditor(text: $viewModel.prompt)
                                .padding() // TODO: fix keyboard
                            Spacer()

                            Spacer()
                            Text("Negative Prompt").font(.title2)
                            TextEditor(text: $viewModel.negative)
                                .padding()
                            Spacer()
                            
                            Text("Lora \(viewModel.enabledLoras.count)").font(.title2)
                            ForEach($viewModel.loras) { $lora in
                                
                                HStack {
                                    Text("\(lora.name) \(                                    lora.weight.formatted(.number.precision(.fractionLength(2...2))))")
                                     Slider(value: $lora.weight)
                                }.padding(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10))
                            }
                            
                            Text("Seed")
                            Text("\(viewModel.seed, format: .number.grouping(.never))")
                                .padding(EdgeInsets(top: 0, leading: 10, bottom: 10, trailing: 10))
                                .onTapGesture {
                                    viewModel.newSeed()
                                }
                        }.onDisappear {
                            guard !viewModel.loading else {
                                return
                            }
                            viewModel.generate(output: $viewModel.output, progress: $viewModel.progress, loading: $viewModel.loading)                        }
                    })
                }
                .background(.white)
                .clipShape(RoundedRectangle(cornerSize: CGSize(width: 10, height: 10)))
                .padding(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10))
                .frame(width: imageSize + 20)
                
                ZStack {
                    if let image = viewModel.output {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: imageSize, height: imageSize)
                            .background(.white)
                            .onTapGesture {
                                viewModel.showTooltip.toggle()
                            }
                    } else {
                        Rectangle()
                            .foregroundColor(.white)
                            .frame(width: imageSize, height: imageSize)
                            .onTapGesture {
                                viewModel.showTooltip.toggle()
                            }
                    }
                    
                    if viewModel.loading {
                        VStack {
                            ProgressView(value: viewModel.progress?.progress ?? 0)
                                .frame(width: imageSize - 10, height: 10)
                            Spacer()
                        }
                    }
                }.frame(height: imageSize)
                Spacer()
                    .frame(height: 20)
            }

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
        PencilDrawingiPhoneView(flowState: flowState, generationService: service)
    }
}

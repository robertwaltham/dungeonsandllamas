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
    @State var showLora = false
    @State var showSettings = false

    let imageSize: CGFloat = 320
    
    @MainActor
    init(flowState: ContentFlowState, generationService: GenerationService) {
        self.viewModel = PencilViewModel(generationService: generationService)
        self.flowState = flowState
        self.generationService = generationService
    }
    
    @MainActor
    init(flowState: ContentFlowState, generationService: GenerationService, history: ImageHistoryModel) {
        let viewModel = PencilViewModel(generationService: generationService)
        viewModel.load(history: history)
        self.viewModel = viewModel
        self.flowState = flowState
        self.generationService = generationService
    }
    
    var body: some View {
        ZStack {
            GradientView(type: .greyscale).ignoresSafeArea()
            VStack {
                HStack {
                    Spacer()
                    
                    Button {
                        viewModel.showTooltip.toggle()
                    } label: {
                        
                        HStack {
                            Label("Tool", systemImage: "paintbrush.pointed")
                        }
                        .foregroundColor(.green)

                    }
                    
                    Spacer()
                    
                    Button {
                        showLora = true
                        viewModel.showTooltip = false
                    } label: {
                        
                        HStack {
                            Label("LoRa", systemImage: "waveform")
                        }
                        .foregroundColor(.blue)

                    }
                    .popover(isPresented: $showLora, content: {
                        loraOverlay()
                    })
                    
                    Spacer()
                    
                    Button {
                        showSettings = true
                        viewModel.showTooltip = false
                    } label: {
                        
                        HStack {
                            Label("Prompt", systemImage: "character.textbox")
                        }
                        .foregroundColor(.yellow)

                    }
                    .popover(isPresented: $showSettings, content: {
                        promptOverlay()
                    })
                    Spacer()
                    
                    Button {
                        viewModel.newSeed()
                        generate()
                    } label: {
                        HStack {
                            Label("Seed", systemImage: "dice")
                        }
                        .foregroundColor(.red)
                    }
                    Spacer()

                }
                
                PencilCanvasView(drawing: $viewModel.drawing, showTooltip: $viewModel.showTooltip, contentSize: $generationService.imageSize)
                    .frame(width: imageSize, height: imageSize)
                    .onChange(of: viewModel.drawing) { oldValue, newValue in
                        guard !viewModel.loading else {
                            return
                        }
                        viewModel.generate(output: $viewModel.output, progress: $viewModel.progress, loading: $viewModel.loading, drawingScale: imageSize)
                    }
                
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
                
                HStack {
                    Text(viewModel.prompt)
                        .padding()
                        .frame(maxHeight: 50)
                }
                .background(.white)
                .clipShape(RoundedRectangle(cornerSize: CGSize(width: 10, height: 10)))
                .padding(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10))
                .frame(width: imageSize + 20)
                
                Spacer()
            }
        }
    }
    
    @ViewBuilder
    func promptOverlay() -> some View {
        VStack {
            HStack {
                Button("Clear Canvas") {
                    viewModel.clear()
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

            Text("Negative Prompt").font(.title2)
            TextEditor(text: $viewModel.negative)
                .padding()
            Spacer()
        }.onDisappear {
            generate()
        }
    }
    
    @ViewBuilder
    func loraOverlay() -> some View {
        VStack {
            Spacer().frame(maxHeight: 10)
            Text("Lora \(viewModel.enabledLoras.count)").font(.title2)
            ForEach($viewModel.loras) { $lora in
                
                HStack {
                    Text("\(lora.name)").frame(width: 220)
                    Slider(value: $lora.weight, in: 0.0...1.5)
                    Text("\(                                    lora.weight.formatted(.number.precision(.fractionLength(2...2))))")
                }.padding(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10))
            }
            Spacer()

        }.onDisappear {
            generate()
        }
    }
    
    func generate() {
        guard !viewModel.loading else {
            return
        }
        viewModel.generate(output: $viewModel.output, progress: $viewModel.progress, loading: $viewModel.loading, drawingScale: imageSize)
    }
}




#Preview {
    let flowState = ContentFlowState()
    let service = GenerationService()
    service.setupForTesting()
    Task {
        service.getModels()
    }
    return ContentFlowCoordinator(flowState: flowState, generationService: service) {
        PencilDrawingiPhoneView(flowState: flowState, generationService: service)
    }
}

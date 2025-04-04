//
//  BracketView.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2025-04-02.
//

import SwiftUI
import Observation
import PencilKit

struct BracketView: View {
    @State var flowState: ContentFlowState
    @State var viewModel: PencilViewModel
    @State var generationService: GenerationService
    
    let imageSize: CGFloat = 200
    
    init(flowState: ContentFlowState, generationService: GenerationService, history: GenerationService.SDHistoryEntry) {
        self.flowState = flowState
        self.viewModel = PencilViewModel(generationService: generationService)
        self.generationService = generationService
        
        self.viewModel.load(history: history)
    }

    var body: some View {
        ZStack {
            GradientView(type: .greyscale)
            VStack {
                Text(viewModel.prompt)
                ZStack {
                    HStack {
                        ZStack {

                            if let input = viewModel.input {
                                Image(uiImage: input)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: imageSize, height: imageSize)
                                    .background(.white)
                            } else {
                                Rectangle()
                                    .foregroundColor(.white)
                                    .frame(width: imageSize, height: imageSize)
                            }
                            
                            VStack {
                                Text("Input")
                                Spacer()
                            }
                            
                        }.frame(maxHeight: imageSize)
                        
                        ZStack {
                            if let output = viewModel.output {
                                Image(uiImage: output)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: imageSize, height: imageSize)
                                    .background(.white)
                            } else {
                                Rectangle()
                                    .foregroundColor(.white)
                                    .frame(width: imageSize, height: imageSize)
                            }
                            VStack {
                                Text("Output")
                                Spacer()
                            }
                        }.frame(maxHeight: imageSize)
                    }
                    if viewModel.loading {
                        VStack {
                            Spacer()
                            HStack {
                                ProgressView(value: viewModel.progress?.progress ?? 0)
                                if viewModel.thirdBracketLora == nil {
                                    Text("\(viewModel.brackets.count) / \(viewModel.bracketSteps * viewModel.bracketSteps)")
                                } else {
                                    Text("\(viewModel.brackets.count) / \(viewModel.bracketSteps * viewModel.bracketSteps * viewModel.bracketSteps)")
                                }

                            }
                            .padding()
                            .frame(width: 400)
                        }
                    }
                }.frame(height: 220)
                HStack {
                    Picker("first lora", selection:$viewModel.firstBracketLora) {
                        Text("pick first lora").tag(nil as GenerationService.LoraInvocation?)
                        ForEach(viewModel.loras, id:\.self) { lora in
                            Text(lora.name).tag(lora)
                        }
                    }
                    .disabled(viewModel.loading)

                    
                    Picker("second lora", selection:$viewModel.secondBracketLora) {
                        Text("pick second lora").tag(nil as GenerationService.LoraInvocation?)
                        ForEach(viewModel.loras, id:\.self) { lora in
                            Text(lora.name).tag(lora)
                        }
                    }
                    .disabled(viewModel.loading)
                    
                    Picker("third lora", selection:$viewModel.thirdBracketLora) {
                        Text("pick third lora").tag(nil as GenerationService.LoraInvocation?)
                        ForEach(viewModel.loras, id:\.self) { lora in
                            Text(lora.name).tag(lora)
                        }
                    }
                    .disabled(viewModel.loading)
                }
                HStack {
                    Button("Generate Brackets") {
                        guard !viewModel.loading else {
                            return
                        }
                        viewModel.generateBrackets(progress: $viewModel.progress, loading: $viewModel.loading)
                    }
                    .disabled(viewModel.loading)
                    .buttonStyle(.bordered)
                    .padding()
                    .foregroundColor(.green)
                    
                    HStack {
                        Text("Min Weight")
                        Picker("min", selection: $viewModel.bracketMin) {
                            ForEach(-10..<5) { value in
                                let weight = Double(value) / 10.0
                                Text(weight.formatted(.number.precision(.fractionLength(0...2)))).tag(weight)
                            }
                        }
                        .disabled(viewModel.loading)

                    }
                    
                    HStack {
                        Text("Max Weight")
                        Picker("max", selection: $viewModel.bracketMax) {
                            ForEach(6..<13) { value in
                                let weight = Double(value) / 10.0
                                Text(weight.formatted(.number.precision(.fractionLength(0...2)))).tag(weight)
                            }
                        }
                        .disabled(viewModel.loading)
                    }
                    
                    HStack {
                        Text("Steps")
                        Picker("steps", selection: $viewModel.bracketSteps) {
                            ForEach(3..<6) { value in
                                Text("\(value)").tag(value)
                            }
                        }
                        .disabled(viewModel.loading)
                    }
                    
                    HStack {
                        Text("Seed")
                        Text("\(viewModel.seed)")
                    }
                }
                Spacer()
                
                if viewModel.brackets.count == 0 {

                } else {
                    ScrollView {
                        let columns: [GridItem] = (0..<viewModel.bracketSteps).map {_ in return GridItem(.flexible())}
                        LazyVGrid(columns: columns) {
                            ForEach(viewModel.brackets) { bracket in
                                
                                ZStack {
                                    Image(uiImage: bracket.result)
                                        .resizable()
                                        .scaledToFit()
                                    
                                    VStack {
                                        Spacer()
                                        
                                        if let third = bracket.thirdLora {
                                            Text("\(bracket.firstLora.weight.formatted(.number.precision(.fractionLength(0...2)))) |  \(bracket.secondLora.weight.formatted(.number.precision(.fractionLength(0...2)))) | \(third.weight.formatted(.number.precision(.fractionLength(0...2))))")
                                        } else {
                                            Text("\(bracket.firstLora.weight.formatted(.number.precision(.fractionLength(0...2)))) |  \(bracket.secondLora.weight.formatted(.number.precision(.fractionLength(0...2))))")
                                        }

                                    }
                                }
                                .shadow(radius: 2)
                                .frame(maxHeight: 320)

                            }
                        }
                    }
                }
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
        BracketView(flowState: flowState, generationService: service, history: service.SDHistory.first!)
    }
}




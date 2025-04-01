//
//  LandingiPhoneView.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2024-04-17.
//

import SwiftUI

struct LandingiPhoneView: View {
    @State var flowState: ContentFlowState
    @State var generationService: GenerationService
    let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    @State var history = [UIImage]()

    var body: some View {
        ZStack {
            GradientView(type: .greyscale)
            LazyVGrid(columns: [ GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]) {
                ForEach(history, id:\.self) { img in
                    
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                }
            }
            .onAppear {
                history = generationService.SDHistory.filter{ entry in
                    entry.errorDescription == nil
                }
                .shuffled()
                .prefix(21)
                .map{ entry in
                    return generationService.loadOutputImage(history: entry)
                }
            }
            .onReceive(timer) { input in
                withAnimation(.linear(duration: 1.0)){
                    if history.count > 1 {
                        let random = Int.random(in: 0..<history.count - 1) // TODO: fix bug with last cell sliding animation
                        let img = generationService.loadOutputImage(history: generationService.SDHistory.randomElement()!)
                        if history.firstIndex(of: img) == nil {
                            history[random] = img
                        }
                    }
                }
            }
            
            VStack {
                Spacer()
                Text("Dungeons & Llamas")
                    .font(.largeTitle)
                    .shadow(color:.gray, radius: 2.0)
                Text("A generative journey").font(.title)
                    .shadow(color:.gray, radius: 2.0)

                Spacer().frame(maxHeight: 200)
                
                HStack {
                    //                Button(action: {
                    //                    flowState.nextLink(.itemGenerator)
                    //                }, label: {
                    //                    Text("Items")
                    //                })
                    //                .frame(width: 200, height: 200)
                    //                .background(Color(white: 0.7))
                    //                .clipShape(RoundedRectangle(cornerSize: CGSize(width: 20, height: 20)))
                    
                    let buttonSize: CGFloat = 120
                    
//                    Button(action: {
//                        flowState.nextLink(.apiTest)
//                    }, label: {
//                        Text("APITest")
//                    })
//                    .frame(width: buttonSize, height: buttonSize)
//                    .background(Color(white: 0.7))
//                    .clipShape(RoundedRectangle(cornerSize: CGSize(width: 20, height: 20)))
//                    
                    Button(action: {
                        flowState.nextLink(.drawing)
                    }, label: {
                        Text("Drawing")
                    })
                    .frame(width: buttonSize, height: buttonSize)
                    .background(Color(white: 0.7))
                    .clipShape(RoundedRectangle(cornerSize: CGSize(width: 20, height: 20)))
                    
                    Button(action: {
                        flowState.nextLink(.sdHistory)
                    }, label: {
                        Text("History")
                    })
                    .frame(width: buttonSize, height: buttonSize)
                    .background(Color(white: 0.7))
                    .clipShape(RoundedRectangle(cornerSize: CGSize(width: 20, height: 20)))
                }
                
                Spacer()
                
                HStack {
                    
                    ZStack {
                        if generationService.llmStatus.connected {
                            RoundedRectangle(cornerSize: CGSize(width: 20, height: 20)).frame(width: 70, height: 70)
                                .foregroundColor(.green)
                        } else {
                            RoundedRectangle(cornerSize: CGSize(width: 20, height: 20)).frame(width: 70, height: 70)
                                .foregroundColor(.red)
                        }
                        
                        Text("LLM")
                    }
                    
                    ZStack {
                        if generationService.sdStatus.connected {
                            RoundedRectangle(cornerSize: CGSize(width: 20, height: 20)).frame(width: 70, height: 70)
                                .foregroundColor(.green)
                        } else {
                            RoundedRectangle(cornerSize: CGSize(width: 20, height: 20)).frame(width: 70, height: 70)
                                .foregroundColor(.red)
                        }
                        
                        Text("SD")
                    }
                    
                    Button("Recheck") {
                        generationService.checkStatusIfNeeded()
                    }
                    .buttonStyle(.bordered)
                    .disabled(generationService.statusTask != nil)
                    
                }.padding()
                
                HStack {
                    let modelDisabled = generationService.modelTask != nil
                    
                    if generationService.selectedSDModel != nil {
                        Picker("Model", selection: $generationService.selectedSDModel) {
                            ForEach(generationService.sdModels) { model in
                                Text(model.modelName).tag(model as StableDiffusionClient.Model?)
                            }
                        }
                        .frame(minWidth: 150)
                        .disabled(modelDisabled)
                    }
                    
                    //                if generationService.selectedLLMModel != nil {
                    //                    Picker("Model", selection: $generationService.selectedLLMModel) {
                    //                        ForEach(generationService.llmModels) { model in
                    //                            Text(model.name).tag(model as LLMModel?)
                    //                        }
                    //                    }
                    //                    .frame(minWidth: 150)
                    //                    .disabled(modelDisabled)
                    //                }
                    
                    
                    if generationService.sdModels.count > 0 {
                        Button("Set Model") {
                            generationService.setSelectedModel()
                        }
                        .buttonStyle(.bordered)
                        .disabled(modelDisabled)
                    } else {
                        Button("Load Models") {
                            generationService.getModels()
                        }
                        .buttonStyle(.bordered)
                        .disabled(modelDisabled)
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
    return ContentFlowCoordinator(flowState: flowState, generationService: service) {
        LandingiPhoneView(flowState: flowState, generationService: service)
    }
}


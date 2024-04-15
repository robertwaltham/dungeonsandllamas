//
//  LandingView.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2024-04-01.
//

import SwiftUI

struct LandingView: View {    
    @State var flowState: ContentFlowState
    @State var generationService: GenerationService

    var body: some View {
        VStack {
            Spacer()
            Text("Dungeons & Llamas")
                .font(.title)
            Text("A generative journey").font(.subheadline)
            
            Spacer().frame(maxHeight: 200)
            
            HStack {
                Button(action: {
                    flowState.nextLink(.itemGenerator)
                }, label: {
                    Text("Items")
                })
                .frame(width: 200, height: 200)
                .background(Color(white: 0.7))
                .clipShape(RoundedRectangle(cornerSize: CGSize(width: 20, height: 20)))
                
                Button(action: {
                    flowState.nextLink(.apiTest)
                }, label: {
                    Text("APITest")
                })
                .frame(width: 200, height: 200)
                .background(Color(white: 0.7))
                .clipShape(RoundedRectangle(cornerSize: CGSize(width: 20, height: 20)))
                
                Button(action: {
                    flowState.nextLink(.drawing)
                }, label: {
                    Text("Drawing")
                })
                .frame(width: 200, height: 200)
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
                
                Spacer()
                
                let modelDisabled = generationService.modelTask != nil
                
                if generationService.selectedSDModel != nil {
                    Picker("Model", selection: $generationService.selectedSDModel) {
                        ForEach(generationService.sdModels) { model in
                            Text(model.modelName).tag(model as StableDiffusionModel?)
                        }
                    }
                    .frame(minWidth: 150)
                    .disabled(modelDisabled)
                }
                
                if generationService.selectedLLMModel != nil {
                    Picker("Model", selection: $generationService.selectedLLMModel) {
                        ForEach(generationService.llmModels) { model in
                            Text(model.name).tag(model as LLMModel?)
                        }
                    }
                    .frame(minWidth: 150)
                    .disabled(modelDisabled)
                }
                

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
            }.padding()
        }
    }
}

#Preview {
    let flowState = ContentFlowState()
    let service = GenerationService()
    return ContentFlowCoordinator(flowState: flowState, generationService: service) {
        LandingView(flowState: flowState, generationService: service)
    }
}

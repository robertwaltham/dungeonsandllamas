//
//  LandingiPhoneView.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2024-04-17.
//

import SwiftUI
import Combine

struct LandingiPhoneView: View {
    let flowState: ContentFlowState
    @Bindable var generationService: GenerationService
    let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    @State var history = [UIImage]()
    @State private var showingComfyUIStatus = false

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
                history = generationService.imageHistory.filter{ entry in
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
                        let random = Int.random(in: 0..<history.count - 2)
                        let img = generationService.loadOutputImage(history: generationService.imageHistory.randomElement()!)
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
                
                VStack (alignment: .center, spacing: 25) {
                    Button(action: {
                        flowState.nextLink(.comfyUITest(.one))
                    }, label: {
                        Text("Flux2 Paint")
                            .padding()
                            .frame(width: 200)
                    })

                    Button(action: {
                        flowState.nextLink(.comfyUITest(.two))
                    }, label: {
                        Text("Flux2 Image+Paint")
                            .padding()
                            .frame(width: 200)

                    })

                    Button(action: {
                        flowState.nextLink(.twoPhotoEdit)
                    }, label: {
                        Text("Flux2 Photo + Photo")
                            .padding()
                            .frame(width: 200)
                    })

                    Button(action: {
                        flowState.nextLink(.sdHistory)
                    }, label: {
                        Text("History")
                            .padding()
                            .frame(width: 200)

                    })
                }
                .buttonStyle(.glass)
                
                Spacer()
                
                Button(action: {
                    showingComfyUIStatus = true
                }, label: {
                    Text("Service Status")
                        .padding()
                })
                .buttonStyle(.glassProminent)
                .tint(generationService.comfyUIStatus.connected ? .green : .red)
                .popover(isPresented: $showingComfyUIStatus) {
                    ComfyUISystemStatusView(
                        connection: generationService.comfyUIConnectionInfo,
                        status: generationService.comfyUISystemStatus,
                        models: generationService.comfyUIModels,
                        error: generationService.comfyUIStatus.error
                    )
                }
                
                Spacer()
            }
        }
    }
}

#Preview {
    let flowState = ContentFlowState()
    let service = GenerationService()
    service.setupForTesting()
    return ContentFlowCoordinator(flowState: flowState) {
        LandingiPhoneView(flowState: flowState, generationService: service)
    }
    .environment(service)
}

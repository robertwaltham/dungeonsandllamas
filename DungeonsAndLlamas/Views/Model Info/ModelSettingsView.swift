//
//  ModelSettingsView.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2024-04-26.
//

import SwiftUI

struct ModelSettingsView: View {
    @State var flowState: ContentFlowState
    @State var generationService: GenerationService
    
    var body: some View {
        ScrollView() {

            Text("Stable Diffusion")
                .font(.largeTitle)
                .padding(EdgeInsets(top: 0, leading: 0, bottom: 20, trailing: 0))
            
            Text("Models")
                .font(.title)

            VStack(alignment: .leading) {
                ForEach(generationService.sdModels) { model in
                    Text(model.title)
                }
            }
            
            HStack {
                let modelDisabled = generationService.modelTask != nil

                Text("Selected Model")
                Picker("Selected Model", selection: $generationService.selectedSDModel) {
                    ForEach(generationService.sdModels) { model in
                        Text(model.modelName).tag(model as StableDiffusionClient.Model?)
                    }
                }
                .disabled(modelDisabled)
                .onChange(of: generationService.selectedSDModel) { oldValue, newValue in
                    generationService.setSelectedModel()
                }
            }
            
            Text("LoRA").font(.title)
                .padding(EdgeInsets(top: 20, leading: 0, bottom: 0, trailing: 0))
            Text("Low-Rank Adaptation of Large Language Models").font(.subheadline)
                .padding(EdgeInsets(top: 0, leading: 0, bottom: 10, trailing: 0))
 
            VStack(alignment: .leading) {
                ForEach(generationService.sdLoras) { lora in
                    HStack {
                        Text(lora.name)
                        Spacer()
                        Button {
                            flowState.presentedItem = .lora(lora: lora)
                        } label: {
                            Label("", systemImage: "info.circle")
                        }
                    }
                    .frame(maxWidth: 700)
                    
                }
            }

            Text("Samplers").font(.title)
                .padding(EdgeInsets(top: 20, leading: 0, bottom: 0, trailing: 0))

            HStack {
                HStack {
                    Text("Selected Sampler")
                    Picker("Selected Sampler", selection: $generationService.selectedSampler) {
                        ForEach(generationService.sdSamplers) { sampler in
                            Text(sampler.name).tag(sampler)
                        }
                    }
                }
                VStack {
                    let array: [String] = generationService.selectedSampler.options.keys.compactMap({$0})
                    ForEach(array, id: \.self) { key in
                        Text("\(key) - \(generationService.selectedSampler.options[key] ?? "")")
                    }
                }
            }

            
            Text("Options").font(.title)
                .padding(EdgeInsets(top: 20, leading: 0, bottom: 10, trailing: 0))

            HStack {
                Text("Image Size:")
                Picker("Size", selection: $generationService.imageSize) {
                    Text("512 x 512").tag(512)
                    Text("1024 x 1024").tag(1024)
                }
            }
            
            HStack {
                Text("Generation Steps")
                Picker("Steps", selection: $generationService.steps) {
                    ForEach(15..<32) { value in
                        Text(value.description).tag(value)
                    }
                }
            }
            
            Spacer()

            Text("Large Language Model")
                .font(.largeTitle)
                .padding(EdgeInsets(top: 0, leading: 0, bottom: 30, trailing: 0))
            
            Text("Models").font(.title)
                .padding(EdgeInsets(top: 0, leading: 0, bottom: 10, trailing: 0))

            VStack(alignment: .leading) {
                ForEach(generationService.llmModels) { model in
                    HStack {
                        Text(model.name)
                        Text(model.details.parameterSize)
                    }

                }
            }
            
//
//            Button("Reload Model Info") {
//                generationService.getModels()
//            }
//            .padding()
//            .buttonStyle(.bordered)
        }
        .frame(width: .infinity)
        .onAppear {
            generationService.getModels()
        }
    }
}

#Preview {
    let flowState = ContentFlowState()
    let service = GenerationService()
    
//    service.getModels()
    return ContentFlowCoordinator(flowState: flowState, generationService: service) {
        ModelSettingsView(flowState: flowState, generationService: service)
    }
}

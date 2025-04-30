//
//  DepthGenerationView.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2025-04-30.
//

import SwiftUI
import UIKit
import Observation

struct DepthGenerationView: View {
    var flowState: ContentFlowState
    var generationService: GenerationService
    @State var viewModel: DepthGenerationViewModel
    @State var showLoras = false
    
    init(flowState: ContentFlowState, generationService: GenerationService, img: PhotoLibraryService.PhotoLibraryImage) {
        self.flowState = flowState
        self.generationService = generationService
        self.viewModel = DepthGenerationViewModel(generationService: generationService, img: img)
    }
    
    var body: some View {
        VStack {
            ZStack {
                Image(uiImage: viewModel.image.image)
                
                if let depth = viewModel.image.depth {
                    HStack {
                        Spacer()
                        VStack {
                            Spacer()
                            Image(uiImage: depth)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 512 / 4, height: 512 / 4)
                                .background(.gray)
                                .padding()
                        }
                    }
                }
                
                VStack {
                    Spacer()
                        .frame(height: 21)
                    TextEditor(text: $viewModel.prompt)
                        .scrollContentBackground(.hidden)
                        .background(Color(white: 0.8, opacity: 0.4))
                        .frame(width: 470, height: 100)
                        .clipped()
                    Spacer()
                }
            }
            .frame(width: 512, height: 512)
            
            Spacer()
            
            HStack {
                Button {
                    showLoras = true
                } label: {
                    
                    HStack {
                        Label("Loras", systemImage: "photo.on.rectangle.angled")
                    }
                    .foregroundColor(.purple)

                    HStack {
                        Text("\(viewModel.enabledLoras.count)")
                    }
                    .foregroundColor(.black)
                }
                .padding()
                .popover(isPresented: $showLoras) {
                    Grid(horizontalSpacing: 10, verticalSpacing: 20) {
                        
                        ForEach($viewModel.loras) { $lora in
                            
                            GridRow {
                                Text(lora.name).frame(minWidth: 200)
                                Slider(value: $lora.weight, in: 0.0...2.0)
                                Text(lora.weight.formatted(.number.precision(.fractionLength(0...2))))
                                    .frame(minWidth: 50)
                            }
                        }
                    }
                    .frame(minWidth: 500)
                    .padding()
                }
                

                
                
                Picker("mode", selection: $viewModel.mode) {
                    ForEach(StableDiffusionClient.ControlNetOptions.ControlMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .frame(width: 270)
                
                Button {
                    guard !viewModel.loading else {
                        return
                    }
                    viewModel.depth(serice: generationService, output: $viewModel.result, progress: $viewModel.progress, loading: $viewModel.loading)
                } label: {
                    
                    HStack {
                        Label("Generate", systemImage: "play.rectangle")
                    }
                    .foregroundColor(.blue)

                }
                .padding()
            }
            
            Spacer()
            
            ZStack {
                if let result = viewModel.result {
                    Image(uiImage: result)
                } else {
                    Rectangle()
                        .foregroundStyle(.gray)
                }
                
                if viewModel.loading {
                    VStack {
                        ProgressView(value: viewModel.progress?.progress ?? 0)
                            .frame(width: 500, height: 10)
                        Spacer()
                    }
                }
            }
            .frame(width: 512, height: 512)

        }
    }
}

@Observable
class DepthGenerationViewModel: @unchecked Sendable {
    
    @MainActor
    init(generationService: GenerationService, img: PhotoLibraryService.PhotoLibraryImage) {
        self.loras = generationService.sdLoras.map { lora in
            GenerationService.LoraInvocation.init(name: lora.name, weight: 0, activation: lora.activation)
        }
        self.image = img

        withObservationTracking {
            _ = generationService.sdLoras
        } onChange: {
            Task {
                // TODO: preserve weights
                self.loras = await generationService.sdLoras.map { lora in
                    GenerationService.LoraInvocation.init(name: lora.name, weight: 0)
                }
            }
        }
    }
        
    var loras: [GenerationService.LoraInvocation]
    var enabledLoras: [GenerationService.LoraInvocation] {
        loras.filter { $0.weight > 0}
    }
    
    var image: PhotoLibraryService.PhotoLibraryImage
    var loading = false
    var progress: StableDiffusionClient.Progress?
    var result: UIImage?
    var prompt = "A cat in a fancy hat"
    var mode: StableDiffusionClient.ControlNetOptions.ControlMode = .balanced
    
    
    @MainActor
    func depth(serice: GenerationService,
               output: Binding<UIImage?>,
               progress: Binding<StableDiffusionClient.Progress?>,
               loading: Binding<Bool>) {

        guard let depth = image.depth else {
            return
        }
        result = nil
        serice.depth(prompt: prompt,
                     loras: enabledLoras,
                     seed: Int.random(in: 0...1000),
                     input: image.image,
                     depth: depth,
                     mode: mode,
                     output: output,
                     progress: progress,
                     loading: loading)
    }

}

#Preview {
    
    let flowState = ContentFlowState()
    let service = GenerationService()
    service.getModels()
    let img = PhotoLibraryService.PhotoLibraryImage(image: UIImage(named: "lighthouse")!)
    return ContentFlowCoordinator(flowState: flowState, generationService: service) {
        DepthGenerationView(flowState: flowState, generationService: service, img: img)
    }
}




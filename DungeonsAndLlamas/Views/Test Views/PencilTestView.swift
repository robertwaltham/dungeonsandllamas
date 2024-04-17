//
//  PencilTestView.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2024-04-15.
//

import SwiftUI
import PencilKit

struct PencilTestView: View {
    @State var viewModel = PencilTestViewModel()
    @State var flowState: ContentFlowState
    @State var generationService: GenerationService
    
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
                        
                        let prompt = viewModel.includePromptAdd ? viewModel.prompt + viewModel.promptAdd : viewModel.prompt
                        
                        generationService.image(prompt: prompt, negativePrompt: viewModel.negative, image: drawing, output: $viewModel.output, progress: $viewModel.progress, loading: $viewModel.loading)
                    }
                    .onChange(of: flowState.coverItem) { oldValue, newValue in
                        if newValue == nil {
                            
                        }
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

@Observable
class PencilTestViewModel {
    var drawing: UIImage?
    var output: UIImage?
//    var prompt = "A dragonborn wizard casting a spell swirling magic"
    var prompt = "A cat wearing a fancy hat"

    var promptAdd = ", modelshoot style, extremely detailed CG unity 8k wallpaper, full shot body photo of the most beautiful artwork in the world, english medieval, nature magic, medieval era, painting by Ed Blinkey, Atey Ghailan, Studio Ghibli, by Jeremy Mann, Greg Manchess, Antonio Moro, trending on ArtStation, trending on CGSociety, Intricate, High Detail, Sharp focus, dramatic, painting art by midjourney and greg rutkowski, petals, countryside, action pose"
    var negative = "worst quality, normal quality, low quality, low res, blurry, text, watermark, logo, banner, extra digits, cropped, jpeg artifacts, signature, username, error,duplicate, ugly, monochrome, horror, geometry, mutation, disgusting"
    var loading = false
    var progress: StableDiffusionProgress?
    var includePromptAdd = true
    var showTooltip = true
}

#Preview {
    let flowState = ContentFlowState()
    let service = GenerationService()
    service.generateHistoryForTesting()
    return ContentFlowCoordinator(flowState: flowState, generationService: service) {
        PencilTestView(flowState: flowState, generationService: service)
    }
}

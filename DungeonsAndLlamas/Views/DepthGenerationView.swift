//
//  DepthGenerationView.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2025-04-30.
//

import SwiftUI
import UIKit
import Observation
import PencilKit

struct DepthGenerationView: View {
    var flowState: ContentFlowState
    var generationService: GenerationService
    @State var viewModel: DepthGenerationViewModel
    @State var showLoras = false
    
    init(flowState: ContentFlowState, generationService: GenerationService, localIdentifier: String) {
        self.flowState = flowState
        self.generationService = generationService
        self.viewModel = DepthGenerationViewModel(generationService: generationService, localIdentifier: localIdentifier)
    }
    
    var body: some View {
        ZStack {
            GradientView(type: .greyscale)
            if let image = viewModel.image {
                VStack {
                    ZStack {
                        Image(uiImage: image.image)
                        
                        VStack {
                            HStack {
                                
                                VStack(alignment: .leading) {
                                    ForEach(viewModel.classifications) { prediction in
                                        Text("\(prediction.label) \(prediction.probability.formatted(.number.precision(.fractionLength(0...2))))")
                                            .padding()
                                            .background(Color(white: 0.9, opacity: 0.5))
                                            .clipShape(RoundedRectangle(cornerRadius: 10.0, style: .circular))
                                            .onTapGesture {
                                                viewModel.addPrompt(prediction.label)
                                            }
                                    }
                                }.padding()
                                
                                Spacer()
                                
                                depthImageView()
                            }
                            Spacer()
                        }

                        
                        VStack {
                            Spacer()
                            TextEditor(text: $viewModel.prompt)
                                .scrollContentBackground(.hidden)
                                .background(Color(white: 0.8, opacity: 0.4))
                                .frame(width: 470, height: 100)
                                .clipped()
                            Spacer()
                                .frame(height: 21)
                        }
                    }
                    .frame(width: 512, height: 512)
                    
                    Spacer()
                    
                    HStack {
                        
                        if viewModel.editedImage != nil {
                            Button {
                                viewModel.editedImage = nil
                                viewModel.depthDrawing = nil
                            } label: {
                                Label("Reset Edits", systemImage: "arrow.uturn.backward")
                            }
                        } else {
                            Toggle(isOn: $viewModel.useEstimate) {
                                viewModel.useEstimate ? Text("Estimated Depth") : Text("Captured Depth")
                            }
                            .frame(width: 150)
                            .disabled(viewModel.image?.depth == nil)
                        }

                        
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
                            loraOverlay()
                        }
                        
                        Picker("mode", selection: $viewModel.mode) {
                            ForEach(StableDiffusionClient.ControlNetOptions.ControlMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .frame(width: 270)
                        
                        Button {
                            viewModel.editDepth(flowState: flowState)
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .foregroundStyle(.yellow)
                        
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
                    .padding()
                    .background(Color(white: 1.0, opacity: 0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 5.0))
                    
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

                }.onAppear {
                    guard viewModel.classifications.isEmpty else {
                        return
                    }
                    viewModel.classify(service: generationService)
                }
            } else {
                ProgressView()
                    .onAppear {
                        viewModel.loadImage(service: generationService)
                    }
            }
        }
    }
    
    @ViewBuilder
    func loraOverlay() -> some View {
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
    
//    @ViewBuilder
    func depthImageView() -> some View {
        let image: UIImage
        if let editedImage = viewModel.editedImage {
            image = editedImage
        } else if viewModel.useEstimate, let estimated = viewModel.image?.estimatedDepth {
            image = estimated
        } else if let depth = viewModel.image?.depth {
            image = depth
        } else {
            image = UIImage(named: "lighthouse")! // should never happen
        }
        
        return Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: 512 / 4, height: 512 / 4)
            .background(.gray)
            .padding()
    }
}

@Observable
class DepthGenerationViewModel: @unchecked Sendable {
    
    var session = NSUUID().uuidString
    var sequence = 0
    
    @MainActor
    init(generationService: GenerationService, localIdentifier: String) {
        self.loras = generationService.sdLoras.map { lora in
            GenerationService.LoraInvocation.init(name: lora.name, weight: 0, activation: lora.activation)
        }
        self.localIdentifier = localIdentifier
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
    let localIdentifier: String
        
    var loras: [GenerationService.LoraInvocation]
    var enabledLoras: [GenerationService.LoraInvocation] {
        loras.filter { $0.weight > 0}
    }
    
    var image: PhotoLibraryService.PhotoLibraryImage?
    var loading = false
    var progress: StableDiffusionClient.Progress?
    var result: UIImage?
    var prompt = ""
    var mode: StableDiffusionClient.ControlNetOptions.ControlMode = .balanced
    var useEstimate = true
    var classifications = [MLService.PredictionResult]()
    var depthDrawing: PKDrawing?
    var editedImage: UIImage?
    
    func loadImage(service: GenerationService) {
        guard image == nil else {
            return
        }
        
        Task {
            self.image = await service.photos.getDepth(identifier: self.localIdentifier)
        }
    }
    
    func classify(service: GenerationService) {
        guard let image else {
            return
        }
        Task {
            self.classifications = await service.photos.classify(image: image.image).filter({ result in
                result.probability > 0.1
            })
        }
    }
    
    func addPrompt(_ text: String) {
        guard !prompt.hasSuffix(text) else {
            return
        }
        
        prompt.append(" ")
        prompt.append(text)
    }
    
    func editDepth(flowState: ContentFlowState) {
        
        guard !loading else {
            return
        }
        
        let input: UIImage
        if useEstimate, let image = image?.estimatedDepth {
            input = image
            self.editedImage = image
        } else if let image = image?.depth {
            input = image
            self.editedImage = image
        } else {
            return
        }
        
        let output = Binding(get: {
            self.editedImage!
        }, set: { newValue in
            self.editedImage = newValue
        })
        
        let drawing = Binding {
            self.depthDrawing
        } set: { newValue in
            self.depthDrawing = newValue
        }
        
        flowState.nextLink(.depthEditor(input: input, output: output, drawing: drawing))
    }
    
    @MainActor
    func depth(serice: GenerationService,
               output: Binding<UIImage?>,
               progress: Binding<StableDiffusionClient.Progress?>,
               loading: Binding<Bool>) {
        
        guard let image = self.image else {
            return
        }

        let depth: UIImage
        if let editedImage {
            depth = editedImage
        } else if let trueDepth = image.depth, !useEstimate {
            depth = trueDepth
        } else if let estimatedDepth = image.estimatedDepth {
            depth = estimatedDepth
        } else {
            return
        }
        result = nil
        sequence += 1
        serice.depth(prompt: prompt,
                     loras: enabledLoras,
                     seed: Int.random(in: 0...1000),
                     input: image.image,
                     depth: depth,
                     mode: mode,
                     session: session,
                     sequence: sequence,
                     output: output,
                     progress: progress,
                     loading: loading)
    }

}

#Preview {
    
    let flowState = ContentFlowState()
    let service = GenerationService()
    service.getModels()
    let id = NSUUID().uuidString
    let view = DepthGenerationView(flowState: flowState, generationService: service, localIdentifier: id)
    let image = PhotoLibraryService.PhotoLibraryImage(id: id, image: UIImage(named: "lighthouse")!, depth: UIImage(named: "depth_preview")!, estimatedDepth: UIImage(named: "depth_preview")!, canny: UIImage(named: "depth_preview")!)
    view.viewModel.image = image
    view.viewModel.classifications = [
        MLService.PredictionResult(label: "Cat", probability: 0.6),
        MLService.PredictionResult(label: "Ham", probability: 0.4),
        MLService.PredictionResult(label: "Green Eggs", probability: 0.2),
    ]
    return ContentFlowCoordinator(flowState: flowState, generationService: service) {
        view
    }
}




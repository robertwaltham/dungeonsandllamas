//
//  PhotoLibraryTestView.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2025-04-14.
//

import SwiftUI
import Observation


struct DepthGenerationView: View {
    var flowState: ContentFlowState
    var generationService: GenerationService
    @State var viewModel: DepthGenerationViewModel
    @State var presentedResult: DepthGenerationViewModel.ImageResult?
    @State var showLoras: Bool = false

    init(flowState: ContentFlowState, generationService: GenerationService) {
        self.flowState = flowState
        self.generationService = generationService
        self.viewModel = DepthGenerationViewModel(generationService: generationService)
    }
    
    var body: some View {
        VStack {
            if let presentedResult {
                let size: CGFloat = 280

                HStack {
                    Image(uiImage: presentedResult.image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                    if let depth = presentedResult.depth {
                        Image(uiImage: depth)
                            .resizable()
                            .scaledToFill()
                            .frame(width: size, height: size)
                    }

                }

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
                    
                    Button("Generate") {
//                        viewModel.upload(image: presentedResult, service: generationService)
                        viewModel.depth(image: presentedResult, serice: generationService, output: $viewModel.result, progress: $viewModel.progress, loading: $viewModel.loading)
                    }.disabled(viewModel.loading)
                    
                    
                    if let result = viewModel.result {
                        ZStack {
                            Image(uiImage: result)
                                .resizable()
                                .scaledToFill()
                                .frame(width: size, height: size)
                            if viewModel.loading {
                                ProgressView()
                            }
                        }

                    } else {
                        ZStack {
                            Rectangle()
                                .frame(width: size, height: size)
                                .foregroundStyle(Color(white: 0.7))
                            if viewModel.loading {
                                ProgressView()
                            }
                        }
                    }
                    
                    
//                    Button {
//                        viewModel.describe(image: presentedResult.image, generationService: generationService)
//                    } label: {
                        Text(viewModel.prompt)
//                    }.disabled(viewModel.loading)

                }
            }
            
            ScrollView {
                let size: CGFloat = 180
                LazyVGrid(columns: [GridItem(.fixed(size)), GridItem(.fixed(size)), GridItem(.fixed(size)), GridItem(.fixed(size))]) {
                    ForEach(viewModel.images) { result in
                        
                        Button {
                            presentedResult = result
                            viewModel.result = nil
                        } label: {
                            ZStack {
                                Image(uiImage: result.image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: size, height: size)

                                if let depth = result.depth {
                                    VStack {
                                        Spacer()
                                        HStack {
                                            Image(uiImage: depth)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: size / 4, height: size / 4)
                                                .background(.gray)
                                                .padding()
                                            Spacer()
                                        }
                                    }
                                }
                            }
                        }.disabled(viewModel.loading)
                    }
                }
                .background(.gray)
                .onAppear {
                    viewModel.getImages(service: generationService)
                }

            }
        }

    }
    

}

@Observable
class DepthGenerationViewModel: @unchecked Sendable {
    
    @MainActor
    init(generationService: GenerationService) {
        self.loras = generationService.sdLoras.map { lora in
            GenerationService.LoraInvocation.init(name: lora.name, weight: 0, activation: lora.activation)
        }
        
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
    
    var loading = false
    
    var loras: [GenerationService.LoraInvocation]
    var enabledLoras: [GenerationService.LoraInvocation] {
        loras.filter { $0.weight > 0}
    }
    
    struct ImageResult: Identifiable {
        var image: UIImage
        var depth: UIImage?
        var canny: UIImage?
        let index: Int
        
        var id: Int {
            index
        }
    }
    static let imageCount = 100
    var prompt = "watercolor"
    let descriptionPrompt = """
    <start_of_turn>user
    Describe the contents of this image in 50 words or less

    <start_of_image>

    <end_of_turn>
    <start_of_turn>model
    """
    var result: UIImage?
    var progress: StableDiffusionClient.Progress?
    
    var images = (0..<imageCount).map { i in ImageResult(image: UIImage(named: "lighthouse")!, index: i) }
    func getImages(service: GenerationService) {
        print("start")
        loading = true
        Task.init {
            var i = 0
            for await image in await service.photos.getImages(limit: DepthGenerationViewModel.imageCount) {

                images[i].image = image.image
                images[i].depth = image.depth
                images[i].canny = image.canny
                i += 1
            }
            loading = false
        }
    }
    
    @MainActor
    func depth(image: ImageResult,
               serice: GenerationService,
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
                     output: output,
                     progress: progress,
                     loading: loading)
    }
    
    func upload(image: ImageResult, service: GenerationService) {
        guard let depth = image.depth, !loading else {
            return
        }
        loading = true
        Task.init {
            do {
                let imgFilename = NSUUID().uuidString + ".png"
                let depthFilename = NSUUID().uuidString + ".png"
                let _ = try await service.stableDiffusionClient.upload(image: image.image, filename: imgFilename)
                let _ = try await service.stableDiffusionClient.upload(image: depth, filename: depthFilename)
                guard let resultFileName = try await service.stableDiffusionClient.depth(inputFileName: imgFilename, depthFileName: depthFilename, prompt: prompt + " watercolor painting", loraWeight: 0.9, seed: Int.random(in: 0...1000)) else {
                    result = nil
                    return
                }
                result = try await service.stableDiffusionClient.download(filename: resultFileName)
                
            } catch {
                print(error)
            }
            loading = false
        }
    }
    
    @MainActor
    func describe(image: UIImage, generationService: GenerationService) {
        guard !loading else {
            return
        }
        loading = true
        prompt = ""
        guard let imageData = image.jpegData(compressionQuality: 0.8)?.base64EncodedString() else {
            loading = false
            return
        }
        
        guard let model = generationService.selectedLLMModel else {
            loading = false
            return
        }
        Task.init {
            do {
                for try await obj in await generationService.llmClient.asyncStreamGenerate(prompt: descriptionPrompt, base64Image: imageData, model: model){
                    if !obj.done {
                        prompt += obj.response
                    }
                }
            } catch {
                print(error)
            }
            loading = false
        }
    }
}

#Preview {
    let flowState = ContentFlowState()
    let service = GenerationService()
    service.photos.checkAuthStatus()
    service.getModels()
    return ContentFlowCoordinator(flowState: flowState, generationService: service) {
        DepthGenerationView(flowState: flowState, generationService: service)
    }
}

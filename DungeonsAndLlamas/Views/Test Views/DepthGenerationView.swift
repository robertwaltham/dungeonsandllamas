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
    @State var viewModel = DepthGenerationViewModel()
    @State var presentedResult: DepthGenerationViewModel.ImageResult?
    
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
                    Button("Generate") {
                        viewModel.upload(image: presentedResult, service: generationService)
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
                    
                    
                    Button {
                        viewModel.describe(image: presentedResult.image, generationService: generationService)
                    } label: {
                        Text(viewModel.prompt)
                    }.disabled(viewModel.loading)

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
@MainActor
class DepthGenerationViewModel {
    
    var loading = false
    
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
    var prompt = "A picture of flowers"
    let descriptionPrompt = """
    <start_of_turn>user
    Describe the contents of this image in 50 words or less

    <start_of_image>

    <end_of_turn>
    <start_of_turn>model
    """
    var result: UIImage?
    
    var images = (0..<imageCount).map { i in ImageResult(image: UIImage(named: "lighthouse")!, index: i) }
    func getImages(service: GenerationService) {
        print("start")
        loading = true
        Task.init {
            var i = 0
            for await image in service.photos.getImages(limit: DepthGenerationViewModel.imageCount) {

                images[i].image = image.image
                images[i].depth = image.depth
                images[i].canny = image.canny
                i += 1
            }
            loading = false
        }
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

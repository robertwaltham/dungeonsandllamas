//
//  PhotoLibraryTestView.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2025-04-14.
//

import SwiftUI
import Observation


struct DepthListView: View {
    var flowState: ContentFlowState
    var generationService: GenerationService
    @State var viewModel: DepthListViewModel
    @State var showLoras: Bool = false

    init(flowState: ContentFlowState, generationService: GenerationService) {
        self.flowState = flowState
        self.generationService = generationService
        self.viewModel = DepthListViewModel()
    }
    
    var body: some View {
        ZStack {
            ScrollView {
                let size: CGFloat = 180
                LazyVGrid(columns: [GridItem(.fixed(size)), GridItem(.fixed(size)), GridItem(.fixed(size)), GridItem(.fixed(size))]) {
                    ForEach(viewModel.images, id: \.self) { result in
                        imageCell(result: result, size: size)
                    }
                }
                .background(.gray)
                .onAppear {
                    viewModel.getImages(service: generationService)
                }

            }
            if viewModel.loading {
                HStack {
                    VStack {
                        ProgressView()
                            .padding()
                        Spacer()
                    }
                    Spacer()
                }
            }
        }
    }
    
    @ViewBuilder
    func imageCell(result: DepthListViewModel.ImageContainer, size: CGFloat) -> some View {
        switch result {
        case .image(let img):
            Button {
                flowState.nextLink(.depthGeneration(img: img))
            } label: {
                ZStack {
                    Image(uiImage: img.image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)

                    if let depth = img.depth {
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
            }
        
        default:
            Image(uiImage: UIImage(named: "lighthouse")!)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
        }
    }
}

@Observable
class DepthListViewModel: @unchecked Sendable {

    var loading = false

    static let imageCount = 200
//    var prompt = "watercolor"
//    let descriptionPrompt = """
//    <start_of_turn>user
//    Describe the contents of this image in 50 words or less
//
//    <start_of_image>
//
//    <end_of_turn>
//    <start_of_turn>model
//    """
//    var result: UIImage?
//    var progress: StableDiffusionClient.Progress?
    
    enum ImageContainer: Identifiable, Hashable {
        case none(Int)
        case image(PhotoLibraryService.PhotoLibraryImage)
        
        var id: Int {
            switch self {
            case .none(let index):
                return index
            case .image(let img):
                return img.id
            }
        }
    }
    
    var images = (0..<imageCount).map { i in ImageContainer.none(i) }
    func getImages(service: GenerationService) {
        print("start")
        loading = true
        Task.init {
            var i = 0
            for await image in await service.photos.getImages(limit: DepthListViewModel.imageCount) {

                images[i] = ImageContainer.image(image)
                i += 1
            }
            loading = false
        }
    }
    
//    
//    func upload(image: ImageResult, service: GenerationService) {
//        guard let depth = image.depth, !loading else {
//            return
//        }
//        loading = true
//        Task.init {
//            do {
//                let imgFilename = NSUUID().uuidString + ".png"
//                let depthFilename = NSUUID().uuidString + ".png"
//                let _ = try await service.stableDiffusionClient.upload(image: image.image, filename: imgFilename)
//                let _ = try await service.stableDiffusionClient.upload(image: depth, filename: depthFilename)
//                guard let resultFileName = try await service.stableDiffusionClient.depth(inputFileName: imgFilename, depthFileName: depthFilename, prompt: prompt + " watercolor painting", loraWeight: 0.9, seed: Int.random(in: 0...1000)) else {
//                    result = nil
//                    return
//                }
//                result = try await service.stableDiffusionClient.download(filename: resultFileName)
//                
//            } catch {
//                print(error)
//            }
//            loading = false
//        }
//    }
//    
//    @MainActor
//    func describe(image: UIImage, generationService: GenerationService) {
//        guard !loading else {
//            return
//        }
//        loading = true
//        prompt = ""
//        guard let imageData = image.jpegData(compressionQuality: 0.8)?.base64EncodedString() else {
//            loading = false
//            return
//        }
//        
//        guard let model = generationService.selectedLLMModel else {
//            loading = false
//            return
//        }
//        Task.init {
//            do {
//                for try await obj in await generationService.llmClient.asyncStreamGenerate(prompt: descriptionPrompt, base64Image: imageData, model: model){
//                    if !obj.done {
//                        prompt += obj.response
//                    }
//                }
//            } catch {
//                print(error)
//            }
//            loading = false
//        }
//    }
}

#Preview {
    let flowState = ContentFlowState()
    let service = GenerationService()
    service.photos.checkAuthStatus()
    service.getModels()
    return ContentFlowCoordinator(flowState: flowState, generationService: service) {
        DepthListView(flowState: flowState, generationService: service)
    }
}

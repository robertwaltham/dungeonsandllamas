//
//  PhotoLibraryTestView.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2025-04-14.
//

import SwiftUI
import Observation


struct PhotoLibraryTestView: View {
    var flowState: ContentFlowState
    var generationService: GenerationService
    var viewModel = PhotoLibraryTestViewModel()
    
    var body: some View {
        ScrollView {
//            Button {
//                viewModel.getImages(service: generationService)
//            } label: {
//                Text("Get Images")
//            }
            
//            LazyVGrid(columns: [.init(), .init(), .init()]) {
            let size: CGFloat = 350
            LazyVStack {
                ForEach(viewModel.images) { result in
                    HStack(spacing: 10) {
                        Image(uiImage: result.image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: size, height: size)
                            .clipped()
                            .background(.gray)
                        
                        if let depth = result.depth {
                            Image(uiImage: depth)
                                .resizable()
                                .scaledToFill()
                                .frame(width: size, height: size)
                                .clipped()
                                .background(.gray)
                        }
                    }
                
                }
            }
            .background(.gray)
            .onAppear {
                viewModel.getImages(service: generationService)
            }
        }
    }
}

@Observable
@MainActor
class PhotoLibraryTestViewModel {
    
    struct ImageResult: Identifiable {
        var image: UIImage
        var depth: UIImage?
        let index: Int
        
        var id: Int {
            index
        }
    }
    static let imageCount = 50
    
    var images = (0..<imageCount).map { i in ImageResult(image: UIImage(named: "lighthouse")!, index: i) }
    func getImages(service: GenerationService) {
        print("start")
        Task.init {
            var i = 0
            for await image in service.photos.getImages(limit: PhotoLibraryTestViewModel.imageCount) {
                images[i].image = image.image
                images[i].depth = image.depth
                i += 1
            }
        }
    }
    


}

#Preview {
    let flowState = ContentFlowState()
    let service = GenerationService()
    service.photos.checkAuthStatus()
    return ContentFlowCoordinator(flowState: flowState, generationService: service) {
        PhotoLibraryTestView(flowState: flowState, generationService: service)
    }
}

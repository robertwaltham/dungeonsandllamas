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
            let size: CGFloat = 240
            LazyVStack {
                ForEach(viewModel.images) { result in
                    HStack(spacing: 10) {
                        Image(uiImage: result.image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: size, height: size)
//                            .clipped()
                            .background(.gray).onTapGesture {
                                viewModel.upload(image: result.image, service: generationService)
                            }
                        
                        if let depth = result.depth {
                            Image(uiImage: depth)
                                .resizable()
                                .scaledToFill()
                                .frame(width: size, height: size)
//                                .clipped()
                                .background(.gray)
                                .background(.gray).onTapGesture {
                                    viewModel.upload(image: depth, service: generationService)
                                }
                        }
                        
                        if let canny = result.canny {
                            Image(uiImage: canny)
                                .resizable()
                                .scaledToFill()
                                .frame(width: size, height: size)
                                .clipped()
                                .background(.gray)
                                .background(.gray).onTapGesture {
                                    viewModel.upload(image: canny, service: generationService)
                                }
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
        var canny: UIImage?
        let index: Int
        
        var id: Int {
            index
        }
    }
    static let imageCount = 30
    
    var images = (0..<imageCount).map { i in ImageResult(image: UIImage(named: "lighthouse")!, index: i) }
    func getImages(service: GenerationService) {
        print("start")
        Task.init {
            var i = 0
            for await image in service.photos.getImages(limit: PhotoLibraryTestViewModel.imageCount) {

                images[i].image = image.image
                images[i].depth = image.depth
                images[i].canny = image.canny
                i += 1
            }
        }
    }
    
    func upload(image: UIImage, service: GenerationService) {
        
        Task.init {
            do {
                let result = try await service.stableDiffusionClient.upload(image: image, filename: NSUUID().uuidString + ".png")
                print(result ?? "")
            } catch {
                print(error)
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

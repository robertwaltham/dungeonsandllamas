//
//  APITestView.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2024-03-26.
//

import SwiftUI
import Observation

struct APITestView: View {
    @State var viewModel = ViewModel()
    @State var contentViewModel: ContentViewModel

    var body: some View {
        VStack {
            HStack {
                Button("Stream Generate") {
                    viewModel.testStream()
                }.buttonStyle(.bordered)
                
                Button("Generate Image") {
                    viewModel.testImage()
                }.buttonStyle(.bordered)
                
                Button("Styles") {
                    viewModel.imagePromptStyles()
                }.buttonStyle(.bordered)
            }
            HStack {
                ForEach(viewModel.images, id: \.self) { image in
                    Image(uiImage: image)
                }
            }
            Text(viewModel.result)
        }
    }
}

@Observable
class ViewModel {
    let client = APIClient()
    var result = ""
    var images = [UIImage]()
    
    func testStream() {
        result = ""
        Task.init {
            do {
                for try await obj in client.asyncStreamGenerate(prompt: "What is the meaning of life in 30 words or less") {
                    if !obj.done {
                        result += obj.response
                    }
                }
            } catch {
                print(error)
            }
        }
    }
    
    func testImage()  {
        images = []
        
        Task.init {
            do {
                let strings = try await client.generateImage(StableDiffusionOptions(prompt: "a cat in a fancy hat"))
                
                for string in strings {
                    if let data = Data(base64Encoded: string), let image = UIImage(data: data) {
                        images.append(image)
                    }
                }
            } catch {
                print(error)
            }
        }

    }
    
    func imagePromptStyles() {
        client.imagePromptStyles()
    }
}

#Preview {
    let viewModel = ContentViewModel()
    return ContentFlowCoordinator(flowState: viewModel) {
        APITestView(contentViewModel: viewModel)
    }
}

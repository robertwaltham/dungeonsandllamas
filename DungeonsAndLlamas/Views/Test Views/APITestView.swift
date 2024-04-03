//
//  APITestView.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2024-03-26.
//

import SwiftUI
import Observation

struct APITestView: View {
    @State var viewModel: ViewModel = ViewModel()
    @State var flowState: ContentFlowState
    
    var body: some View {
        VStack {
            HStack {
                Button("Stream Generate") {
                    viewModel.testStream()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.loading)
                
                TextField("Stream Prompt", text: $viewModel.llmPrompt, prompt: Text("Prompt"))
                    .frame(minHeight: 30)
                    .padding()
                    .background(Color(white: 0.9))

            }.padding()
            
            Text(viewModel.result)
                .padding()

            HStack {
                Button("Generate Image") {
                    viewModel.testImage()
                }                
                .buttonStyle(.bordered)
                .disabled(viewModel.loading)
                
                TextField("Image Prompt", text: $viewModel.sdPrompt, prompt: Text("Prompt"))
                    .frame(minHeight: 30)
                    .padding()
                    .background(Color(white: 0.9))
            }.padding()
            
            HStack {
                ForEach(viewModel.images, id: \.self) { image in
                    Image(uiImage: image)
                }
            }.padding()
        }
    }
}

@Observable
@MainActor
class ViewModel {
    let client = APIClient()
    var result = ""
    var images = [UIImage]()
    var llmPrompt = "What is the meaning of life in 30 words or less"
    var sdPrompt = "a cat in a fancy hat"
    var loading = false
    
    // SwiftUI will create the state object in a non-isolated context
    nonisolated init() {}
    
    func testStream() {
        
        guard !loading else {
            return
        }
        result = ""
        loading = true
        Task.init {
            do {
                for try await obj in await self.client.asyncStreamGenerate(prompt: llmPrompt) {
                    if !obj.done {
                        self.result += obj.response
                    }
                }
            } catch {
                print(error)
            }
            loading = false
        }
    }
    
    func testImage()  {
        
        guard !loading else {
            return
        }
        images = []
        loading = true
        Task.init {
            do {
                let strings = try await client.generateBase64EncodedImages(StableDiffusionOptions(prompt: sdPrompt))
                
                for string in strings {
                    if let data = Data(base64Encoded: string), let image = UIImage(data: data) {
                        images.append(image)
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
    return ContentFlowCoordinator(flowState: flowState) {
        APITestView(flowState: flowState)
    }
}

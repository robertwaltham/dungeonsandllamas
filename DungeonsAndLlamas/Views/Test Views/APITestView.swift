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
                VStack {
                    Button("Generate Image") {
                        viewModel.testImage()
                    }                
                    .buttonStyle(.bordered)
                    .disabled(viewModel.loading)
                }
                
                VStack {
                    TextField("Image Prompt", text: $viewModel.sdOptions.prompt, prompt: Text("Prompt"))
                        .frame(minHeight: 30)
                        .padding()
                    .background(Color(white: 0.9))
                    
                    TextField("Negative Prompt", text: $viewModel.sdOptions.negativePrompt, prompt: Text("Negative Prompt"))
                        .frame(minHeight: 30)
                        .padding()
                    .background(Color(white: 0.9))
                    
                    HStack {
                        Text("Batch Size \(viewModel.sdOptions.batchSize)")
                        Slider(value: viewModel.batchSizeProxy, in: 1...5)
                    }
                    HStack {
                        Text("Steps \(viewModel.sdOptions.steps)")
                        Slider(value: viewModel.stepsProxy, in: 10...50)
                    }
                    HStack {
                        Text("Size \(viewModel.sdOptions.size)")
                        Slider(value: viewModel.sizeProxy, in: 64...512, step: 64)
                    }
                }
                
            }.padding()
            
            HStack {
                Button("Get Options") {
                    viewModel.getOptions()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.loading)
                
                Spacer()
                
                Button("Get Models") {
                    viewModel.getModels()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.loading)
                
                Picker("Model", selection: $viewModel.selectedModel) {
                    ForEach(viewModel.models, id:\.self) { model in
                        Text(model.modelName)
                    }
                }.frame(minWidth: 300)
                
                Button("Set Model") {
                    viewModel.setModel()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.loading)
            }.padding()
            
            if viewModel.loading {
                HStack {
                    Text("\(viewModel.steps)/\(viewModel.stepGoal)")
                    ProgressView(value: viewModel.progress)
                    Text("\(viewModel.eta)")
                }.padding()
                
                if let image = viewModel.inProgressImage {
                    Image(uiImage: image)
                }
            } else {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(viewModel.images, id: \.self) { image in
                            Image(uiImage: image)
                        }
                    }.padding()
                }
            }

            Spacer()
        }
    }
}

@Observable
@MainActor
class ViewModel {
    let client = APIClient()
    var result = ""
    var images = [UIImage]()
    var inProgressImage: UIImage?
    var llmPrompt = "What is the meaning of life in 30 words or less"
    var loading = false
    var sdOptions = StableDiffusionGenerationOptions(prompt: "a large wizard staff that is presented formally, lying horizontally on a fancy table", negativePrompt: "worst quality, normal quality, low quality, low res, blurry, text, watermark, logo, banner, extra digits, cropped, jpeg artifacts, signature, username, error, sketch ,duplicate, ugly, monochrome, horror, geometry, mutation, disgusting")
    var selectedModel = StableDiffusionModel(title: "n/a", modelName: "n/a", hash: "", sha256: "", filename: "")
    var models = [StableDiffusionModel(title: "n/a", modelName: "n/a", hash: "", sha256: "", filename: "")]

    var batchSizeProxy: Binding<Double>{
        Binding<Double>(get: {
            return Double(self.sdOptions.batchSize)
        }, set: {
            self.sdOptions.batchSize = Int($0)
        })
    }
    
    var stepsProxy: Binding<Double>{
        Binding<Double>(get: {
            return Double(self.sdOptions.steps)
        }, set: {
            self.sdOptions.steps = Int($0)
        })
    }
    
    var sizeProxy: Binding<Double>{
        Binding<Double>(get: {
            return Double(self.sdOptions.size)
        }, set: {
            self.sdOptions.size = Int($0)
        })
    }
    
    var eta = 0.0
    var progress = 0.0
    var steps = 0
    var stepGoal = 0
    
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
    
    func getOptions() {
        loading = true
        Task.init {
            do {
                let options = try await client.imageGenerationOptions()
                print(options)
            } catch {
                print(error)
            }
            loading = false
        }
    }
    
    func getModels() {
        loading = true
        Task.init {
            do {
                models = try await client.imageGenerationModels()
            } catch {
               print(error)
            }
            loading = false
        }
    }
    
    func setModel() {
        loading = true
        Task.init {
            do {
                try await client.setImageGenerationModel(model: selectedModel)
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
        steps = 0
        eta = 0
        stepGoal = sdOptions.steps
        inProgressImage = nil
        
        Task.init {
            do {
                let strings = try await client.generateBase64EncodedImages(sdOptions)
                
                for string in strings {
                    if let data = Data(base64Encoded: string), 
                        let image = UIImage(data: data),
                        Int(image.size.width) <= sdOptions.size { // skip combined image
                        images.append(image)
                    }
                }
            } catch {
                print(error)
            }
            loading = false
        }
        
        Task.init {
            do {
                while loading == true {
                    let progress = try await self.client.imageGenerationProgress()
                    
                    eta = progress.etaRelative
                    self.progress = progress.progress
                    steps = progress.state.samplingStep
                    stepGoal = progress.state.samplingSteps
                    
                    if let currentImage = progress.currentImage,
                        let data = Data(base64Encoded: currentImage),
                        let image = UIImage(data: data) {
                        inProgressImage = image
                    }
                    
                    try await Task.sleep(nanoseconds: 200_000_000)
                }
            } catch {
                print(error)
            }
        }
    }

}

#Preview {
    let flowState = ContentFlowState()
    return ContentFlowCoordinator(flowState: flowState) {
        APITestView(flowState: flowState)
    }
}

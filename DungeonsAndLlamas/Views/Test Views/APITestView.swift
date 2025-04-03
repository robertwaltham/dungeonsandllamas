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
            
            HStack {
                Button("Get Local Models") {
                    viewModel.getLLMModels()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.loading)
                .padding()
                
                Spacer()
                Picker("Model", selection: $viewModel.llmModel) {
                    ForEach(viewModel.llmModels, id:\.self) { model in
                        Text(model.name).tag(model.id)
                    }
                }
                .frame(minWidth: 300)
                Spacer()
            }.onAppear {
                viewModel.getLLMModels()
            }
            
            Text(viewModel.result)
                .padding()
                .onTapGesture {
                    viewModel.sdOptions.prompt += viewModel.result
                }
            
            HStack {
                VStack {
                    Button("Generate Image") {
                        viewModel.testImage()
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.loading)
                    
                    Button("Generate From") {
                        if viewModel.result.count > 0 {
                            viewModel.sdOptions.prompt = viewModel.result
                        }
                        viewModel.testImage2Image()
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.loading)
                    
                    if let image = UIImage(named: "lighthouse") {
                        Image(uiImage: image)
                            .resizable()
                            .frame(width: 100, height: 100).clipped()
                            .onTapGesture {
                                viewModel.describe(image: image)
                            }
                    }
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
                        Slider(value: viewModel.stepsProxy, in: 1...50)
                    }
                    HStack {
                        Text("Size \(viewModel.sdOptions.width)")
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
                            Image(uiImage: image).onTapGesture {
                                viewModel.describe(image: image)
                            }
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
    let llmClient = LargeLangageModelClient()
    let sdClient = StableDiffusionClient()
    var result = ""
    var images = [UIImage]()
    var inProgressImage: UIImage?
//    var llmPrompt = "Describe the image in 30 words or less. Respond only with a comma separated list of the contents"
    var llmPrompt = "Describe the image in as much detail as possible, as if it were a painting"

    var loading = false
    let dndprompt = "modelshoot style, (extremely detailed CG unity 8k wallpaper), full shot body photo of the most beautiful artwork in the world, english medieval pink (dragonborn druid) witch, black silk robe, nature magic, medieval era, painting by Ed Blinkey, Atey Ghailan, Studio Ghibli, by Jeremy Mann, Greg Manchess, Antonio Moro, trending on ArtStation, trending on CGSociety, Intricate, High Detail, Sharp focus, dramatic, painting art by midjourney and greg rutkowski, teal and gold, petals, countryside, action pose, casting a spell, green swirling magic"
    var sdOptions = StableDiffusionClient.GenerationOptions(prompt: "watercolor, painting, ", negativePrompt: "worst quality, normal quality, low quality, low res, blurry, text, watermark, logo, banner, extra digits, cropped, jpeg artifacts, signature, username, error, sketch ,duplicate, ugly, monochrome, horror, geometry, mutation, disgusting")
    var selectedModel = StableDiffusionClient.Model(title: "n/a", modelName: "n/a", hash: "", sha256: "", filename: "")
    var models = [StableDiffusionClient.Model(title: "n/a", modelName: "n/a", hash: "", sha256: "", filename: "")]
    
    var llmModel = LargeLangageModelClient.Model(name: "llama", modifiedAt: "", size: 0, digest: "asdf", details: LargeLangageModelClient.ModelDetails(format: "", family: "llama", parameterSize: "too many", quantizationLevel: "1"))
    var llmModels = [LargeLangageModelClient.Model]()
    
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
            return Double(self.sdOptions.width)
        }, set: {
            self.sdOptions.width = Int($0)
            self.sdOptions.height = Int($0)
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
                for try await obj in await self.llmClient.asyncStreamGenerate(prompt: llmPrompt, model: llmModel) {
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
                let options = try await sdClient.imageGenerationOptions()
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
                models = try await sdClient.imageGenerationModels()
            } catch {
                print(error)
            }
            loading = false
        }
    }
    
    func getLLMModels() {
        loading = true
        Task.init {
            do {
                llmModels = try await llmClient.getLocalModels()
                if let first = llmModels.first {
                    llmModel = first
                }
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
                try await sdClient.setImageGenerationModel(model: selectedModel)
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
                let strings = try await sdClient.generateBase64EncodedImages(sdOptions)
                
                for string in strings {
                    if let data = Data(base64Encoded: string),
                        let image = UIImage(data: data),
                       Int(image.size.width) <= sdOptions.width { // skip combined image
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
                    let progress = try await self.sdClient.imageGenerationProgress()
                    
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
    
    func testImage2Image()  {
        
        guard !loading else {
            return
        }
        images = []
        loading = true
        steps = 0
        eta = 0
        stepGoal = sdOptions.steps
        inProgressImage = nil
        let image = UIImage(named: "lighthouse")!
        guard let base64Image = image.pngData()?.base64EncodedString() else {
            return
        }
        
        
        Task.init {
            do {
                let options = StableDiffusionClient.GenerationOptions(prompt: sdOptions.prompt, negativePrompt: sdOptions.negativePrompt, initImages: [base64Image])
                let strings = try await sdClient.generateBase64EncodedImages(options)
                
                for string in strings {
                    if let data = Data(base64Encoded: string),
                       let image = UIImage(data: data),
                       Int(image.size.width) <= sdOptions.width { // skip combined image
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
                    let progress = try await self.sdClient.imageGenerationProgress()
                    
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
    
    func describe(image: UIImage) {
        guard !loading else {
            return
        }
        loading = true
        result = ""
        guard let imageData = image.jpegData(compressionQuality: 0.8)?.base64EncodedString() else {
            return
        }
        Task.init {
            do {
                for try await obj in await llmClient.asyncStreamGenerate(prompt: llmPrompt, base64Image: imageData, model: llmModel){
                    if !obj.done {
                        result += obj.response
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
    return ContentFlowCoordinator(flowState: flowState, generationService: service) {
        APITestView(flowState: flowState)
    }
}

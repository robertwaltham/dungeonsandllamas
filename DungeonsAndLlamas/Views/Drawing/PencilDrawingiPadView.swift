//
//  PencilDrawingiPadView.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2024-04-15.
//

import SwiftUI
import PencilKit

struct PencilDrawingiPadView: View {
    @State var viewModel: PencilViewModel
    @State var flowState: ContentFlowState
    @State var generationService: GenerationService
    @FocusState private var keyboardShown: Bool
    @State var showPrompts: Bool = false
    @State var showLoras: Bool = false
    @State var generateOnChange: Bool = true

    @State var historyPrompt: String = "History"
    @State var promptAdd: String?

    @MainActor
    init(flowState: ContentFlowState, generationService: GenerationService) {
        self.viewModel = PencilViewModel(generationService: generationService)
        self.flowState = flowState
        self.generationService = generationService
    }
    
    @MainActor
    init(flowState: ContentFlowState, generationService: GenerationService, history: ImageHistoryModel) {
        let viewModel = PencilViewModel(generationService: generationService)
        viewModel.load(history: history)
        self.viewModel = viewModel
        self.flowState = flowState
        self.generationService = generationService
    }
    
    var body: some View {
        ZStack {
            GradientView(type: .greyscale)
            VStack {

                PencilCanvasView(drawing: $viewModel.drawing, showTooltip: $viewModel.showTooltip, contentSize: $generationService.imageSize)
                    .frame(width: 512, height: 512)
                    .onChange(of: viewModel.drawing) { oldValue, newValue in
                        guard !viewModel.loading, generateOnChange else {
                            return
                        }
                        viewModel.generate(output: $viewModel.output, progress: $viewModel.progress, loading: $viewModel.loading, drawingScale: 512)
                    }
                
                TextField("Prompt", text: $viewModel.prompt)
                    .focused($keyboardShown)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .frame(width: 482)
                    .padding()
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerSize: CGSize(width: 10, height: 10)))
                    .onChange(of: keyboardShown) { oldValue, newValue in
                        withAnimation {
                            showPrompts.toggle()
                        }
                    }
                
                if showPrompts {
                    Picker("Prompt", selection: $historyPrompt) {
                        Text("History").tag("History")
                        ForEach(generationService.promptsFromHistory(), id:\.self) { text in
                            Text(text.prefix(60).description)
                        }
                    }
                    .transition(.scale)
                    .animation(.easeInOut(duration: 0.2), value: keyboardShown)
                    .frame(width: 482)
                    .padding()
                    .background(.white)
                    .onChange(of: historyPrompt) { oldValue, newValue in
                        if newValue != "History" {
                            viewModel.prompt = newValue
                        }
                    }
                }
                
                ZStack {
                    if let image = viewModel.output {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 512, height: 512)
                            .background(.white)
                    } else {
                        Rectangle()
                            .foregroundColor(.white)
                            .frame(width: 512, height: 512)
                    }
                    
                    if viewModel.loading {
                        VStack {
                            Spacer()
                            ProgressView(value: viewModel.progress?.progress ?? 0)
                                .frame(width: 500, height: 10)

                        }
                    }
                }.frame(height: 512)

            }                   

            HStack {
                Spacer()
                VStack {
                                
                    Button {
                        guard !viewModel.loading else {
                            return
                        }
                        viewModel.generate(output: $viewModel.output, progress: $viewModel.progress, loading: $viewModel.loading, drawingScale: 512)
                    } label: {
                        
                        HStack {
                            Label("Generate", systemImage: "play.rectangle")
                        }
                        .foregroundColor(.blue)

                    }
                    .padding()
                    
                    
                    Button {
                        guard !viewModel.loading else {
                            return
                        }
                        viewModel.newSeed()
                        viewModel.generate(output: $viewModel.output, progress: $viewModel.progress, loading: $viewModel.loading, drawingScale: 512)
                    } label: {
                        
                        HStack {
                            Label("Seed", systemImage: "dice")
                        }
                        .foregroundColor(.blue)
                    }
                    .padding()

                    Button {
                        viewModel.showTooltip.toggle()
                    } label: {
                        
                        HStack {
                            Label("Tool", systemImage: "paintbrush.pointed")
                        }
                        .foregroundColor(.purple)

                    }
                    .padding()

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
                               
                    Button {
                        viewModel.showTooltip = false
                        flowState.coverItem = .sdHistory
                    } label: {
                        
                        HStack {
                            Label("History", systemImage: "books.vertical.fill")
                        }
                        .foregroundColor(.green)
                        
//                        HStack {
//                            Text("\(viewModel.sequence)")
//                        }
//                        .foregroundColor(.black)

                    }
                    .padding()
                    
                    if let output = viewModel.output {
                        let photo = Photo(image:Image(uiImage:output), caption: viewModel.prompt, description: viewModel.prompt)
                        
                        ShareLink(item: photo,
                                  message: Text(viewModel.prompt) ,
                                  preview: SharePreview(viewModel.prompt,
                                  image: photo))
                        .padding()
                    } else {
                        Label("Share...", systemImage: "square.and.arrow.up")
                        .padding()
                        .foregroundColor(.blue)
                    }
                    
//                    if let drawing = viewModel.drawing {
//                        let drawingFile = Drawing(data: drawing.dataRepresentation(), caption: viewModel.prompt, description: viewModel.prompt)
//                        let image = drawing.image(from: CGRect(x: 0, y: 0, width: 512, height: 512), scale: 1.0)
//                        let photo = Photo(image: Image(uiImage: image), caption: viewModel.prompt, description: viewModel.prompt)
//                        
//                        ShareLink(item: drawingFile,
//                                  message: Text(viewModel.prompt) ,
//                                  preview: SharePreview(viewModel.prompt,
//                                                        image: photo))
//                    }

                    
                    if !viewModel.saved {
                        let label = HStack {
                            Label("Save", systemImage: "photo.badge.arrow.down.fill")
                        }
                        .foregroundColor(.purple)
                        
                        if let output = viewModel.output {
                            Button {
                                UIImageWriteToSavedPhotosAlbum(output, nil, nil, nil)
                                withAnimation(.bouncy) {
                                    viewModel.saved = true
                                }
                            } label: {
                                label
                            }
                            .padding()
                            .disabled(viewModel.loading)
                        } else {
                            label
                                .padding()
                        }

                    } else {
                        Text("Saved!")
                            .padding()
                            .foregroundColor(.purple)
                    }
                    
                    Button {
                        bracket()
                    } label: {
                        
                        HStack {
                            Label("Bracket", systemImage: "list.bullet.clipboard")
                        }
                        .foregroundColor(.yellow)

                    }
                    .disabled(viewModel.loading)
                    .padding()
                    
                    
                    Button {
                        inpaint()
                    } label: {
                        
                        HStack {
                            Label("Inpaint", systemImage: "paintbrush.pointed")
                        }
                        .foregroundColor(.yellow)

                    }
                    .disabled(viewModel.loading)
                    .padding()
                    
                    
                    Button {
                        viewModel.clear()
                    } label: {
                        
                        HStack {
                            Label("Clear", systemImage: "clear")
                        }
                        .foregroundColor(.red)

                    }
                    .disabled(viewModel.loading)
                    .padding()
                    
                }
                .background(Color(white: 0.9))
                .clipShape(RoundedRectangle(cornerSize: CGSize(width: 20, height: 20)))
            }
            .padding(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 10))
            
            HStack {
                Spacer()
                VStack {
                    Spacer()
                    VStack {
                        Picker("Sampler", selection: $viewModel.generationService.selectedSampler) {
                            ForEach(viewModel.generationService.sdSamplers, id:\.self) { sampler in
                                Text(sampler.name).id(sampler)
                            }
                        }
                    }.padding()
                }
            }
        }
    }
    
    func bracket() {
        guard !viewModel.loading else {
            return
        }
        
        guard let history = generationService.lastHistory else {
            return
        }
        
        flowState.nextLink(.bracket(history: history))
    }
    
    func inpaint() {
        guard !viewModel.loading else {
            return
        }
        
        guard let history = generationService.lastHistory else {
            return
        }
        
        flowState.nextLink(.inpaint(history: history))
    }
}

#Preview {
    let flowState = ContentFlowState()
    let service = GenerationService()
    service.setupForTesting()
    Task {
        service.getModels()
    }
    return ContentFlowCoordinator(flowState: flowState, generationService: service) {
        PencilDrawingiPadView(flowState: flowState, generationService: service)
    }
}

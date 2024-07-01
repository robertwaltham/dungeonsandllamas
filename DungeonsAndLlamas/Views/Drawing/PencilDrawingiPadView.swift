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
    init(flowState: ContentFlowState, generationService: GenerationService, history: GenerationService.SDHistoryEntry) {
        let viewModel = PencilViewModel(generationService: generationService)
        viewModel.load(history: history)
        self.viewModel = viewModel
        self.flowState = flowState
        self.generationService = generationService
    }
    
    var body: some View {
        ZStack {
            Color(white: 0.7)
            VStack {

                PencilCanvasView(drawing: $viewModel.drawing, showTooltip: $viewModel.showTooltip, contentSize: $generationService.imageSize)
                    .frame(width: 512, height: 512)
                    .onChange(of: viewModel.drawing) { oldValue, newValue in
                        guard !viewModel.loading, generateOnChange else {
                            return
                        }
                        viewModel.generate(output: $viewModel.output, progress: $viewModel.progress, loading: $viewModel.loading)
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
                    Button("Clear") {
                        viewModel.drawing = nil
                    }
                    .buttonStyle(.bordered)
                    .padding()
                    .foregroundColor(.red)
                    
                    Toggle("", isOn: $generateOnChange)
                        .frame(maxWidth: 0)
                    
                    Button("Go Again") {
                        guard !viewModel.loading else {
                            return
                        }
                        viewModel.generate(output: $viewModel.output, progress: $viewModel.progress, loading: $viewModel.loading)
                    }
                    .buttonStyle(.bordered)
                    .padding()
                    .foregroundColor(.green)
                    
                    let adds = generationService.suggestedPromptAdds()
                    Picker("Prompt Add", selection: $promptAdd) {
                        Label(" Add", systemImage: "plus.app").tag(nil as String?)
                        ForEach(adds.keys.map({$0}), id:\.self) { label in
                            Text(label).tag(label as String?)
                        }
                    }.onChange(of: promptAdd) { _, newValue in
                        if let newValue {
                            viewModel.promptAdd = newValue
                        } else {
                            viewModel.promptAdd = nil
                        }
                    }

                    Button {
                        viewModel.showTooltip.toggle()
                    } label: {
                        
                        HStack {
                            Label("Tool", systemImage: "paintbrush.pointed")
                        }
                        .foregroundColor(.green)

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
                                    Slider(value: $lora.weight)
                                    Text(lora.weight.formatted(.number.precision(.fractionLength(0...2))))
                                        .frame(minWidth: 50)
                                }
                            }
                        }
                        .frame(minWidth: 500)
                        .padding()
                    }

                    
                    Text("Seed")
                    Text("\(viewModel.seed, format: .number.grouping(.never))")
                        .padding(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10))
                        .onTapGesture {
                            viewModel.newSeed()
                        }
                    
                    Button("History") {
                        viewModel.showTooltip = false
                        flowState.coverItem = .sdHistory
                    }
                    .buttonStyle(.bordered)
                    .padding()
                    
                }
                .background(Color(white: 0.9))
                .clipShape(RoundedRectangle(cornerSize: CGSize(width: 20, height: 20)))
            }
            .padding(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 10))
        }
    }
}

#Preview {
    let flowState = ContentFlowState()
    let service = GenerationService()
    service.generateHistoryForTesting()
    Task {
        service.getModels()
    }
    return ContentFlowCoordinator(flowState: flowState, generationService: service) {
        PencilDrawingiPadView(flowState: flowState, generationService: service)
    }
}

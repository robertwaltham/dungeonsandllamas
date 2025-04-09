//
//  PencilOverlayDrawingView.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2025-04-08.
//

import UIKit
import SwiftUI
import PencilKit

struct PencilOverlayDrawingView: View {
    @State var viewModel: PencilViewModel
    @State var flowState: ContentFlowState
    @State var generationService: GenerationService
    @State var showPopover = false
    
    var body: some View {
        
        ZStack {
            GradientView(type: .greyscale)
            
            VStack {
                ZStack {
                    if let input = viewModel.output {
                        Image(uiImage: input)
                    } else {
                        Rectangle().background(.white)
                    }
                    
                    PencilCanvasView(drawing: $viewModel.drawing,
                                     showTooltip: $viewModel.showTooltip,
                                     contentSize: $generationService.imageSize,
                                     opaque: false,
                                     tool: PKInkingTool(.pen, color: .white, width: 1000))
                
                }
                .frame(width: 512, height: 512)
                .onChange(of: viewModel.drawing) { oldValue, newValue in
                    guard !viewModel.loading else {
                        return
                    }
                    viewModel.inpaint(output: $viewModel.inpaintOutput,
                                      progress: $viewModel.progress,
                                      loading: $viewModel.loading,
                                      drawingScale: 512)
                }
                
                HStack {
                    TextEditor(text: $viewModel.prompt)
                    
                    
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
                    
                    Button {
                        showPopover = true
                    } label: {
                        Label("Params", systemImage: "gearshape")
                    }
                    .popover(isPresented: $showPopover) {
                        
                        /*
                         var scheduleBias = 1.0 // 1-8 step 0.1
                         var preservationStrength = 0.5 // 1-8 step 0.05
                         var transitionContrastBoost = 4.0 // 1-32 step 0.5
                         var maskInfluence = 0.0 // 0-1 step 0.05
                         var differenceThreshold = 0.5 // 0-8 step 0.25
                         var differenceContrast = 2 // 0-8 step 0.25
                         */
                        VStack {
                            
                            HStack {
                                Text("Schedule Bias")
                                Slider(value: $viewModel.inpaintOptions.scheduleBias, in: 1.0...8.0, step: 0.1)
                                Text(formatted(viewModel.inpaintOptions.scheduleBias))
                                    .frame(minWidth: 50)
                            }
                            
                            
                        }
                        .onDisappear {
                            print("dissapear")
                            guard !viewModel.loading else {
                                return
                            }
                            viewModel.inpaint(output: $viewModel.inpaintOutput,
                                              progress: $viewModel.progress,
                                              loading: $viewModel.loading,
                                              drawingScale: 512)
                        }
                        .frame(minWidth: 512)
                        .padding()


                    }
                }
                .frame(maxWidth: 512)
                
                
                ZStack {
                    if let input = viewModel.inpaintOutput {
                        Image(uiImage: input)
                    } else {
                        Rectangle().foregroundStyle(.white)
                    }
                    
                    if viewModel.loading {
                        VStack {
                            Spacer()
                            ProgressView(value: viewModel.progress?.progress ?? 0)
                                .frame(width: 500, height: 10)

                        }
                    }
                }
                .frame(width: 512, height: 512)
            }
        }
    }
    
    init(flowState: ContentFlowState, generationService: GenerationService, history: ImageHistoryModel) {
        self.viewModel = PencilViewModel(generationService: generationService)
        self.flowState = flowState
        self.generationService = generationService
        
        self.viewModel.load(history: history)
        self.viewModel.drawing = nil // we don't want the old drawing
        self.viewModel.prompt = "A cat with a fancy hat"
    }
    
    private func formatted(_ input: Double) -> String {
        return input.formatted(.number.precision(.fractionLength(1...2)))
    }
    
}

#Preview {
    
    let flowState = ContentFlowState()
    let service = GenerationService()
    service.setupForTesting()
    Task {
        service.getModels()
    }
    
    let drawingUrl = Bundle.main.url(forResource: "inpaint", withExtension: "drawing")!
    let drawingData = try! Data(contentsOf: drawingUrl)
    let drawing = try! PKDrawing(data: drawingData)
    
    var view = PencilOverlayDrawingView(flowState: flowState,
                                        generationService: service,
                                        history: service.imageHistory.first!)
    view.viewModel.drawing = drawing
    
    return ContentFlowCoordinator(flowState: flowState, generationService: service) {
        view
    }
}

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
                
                Text(viewModel.prompt)
                
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
    
}

#Preview {
    
    let flowState = ContentFlowState()
    let service = GenerationService()
    service.setupForTesting()
    Task {
        service.getModels()
    }
    return ContentFlowCoordinator(flowState: flowState, generationService: service) {
        PencilOverlayDrawingView(flowState: flowState,
                                 generationService: service,
                                 history: service.imageHistory.first!)
    }
}

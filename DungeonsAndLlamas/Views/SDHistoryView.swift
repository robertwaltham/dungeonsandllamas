//
//  SDHistoryView.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2024-04-16.
//

import SwiftUI

struct SDHistoryView: View {
    @State var flowState: ContentFlowState
    @State var generationService: GenerationService

    var body: some View {
        
        VStack {
            
            if flowState.coverItem != nil {
                HStack {
                    Spacer()
                    Button("Close") {
                        flowState.coverItem = nil
                    }
                    .buttonStyle(.bordered)
                    .padding()
                }
            }

            ScrollView {
                ForEach(generationService.SDHistory.reversed()) { history in
                    HStack {
                        
                        if let inputFilePath = history.inputFilePath {
                            Image(uiImage: generationService.fileService.loadImage(path: inputFilePath))
                                .scaleEffect(CGSize(width: 0.5, height: 0.5))
                                .frame(width: 256, height: 256)
                                .clipped()
                                
                        }

                        if let outputFilePath = history.outputFilePaths.first {
                            Image(uiImage: generationService.fileService.loadImage(path: outputFilePath))
                                .scaleEffect(CGSize(width: 0.5, height: 0.5))
                                .frame(width: 256, height: 256)
                                .clipped()

                        }
                        
                        Text(history.prompt)
                            .frame(maxHeight: 256)

                    }
                    .padding()
                }
            }
        }
    }
}

#Preview {
    let flowState = ContentFlowState()
//    flowState.coverItem = .sdHistory
    let service = GenerationService()
    service.generateHistoryForTesting()
    
    return ContentFlowCoordinator(flowState: flowState, generationService: service) {
        SDHistoryView(flowState: flowState, generationService: service)
    }
}

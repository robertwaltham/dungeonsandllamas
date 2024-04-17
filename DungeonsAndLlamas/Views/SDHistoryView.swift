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
    
    @State var presentedHistory: GenerationService.SDHistoryEntry?
    
    
    @ViewBuilder
    @MainActor
    func info(history: GenerationService.SDHistoryEntry) -> some View {
        HStack {
            
            Text(history.prompt)
            Image(uiImage: generationService.loadOutputImage(history: history))
                .resizable()
                .scaledToFit()
        }
    }

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
            
            if let history = presentedHistory {
                VStack{
                    HStack {
                        Image(uiImage: generationService.loadOutputImage(history: history))
                        .resizable()
                        .scaledToFit()
                        
                        Image(uiImage: generationService.loadInputImage(history: history))
                            .resizable()
                            .scaledToFit()
                    }

                    
                    HStack {
                        Text(history.prompt)
                        Text(history.negativePrompt)
                        Button("Close") {
                            withAnimation {
                                presentedHistory = nil
                            }
                        }.buttonStyle(.bordered)
                            .transition(.slide)
                    }
                }
            }

            ScrollView {
                
                let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
                LazyVGrid(columns: columns) {
                    ForEach(generationService.SDHistory.reversed()) { history in
                        Button {
                            withAnimation {
                                presentedHistory = history
                            }
                        } label: {
                            Image(uiImage: generationService.loadOutputImage(history: history))
                                .resizable()
                                .scaledToFit()
                        }
                    }
                }
            }
        }.padding()
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

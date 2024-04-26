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
    @State var filter: String?
    @State var loraFilter: String?
    @State var saved: String?

    
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
 
            HStack {
                Picker("Filter", selection: $filter) {
                    Text("Model Filter").tag(nil as String?)
                    ForEach(generationService.modelsFromHistory(), id: \.self) { model in
                        Text(model).tag(model as String?)
                    }
                }
                Picker("Lora Filter", selection: $loraFilter) {
                    Text("Lora Filter").tag(nil as String?)
                    ForEach(generationService.lorasFromHistory(), id: \.self) { lora in
                        Text(lora).tag(lora as String?)
                    }
                }
                Spacer()
                
                if flowState.coverItem != nil {
                    Button("Close", systemImage: "x.circle") {
                        flowState.coverItem = nil
                    }
                }
            }

            if let history = presentedHistory {
                let image = generationService.loadOutputImage(history: history)
                let output = Image(uiImage: image)

                VStack{
                    HStack {
                        output
                            .resizable()
                            .scaledToFit()
                          
                        
                        Image(uiImage: generationService.loadInputImage(history: history))
                            .resizable()
                            .scaledToFit()
                    }
                    
                    
                    HStack {

                        VStack {
                            Text(history.prompt)
                            if let error = history.errorDescription {
                                Text(error)
                            }
                            if let lora = history.lora {
                                Text(lora + " weight: \(history.loraWeight ?? 0)")
                            }
                        }
                        

                        VStack {


                            HStack {
                                
                                if history.drawingPath != nil {
                                    Button("Remix") {
                                        flowState.nextLink(.drawingFrom(history: history))
                                    }.buttonStyle(.bordered)
                                }
                                
                                Button("Close") {
                                    withAnimation {
                                        presentedHistory = nil
                                    }
                                }.buttonStyle(.bordered)
                                    .transition(.slide)
                                
                            }
                            
                            HStack {
                                let photo = Photo(image: output, caption: history.prompt, description: history.prompt)
                                
                                ShareLink(item: photo, message: Text(history.prompt) ,preview: SharePreview(history.prompt, image: photo))
                                    .padding()
                                
                                if saved != history.id.description {
                                    Button {
                                        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                                        withAnimation(.bouncy) {
                                            saved = history.id.description
                                        }
                                    } label: {
                                        HStack {
                                            Label("Save", systemImage: "photo.on.rectangle.angled")
                                        }
                                        .foregroundColor(.purple)
                                    }
                                } else {
                                    Text("Saved!")
                                        .foregroundColor(.purple)
                                }
  
                            }
                       
                        }
                        

                    }
                }
            }
            
            ScrollView {
                
                let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
                LazyVGrid(columns: columns) {
                    ForEach(generationService.SDHistory.filter({ e in
                        var result = true
                        if let filter {
                            result = e.model == filter
                        }
                        if let loraFilter, result {
                            result = e.lora == loraFilter
                        }
                        return result
                    }) .reversed()) { history in
                        
                        Image(uiImage: generationService.loadOutputImage(history: history))
                            .resizable()
                            .scaledToFit()
                            .onTapGesture {
                                withAnimation {
                                    presentedHistory = history
                                }
                            }
    
                    }
                }
            }
            
            
        }
        .padding()
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

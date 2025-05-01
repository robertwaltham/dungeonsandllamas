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
    @State var presentedHistory: ImageHistoryModel?
    @State var filter: String?
    @State var loraFilter: String?
    @State var saved: String?
    @State var columns = 4
    
    @ViewBuilder
    @MainActor
    func info(history: ImageHistoryModel) -> some View {
        HStack {
            
            Text(history.prompt)
            Image(uiImage: generationService.loadOutputImage(history: history))
                .resizable()
                .scaledToFit()
        }
    }
    
    var body: some View {
        
        ZStack {
            GradientView(type: .greyscale)

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
                    
                    Text("Cols")
                    Picker("End", selection: $columns) {
                        ForEach(3..<10) { i in
                            Text("\(i)").tag(i)
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
                    let imageSize: CGFloat = 400
                    
                    VStack {
                        Text(history.prompt)
                        if let error = history.errorDescription {
                            Text(error)
                        }
                        
                        HStack {
                            output
                                .resizable()
                                .scaledToFit()
                                .frame(width: imageSize, height: imageSize)
                            
                            
                            if history.depthFilePath != nil {
                                ZStack {
                                    Image(uiImage: generationService.loadInputImage(history: history))
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: imageSize, height: imageSize)

                                    HStack {
                                        VStack {
                                            Spacer()
                                            
                                            Image(uiImage: generationService.loadDepthImage(history: history))
                                                .resizable()
                                                .scaledToFit()
                                                .frame(width: imageSize / 4, height: imageSize / 4)
                                                .padding()
                                        }
                                        Spacer()
                                    }
                                }
                                
                            } else {
                                Image(uiImage: generationService.loadInputImage(history: history))
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: imageSize, height: imageSize)
                            }
                        }
                        
                        VStack {
                            
                            HStack {
                                ForEach(history.loras) { lora in
                                    Text(lora.name + ":")
                                    Text(lora.weight, format: .number.precision(.fractionLength(0...2)))
                                }
                                Text(history.sampler)
                                Text("Steps: \(history.steps)")
                                Text("Size: \(history.size)")
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
                                            Label("Save", systemImage: "photo.badge.arrow.down.fill")
                                        }
                                        .foregroundColor(.purple)
                                    }
                                } else {
                                    Text("Saved!")
                                        .foregroundColor(.purple)
                                }
                                
                                if history.drawingFilePath != nil {
                                    Button {
                                        flowState.nextLink(.drawingFrom(history: history))
                                    } label: {
                                        HStack {
                                            Label("Remix", systemImage: "photo.on.rectangle.angled")
                                        }
                                        .foregroundColor(.green)
                                    }
                                    .padding(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 0))
                                }
                                
                                Button {
                                    flowState.nextLink(.bracket(history: history))
                                } label: {
                                    HStack {
                                        Label("Batch", systemImage: "list.bullet.clipboard")
                                    }
                                    .foregroundColor(.yellow)
                                }
                                .padding(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 0))
                                
                                Button {
                                    flowState.nextLink(.step(history: history))
                                } label: {
                                    HStack {
                                        Label("Step", systemImage: "figure.stair.stepper")
                                    }
                                    .foregroundColor(.yellow)
                                }
                                .padding(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 0))
                                
                                Button {
                                    flowState.nextLink(.inpaint(history: history))
                                } label: {
                                    HStack {
                                        Label("InPaint", systemImage: "paintbrush.pointed")
                                    }
                                    .foregroundColor(.green)
                                }
                                .padding(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 0))
                                
                            }
                            
                        }
                    }
                }
                
                ScrollView {
                    
                    let columns: [GridItem] = (0..<columns).map {_ in return GridItem(.flexible())}
                    LazyVGrid(columns: columns) {
                        ForEach(generationService.imageHistory.filter({ e in
                            var result = true
                            if let filter {
                                result = e.model == filter
                            }
                            if let loraFilter, result {
                                result = e.loras.contains { e in
                                    e.name == loraFilter
                                }
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
}

#Preview {
    let flowState = ContentFlowState()
    let service = GenerationService()
    service.setupForTesting()
    
    return ContentFlowCoordinator(flowState: flowState, generationService: service) {
        SDHistoryView(flowState: flowState, generationService: service)
    }
}

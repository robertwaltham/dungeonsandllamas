//
//  SDHistoryView.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2024-04-16.
//

import SwiftUI

struct SDHistoryView: View {
    let flowState: ContentFlowState
    let generationService: GenerationService
    @State var filter: String?
    @State var loraFilter: String?
    @State var columns = 4
    @State private var searchText = ""
    @State private var searchResults: [ImageHistoryModel]?
    @State private var isSearching = false
    @State private var searchError: String?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isCompact: Bool {
        horizontalSizeClass == .compact
    }
    
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
    
    private var displayedHistory: [ImageHistoryModel] {
        let history = searchResults ?? generationService.imageHistory.reversed()
        return history.filter { entry in
            var result = true
            if let filter {
                result = entry.model == filter
            }
            if let loraFilter, result {
                result = entry.loras.contains { lora in
                    lora.name == loraFilter
                }
            }
            return result
        }
    }
    
    private func runSearch() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = nil
            searchError = nil
            return
        }
        
        isSearching = true
        searchError = nil
        Task {
            do {
                searchResults = try await generationService.searchHistory(query: query)
            } catch {
                searchError = error.localizedDescription
                searchResults = []
            }
            isSearching = false
        }
    }
    
    private func clearSearch() {
        searchText = ""
        searchResults = nil
        searchError = nil
    }

    var body: some View {
        
        ZStack {
            GradientView(type: .greyscale)

            VStack {
                
                HStack {
                    
                    if !isCompact {
                        Text("Cols")
                        Picker("End", selection: $columns) {
                            ForEach(3..<10) { i in
                                Text("\(i)").tag(i)
                            }
                        }
                    }
                    
                    TextField("Search", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: isCompact ? 150 : 220)
                        .onSubmit(runSearch)
                    Button("Search", systemImage: "magnifyingglass") {
                        runSearch()
                    }
                    .disabled(isSearching)
                    
                    Button("Clear", systemImage: "xmark.circle") {
                        clearSearch()
                    }
                    .disabled(searchResults == nil)

                    Spacer()
                    
                    if flowState.coverItem != nil {
                        Button("Close", systemImage: "x.circle") {
                            flowState.coverItem = nil
                        }
                    }
                }
                
                if let searchError {
                    Text(searchError)
                        .foregroundStyle(.red)
                }
                
                ScrollView {
                    
                    let columns: [GridItem] = (0..<columns).map {_ in return GridItem(.flexible())}
                    LazyVGrid(columns: columns) {
                        ForEach(displayedHistory) { history in
                            
                            Image(uiImage: generationService.loadOutputImage(history: history))
                                .resizable()
                                .scaledToFit()
                                .onTapGesture {
                                    flowState.sheet(.sdHistoryDetail(history: history))
                                }
                            
                        }
                    }
                }
                
                
            }
            .padding()
        }
    }
}

struct SDHistoryDetailView: View {
    let flowState: ContentFlowState
    let generationService: GenerationService
    let history: ImageHistoryModel
    @State private var saved: String?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var outputImageSize: CGFloat {
        horizontalSizeClass == .compact ? 320 : 400
    }

    private var inputImageSize: CGFloat {
        horizontalSizeClass == .compact ? 180 : 400
    }

    @ViewBuilder
    @MainActor
    private var presentedHistoryView: some View {
        let image = generationService.loadOutputImage(history: history)
        let output = Image(uiImage: image)
        
        ZStack {
            GradientView(type: .greyscale)

            VStack {
                
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
                    
                    if let remixLink = remixLink(for: history) {
                        Button {
                            flowState.presentedItem = nil
                            flowState.nextLink(remixLink)
                        } label: {
                            HStack {
                                Label("Remix", systemImage: "photo.on.rectangle.angled")
                            }
                            .foregroundColor(.green)
                        }
                        .padding(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 0))
                    }
                }
                
                if let error = history.errorDescription {
                    Text(error)
                }

                output
                    .resizable()
                    .scaledToFit()
                    .frame(width: outputImageSize, height: outputImageSize)
                
                Text(history.prompt)

                
                if history.depthFilePath != nil {
                    ZStack {
                        Image(uiImage: generationService.loadInputImage(history: history))
                            .resizable()
                            .scaledToFit()
                            .frame(width: inputImageSize, height: inputImageSize)

                        HStack {
                            VStack {
                                Spacer()
                                
                                Image(uiImage: generationService.loadDepthImage(history: history))
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: inputImageSize / 4, height: inputImageSize / 4)
                                    .padding()
                            }
                            Spacer()
                        }
                    }
                    
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: inputImageSize), spacing: 8)], spacing: 8) {
                        ForEach(Array(generationService.loadInputImages(history: history).enumerated()), id: \.offset) { index, inputImage in
                            VStack(spacing: 4) {
                                Image(uiImage: inputImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: inputImageSize, height: inputImageSize)
                                if history.inputFilePaths.count > 1 {
                                    Text("Image \(index + 1)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var body: some View {
        presentedHistoryView
    }

    private func remixLink(for history: ImageHistoryModel) -> ContentLink? {
        if history.drawingFilePath != nil {
            return .drawingFrom(history: history)
        }
        if history.inputFilePaths.count >= 2,
           history.negativePrompt == "Flux2 Klein 2 image edit" {
            return .twoPhotoEditFrom(history: history)
        }
        return nil
    }
}

#Preview {
    let flowState = ContentFlowState()
    let service = GenerationService()
    service.setupForTesting()
    
    return ContentFlowCoordinator(flowState: flowState) {
        SDHistoryView(flowState: flowState, generationService: service)
    }
    .environment(service)
}

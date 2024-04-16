//
//  PencilTestView.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2024-04-15.
//

import SwiftUI
import PencilKit

struct PencilTestView: View {
    @State var viewModel = PencilTestViewModel()
    @State var flowState: ContentFlowState
    @State var generationService: GenerationService
    
    var body: some View {
        ZStack {
            Color(white: 0.7)
            VStack {

                PencilCanvasView(image: $viewModel.drawing)
                    .frame(width: 512, height: 512)
                    .onChange(of: viewModel.drawing) { oldValue, newValue in
                        guard let drawing = newValue, !viewModel.loading else {
                            return
                        }
                        generationService.image(prompt: viewModel.prompt + viewModel.promptAdd, negativePrompt: viewModel.negative, image: drawing, output: $viewModel.output, progress: $viewModel.progress, loading: $viewModel.loading)
                    }
                
                TextField("Prompt", text: $viewModel.prompt)
                    .frame(width: 482)
                    .padding()
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerSize: CGSize(width: 10, height: 10)))
                ZStack {
                    if let image = viewModel.output {
                        Image(uiImage: image)
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
                    
                    Button("History") {
                        flowState.coverItem = .sdHistory
                    }
                    .buttonStyle(.bordered)
                    .padding()
                    
//                    GeometryReader { proxy in
//                        Button("History") {
//                            flowState.popover(.sdHistory, bounds: .rect(.rect(proxy.frame(in: .global))))
//                        }
//                        .buttonStyle(.bordered)
//                        .position(x: proxy.frame(in: .local).width / 2.0, y: proxy.frame(in: .local).height / 2.0)
//                    }
//                    .frame(maxWidth: 100, maxHeight: 100)
                }
                .background(Color(white: 0.9))
                .clipShape(RoundedRectangle(cornerSize: CGSize(width: 20, height: 20)))
            }
            .padding()
        }
    }
}

@Observable
class PencilTestViewModel {
    var drawing: UIImage?
    var output: UIImage?
    var prompt = "A dragonborn wizard casting a spell swirling magic"
    var promptAdd = ", modelshoot style, extremely detailed CG unity 8k wallpaper, full shot body photo of the most beautiful artwork in the world, english medieval, nature magic, medieval era, painting by Ed Blinkey, Atey Ghailan, Studio Ghibli, by Jeremy Mann, Greg Manchess, Antonio Moro, trending on ArtStation, trending on CGSociety, Intricate, High Detail, Sharp focus, dramatic, painting art by midjourney and greg rutkowski, petals, countryside, action pose"
    var negative = "worst quality, normal quality, low quality, low res, blurry, text, watermark, logo, banner, extra digits, cropped, jpeg artifacts, signature, username, error,duplicate, ugly, monochrome, horror, geometry, mutation, disgusting"
    var loading = false
    var progress: StableDiffusionProgress?
}

struct PencilCanvasView: UIViewRepresentable {
    
    var image: Binding<UIImage?>
    
    func makeUIView(context: Context) -> PKCanvasView {
        let view = PKCanvasView()
        view.drawingPolicy = .anyInput
        view.minimumZoomScale = 1
        view.maximumZoomScale = 1
        view.delegate = context.coordinator
        view.translatesAutoresizingMaskIntoConstraints = false
        
        let picker = PKToolPicker()
        picker.addObserver(context.coordinator)
        picker.addObserver(view)
        picker.setVisible(true, forFirstResponder: view)
        view.becomeFirstResponder()
        context.coordinator.picker = picker

        return view
    }
    
    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        if image.wrappedValue == nil {
            context.coordinator.skipUpdate = true
            uiView.drawing = PKDrawing()
            DispatchQueue.main.async {
                uiView.becomeFirstResponder() // hack to make tool picker show again
            }
        }
    }
    
    func makeCoordinator() -> PencilCanvasViewCoordinator {
        let coordinator = PencilCanvasViewCoordinator()
        coordinator.dataChanged = { image in
            DispatchQueue.main.async {
                self.image.wrappedValue = image
            }
        }
        return coordinator
    }
    
    typealias UIViewType = PKCanvasView
    
    class PencilCanvasViewCoordinator: NSObject, PKCanvasViewDelegate, PKToolPickerObserver {
        
        var dataChanged: ((UIImage) -> Void)?
        var picker: PKToolPicker?
        var skipUpdate = true

        // TODO: figure out why this throws concurrency warnings
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !skipUpdate else {
                skipUpdate = false
                return
            }
            dataChanged?(canvasView.drawing.image(from: CGRect(x: 0, y: 0, width: 512, height: 512), scale: 1.0))
        }
    }
    
}

#Preview {
    let flowState = ContentFlowState()
    let service = GenerationService()
    return ContentFlowCoordinator(flowState: flowState, generationService: service) {
        PencilTestView(flowState: flowState, generationService: service)
    }
}

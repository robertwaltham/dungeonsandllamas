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
                TextField("Prompt", text: $viewModel.prompt)
                    .frame(width: 482)
                    .padding()
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerSize: CGSize(width: 10, height: 10)))
                
//                TextField("Negative", text: $viewModel.negative)
//                    .frame(width: 482)
//                    .padding()
//                    .background(.white)
//                    .clipShape(RoundedRectangle(cornerSize: CGSize(width: 10, height: 10)))

                PencilCanvasView(image: $viewModel.drawing)
                    .frame(width: 512, height: 512)
                    .onChange(of: viewModel.drawing) { oldValue, newValue in
                        guard let drawing = newValue, !viewModel.loading else {
                            return
                        }
                        generationService.image(prompt: viewModel.prompt, negativePrompt: viewModel.negative, image: drawing, output: $viewModel.output, progress: $viewModel.progress, loading: $viewModel.loading)
                    }
                
                if let image = viewModel.output {
                    Image(uiImage: image)
                        .frame(width: 512, height: 512)
                        .background(.white)
                } else {
                    Rectangle()
                        .foregroundColor(.white)
                        .frame(width: 512, height: 512)
                }
            }
            HStack {
                Spacer()
                Button("Clear") {
                    viewModel.drawing = nil
                }
                .buttonStyle(.bordered)
                .padding()
                .foregroundColor(.red)
                
                if viewModel.loading {
                    ProgressView()
                }
            }
        }
    }
}

@Observable
class PencilTestViewModel {
    var drawing: UIImage?
    var output: UIImage?
    var prompt = "A cat wearing a fancy hat"
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
            uiView.drawing = PKDrawing()
        }
    }
    
    func makeCoordinator() -> PencilCanvasViewCoordinator {
        let coordinator = PencilCanvasViewCoordinator()
        coordinator.dataChanged = { image in
            self.image.wrappedValue = image
        }
        return coordinator
    }
    
    typealias UIViewType = PKCanvasView
    
    class PencilCanvasViewCoordinator: NSObject, PKCanvasViewDelegate, PKToolPickerObserver {
        
        var dataChanged: ((UIImage) -> Void)?
        var picker: PKToolPicker?

        // TODO: figure out why this throws concurrency warnings
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
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

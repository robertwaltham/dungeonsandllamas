//
//  PencilCanvasView.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2024-04-16.
//

import Foundation
import SwiftUI
import PencilKit

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

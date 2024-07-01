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
    
    var drawing: Binding<PKDrawing?>
    var showTooltip: Binding<Bool>
    var contentSize: Binding<Int>
    
    func makeUIView(context: Context) -> PKCanvasView {
        let view = PKCanvasView()
        view.drawingPolicy = .anyInput
//        view.minimumZoomScale = 1
//        view.maximumZoomScale = 2
        view.delegate = context.coordinator
        view.translatesAutoresizingMaskIntoConstraints = false
        if let drawing = drawing.wrappedValue {
            view.drawing = drawing
        }
        
        let picker = PKToolPicker()
        picker.addObserver(context.coordinator)
        picker.addObserver(view)
        picker.setVisible(true, forFirstResponder: view)
        view.becomeFirstResponder()
        context.coordinator.picker = picker

        return view
    }
    
    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        if drawing.wrappedValue == nil {
            context.coordinator.skipUpdate = true
            uiView.drawing = PKDrawing()
        }
        
//        uiView.contentSize = CGSize(width: contentSize.wrappedValue, height: contentSize.wrappedValue)
        
        if showTooltip.wrappedValue {
            DispatchQueue.main.async {
                uiView.becomeFirstResponder()
            }
        } else {
            uiView.resignFirstResponder()
        }
    }
    
    func makeCoordinator() -> PencilCanvasViewCoordinator {
        let coordinator = PencilCanvasViewCoordinator()
        coordinator.dataChanged = { image in
            DispatchQueue.main.async {
                self.drawing.wrappedValue = image
            }
        }
        return coordinator
    }
    
    typealias UIViewType = PKCanvasView
    

    class PencilCanvasViewCoordinator: NSObject, PKCanvasViewDelegate, PKToolPickerObserver {
        
        var dataChanged: ((PKDrawing) -> Void)?
        var picker: PKToolPicker?
        var skipUpdate = true

        // TODO: figure out why this throws concurrency warnings
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !skipUpdate else {
                skipUpdate = false
                return
            }
            dataChanged?(canvasView.drawing)
        }
    }
    
}

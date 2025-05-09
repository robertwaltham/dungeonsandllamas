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
    var opaque = true
    var tool: PKTool? = nil
    
    init(drawing: Binding<PKDrawing?>, showTooltip: Binding<Bool>, contentSize: Binding<Int>, opaque: Bool = true,
         tool: PKTool? = nil) {
        self.drawing = drawing
        self.showTooltip = showTooltip
        self.contentSize = contentSize
        self.opaque = opaque
        self.tool = tool
    }
    
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
        view.isOpaque = opaque
        
        if let tool {
            view.tool = tool
        } else {
            let picker = PKToolPicker()
            picker.addObserver(context.coordinator)
            picker.addObserver(view)
            picker.setVisible(true, forFirstResponder: view)
            view.becomeFirstResponder()
            context.coordinator.picker = picker
        }


        return view
    }
    
    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        if drawing.wrappedValue == nil {
            context.coordinator.skipUpdate = true
            uiView.drawing = PKDrawing()
        }
                
        if showTooltip.wrappedValue {
            DispatchQueue.main.async {
                uiView.becomeFirstResponder()
            }
        } else {
            uiView.resignFirstResponder()
        }
        
        if let tool {
            uiView.tool = tool
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

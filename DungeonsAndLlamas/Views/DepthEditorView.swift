//
//  DepthEditorView.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2025-05-08.
//

import SwiftUI
import Observation
import PencilKit

struct DepthEditorView: View {
    var flowState: ContentFlowState
    @State var generationService: GenerationService
    @State var viewModel: DepthEditorViewModel
    @Environment(\.undoManager) private var undoManager
    
    var body: some View {
        ZStack {
            GradientView(type: .greyscale)
            VStack {
                ZStack {
                    Image(uiImage: viewModel.input)
                    PencilCanvasView(drawing: viewModel.drawing,
                                     showTooltip: $viewModel.showTooltip,
                                     contentSize: $generationService.imageSize,
                                     opaque: false,
                                     tool: viewModel.tool)
                }
                .frame(width: CGFloat(generationService.imageSize),
                       height: CGFloat(generationService.imageSize))
                
                VStack {
                    HStack {
                        Slider(value: $viewModel.toolWhite) {
                            Text("Depth")
                        } minimumValueLabel: {
                            Text("Farther")
                        } maximumValueLabel: {
                            Text("Nearer")
                        }
                        .onChange(of: viewModel.toolWhite, { oldValue, newValue in
                            viewModel.updateTool()
                        })
                        .padding()
                        
                        Button {
                            undoManager?.undo()
                        } label: {
                            Text("Undo")
                        }
                        .padding(EdgeInsets(top: 5, leading: 5, bottom: 5, trailing: 5))
                        .background(Color(white: 0.8))
                        .clipShape(RoundedRectangle(cornerSize: CGSize(width: 5, height: 5)))

                    }
                    .padding()
                    
                    HStack {
                        Picker("style", selection: $viewModel.inkType) {
                            Text("Watercolor").tag(PKInkingTool.InkType.watercolor)
                            Text("Crayon").tag(PKInkingTool.InkType.crayon)
                            Text("Marker").tag(PKInkingTool.InkType.marker)

                        }
                        .pickerStyle(.segmented)
                        .padding()
                        .onChange(of: viewModel.inkType, { oldValue, newValue in
                            viewModel.updateTool()
                        })
                        
                        Button {
                            viewModel.finalize(size: CGFloat(generationService.imageSize), flowState: flowState)
                        } label: {
                            Label("Done", systemImage: "square.and.arrow.down")
                        }
                        .padding(EdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 8))
                        .background(Color(white: 0.8))
                        .clipShape(RoundedRectangle(cornerSize: CGSize(width: 5, height: 5)))
                        .padding()
                    }
                }
                .background(Color(white: 1.0, opacity: 0.5))
                .clipShape(RoundedRectangle(cornerSize: CGSize(width: 10, height: 10)))
                .padding()
                
            }
        }
    }
}

@Observable
class DepthEditorViewModel {
    let output: Binding<UIImage>
    let input: UIImage
    var showTooltip = false
    var drawing: Binding<PKDrawing?>
    var toolWhite = 0.5
    var tool = PKInkingTool(.watercolor, color: UIColor(white: 0.5, alpha: 1.0))
    var inkType: PKInkingTool.InkType = .watercolor
    
    func updateTool() {
        tool = PKInkingTool(inkType, color: UIColor(white: toolWhite, alpha: 1.0))
    }
    
    init(output: Binding<UIImage>, input: UIImage, drawing: Binding<PKDrawing?>) {
        self.output = output
        self.drawing = drawing
        self.input = input
    }
    
    func finalize(size: CGFloat, flowState: ContentFlowState) {
        
        defer {
            flowState.pop()
        }
        
        guard let drawing = drawing.wrappedValue else {
            return
        }
        
        let size = CGSize(width: size, height: size)
        let areaSize = CGRect(x: 0, y: 0, width: size.width, height: size.height)

        
        let drawingImage = drawing.image(from: areaSize, scale: 1.0)
        
        UIGraphicsBeginImageContext(size)
        input.draw(in: areaSize)
        drawingImage.draw(in: areaSize, blendMode: .normal, alpha: 1.0)
        guard let newImage:UIImage = UIGraphicsGetImageFromCurrentImageContext() else {
            return
        }
        UIGraphicsEndImageContext()
        
        output.wrappedValue = newImage
    }
}


#Preview {
    let flowState = ContentFlowState()
    let service = GenerationService()
    service.setupForTesting()
    var image = UIImage(named: "depth_preview")!
    var drawing: PKDrawing? = nil
    let drawiningBinding = Binding {
        drawing
    } set: { newDrawing in
        drawing = newDrawing
    }
    
    let output = Binding {
        image
    } set: { newImage in
        image = newImage
    }

    let viewModel = DepthEditorViewModel(output: output, input: image, drawing: drawiningBinding)
    
    return ContentFlowCoordinator(flowState: flowState, generationService: service) {
        DepthEditorView(flowState: flowState, generationService: service, viewModel: viewModel)
    }
}

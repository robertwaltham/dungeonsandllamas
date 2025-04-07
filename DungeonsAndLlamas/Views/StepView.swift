//
//  StepView.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2025-04-07.
//

import SwiftUI
import UIKit
import Foundation


struct StepView: View {
    
    @State var flowState: ContentFlowState
    @State var viewModel: PencilViewModel
    @State var generationService: GenerationService
    @State var cancel = true

    let imageSize: CGFloat = 200
    
    init(flowState: ContentFlowState, generationService: GenerationService, history: ImageHistoryModel) {
        self.flowState = flowState
        self.viewModel = PencilViewModel(generationService: generationService)
        self.generationService = generationService
        
        self.viewModel.load(history: history)
    }
    
    var body: some View {
        
        ZStack {
            GradientView(type: .greyscale)
            
            ScrollView {
                ZStack {
                    HStack {
                        ZStack {

                            if let input = viewModel.input {
                                Image(uiImage: input)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: imageSize, height: imageSize)
                                    .background(.white)
                            } else {
                                Rectangle()
                                    .foregroundColor(.white)
                                    .frame(width: imageSize, height: imageSize)
                            }
                            
                            VStack {
                                Text("Input")
                                Spacer()
                            }
                            
                        }.frame(maxHeight: imageSize)
                        
                        ZStack {
                            if let output = viewModel.output {
                                Image(uiImage: output)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: imageSize, height: imageSize)
                                    .background(.white)
                            } else {
                                Rectangle()
                                    .foregroundColor(.white)
                                    .frame(width: imageSize, height: imageSize)
                            }
                            VStack {
                                Text("Output")
                                Spacer()
                            }
                        }.frame(maxHeight: imageSize)
                    }
                   
                    if viewModel.loading {
                        VStack {
                            Spacer()
                            HStack {
                                ProgressView(value: viewModel.progress?.progress ?? 0)
                                Text("\(viewModel.stepResult.count) / \(viewModel.stepEnd + 1 - viewModel.stepStart)")
                            }
                            .padding()
                            .frame(width: 400)
                        }
                    }
                }
                
                
                Text(viewModel.prompt)

                
                HStack {
                    
                    VStack {
                        if !cancel {
                            Button("Cancel") {
                                cancel = true
                            }
                            .buttonStyle(.bordered)
                            .padding()
                            .foregroundColor(.red)
                        } else {
                            Button("Generate") {
                                guard !viewModel.loading else {
                                    return
                                }
                                
                                viewModel.generateSteps(progress: $viewModel.progress, loading: $viewModel.loading, cancel: $cancel)

                            }
                            .disabled(viewModel.loading)
                            .buttonStyle(.bordered)
                            .padding()
                            .foregroundColor(.green)
                        }

                    }.frame(minWidth: 225)
                    
                    Text("Start")
                    Picker("Start", selection: $viewModel.stepStart) {
                        ForEach(1..<30) { i in
                            Text("\(i)").tag(i)
                        }
                    }
                    .pickerStyle(.wheel)
                    
                    Text("End")
                    Picker("End", selection: $viewModel.stepEnd) {
                        ForEach(1..<30) { i in
                            Text("\(i)").tag(i)
                        }
                    }
                    .pickerStyle(.wheel)
                    
                }.frame(maxHeight: 125)
                
                if viewModel.stepResult.count > 0  {
                    let columns: [GridItem] = (0..<3).map {_ in return GridItem(.flexible())}
                    LazyVGrid(columns: columns) {
                        ForEach(viewModel.stepResult, id: \.self) { stepResult in
                            ZStack {
                                Image(uiImage: stepResult.result)
                                    .resizable()
                                    .scaledToFit()
                                
                                VStack {
                                    
                                    if viewModel.savedResults.contains(stepResult.id) {
                                        Text("Saved!")
                                            .foregroundColor(.yellow)
                                    } else {
                                        Button {
                                            viewModel.save(stepResult: stepResult)
                                        } label: {
                                            Label("Save", systemImage: "square.and.arrow.down")
                                        }
                                        .foregroundColor(.yellow)
                                    }

                                    
                                    Spacer()
                                    
                                    Text("\(stepResult.steps)")
                                    
                                }
                            }
                            .shadow(radius: 2)
                            .frame(maxHeight: 320)
                        }
                    }
                }
            }
        }
        
    }
}


#Preview {
    let flowState = ContentFlowState()
    let service = GenerationService()
    service.setupForTesting()
    Task {
        service.getModels()
    }
    let view = StepView(flowState: flowState, generationService: service, history: service.imageHistory.first!)
    for i in 0..<27 {
        view.viewModel.stepResult.append(
            GenerationService.Step.init(steps: i, start: Date.now.addingTimeInterval(TimeInterval(i)), end: Date.now.addingTimeInterval(TimeInterval(i + 5)), result: UIImage(named: "lighthouse")!)
        )
    }
    return ContentFlowCoordinator(flowState: flowState, generationService: service) {
        return view
    }
}

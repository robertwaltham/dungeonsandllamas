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
    @State var iterateSamplers = false
    @State var columns = 3

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
                                let stepCount = viewModel.stepEnd + 1 - viewModel.stepStart
                                if (iterateSamplers) {
                                    Text("\(viewModel.stepResult.count) / \(stepCount * generationService.sdSamplers.count)")
                                } else {
                                    Text("\(viewModel.stepResult.count) / \(viewModel.stepEnd + 1 - viewModel.stepStart)")

                                }
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
                                
                                viewModel.generateSteps(progress: $viewModel.progress,
                                                        loading: $viewModel.loading,
                                                        cancel: $cancel,
                                                        iterateSamplers: iterateSamplers)

                            }
                            .disabled(viewModel.loading)
                            .buttonStyle(.bordered)
                            .padding()
                            .foregroundColor(.green)
                        }

                    }
                    
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
                    
                    Toggle("Sampler", isOn: $iterateSamplers).padding()
                    
                    
                    Text("Cols")
                    Picker("End", selection: $columns) {
                        ForEach(3..<7) { i in
                            Text("\(i)").tag(i)
                        }
                    }
                    
                }
                .frame(maxHeight: 125)
                .disabled(viewModel.loading)
                
                if viewModel.stepResult.count > 0  {
                    let columns: [GridItem] = (0..<columns).map {_ in return GridItem(.flexible())}
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
                                    
                                    Text("\(stepResult.steps) | \(stepResult.sampler)")
                                    
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
            GenerationService.Step.init(steps: i, start: Date.now.addingTimeInterval(TimeInterval(i)), end: Date.now.addingTimeInterval(TimeInterval(i + 5)), result: UIImage(named: "lighthouse")!, sampler: "sampler \(i)")
        )
    }
    return ContentFlowCoordinator(flowState: flowState, generationService: service) {
        return view
    }
}

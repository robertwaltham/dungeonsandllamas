//
//  BracketView.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2025-04-02.
//

import SwiftUI
import Observation
import PencilKit

struct BracketView: View {
    @State var flowState: ContentFlowState
    @State var viewModel: PencilViewModel
    @State var generationService: GenerationService
    @State private var showingPopover = false
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
                                Text("\(viewModel.brackets.count) / \(viewModel.bracketCount())")
                            }
                            .padding()
                            .frame(width: 400)
                        }
                    }
                }.frame(height: 220)
                VStack {

                    HStack {
                        
                        let nameBinding = Binding {
                            viewModel.firstBracketLora.name
                        } set: { value in
                            viewModel.firstBracketLora.name = value
                            viewModel.firstBracketLora.activation = viewModel.loras.first(where: { lora in
                                lora.name == value
                            })?.activation // TODO: fix this stupid garbage
                        }
                        
                        Picker("First Lora", selection: nameBinding) {
                            Text("First Lora").tag("n/a")
                            ForEach(viewModel.loras, id:\.self) { lora in
                                Text(lora.name).tag(lora.name)
                            }
                        }
                        
                        let minBinding = Binding {
                            viewModel.firstBracketLora.bracketMin
                        } set: { value in
                            viewModel.firstBracketLora.bracketMin = value
                        }

                        Text("Min")
                        Picker("Min", selection: minBinding) {
                            ForEach(-5..<8) { value in
                                let weight = Double(value) / 10.0
                                Text(formatted(weight)).tag(weight)
                            }
                        }
                        
                        let maxBinding = Binding {
                            viewModel.firstBracketLora.bracketMax
                        } set: { value in
                            viewModel.firstBracketLora.bracketMax = value
                        }

                        Text("Max")
                        Picker("Max", selection: maxBinding) {
                            ForEach(5..<12) { value in
                                let weight = Double(value) / 10.0
                                Text(formatted(weight)).tag(weight)
                            }
                        }
                        
                        let stepBinding = Binding {
                            viewModel.firstBracketLora.bracketSteps
                        } set: { value in
                            viewModel.firstBracketLora.bracketSteps = value
                        }

                        Text("Steps")
                        Picker("Steps", selection: stepBinding) {
                            ForEach(3..<6) { value in
                                Text(value.description).tag(value)
                            }
                        }
                    }
                    .disabled(viewModel.loading)
                    
                    HStack {
                        
                        let nameBinding = Binding {
                            viewModel.secondBracketLora.name
                        } set: { value in
                            viewModel.secondBracketLora.name = value
                            viewModel.secondBracketLora.activation = viewModel.loras.first(where: { lora in
                                lora.name == value
                            })?.activation // TODO: fix this stupid garbage
                        }
                        
                        Picker("Second Lora", selection: nameBinding) {
                            Text("Second Lora").tag("n/a")
                            ForEach(viewModel.loras, id:\.self) { lora in
                                Text(lora.name).tag(lora.name)
                            }
                        }
                        
                        let minBinding = Binding {
                            viewModel.secondBracketLora.bracketMin
                        } set: { value in
                            viewModel.secondBracketLora.bracketMin = value
                        }

                        Text("Min")
                        Picker("Min", selection: minBinding) {
                            ForEach(-5..<8) { value in
                                let weight = Double(value) / 10.0
                                Text(formatted(weight)).tag(weight)
                            }
                        }
                        
                        let maxBinding = Binding {
                            viewModel.secondBracketLora.bracketMax
                        } set: { value in
                            viewModel.secondBracketLora.bracketMax = value
                        }

                        Text("Max")
                        Picker("Max", selection: maxBinding) {
                            ForEach(5..<12) { value in
                                let weight = Double(value) / 10.0
                                Text(formatted(weight)).tag(weight)
                            }
                        }
                        
                        let stepBinding = Binding {
                            viewModel.secondBracketLora.bracketSteps
                        } set: { value in
                            viewModel.secondBracketLora.bracketSteps = value
                        }

                        Text("Steps")
                        Picker("Steps", selection: stepBinding) {
                            ForEach(3..<6) { value in
                                Text(value.description).tag(value)
                            }
                        }
                    }
                    .disabled(viewModel.loading)
                    
                    HStack {
                        
                        let nameBinding = Binding {
                            viewModel.thirdBracketLora.name
                        } set: { value in
                            viewModel.thirdBracketLora.name = value
                            viewModel.thirdBracketLora.activation = viewModel.loras.first(where: { lora in
                                lora.name == value
                            })?.activation // TODO: fix this stupid garbage
                        }
                        
                        Picker("Third Lora", selection: nameBinding) {
                            Text("Third Lora").tag("n/a")
                            ForEach(viewModel.loras, id:\.self) { lora in
                                Text(lora.name).tag(lora.name)
                            }
                        }
                        
                        let minBinding = Binding {
                            viewModel.thirdBracketLora.bracketMin
                        } set: { value in
                            viewModel.thirdBracketLora.bracketMin = value
                        }

                        Text("Min")
                        Picker("Min", selection: minBinding) {
                            ForEach(-5..<8) { value in
                                let weight = Double(value) / 10.0
                                Text(formatted(weight)).tag(weight)
                            }
                        }
                        
                        let maxBinding = Binding {
                            viewModel.thirdBracketLora.bracketMax
                        } set: { value in
                            viewModel.thirdBracketLora.bracketMax = value
                        }

                        Text("Max")
                        Picker("Max", selection: maxBinding) {
                            ForEach(5..<12) { value in
                                let weight = Double(value) / 10.0
                                Text(formatted(weight)).tag(weight)
                            }
                        }
                        
                        let stepBinding = Binding {
                            viewModel.thirdBracketLora.bracketSteps
                        } set: { value in
                            viewModel.thirdBracketLora.bracketSteps = value
                        }

                        Text("Steps")
                        Picker("Steps", selection: stepBinding) {
                            Text("n/a").tag(0)
                            ForEach(3..<6) { value in
                                Text(value.description).tag(value)
                            }
                        }
                    }
                    .disabled(viewModel.loading)
                }
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
                            Button("Generate Brackets") {
                                guard !viewModel.loading else {
                                    return
                                }
                                viewModel.generateBrackets(progress: $viewModel.progress, loading: $viewModel.loading, cancel: $cancel)
                            }
                            .disabled(viewModel.loading)
                            .buttonStyle(.bordered)
                            .padding()
                            .foregroundColor(.green)
                        }

                    }.frame(minWidth: 225)
                    
                    Text(viewModel.prompt)
                }
                Spacer()
                

                if viewModel.brackets.count > 0  {
                    let columns: [GridItem] = (0..<4).map {_ in return GridItem(.flexible())}
                    LazyVGrid(columns: columns) {
                        ForEach(viewModel.brackets, id: \.self) { bracket in
                            ZStack {
                                Image(uiImage: bracket.result)
                                    .resizable()
                                    .scaledToFit()
                                
                                VStack {
                                    
                                    if viewModel.savedBrackets.contains(bracket.id) {
                                        Text("Saved!")
                                            .foregroundColor(.yellow)
                                    } else {
                                        Button {
                                            viewModel.save(bracket: bracket)
                                            
                                        } label: {
                                            Label("Save", systemImage: "square.and.arrow.down")
                                        }
                                        .foregroundColor(.yellow)
                                    }

                                    
                                    Spacer()
                                    
                                    if let third = bracket.thirdLora {
                                        Text("\(formatted(bracket.firstLora.weight)) |  \(formatted(bracket.secondLora.weight)) | \(formatted(third.weight))")
                                    } else {
                                        Text("\(formatted(bracket.firstLora.weight)) |  \(formatted(bracket.secondLora.weight))")
                                    }
                                    
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
    
    private func formatted(_ input: Double) -> String {
        return input.formatted(.number.precision(.fractionLength(0...2)))
    }
}

#Preview {
    let flowState = ContentFlowState()
    let service = GenerationService()
    service.setupForTesting()
    Task {
        service.getModels()
    }
    let view = BracketView(flowState: flowState, generationService: service, history: service.imageHistory.first!)
    for _ in 0..<27 {
        view.viewModel.brackets.append(
            GenerationService.Bracket.init(firstLora: GenerationService.LoraInvocation.init(name: "first lora", weight: Double.random(in: 0.0...1.0)),
                                           secondLora: GenerationService.LoraInvocation.init(name: "second lora", weight: Double.random(in: 0.0...1.0)),
                                           thirdLora: nil,
                                           start: Date.now,
                                           end: Date.now,
                                           result: UIImage(named: "lighthouse")!)
        )
    }
    return ContentFlowCoordinator(flowState: flowState, generationService: service) {
        return view
    }
}




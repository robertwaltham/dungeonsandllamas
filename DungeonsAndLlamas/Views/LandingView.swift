//
//  LandingView.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2024-04-01.
//

import SwiftUI

struct LandingView: View {    
    @State var flowState: ContentFlowState
    @State var generationService: GenerationService
    @State var history = [UIImage]()
    let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    
    var body: some View {
        ZStack {
            GradientView(type: .greyscale)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]) {
                ForEach(history, id:\.self) { img in
                    
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                }
            }
            .onAppear {
                history = generationService.imageHistory.filter { entry in
                    entry.errorDescription == nil
                }
                .shuffled()
                .prefix(20)
                .map{ entry in
                    return generationService.loadOutputImage(history: entry)
                }
            }
            .onReceive(timer) { input in
                withAnimation(.linear(duration: 1.0)) {
                    if history.count > 1 {
                        let random = Int.random(in: 0..<history.count - 1) // TODO: fix bug with last cell sliding animation
                        let img = generationService.loadOutputImage(history: generationService.imageHistory.randomElement()!)
                        if history.firstIndex(of: img) == nil {
                            history[random] = img
                        }
                    }
                }
            }
                
            VStack {
                Spacer()
                VStack{
                    Text("Dungeons & Llamas")
                        .font(.largeTitle)
                        .shadow(color:.gray, radius: 2.0)
                    
                    Text("A generative journey")
                        .font(.title)
                        .shadow(color:.gray, radius: 2.0)

                }
//                .shadow(radius: 10)
//                .padding(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
//                .background(Color(red: 0.8, green: 0.8, blue: 0.8, opacity: 0.5))
//                .clipShape(RoundedRectangle(cornerSize: CGSize(width: 20, height: 20)))
                
        
                
                Spacer().frame(maxHeight: 200)
                
                let size: CGFloat = 150
                HStack {
                    Button(action: {
                        flowState.nextLink(.modelInfo)
                    }, label: {
                        Text("Model Info")
                    })
                    .frame(width: size, height: size)
                    .background(Color(white: 0.7))
                    .clipShape(RoundedRectangle(cornerSize: CGSize(width: 20, height: 20)))
                    
                    Button(action: {
                        flowState.nextLink(.drawing)
                    }, label: {
                        Text("Drawing")
                    })
                    .frame(width: size, height: size)
                    .background(Color(white: 0.7))
                    .clipShape(RoundedRectangle(cornerSize: CGSize(width: 20, height: 20)))
                    
                    Button(action: {
                        flowState.nextLink(.sdHistory)
                    }, label: {
                        Text("History")
                    })
                    .frame(width: size, height: size)
                    .background(Color(white: 0.7))
                    .clipShape(RoundedRectangle(cornerSize: CGSize(width: 20, height: 20)))
                }
                
                HStack {
                    Button(action: {
                        flowState.nextLink(.depth)
                    }, label: {
                        Text("Depth")
                    })
                    .frame(width: size, height: size)
                    .background(Color(white: 0.7))
                    .clipShape(RoundedRectangle(cornerSize: CGSize(width: 20, height: 20)))
                    
                    Button(action: {
                        flowState.nextLink(.apiTest)
                    }, label: {
                        Text("API Test")
                    })
                    .frame(width: size, height: size)
                    .background(Color(white: 0.7))
                    .clipShape(RoundedRectangle(cornerSize: CGSize(width: 20, height: 20)))
                }
                
                Spacer()
                
                HStack {
                    
                    ZStack {
                        if generationService.llmStatus.connected {
                            RoundedRectangle(cornerSize: CGSize(width: 20, height: 20)).frame(width: 70, height: 70)
                                .foregroundColor(.green)
                        } else {
                            RoundedRectangle(cornerSize: CGSize(width: 20, height: 20)).frame(width: 70, height: 70)
                                .foregroundColor(.red)
                        }
                        
                        Text("LLM")
                    }

                    ZStack {
                        if generationService.sdStatus.connected {
                            RoundedRectangle(cornerSize: CGSize(width: 20, height: 20)).frame(width: 70, height: 70)
                                .foregroundColor(.green)
                        } else {
                            RoundedRectangle(cornerSize: CGSize(width: 20, height: 20)).frame(width: 70, height: 70)
                                .foregroundColor(.red)
                        }
                        
                        Text("SD")
                    }
                }.padding()
                    .onTapGesture {
                        generationService.checkStatusIfNeeded()
                    }
            }
        }
    }
}

#Preview {
    let flowState = ContentFlowState()
    let service = GenerationService()
    service.setupForTesting()
    return ContentFlowCoordinator(flowState: flowState, generationService: service) {
        LandingView(flowState: flowState, generationService: service)
    }
}

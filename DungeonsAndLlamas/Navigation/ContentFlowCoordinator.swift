//
//  ContentFlowCoordinator.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2024-04-01.
//

import Foundation
import SwiftUI

struct ContentFlowCoordinator<Content: View>: View {
    @State var flowState: ContentFlowState
    @State var generationService: GenerationService
    let userInterfaceIdiom: UIUserInterfaceIdiom
    
    @MainActor
    init(flowState: ContentFlowState, generationService: GenerationService, content: @escaping () -> Content) {
        self.flowState = flowState
        self.generationService = generationService
        self.content = content
        
        self.userInterfaceIdiom = UIDevice.current.userInterfaceIdiom
    }
    
    let content: () -> Content
    
    var body: some View {
        NavigationStack(path: $flowState.path) {
            ZStack {
                content()
                    .sheet(item: $flowState.presentedItem, content: sheetContent)
                    .fullScreenCover(item: $flowState.coverItem, content: coverContent)
            }
            .navigationDestination(for: ContentLink.self, destination: linkDestination)
            .popover(item: $flowState.popoverItem, attachmentAnchor: flowState.popoverBounds, content: popoverContent)
        }
    }
}

extension ContentFlowCoordinator {
    
    @MainActor @ViewBuilder private func destination(link: ContentLink) -> some View {
        
        switch userInterfaceIdiom {
            
        case .phone:
            
            switch link {
            case .drawing:
                PencilDrawingiPhoneView(flowState: flowState, generationService: generationService)
                //                    .navigationTitle("Drawing")
            case .drawingFrom(let history):
                PencilDrawingiPhoneView(flowState: flowState, generationService: generationService, history: history)
                //                    .navigationTitle("Drawing")
            case .accelerometer:
                AccelerometerTestView(flowState: flowState)
            case .apiTest:
                APITestView(flowState: flowState)
            case .itemGenerator:
                ItemGeneratorView(flowState: flowState)
            case .sdHistory:
                SDHistoryView(flowState: flowState, generationService: generationService)
                    .navigationTitle("History")
            case .modelInfo:
                ModelSettingsView(flowState: flowState, generationService: generationService)
                    .navigationTitle("Model Info")
            case .bracket(history: let history):
                BracketView(flowState: flowState, generationService: generationService, history: history)
            case .lora(lora: let lora):
                LoraView(lora: lora)
            case .step(history: let history):
                StepView(flowState: flowState, generationService: generationService, history: history)
            case .inpaint(history: let history):
                PencilOverlayDrawingView(flowState: flowState, generationService: generationService, history: history)
           
            default:
                VStack {
                    Text("Implement Me in ContentFlowCoordinator.swift").font(.largeTitle)
                }
            }
            
        default:
            
            switch link {
            case .drawing:
                PencilDrawingiPadView(flowState: flowState, generationService: generationService)
                    .navigationTitle("Drawing")
            case .drawingFrom(let history):
                PencilDrawingiPadView(flowState: flowState, generationService: generationService, history: history)
                    .navigationTitle("Drawing")
            case .accelerometer:
                AccelerometerTestView(flowState: flowState)
            case .apiTest:
                APITestView(flowState: flowState)
            case .itemGenerator:
                ItemGeneratorView(flowState: flowState)
            case .sdHistory:
                SDHistoryView(flowState: flowState, generationService: generationService)
                    .navigationTitle("History")
            case .modelInfo:
                ModelSettingsView(flowState: flowState, generationService: generationService)
                    .navigationTitle("Model Info")
            case .bracket(history: let history):
                BracketView(flowState: flowState, generationService: generationService, history: history)
            case .lora(lora: let lora):
                LoraView(lora: lora)
            case .step(history: let history):
                StepView(flowState: flowState, generationService: generationService, history: history)
            case .inpaint(history: let history):
                PencilOverlayDrawingView(flowState: flowState, generationService: generationService, history: history)
            case .depth:
                DepthGenerationView(flowState: flowState, generationService: generationService)
            default:
                VStack {
                    Text("Implement Me in ContentFlowCoordinator.swift").font(.largeTitle)
                }
            }
        }
        
    }
    
    @MainActor @ViewBuilder private func linkDestination(link: ContentLink) -> some View {
        destination(link: link)
    }
    
    @MainActor @ViewBuilder private func sheetContent(link: ContentLink) -> some View {
        destination(link: link)
    }
    
    @MainActor @ViewBuilder private func coverContent(link: ContentLink) -> some View {
        destination(link: link)
    }
    
    @MainActor @ViewBuilder private func popoverContent(link: ContentLink) -> some View {
        destination(link: link).padding()
    }
}

@Observable
class ContentFlowState {
    var path: NavigationPath = NavigationPath()
    var presentedItem: ContentLink?
    var coverItem: ContentLink?
    var popoverItem: ContentLink?
    var popoverBounds: PopoverAttachmentAnchor = .rect(.rect(CGRect()))
    
    func pop() {
        guard !path.isEmpty else {
            return
        }
        
        path.removeLast()
    }
    
    func closeCover() {
        coverItem = nil
    }
    
    func closePopover() {
        popoverItem = nil
    }
    
    func sheet(_ link: ContentLink) {
        guard coverItem == nil && presentedItem == nil else {
            return
        }
        
        presentedItem = link
    }
    
    func cover(_ link: ContentLink) {
        guard coverItem == nil && presentedItem == nil else {
            return
        }
        
        coverItem = link
    }
    
    func popover(_ link: ContentLink, bounds: PopoverAttachmentAnchor) {
        self.popoverBounds = bounds
        popoverItem = link
    }
    
    func nextLink(_ link: ContentLink) {
        guard coverItem == nil && presentedItem == nil else {
            return
        }
        
        path.append(link)
    }
}

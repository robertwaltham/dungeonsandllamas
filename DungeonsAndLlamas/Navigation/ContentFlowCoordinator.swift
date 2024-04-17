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
    
    @ViewBuilder private func destination(link: ContentLink) -> some View {
        
        switch link {
        case .drawing:
            PencilTestView(flowState: flowState, generationService: generationService)
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
        default:
            VStack {
                Text("Link Destination \(link.id)")
                HStack {
                    Button("pop") {
                        flowState.pop()
                    }.buttonStyle(.bordered)
                    
                    Button("push") {
                        flowState.nextLink(.firstLink(text: "push"))
                    }.buttonStyle(.bordered)
                }
                HStack {
                    Button("close cover") {
                        flowState.closeCover()
                    }.buttonStyle(.bordered)
                    Button("close popover") {
                        flowState.closePopover()
                    }.buttonStyle(.bordered)
                }
            }
        }

    }
    
    @ViewBuilder private func linkDestination(link: ContentLink) -> some View {
        destination(link: link)
    }
    
    @ViewBuilder private func sheetContent(link: ContentLink) -> some View {
        destination(link: link)
    }
    
    @ViewBuilder private func coverContent(link: ContentLink) -> some View {
        destination(link: link)
    }
    
    @ViewBuilder private func popoverContent(link: ContentLink) -> some View {
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

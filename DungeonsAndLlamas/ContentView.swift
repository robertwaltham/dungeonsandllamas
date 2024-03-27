//
//  ContentView.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2024-03-26.
//

import SwiftUI
import SwiftData
import Observation

struct ContentView: View {
    @State var viewModel = ContentViewModel()
    
    var body: some View {
        ContentFlowCoordinator(flowState: viewModel) {
            VStack {
                HStack {
                    NavigationLink("Link", value: ContentLink.firstLink(text: "text"))

                    Button("Sheet") {
                        viewModel.sheet(.firstLink(text: "sheet"))
                    }.buttonStyle(.bordered)
                    
                    Button("Cover") {
                        viewModel.cover(.firstLink(text: "cover"))
                    }.buttonStyle(.bordered)
                    
                    Button("Link") {
                        viewModel.nextLink(.firstLink(text: "link"))
                    }.buttonStyle(.bordered)
                    
                    GeometryReader { proxy in
                        Button("Popover") {
                            viewModel.popover(.firstLink(text: "popover"), bounds: .rect(.rect(proxy.frame(in: .global))))
                        }
                        .buttonStyle(.bordered)
                        .position(x: proxy.frame(in: .local).width / 2.0, y: proxy.frame(in: .local).height / 2.0)
                    }
                    .frame(maxWidth: 100, maxHeight: 100)
                }
                
                Button("Accelerometer") {
                    viewModel.nextLink(.accelerometer)
                }
                .frame(width: 200, height: 200)
                .buttonStyle(.bordered)

                
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct ContentFlowCoordinator<Content: View>: View {
    @State var flowState: ContentViewModel
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
        
        if link == .accelerometer {
            AccelerometerView(contentViewModel: flowState)
        } else {
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
}

class ContentViewModel: ContentFlowState {
    
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

enum ContentLink: Identifiable, Hashable {
    var id: String {
        String(describing: self)
    }
    
//    var description: String {
//        switch self {
//            
//        case .firstLink(text: let text):
//            return "/First/\(text)"
//        case .secondLink(text: let text):
//            return "/Second/\(text)"
//        }
//    }
    
    case firstLink(text: String)
    case secondLink(text: String)
    case accelerometer
}

#Preview {
    ContentView()
}

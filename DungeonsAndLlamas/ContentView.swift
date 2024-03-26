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
    @State var path = NavigationPath()
    @State var viewModel = ContentViewModel()
    
    var body: some View {
        ContentFlowCoordinator(flowState: viewModel) {
            VStack {
                NavigationLink("Link", value: ContentLink.firstLink(text: "text"))
                Button("Sheet") {
                    viewModel.sheet()
                }.buttonStyle(.bordered)
                Button("Cover") {
                    viewModel.cover()
                }.buttonStyle(.bordered)
                
                GeometryReader { proxy in
                    Button("Popover") {
                        viewModel.popover(bounds: .rect(.rect(proxy.frame(in: .global))))
                    }
                    .buttonStyle(.bordered)
                    .position(x: proxy.frame(in: .local).width / 2.0, y: proxy.frame(in: .local).height / 2.0)
                }
                .frame(maxWidth: 200, maxHeight: 100)

                
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
    @ViewBuilder private func linkDestination(link: ContentLink) -> some View {
        Text("Link Destination \(link.id)")
    }
    
    @ViewBuilder private func sheetContent(link: ContentLink) -> some View {
        Text("Sheet Content \(link.id)")
    }
    
    @ViewBuilder private func coverContent(link: ContentLink) -> some View {
        Text("Cover content \(link.id)")
    }
    
    @ViewBuilder private func popoverContent(link: ContentLink) -> some View {
        Text("Popover content \(link.id)")
    }
}

@Observable
class ContentFlowState {
    var path = NavigationPath()
    var presentedItem: ContentLink?
    var coverItem: ContentLink?
    var popoverItem: ContentLink?
    var popoverBounds: PopoverAttachmentAnchor = .rect(.rect(CGRect()))
}

class ContentViewModel: ContentFlowState {
    func sheet() {
        presentedItem = .firstLink(text: "first link")
    }
    
    func cover() {
        coverItem = .secondLink(text: "second link")
    }
    
    func popover(bounds: PopoverAttachmentAnchor) {
        self.popoverBounds = bounds
        popoverItem = .secondLink(text: "second link")
    }
}

enum ContentLink: Identifiable, Hashable {
    var id: String {
        String(describing: self)
    }
    
    case firstLink(text: String)
    case secondLink(text: String)
}

#Preview {
    ContentView()
}

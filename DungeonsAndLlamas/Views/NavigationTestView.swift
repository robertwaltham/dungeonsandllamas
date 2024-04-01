//
//  NavigationTestView.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2024-04-01.
//

import SwiftUI

struct NavigationTestView: View {
    @State var viewModel: ContentViewModel

    var body: some View {
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
            
            HStack {
                Button("Accelerometer") {
                    viewModel.nextLink(.accelerometer)
                }
                .frame(width: 200, height: 200)
                .buttonStyle(.bordered)
                
                Button("API Test") {
                    viewModel.nextLink(.apiTest)
                }
                .frame(width: 200, height: 200)
                .buttonStyle(.bordered)
                
                Button("Item Generator") {
                    viewModel.nextLink(.itemGenerator)
                }
                .frame(width: 200, height: 200)
                .buttonStyle(.bordered)
            }

            
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    let viewModel = ContentViewModel()
    return ContentFlowCoordinator(flowState: viewModel) {
        NavigationTestView(viewModel: viewModel)
    }
}

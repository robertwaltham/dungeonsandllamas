//
//  LandingView.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2024-04-01.
//

import SwiftUI

struct LandingView: View {    
    @State var viewModel: ContentViewModel

    var body: some View {
        VStack {
            Text("Dungeons & Llamas")
                .font(.title)
            Text("A generative journey").font(.subheadline)
            
            Spacer().frame(maxHeight: 200)
            
            Button(action: {
                viewModel.nextLink(.itemGenerator)
            }, label: {
                Text("Items")
            })
            .frame(width: 200, height: 200)
            .background(Color(white: 0.7))
            .clipShape(RoundedRectangle(cornerSize: CGSize(width: 20, height: 20)))
        }
    }
}

#Preview {
    let viewModel = ContentViewModel()
    return ContentFlowCoordinator(flowState: viewModel) {
        LandingView(viewModel: viewModel)
    }
}

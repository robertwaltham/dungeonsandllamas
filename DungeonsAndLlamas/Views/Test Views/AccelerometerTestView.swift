//
//  AccelerometerView.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2024-03-26.
//

import SwiftUI
import CoreMotion

struct AccelerometerTestView: View {
    @State var viewModel = AccelerometerViewModel()
    @State var flowState: ContentFlowState
    
    var body: some View {
        VStack {
            Text("Hello, World!")
          
            Rectangle()
                .foregroundStyle(Color(white: 0.9))
                .frame(maxWidth: 300, maxHeight: 300)
                .shadow(radius: 10, x: viewModel.roll * 20, y: viewModel.pitch * 20)

            Button("Cover") {
                flowState.cover(.firstLink(text: "cover"))
            }.buttonStyle(.bordered)
            
            Button("next") {
                flowState.nextLink(.accelerometer)
            }.buttonStyle(.bordered)
        }
    }
}

@Observable
class AccelerometerViewModel {
    private var manager: CMMotionManager?
    var pitch = 0.0
    var roll = 0.0
    var yaw = 0.0
    init() {
        manager = CMMotionManager()
        manager?.deviceMotionUpdateInterval = 0.1
        manager?.startDeviceMotionUpdates(to: .main) { [weak self] (motion, error) in
            if let motion = motion {
                self?.pitch = motion.attitude.pitch
                self?.roll = motion.attitude.roll
                self?.yaw = motion.attitude.yaw
            }
        }
    }
}

#Preview {
    let flowState = ContentFlowState()
    let service = GenerationService()
    return ContentFlowCoordinator(flowState: flowState, generationService: service) {
        AccelerometerTestView(flowState: flowState)
    }
}

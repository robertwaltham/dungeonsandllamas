//
//  CameraTestView.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2025-04-02.
//

import SwiftUI
import MijickCamera

struct CameraTestView: View {
    
    var body: some View {
        MCamera()
            .setAudioAvailability(false)
            .onImageCaptured { image, controller in
                print(image)
                controller.reopenCameraScreen()
            }
        
            .startSession()
    }
}

#Preview {
    CameraTestView()
}


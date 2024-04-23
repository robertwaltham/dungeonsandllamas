//
//  Pencilswift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2024-04-17.
//

import Foundation
import UIKit
import PencilKit
import SwiftUI

@Observable
class PencilViewModel {
    
    @MainActor
    init(generationService: GenerationService) {
        self.generationService = generationService
        self.prompt = generationService.lastPrompt()
    }
    
    var generationService: GenerationService
    var drawing: PKDrawing?
    var output: UIImage?
    var prompt: String

    var promptAdd: String?
    
    var negative = "worst quality, normal quality, low quality, low res, blurry, text, watermark, logo, banner, extra digits, cropped, jpeg artifacts, signature, username, error,duplicate, ugly, monochrome, horror, geometry, mutation, disgusting"
    
    var loading = false
    var progress: StableDiffusionProgress?
    var showTooltip = true
    var useLora = false
    var selectedLora: StableDiffusionLora?
    var loraWeight: Double = 0
    var seed = Int.random(in: 0...Int(Int16.max))
    
    func newSeed() {
        seed = Int.random(in: 0...Int(Int16.max))
    }
    
    @MainActor
    func load(history: GenerationService.SDHistoryEntry) {
        drawing = generationService.loadDrawing(history: history)
        prompt = history.prompt
        output = generationService.loadOutputImage(history: history)
        useLora = history.lora != nil
        selectedLora = generationService.SDLoras.first { lora in
            lora.name == history.lora
        }
        loraWeight = history.loraWeight ?? 0
        promptAdd = history.promptAdd
        seed = history.seed ?? -1
    }
    
    @MainActor
    func generate(output: Binding<UIImage?>, progress: Binding<StableDiffusionProgress?>, loading: Binding<Bool>) {
        if let drawing {
            generationService.image(prompt: prompt, promptAddon: promptAdd, negativePrompt: negative, lora: selectedLora, loraWeight: loraWeight, seed: seed, drawing: drawing, output: output, progress: progress, loading: loading)
        }
    }
}

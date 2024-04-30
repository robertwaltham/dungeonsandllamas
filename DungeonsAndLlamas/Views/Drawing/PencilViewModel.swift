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
class PencilViewModel: @unchecked Sendable { // TODO: proper approach to making the observation tracking sendable
    
    @MainActor
    init(generationService: GenerationService) {
        self.generationService = generationService
        self.prompt = generationService.lastPrompt()
        self.loras = generationService.sdLoras.map { lora in
            GenerationService.LoraInvocation.init(name: lora.name, weight: 0)
        }
        withObservationTracking {
            _ = generationService.sdLoras
        } onChange: {
            Task {
                // TODO: preserve weights
                self.loras = await generationService.sdLoras.map { lora in
                    GenerationService.LoraInvocation.init(name: lora.name, weight: 0)
                }
            }
        }

    }
    
    var generationService: GenerationService
    var drawing: PKDrawing?
    var output: UIImage?
    var prompt: String

    var promptAdd: String?
    
    var negative = "worst quality, normal quality, low quality, low res, blurry, text, watermark, logo, banner, extra digits, cropped, jpeg artifacts, signature, username, error, duplicate, ugly, monochrome, horror, geometry, mutation, disgusting"
    
    var loading = false
    var progress: StableDiffusionClient.Progress?
    var showTooltip = true
    
    var loras: [GenerationService.LoraInvocation]
    var enabledLoras: [GenerationService.LoraInvocation] {
        loras.filter { $0.weight > 0}
    }
    var seed = Int.random(in: 0...Int(Int16.max))
    
    func newSeed() {
        seed = Int.random(in: 0...Int(Int16.max))
    }
    
    @MainActor
    func load(history: GenerationService.SDHistoryEntry) {
        drawing = generationService.loadDrawing(history: history)
        prompt = history.prompt
        output = generationService.loadOutputImage(history: history)
        for i in 0..<loras.count {
            loras[i].weight = history.loras?.first { lora in lora.name == loras[i].name }?.weight ?? 0
        }
        promptAdd = history.promptAdd
        seed = history.seed ?? -1
        generationService.selectedSampler = generationService.sdSamplers.first { sampler in
            sampler.name == history.sampler
        } ?? StableDiffusionClient.defaultSampler
    }
    
    @MainActor
    func generate(output: Binding<UIImage?>, progress: Binding<StableDiffusionClient.Progress?>, loading: Binding<Bool>) {
        if let drawing {
            generationService.image(prompt: prompt, promptAddon: promptAdd, negativePrompt: negative, loras: enabledLoras, seed: seed, drawing: drawing, output: output, progress: progress, loading: loading)
        }
    }
}

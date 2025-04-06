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
            GenerationService.LoraInvocation.init(name: lora.name, weight: 0, activation: lora.activation)
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
    var input: UIImage?
    var prompt: String
    var promptAdd: String?
    
    var session = NSUUID().uuidString
    var sequence = 0
    
    var negative = ""//"worst quality, normal quality, low quality, low res, blurry, text, watermark, logo, banner, extra digits, cropped, jpeg artifacts, signature, username, error, duplicate, ugly, monochrome, horror, geometry, mutation, disgusting"
    
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
    
    var brackets: [GenerationService.Bracket] = []
    var firstBracketLora = GenerationService.LoraInvocation(name: "n/a", weight: 0, bracketSteps: 3, bracketMin: 0.0, bracketMax: 1.0)
    var secondBracketLora = GenerationService.LoraInvocation(name: "n/a", weight: 0, bracketSteps: 3, bracketMin: 0.0, bracketMax: 1.0)
    var thirdBracketLora = GenerationService.LoraInvocation(name: "n/a", weight: 0, bracketSteps: 0, bracketMin: 0.0, bracketMax: 1.0)
    
    var saved: Bool = false
    
    @MainActor func clear() {
        drawing = nil
        output = nil
        input = nil
        sequence = 0
        session = NSUUID().uuidString
    }
    
    @MainActor
    func load(history: ImageHistoryModel) {
        drawing = generationService.loadDrawing(history: history)
        prompt = history.prompt
        output = generationService.loadOutputImage(history: history)
        input = generationService.loadInputImage(history: history)
        session = history.session
        sequence = history.sequence

        var loadedCount = 0
        for i in 0..<loras.count {
            loras[i].weight = history.loras.first { lora in lora.name == loras[i].name }?.weight ?? 0
            
            if loras[i].weight > 0 {
                if loadedCount == 0 {
                    firstBracketLora.name = loras[i].name
                    loadedCount += 1;
                } else if loadedCount == 1 {
                    secondBracketLora.name = loras[i].name
                    loadedCount += 1;
                } else if loadedCount == 2 {
                    thirdBracketLora.name = loras[i].name
                    loadedCount += 1;
                }
            }
        }
        seed = history.seed
        generationService.selectedSampler = generationService.sdSamplers.first { sampler in
            sampler.name == history.sampler
        } ?? StableDiffusionClient.defaultSampler
        generationService.steps = history.steps
        generationService.imageSize = history.size
    }
    
    @MainActor
    func generate(output: Binding<UIImage?>, progress: Binding<StableDiffusionClient.Progress?>, loading: Binding<Bool>, drawingScale: CGFloat) {
        if let drawing {
            generationService.image(prompt: prompt,
                                    promptAddon: promptAdd,
                                    negativePrompt: negative,
                                    loras: enabledLoras,
                                    seed: seed,
                                    session: session,
                                    sequence: sequence,
                                    drawing: drawing,
                                    drawingScale: drawingScale,
                                    output: output,
                                    progress: progress,
                                    loading: loading)
            sequence += 1
            saved = false
        }
    }
    
    func bracketCount() -> Int {
        return firstBracketLora.bracketSteps * secondBracketLora.bracketSteps * (thirdBracketLora.bracketSteps > 0 ? thirdBracketLora.bracketSteps : 1)
    }
    
    @MainActor
    func generateBrackets(progress: Binding<StableDiffusionClient.Progress?>, loading: Binding<Bool>) {
        brackets = []
        guard let input else {
            return
        }
        guard firstBracketLora.bracketSteps > 0 else {
            return
        }
        guard secondBracketLora.bracketSteps > 0 else {
            return
        }
        print("generating")
        loading.wrappedValue = true
        
        Task.detached {
            // TODO: inherit known values from options
            progress.wrappedValue = StableDiffusionClient.Progress(progress: 0, etaRelative: 0, state: StableDiffusionClient.Progress.State.initial())
            do {
                while loading.wrappedValue == true {
                    progress.wrappedValue = try await self.generationService.stableDiffusionClient.imageGenerationProgress()
                    
                    if let prog = progress.wrappedValue {
                        print("eta:\(prog.etaRelative) count:\(prog.state.jobCount)")
                    }

                    try await Task.sleep(nanoseconds: 200_000_000)
                }
            } catch {
                print(error)
            }
        }

        Task.init {
            for try await obj in generationService.bracketImage(input: input, prompt: prompt, negativePrompt: negative, seed: seed, firstLora: firstBracketLora, secondLora: secondBracketLora, thirdLora: thirdBracketLora, loading: loading, progress: progress) {
                brackets.append(obj)
            }
            loading.wrappedValue = false
            print("finished")
        }
    }
}


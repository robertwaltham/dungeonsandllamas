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
    
    var bracketResult: [GenerationService.Bracket] = []
    var firstBracketLora = GenerationService.LoraInvocation(name: "n/a", weight: 0, bracketSteps: 3, bracketMin: 0.0, bracketMax: 1.0)
    var secondBracketLora = GenerationService.LoraInvocation(name: "n/a", weight: 0, bracketSteps: 3, bracketMin: 0.0, bracketMax: 1.0)
    var thirdBracketLora = GenerationService.LoraInvocation(name: "n/a", weight: 0, bracketSteps: 0, bracketMin: 0.0, bracketMax: 1.0)
    var savedResults = [String]()
    var stepResult: [GenerationService.Step] = []
    var stepStart: Int = 20
    var stepEnd: Int = 23

    
    var saved: Bool = false
    var loadedHistory: ImageHistoryModel?
    
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
                    firstBracketLora.activation = loras[i].activation
                    loadedCount += 1;
                } else if loadedCount == 1 {
                    secondBracketLora.name = loras[i].name
                    secondBracketLora.activation = loras[i].activation
                    loadedCount += 1;
                } else if loadedCount == 2 {
                    thirdBracketLora.name = loras[i].name
                    thirdBracketLora.activation = loras[i].activation
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
        loadedHistory = history
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
    func save(bracket: GenerationService.Bracket) {
        loadedHistory?.sequence += 1 // TODO: make database own sequences
        
        guard let loadedHistory else {
            return
        }
        
        guard !savedResults.contains(bracket.id) else {
            return
        }
        
        var newHistory = loadedHistory
        newHistory.id = bracket.id
        newHistory.outputFilePath = generationService.fileService.save(image: bracket.result)
        newHistory.loras = []
        newHistory.loras.append(LoraHistoryModel(id: NSUUID().uuidString, name: bracket.firstLora.name, weight: bracket.firstLora.weight, historyModelId: newHistory.id))
        newHistory.loras.append(LoraHistoryModel(id: NSUUID().uuidString, name: bracket.secondLora.name, weight: bracket.secondLora.weight, historyModelId: newHistory.id))
        if let thirdLora = bracket.thirdLora {
            newHistory.loras.append(LoraHistoryModel(id: NSUUID().uuidString, name: thirdLora.name, weight: thirdLora.weight, historyModelId: newHistory.id))
        }
        
        generationService.db.save(history: newHistory)
        generationService.imageHistory.append(newHistory)
        savedResults.append(bracket.id)
        print("saved")
    }
    
    @MainActor
    func save(stepResult: GenerationService.Step) {
        loadedHistory?.sequence += 1 // TODO: make database own sequences
        
        guard let loadedHistory else {
            return
        }
        
        guard !savedResults.contains(stepResult.id) else {
            return
        }
        
        var newHistory = loadedHistory
        newHistory.id = stepResult.id
        newHistory.outputFilePath = generationService.fileService.save(image: stepResult.result)
        newHistory.steps = stepResult.steps
        generationService.db.save(history: newHistory)
        generationService.imageHistory.append(newHistory)
        savedResults.append(stepResult.id)
        print("saved")
    }
    
    @MainActor
    func generateSteps(progress: Binding<StableDiffusionClient.Progress?>, loading: Binding<Bool>, cancel: Binding<Bool>) {
        
        guard let input else {
            print("no input")
            return
        }
        
        guard let loadedHistory else {
            print("no history")
            return
        }
        
//        guard stepStart < stepEnd else {
//            return
//        }
        stepResult = []
        print("generating")
        loading.wrappedValue = true
        cancel.wrappedValue = false
        
        Task.detached {
            // TODO: inherit known values from options
            progress.wrappedValue = StableDiffusionClient.Progress(progress: 0, etaRelative: 0, state: StableDiffusionClient.Progress.State.initial())
            do {
                while loading.wrappedValue == true {
                    progress.wrappedValue = try await self.generationService.stableDiffusionClient.imageGenerationProgress()

                    try await Task.sleep(nanoseconds: 200_000_000)
                }
            } catch {
                print(error)
            }
        }
        
        Task.init {
            for try await obj in generationService.stepImage(input: input,
                                                             stepStart: stepStart,
                                                             stepEnd: stepEnd,
                                                             history: loadedHistory,
                                                             loading: loading,
                                                             progress: progress,
                                                             cancel: cancel) {
                
                stepResult.append(obj)
            }
            loading.wrappedValue = false
            cancel.wrappedValue = true
            print("finished")
        }
        
    }
    
    @MainActor
    func generateBrackets(progress: Binding<StableDiffusionClient.Progress?>, loading: Binding<Bool>, cancel: Binding<Bool>) {
        guard let input else {
            return
        }
        guard firstBracketLora.bracketSteps > 0 && firstBracketLora.name !=  "n/a" else {
            return
        }
        guard secondBracketLora.bracketSteps > 0 && secondBracketLora.name != "n/a" else {
            return
        }
        
        bracketResult = []
        print("generating")
        loading.wrappedValue = true
        cancel.wrappedValue = false
        
        Task.detached {
            // TODO: inherit known values from options
            progress.wrappedValue = StableDiffusionClient.Progress(progress: 0, etaRelative: 0, state: StableDiffusionClient.Progress.State.initial())
            do {
                while loading.wrappedValue == true {
                    progress.wrappedValue = try await self.generationService.stableDiffusionClient.imageGenerationProgress()

                    try await Task.sleep(nanoseconds: 200_000_000)
                }
            } catch {
                print(error)
            }
        }

        Task.init {
            for try await obj in generationService.bracketImage(input: input,
                                                                prompt: prompt,
                                                                negativePrompt: negative,
                                                                seed: seed,
                                                                firstLora: firstBracketLora,
                                                                secondLora: secondBracketLora,
                                                                thirdLora: thirdBracketLora,
                                                                loading: loading,
                                                                progress: progress,
                                                                cancel: cancel) {
                bracketResult.append(obj)
            }
            loading.wrappedValue = false
            cancel.wrappedValue = true

            print("finished")
        }
    }
}


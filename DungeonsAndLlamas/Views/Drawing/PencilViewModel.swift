//
//  PencilViewModel.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2024-04-17.
//

import Foundation
import UIKit

@Observable
class PencilViewModel {
    
    init(generationService: GenerationService) {
        self.generationService = generationService
    }
    
    var generationService: GenerationService
    var drawing: UIImage?
    var output: UIImage?
//    var prompt = "A dragonborn wizard casting a spell swirling magic"
    var prompt = "A cat wearing a fancy hat"

    var promptAdd = ", modelshoot style, extremely detailed CG unity 8k wallpaper, full shot body photo of the most beautiful artwork in the world, english medieval, nature magic, medieval era, painting by Ed Blinkey, Atey Ghailan, Studio Ghibli, by Jeremy Mann, Greg Manchess, Antonio Moro, trending on ArtStation, trending on CGSociety, Intricate, High Detail, Sharp focus, dramatic, painting art by midjourney and greg rutkowski, petals, countryside, action pose"
    var negative = "worst quality, normal quality, low quality, low res, blurry, text, watermark, logo, banner, extra digits, cropped, jpeg artifacts, signature, username, error,duplicate, ugly, monochrome, horror, geometry, mutation, disgusting"
    var loading = false
    var progress: StableDiffusionProgress?
    var includePromptAdd = true
    var showTooltip = true
    var useLora = false
    var selectedLora: StableDiffusionLora?
    var loraWeight: Double = 0
    
    func imagePrompt() -> String {
        
        return includePromptAdd ? prompt + promptAdd : prompt
    }
}

//
//  ContentLink.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2024-04-01.
//

import Foundation
import SwiftUI
import UIKit
import PencilKit

enum ContentLink: Hashable, Equatable, Identifiable {
    static func == (lhs: ContentLink, rhs: ContentLink) -> Bool {
        return lhs.hashValue == rhs.hashValue
    }
    
    // TODO: handle non-hashable types better
    func hash(into hasher: inout Hasher) {
        switch self {
            
        case .firstLink(text: let text):
            hasher.combine("firstLink" + text)
        case .secondLink(text: let text):
            hasher.combine("secondLink" + text)
        case .accelerometer:
            hasher.combine("accelerometer")
        case .apiTest:
            hasher.combine("apiTest")
        case .drawing:
            hasher.combine("drawing")
        case .drawingFrom(history: let history):
            hasher.combine("drawingFrom" + history.id)
        case .itemGenerator:
            hasher.combine("itemGenerator")
        case .sdHistory:
            hasher.combine("sdHistory")
        case .modelInfo:
            hasher.combine("modelInfo")
        case .bracket(history: let history):
            hasher.combine("bracket" + history.id)
        case .step(history: let history):
            hasher.combine("step" + history.id)
        case .lora(lora: let lora):
            hasher.combine("lora" + lora.id)
        case .inpaint(history: let history):
            hasher.combine("inpaint" + history.id)
        case .depth:
            hasher.combine("depth")
        case .depthGeneration(localIdentifier: let localIdentifier):
            hasher.combine("depthGeneration" + localIdentifier)
        case .depthEditor(input: let input, output: _, drawing: _):
            hasher.combine("depthEdit" + input.hashValue.description)
        }
    }
    
    var id: Int {
        self.hashValue
    }
    
    case firstLink(text: String)
    case secondLink(text: String)
    case accelerometer
    case apiTest
    case drawing
    case drawingFrom(history: ImageHistoryModel)
    case itemGenerator
    case sdHistory
    case modelInfo
    case bracket(history: ImageHistoryModel)
    case step(history: ImageHistoryModel)
    case lora(lora: StableDiffusionClient.Lora)
    case inpaint(history: ImageHistoryModel)
    case depth
    case depthGeneration(localIdentifier: String)
    case depthEditor(input: UIImage, output: Binding<UIImage>, drawing: Binding<PKDrawing?>)
}


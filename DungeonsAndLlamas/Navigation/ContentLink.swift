//
//  ContentLink.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2024-04-01.
//

import Foundation

enum ContentLink: Identifiable, Hashable {
    var id: String {
        String(describing: self)
    }
    
//    var description: String {
//        switch self {
//
//        case .firstLink(text: let text):
//            return "/First/\(text)"
//        case .secondLink(text: let text):
//            return "/Second/\(text)"
//        }
//    }
    
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

}

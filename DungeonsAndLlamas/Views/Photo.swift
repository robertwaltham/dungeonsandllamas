//
//  Photo.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2024-04-21.
//

import Foundation

import SwiftUI
    
struct Photo: Identifiable {
    var id = UUID()
    var image: Image
    var caption: String
    var description: String
}

extension Photo: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.image)
    }
}

struct Drawing: Identifiable {
    var id = UUID()
    var data: Data
    var caption: String
    var description: String
}

extension Drawing: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .data) { drawing in
            drawing.data
        }
        .suggestedFileName("filename.drawing")
    }
}

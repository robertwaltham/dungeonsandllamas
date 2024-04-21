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


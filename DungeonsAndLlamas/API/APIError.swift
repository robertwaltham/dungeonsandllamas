//
//  APIError.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2024-04-29.
//

import Foundation

enum APIError: Error {
    case requestError(String)
    case badURL(String)
}

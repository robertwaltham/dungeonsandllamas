//
//  DelegateToSupressWarning.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2024-04-29.
//

import Foundation

// (any URLSessionTaskDelegate)? is not sendable??? use this to surpress warning from Swift Concurrency Checking being set to complete
final class DelegateToSupressWarning: NSObject, URLSessionTaskDelegate, Sendable {}

//
//  LoggingService.swift
//  DungeonsAndLlamas
//

import Foundation
import OSLog

/// Centralizes the app's OSLog configuration while keeping category-specific
/// loggers available for privacy-aware interpolation at the call site.
final class LoggingService: Sendable {
    static let shared = LoggingService()

    let subsystem: String
    let app: Logger
    let database: Logger
    let generation: Logger
    let ml: Logger
    let network: Logger
    let photoLibrary: Logger
    let storage: Logger
    let tokenizer: Logger
    let ui: Logger

    private init(subsystem: String = Bundle.main.bundleIdentifier ?? "DungeonsAndLlamas") {
        self.subsystem = subsystem
        app = Logger(subsystem: subsystem, category: "app")
        database = Logger(subsystem: subsystem, category: "database")
        generation = Logger(subsystem: subsystem, category: "generation")
        ml = Logger(subsystem: subsystem, category: "ml")
        network = Logger(subsystem: subsystem, category: "network")
        photoLibrary = Logger(subsystem: subsystem, category: "photo-library")
        storage = Logger(subsystem: subsystem, category: "storage")
        tokenizer = Logger(subsystem: subsystem, category: "tokenizer")
        ui = Logger(subsystem: subsystem, category: "ui")
    }

    /// Creates a signposter using the same subsystem/category configuration.
    /// Use this for intervals such as indexing or model inference that should
    /// be inspected in Instruments rather than logged on every iteration.
    func signposter(for category: LoggerCategory) -> OSSignposter {
        OSSignposter(logger: Logger(subsystem: subsystem, category: category.rawValue))
    }

    enum LoggerCategory: String, Sendable {
        case app
        case database
        case generation
        case ml
        case network
        case photoLibrary = "photo-library"
        case storage
        case tokenizer
        case ui
    }
}

import SwiftUI
import SQLite

@attached(peer, names: arbitrary)
public macro sqlProperty() = #externalMacro(module: "SQLPropertyMacros", type: "SQLPropertyMacro")

// Example usage:
/*
@sqlProperty 
var tertiaryMuscle: String?

// Generates:
fileprivate static var tertiaryMuscleExp: SQLite.Expression<String?> {
    Expression<String?>("tertiary_muscle")
}
*/ 
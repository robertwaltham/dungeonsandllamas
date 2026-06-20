import SQLPropertyMacros
import SQLite

struct ExampleModel {
    @sqlProperty
    var tertiaryMuscle: String?
    
    @sqlProperty
    var primaryMuscle: String
    
    @sqlProperty
    var exerciseCount: Int
}

// The macro will generate:
/*
fileprivate static var tertiaryMuscleExp: SQLite.Expression<String?> {
    Expression<String?>("tertiary_muscle")
}

fileprivate static var primaryMuscleExp: SQLite.Expression<String> {
    Expression<String>("primary_muscle")
}

fileprivate static var exerciseCountExp: SQLite.Expression<Int> {
    Expression<Int>("exercise_count")
}
*/ 
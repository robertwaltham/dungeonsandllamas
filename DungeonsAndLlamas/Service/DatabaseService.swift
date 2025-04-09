//
//  DatabaseService.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2025-04-04.
//

import SQLite
import Foundation
import UIKit
import PencilKit

class DatabaseService {
    private var db: Connection!
    
    func setupForTesting(fileService: FileService) {
        connectForTesting()
        createTables()
        
        do {
            try ImageHistoryModel.generateHistoryForTesting(db: db, fileService: fileService)
        } catch {
            print(error)
        }
    }
    
    func setup() {
        connect()
        createTables()
    }
    
    fileprivate func connect() {
        let path = NSSearchPathForDirectoriesInDomains(
            .documentDirectory, .userDomainMask, true
        ).first!

        do {
            db = try Connection("\(path)/db.sqlite3")
        } catch {
            fatalError(error.localizedDescription)
        }
    }
    
    fileprivate func connectForTesting() {
        do {
            db = try Connection() // in memory
        } catch {
            fatalError(error.localizedDescription)
        }
    }
    
    fileprivate func createTables() {
        do {
            try ImageHistoryModel.createTable(db: db)
            try LoraHistoryModel.createTable(db: db)
        } catch {
            fatalError(error.localizedDescription)
        }
    }
}

extension DatabaseService {
    func loadHistory() -> [ImageHistoryModel] {
        do {
            return try ImageHistoryModel.load(db: db)
        } catch {
            print(error)
            return []
        }
    }
    
    func save(history: ImageHistoryModel) {
        do {
            try history.save(db: db)
        } catch {
            print(error)
        }
    }
}

struct LoraHistoryModel: Codable, Identifiable, Hashable {
    var id: String
    fileprivate static var idExp: SQLite.Expression<String> {
        Expression<String>("id")
    }
    var name: String
    fileprivate static var nameExp: SQLite.Expression<String> {
        Expression<String>("name")
    }
    var weight: Double
    fileprivate static var weightExp: SQLite.Expression<Double> {
        Expression<Double>("weight")
    }
    var historyModelId: String
    fileprivate static var historyModelIdExp: SQLite.Expression<String> {
        Expression<String>("history_model_id")
    }
    
    fileprivate static func table() -> Table {
        return Table("lora_history")
    }
    
    fileprivate static func createTable(db: Connection) throws {
        try db.run(
            table().create(ifNotExists: true) { t in
                t.column(idExp, primaryKey: true)
                t.column(nameExp)
                t.column(weightExp)
                t.column(historyModelIdExp)
            }
        )
    }
    
    fileprivate func save(db: Connection) throws { // TODO: what about mutability
        try db.run(
            LoraHistoryModel.table().insert(
                LoraHistoryModel.idExp <- id,
                LoraHistoryModel.nameExp <- name,
                LoraHistoryModel.weightExp <- weight,
                LoraHistoryModel.historyModelIdExp <- historyModelId
            )
        )
    }
    
    fileprivate static func load(db: Connection, parentId: String) throws -> [LoraHistoryModel] {
        var result = [LoraHistoryModel]()
        for entry in try db.prepare(table().filter(historyModelIdExp == parentId)) {
            result.append(LoraHistoryModel(id: entry[idExp],
                                           name: entry[nameExp],
                                           weight: entry[weightExp],
                                           historyModelId:
                                            entry[historyModelIdExp]))
        }
        return result
    }

}


struct ImageHistoryModel: Codable, Identifiable, Hashable {
    
    var id: String
    fileprivate static var idExp: SQLite.Expression<String> {
        Expression<String>("id")
    }
    var start: Date
    fileprivate static var startExp: SQLite.Expression<Date> {
        Expression<Date>("start")
    }
    var end: Date?
    fileprivate static var endExp: SQLite.Expression<Date?> {
        Expression<Date?>("end")
    }
    var prompt: String
    fileprivate static var promptExp: SQLite.Expression<String> {
        Expression<String>("prompt")
    }
    var negativePrompt: String?
    fileprivate static var negativePromptExp: SQLite.Expression<String?> {
        Expression<String?>("negative_prompt")
    }
    var model: String
    fileprivate static var modelExp: SQLite.Expression<String> {
        Expression<String>("model")
    }
    var sampler: String
    fileprivate static var samplerExp: SQLite.Expression<String> {
        Expression<String>("sampler")
    }
    var steps: Int
    fileprivate static var stepsExp: SQLite.Expression<Int> {
        Expression<Int>("steps")
    }
    var size: Int
    fileprivate static var sizeExp: SQLite.Expression<Int> {
        Expression<Int>("size")
    }
    var seed: Int
    fileprivate static var seedExp: SQLite.Expression<Int> {
        Expression<Int>("seed")
    }

    var inputFilePath: String?
    fileprivate static var inputFilePathExp: SQLite.Expression<String?> {
        Expression<String?>("input_file_path")
    }
    var outputFilePath: String?
    fileprivate static var outputFilePathExp: SQLite.Expression<String?> {
        Expression<String?>("output_file_path")
    }
    var drawingFilePath: String?
    fileprivate static var drawingFilePathExp: SQLite.Expression<String?> {
        Expression<String?>("drawing_file_path")
    }
    
    var errorDescription: String?
    fileprivate static var errorDescriptionExp: SQLite.Expression<String?> {
        Expression<String?>("error_description")
    }
    
    var session: String
    fileprivate static var sessionExp: SQLite.Expression<String> {
        Expression<String>("session")
    }
    
    var sequence: Int
    fileprivate static var sequenceExp: SQLite.Expression<Int> {
        Expression<Int>("sequence")
    }
    
    var loras: [LoraHistoryModel]
    
    fileprivate func save(db: Connection) throws { // TODO: what about mutability
        try db.run(ImageHistoryModel.table().insert(
            ImageHistoryModel.idExp <- id,
            ImageHistoryModel.startExp <- start,
            ImageHistoryModel.endExp <- end,
            ImageHistoryModel.promptExp <- prompt,
            ImageHistoryModel.negativePromptExp <- negativePrompt,
            ImageHistoryModel.modelExp <- model,
            ImageHistoryModel.samplerExp <- sampler,
            ImageHistoryModel.stepsExp <- steps,
            ImageHistoryModel.sizeExp <- size,
            ImageHistoryModel.seedExp <- seed,
            ImageHistoryModel.inputFilePathExp <- inputFilePath,
            ImageHistoryModel.outputFilePathExp <- outputFilePath,
            ImageHistoryModel.drawingFilePathExp <- drawingFilePath,
            ImageHistoryModel.errorDescriptionExp <- errorDescription,
            ImageHistoryModel.sessionExp <- session,
            ImageHistoryModel.sequenceExp <- sequence,
        ))
        
        for lora in loras {
            try lora.save(db: db)
        }
    }
    
    fileprivate static func load(db: Connection) throws -> [ImageHistoryModel] {
        var result = [ImageHistoryModel]()
        for entry in try db.prepare(table()) {
            
            let loras = try LoraHistoryModel.load(db: db, parentId: entry[idExp])
            result.append(ImageHistoryModel(id: entry[idExp],
                                            start: entry[startExp],
                                            end: entry[endExp],
                                            prompt: entry[promptExp],
                                            negativePrompt: entry[negativePromptExp],
                                            model: entry[modelExp],
                                            sampler: entry[samplerExp],
                                            steps: entry[stepsExp],
                                            size: entry[sizeExp],
                                            seed: entry[seedExp],
                                            inputFilePath: entry[inputFilePathExp],
                                            outputFilePath: entry[outputFilePathExp],
                                            drawingFilePath: entry[drawingFilePathExp],
                                            errorDescription: entry[errorDescriptionExp],
                                            session: entry[sessionExp],
                                            sequence: entry[sequenceExp],
                                            loras: loras))
        }
        return result
    }
    
    fileprivate static func createTable(db: Connection) throws {
        try db.run(
            table().create(ifNotExists: true) { t in
                t.column(idExp, primaryKey: true)
                t.column(startExp)
                t.column(endExp)
                t.column(promptExp)
                t.column(negativePromptExp)
                t.column(modelExp)
                t.column(samplerExp)
                t.column(stepsExp)
                t.column(sizeExp)
                t.column(seedExp)
                t.column(inputFilePathExp)
                t.column(outputFilePathExp)
                t.column(drawingFilePathExp)
                t.column(errorDescriptionExp)
                t.column(sessionExp)
                t.column(sequenceExp)
            }
        )
    }
    
    fileprivate static func table() -> Table {
        return Table("image_history")
    }

    static func generateHistoryForTesting(db: Connection, fileService: FileService) throws {
        var entry = ImageHistoryModel(id: "",
                                      start: Date.now,
                                      prompt: "a cat in a fancy hat, with a really long prompt that doesn't fit on the page properly, best quality, realistic, etc etc",
                                      model: "SD 1.5",
                                      sampler: "Euler",
                                      steps: 20,
                                      size: 512,
                                      seed: 0,
                                      session: NSUUID().uuidString,
                                      sequence: 0,
                                      loras: [])
        entry.inputFilePath = fileService.save(image: UIImage(named: "lighthouse")!)
        entry.outputFilePath = fileService.save(image: UIImage(named: "trees")!)
        let drawingUrl = Bundle.main.url(forResource: "fancycat", withExtension: "drawing")!
        let drawingData = try! Data(contentsOf: drawingUrl)
        let drawing = try! PKDrawing(data: drawingData)
        entry.drawingFilePath = fileService.save(drawing: drawing)
        
        
        for i in 0..<30 {
            entry.start = Date.now.addingTimeInterval(TimeInterval(i))
            entry.end = Date.now.addingTimeInterval(TimeInterval(i + 5))
            entry.sequence = i % 5
            if i % 5 == 0 {
                entry.session = NSUUID().uuidString
            }
            if i % 2 == 0 {
                entry.loras = [
                    LoraHistoryModel(id: NSUUID().uuidString, name: "Add Details", weight: Double.random(in: 0.0...1.0), historyModelId: entry.id)
                ]
            } else {
                entry.loras = []
            }
            entry.id = NSUUID().uuidString
            try entry.save(db: db)
        }
    }
}

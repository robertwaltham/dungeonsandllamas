//
//  DatabaseService.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2025-04-04.
//

import SQLite
import SQLPropertyMacros
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
            try migrateDatabase()
        } catch {
            fatalError(error.localizedDescription)
        }
    }
    
    fileprivate func migrateDatabase() throws {
        let currentVersion = db.userVersion ?? 0
        
        if currentVersion < 1 {
            if try !ImageHistoryModel.columnExists(db: db, name: "output_embedding") {
                try db.run(ImageHistoryModel.table().addColumn(ImageHistoryModel.outputEmbeddingExp))
            }
            db.userVersion = 1
        }
        
        if currentVersion < 2 {
            if try !ImageHistoryModel.columnExists(db: db, name: "input_embedding") {
                try db.run(ImageHistoryModel.table().addColumn(ImageHistoryModel.inputEmbeddingExp))
            }
            db.userVersion = 2
        }
        
        if currentVersion < 3 {
            if try !ImageHistoryModel.columnExists(db: db, name: "prompt_embedding") {
                try db.run(ImageHistoryModel.table().addColumn(ImageHistoryModel.promptEmbeddingExp))
            }
            db.userVersion = 3
        }

        if currentVersion < 4 {
            if try !ImageHistoryModel.columnExists(db: db, name: "prompt_id") {
                try db.run(ImageHistoryModel.table().addColumn(ImageHistoryModel.promptIdExp))
            }
            db.userVersion = 4
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
    
    func updateEmbeddings(history: ImageHistoryModel) {
        do {
            try history.updateEmbeddings(db: db)
        } catch {
            print(error)
        }
    }

    func updateAssets(history: ImageHistoryModel) {
        do {
            try history.updateAssets(db: db)
        } catch {
            print(error)
        }
    }
}

struct LoraHistoryModel: Codable, Identifiable, Hashable {
    @SqlProperty
    var id: String
    @SqlProperty
    var name: String
    @SqlProperty
    var weight: Double
    @SqlProperty
    var historyModelId: String
    
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
    
    @SqlProperty
    var id: String
    @SqlProperty
    var start: Date
    @SqlProperty
    var end: Date?
    @SqlProperty
    var prompt: String
    @SqlProperty
    var promptId: String? = nil
    var promptEmbedding: [Float]?
    fileprivate static var promptEmbeddingExp: SQLite.Expression<Data?> {
        Expression<Data?>("prompt_embedding")
    }
    @SqlProperty
    var negativePrompt: String?
    @SqlProperty
    var model: String
    @SqlProperty
    var sampler: String
    @SqlProperty
    var steps: Int
    @SqlProperty
    var size: Int
    @SqlProperty
    var seed: Int

    var inputFilePaths = [String]()
    fileprivate static var inputFilePathsExp: SQLite.Expression<String> {
        Expression<String>("input_file_paths")
    }
    var inputEmbedding: [Float]?
    fileprivate static var inputEmbeddingExp: SQLite.Expression<Data?> {
        Expression<Data?>("input_embedding")
    }
    @SqlProperty
    var outputFilePath: String?
    var outputEmbedding: [Float]?
    fileprivate static var outputEmbeddingExp: SQLite.Expression<Data?> {
        Expression<Data?>("output_embedding")
    }
    @SqlProperty
    var drawingFilePath: String?
    @SqlProperty
    var depthFilePath: String?
    @SqlProperty
    var errorDescription: String?
    @SqlProperty
    var session: String
    @SqlProperty
    var sequence: Int
    
    var loras: [LoraHistoryModel]
    
    fileprivate func save(db: Connection) throws { // TODO: what about mutability
        try db.run(ImageHistoryModel.table().insert(
            ImageHistoryModel.idExp <- id,
            ImageHistoryModel.startExp <- start,
            ImageHistoryModel.endExp <- end,
            ImageHistoryModel.promptExp <- prompt,
            ImageHistoryModel.promptIdExp <- promptId,
            ImageHistoryModel.promptEmbeddingExp <- ImageHistoryModel.encodedEmbedding(promptEmbedding),
            ImageHistoryModel.negativePromptExp <- negativePrompt,
            ImageHistoryModel.modelExp <- model,
            ImageHistoryModel.samplerExp <- sampler,
            ImageHistoryModel.stepsExp <- steps,
            ImageHistoryModel.sizeExp <- size,
            ImageHistoryModel.seedExp <- seed,
            ImageHistoryModel.inputFilePathsExp <- ImageHistoryModel.encodedInputFilePaths(inputFilePaths),
            ImageHistoryModel.inputEmbeddingExp <- ImageHistoryModel.encodedEmbedding(inputEmbedding),
            ImageHistoryModel.outputFilePathExp <- outputFilePath,
            ImageHistoryModel.outputEmbeddingExp <- ImageHistoryModel.encodedEmbedding(outputEmbedding),
            ImageHistoryModel.drawingFilePathExp <- drawingFilePath,
            ImageHistoryModel.depthFilePathExp <- depthFilePath,
            ImageHistoryModel.errorDescriptionExp <- errorDescription,
            ImageHistoryModel.sessionExp <- session,
            ImageHistoryModel.sequenceExp <- sequence,
        ))
        
        for lora in loras {
            try lora.save(db: db)
        }
    }
    
    fileprivate func updateEmbeddings(db: Connection) throws {
        try db.run(ImageHistoryModel.table().filter(ImageHistoryModel.idExp == id).update(
            ImageHistoryModel.promptEmbeddingExp <- ImageHistoryModel.encodedEmbedding(promptEmbedding),
            ImageHistoryModel.inputEmbeddingExp <- ImageHistoryModel.encodedEmbedding(inputEmbedding),
            ImageHistoryModel.outputEmbeddingExp <- ImageHistoryModel.encodedEmbedding(outputEmbedding)
        ))
    }

    fileprivate func updateAssets(db: Connection) throws {
        try db.run(ImageHistoryModel.table().filter(ImageHistoryModel.idExp == id).update(
            ImageHistoryModel.inputFilePathsExp <- ImageHistoryModel.encodedInputFilePaths(inputFilePaths),
            ImageHistoryModel.outputFilePathExp <- outputFilePath
        ))
    }
    
    fileprivate static func load(db: Connection) throws -> [ImageHistoryModel] {
        var result = [ImageHistoryModel]()
        for entry in try db.prepare(table()) {
            
            let loras = try LoraHistoryModel.load(db: db, parentId: entry[idExp])
            result.append(ImageHistoryModel(id: entry[idExp],
                                            start: entry[startExp],
                                            end: entry[endExp],
                                            prompt: entry[promptExp],
                                            promptId: entry[promptIdExp],
                                            promptEmbedding: decodedEmbedding(entry[promptEmbeddingExp]),
                                            negativePrompt: entry[negativePromptExp],
                                            model: entry[modelExp],
                                            sampler: entry[samplerExp],
                                            steps: entry[stepsExp],
                                            size: entry[sizeExp],
                                            seed: entry[seedExp],
                                            inputFilePaths: decodedInputFilePaths(entry[inputFilePathsExp]),
                                            inputEmbedding: decodedEmbedding(entry[inputEmbeddingExp]),
                                            outputFilePath: entry[outputFilePathExp],
                                            outputEmbedding: decodedEmbedding(entry[outputEmbeddingExp]),
                                            drawingFilePath: entry[drawingFilePathExp],
                                            depthFilePath: entry[depthFilePathExp],
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
                t.column(promptEmbeddingExp)
                t.column(negativePromptExp)
                t.column(modelExp)
                t.column(samplerExp)
                t.column(stepsExp)
                t.column(sizeExp)
                t.column(seedExp)
                t.column(inputFilePathsExp)
                t.column(inputEmbeddingExp)
                t.column(outputFilePathExp)
                t.column(outputEmbeddingExp)
                t.column(drawingFilePathExp)
                t.column(depthFilePathExp)
                t.column(errorDescriptionExp)
                t.column(sessionExp)
                t.column(sequenceExp)
            }
        )
    }
    
    fileprivate static func table() -> Table {
        return Table("image_history")
    }

    fileprivate static func encodedInputFilePaths(_ paths: [String]) -> String {
        guard let data = try? JSONEncoder().encode(paths),
              let encoded = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return encoded
    }

    fileprivate static func decodedInputFilePaths(_ encoded: String) -> [String] {
        guard let data = encoded.data(using: .utf8),
              let paths = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return paths
    }
    
    fileprivate static func encodedEmbedding(_ embedding: [Float]?) -> Data? {
        guard let embedding else {
            return nil
        }
        return embedding.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }
    }
    
    fileprivate static func decodedEmbedding(_ data: Data?) -> [Float]? {
        guard let data else {
            return nil
        }
        let floatSize = MemoryLayout<Float>.stride
        guard data.count.isMultiple(of: floatSize) else {
            return nil
        }
        return data.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }
    }
    
    fileprivate static func columnExists(db: Connection, name: String) throws -> Bool {
        try db.schema.columnDefinitions(table: "image_history").contains { column in
            column.name == name
        }
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
        entry.inputFilePaths = [fileService.save(image: UIImage(named: "catglasses")!)]
        entry.outputFilePath = fileService.save(image: UIImage(named: "trees")!)
        entry.depthFilePath = fileService.save(image: UIImage(named: "depth_preview")!)
        let drawingUrl = Bundle.main.url(forResource: "fancycat", withExtension: "drawing")!
        let drawingData = try! Data(contentsOf: drawingUrl)
        let drawing = try! PKDrawing(data: drawingData)
        entry.drawingFilePath = fileService.save(drawing: drawing)
        
        
        for i in 0..<30 {
            var entry = entry

            entry.start = Date.now.addingTimeInterval(TimeInterval(i))
            entry.end = Date.now.addingTimeInterval(TimeInterval(i + 5))
            entry.sequence = i % 5
            if i % 5 == 0 {
                entry.session = NSUUID().uuidString
            }
            
            if i % 4 == 0 {
                entry.drawingFilePath = nil
            } else {
                entry.depthFilePath = nil
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

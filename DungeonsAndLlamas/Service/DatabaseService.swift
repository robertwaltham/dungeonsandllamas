//
//  DatabaseService.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2025-04-04.
//

import SQLite

private let databaseLogger = LoggingService.shared.database
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
            databaseLogger.error("Test history generation failed: \(String(describing: error), privacy: .private)")
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
            try PhotoIndexModel.createTable(db: db)
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

        if currentVersion < 5 {
            try migrateLegacyPhotoIndex()
            db.userVersion = 5
        }
    }

    private func migrateLegacyPhotoIndex() throws {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PhotoLibrary", isDirectory: true)
        let legacyURL = root.appendingPathComponent("photo-index.sqlite3")
        guard FileManager.default.fileExists(atPath: legacyURL.path) else { return }

        let legacyDB = try Connection(legacyURL.path)
        let legacyTable = Table("photo_asset")
        let id = Expression<String>("id")
        let creationDate = Expression<Double?>("creation_date")
        let modificationDate = Expression<Double?>("modification_date")
        let thumbnailPath = Expression<String?>("thumbnail_path")
        let sensorDepthPath = Expression<String?>("sensor_depth_path")
        let estimatedDepthPath = Expression<String?>("estimated_depth_path")
        let sourceState = Expression<String>("source_state")
        let sensorDepthState = Expression<String>("sensor_depth_state")
        let estimatedDepthState = Expression<String>("estimated_depth_state")
        let embedding = Expression<Data?>("embedding")
        let categories = Expression<Data?>("categories")
        let processingVersion = Expression<Int>("processing_version")

        for row in try legacyDB.prepare(legacyTable) {
            let photo = PhotoIndexModel(
                id: row[id],
                creationDate: row[creationDate].map(Date.init(timeIntervalSince1970:)),
                modificationDate: row[modificationDate].map(Date.init(timeIntervalSince1970:)),
                thumbnailPath: row[thumbnailPath],
                sensorDepthPath: row[sensorDepthPath],
                estimatedDepthPath: row[estimatedDepthPath],
                sourceState: row[sourceState],
                sensorDepthState: row[sensorDepthState],
                estimatedDepthState: row[estimatedDepthState],
                embedding: PhotoIndexModel.decodedEmbeddingForMigration(row[embedding]),
                categories: PhotoIndexModel.decodedCategoriesForMigration(row[categories]),
                processingVersion: row[processingVersion]
            )
            try photo.save(db: db)
        }
    }
}

extension DatabaseService {
    func loadHistory() -> [ImageHistoryModel] {
        do {
            return try ImageHistoryModel.load(db: db)
        } catch {
            databaseLogger.error("History load failed: \(String(describing: error), privacy: .private)")
            return []
        }
    }
    
    func save(history: ImageHistoryModel) {
        do {
            try history.save(db: db)
        } catch {
            databaseLogger.error("History save failed: \(String(describing: error), privacy: .private)")
        }
    }
    
    func updateEmbeddings(history: ImageHistoryModel) {
        do {
            try history.updateEmbeddings(db: db)
        } catch {
            databaseLogger.error("History embedding update failed: \(String(describing: error), privacy: .private)")
        }
    }

    func updateAssets(history: ImageHistoryModel) {
        do {
            try history.updateAssets(db: db)
        } catch {
            databaseLogger.error("History asset update failed: \(String(describing: error), privacy: .private)")
        }
    }

    func loadPhotoIndex() -> [PhotoIndexModel] {
        do {
            return try PhotoIndexModel.load(db: db)
        } catch {
            databaseLogger.error("Photo index load failed: \(String(describing: error), privacy: .private)")
            return []
        }
    }

    func save(photo: PhotoIndexModel) {
        do {
            try photo.save(db: db)
        } catch {
            databaseLogger.error("Photo index save failed: \(String(describing: error), privacy: .private)")
        }
    }

    func removePhotos(ids: [String]) -> [String] {
        do {
            return try PhotoIndexModel.remove(db: db, ids: ids)
        } catch {
            databaseLogger.error("Photo index removal failed: \(String(describing: error), privacy: .private)")
            return []
        }
    }
}

struct PhotoIndexModel: Codable, Identifiable, Hashable, Sendable {
    static let processingVersion = 2

    @SqlProperty
    var id: String
    @SqlProperty
    var creationDate: Date?
    @SqlProperty
    var modificationDate: Date?
    @SqlProperty
    var thumbnailPath: String?
    @SqlProperty
    var sensorDepthPath: String?
    @SqlProperty
    var estimatedDepthPath: String?
    @SqlProperty
    var sourceState: String
    @SqlProperty
    var sensorDepthState: String
    @SqlProperty
    var estimatedDepthState: String
    var embedding: [Float]?
    var categories: [PhotoCategory]
    @SqlProperty
    var processingVersion: Int

    fileprivate static var embeddingExp: SQLite.Expression<Data?> {
        Expression<Data?>("embedding")
    }

    fileprivate static var categoriesExp: SQLite.Expression<Data?> {
        Expression<Data?>("categories")
    }

    fileprivate static func table() -> Table {
        Table("photo_asset")
    }

    fileprivate static func createTable(db: Connection) throws {
        try db.run(table().create(ifNotExists: true) { t in
            t.column(idExp, primaryKey: true)
            t.column(creationDateExp)
            t.column(modificationDateExp)
            t.column(thumbnailPathExp)
            t.column(sensorDepthPathExp)
            t.column(estimatedDepthPathExp)
            t.column(sourceStateExp)
            t.column(sensorDepthStateExp)
            t.column(estimatedDepthStateExp)
            t.column(embeddingExp)
            t.column(categoriesExp)
            t.column(processingVersionExp)
        })
    }

    fileprivate func save(db: Connection) throws {
        try db.run(Self.table().insert(or: .replace,
            Self.idExp <- id,
            Self.creationDateExp <- creationDate,
            Self.modificationDateExp <- modificationDate,
            Self.thumbnailPathExp <- thumbnailPath,
            Self.sensorDepthPathExp <- sensorDepthPath,
            Self.estimatedDepthPathExp <- estimatedDepthPath,
            Self.sourceStateExp <- sourceState,
            Self.sensorDepthStateExp <- sensorDepthState,
            Self.estimatedDepthStateExp <- estimatedDepthState,
            Self.embeddingExp <- Self.encodedEmbedding(embedding),
            Self.categoriesExp <- Self.encodedCategories(categories),
            Self.processingVersionExp <- processingVersion
        ))
    }

    fileprivate static func load(db: Connection) throws -> [PhotoIndexModel] {
        try db.prepare(table().order(creationDateExp.desc)).map { row in
            PhotoIndexModel(
                id: row[idExp],
                creationDate: row[creationDateExp],
                modificationDate: row[modificationDateExp],
                thumbnailPath: row[thumbnailPathExp],
                sensorDepthPath: row[sensorDepthPathExp],
                estimatedDepthPath: row[estimatedDepthPathExp],
                sourceState: row[sourceStateExp],
                sensorDepthState: row[sensorDepthStateExp],
                estimatedDepthState: row[estimatedDepthStateExp],
                embedding: decodedEmbedding(row[embeddingExp]),
                categories: decodedCategories(row[categoriesExp]),
                processingVersion: row[processingVersionExp]
            )
        }
    }

    fileprivate static func remove(db: Connection, ids: [String]) throws -> [String] {
        guard !ids.isEmpty else { return [] }
        let records = try load(db: db).filter { ids.contains($0.id) }
        for id in ids {
            try db.run(table().filter(idExp == id).delete())
        }
        return records.flatMap { [$0.thumbnailPath, $0.sensorDepthPath, $0.estimatedDepthPath].compactMap { $0 } }
    }

    private static func encodedEmbedding(_ embedding: [Float]?) -> Data? {
        guard let embedding else { return nil }
        return embedding.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private static func decodedEmbedding(_ data: Data?) -> [Float]? {
        guard let data, data.count.isMultiple(of: MemoryLayout<Float>.stride) else { return nil }
        return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    private static func encodedCategories(_ categories: [PhotoCategory]) -> Data? {
        try? JSONEncoder().encode(categories)
    }

    private static func decodedCategories(_ data: Data?) -> [PhotoCategory] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([PhotoCategory].self, from: data)) ?? []
    }

    fileprivate static func decodedEmbeddingForMigration(_ data: Data?) -> [Float]? {
        decodedEmbedding(data)
    }

    fileprivate static func decodedCategoriesForMigration(_ data: Data?) -> [PhotoCategory] {
        decodedCategories(data)
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

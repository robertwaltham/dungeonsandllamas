//
//  PhotoLibraryService.swift
//  DungeonsAndLlamas
//

import Foundation
import Photos
import PhotosUI
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import SQLite

enum PhotoRepresentation: String, CaseIterable, Codable, Hashable, Identifiable {
    case source
    case sensorDepth
    case estimatedDepth

    var id: String { rawValue }

    var title: String {
        switch self {
        case .source: return "Source"
        case .sensorDepth: return "Sensor Depth"
        case .estimatedDepth: return "Estimated Depth"
        }
    }

    var systemImage: String {
        switch self {
        case .source: return "photo"
        case .sensorDepth: return "sensor.tag.radiowaves.forward"
        case .estimatedDepth: return "square.3.layers.3d"
        }
    }
}

struct PhotoPickerSelection: Hashable, Sendable {
    let assetIdentifier: String
    let representation: PhotoRepresentation
}

struct PhotoCategory: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let probability: Double
    let count: Int
}

enum PhotoProcessingState: String, Codable, Hashable, Sendable {
    case pending
    case processing
    case available
    case unavailable
    case deferredForDownload
    case failed
}

struct PhotoRecordSummary: Identifiable, Hashable, Sendable {
    let id: String
    let creationDate: Date?
    let modificationDate: Date?
    let thumbnailPath: String?
    let sensorDepthPath: String?
    let estimatedDepthPath: String?
    let sourceState: PhotoProcessingState
    let sensorDepthState: PhotoProcessingState
    let estimatedDepthState: PhotoProcessingState
    let categories: [PhotoCategory]

    var representationStates: [PhotoRepresentation: PhotoProcessingState] {
        [.source: sourceState, .sensorDepth: sensorDepthState, .estimatedDepth: estimatedDepthState]
    }
}

struct PhotoPageCursor: Hashable, Codable, Sendable {
    let offset: Int
}

struct PhotoPage: Sendable {
    let records: [PhotoRecordSummary]
    let nextCursor: PhotoPageCursor?
}

struct PhotoQuery: Hashable, Sendable {
    var text = ""
    var categoryIDs: Set<String> = []
    var pageSize = 60
}

private struct IndexedPhoto: Sendable {
    static let processingVersion = 2
    let id: String
    let creationDate: Date?
    let modificationDate: Date?
    let thumbnailPath: String?
    let sensorDepthPath: String?
    let estimatedDepthPath: String?
    let sourceState: PhotoProcessingState
    let sensorDepthState: PhotoProcessingState
    let estimatedDepthState: PhotoProcessingState
    let embedding: [Float]?
    let categories: [PhotoCategory]
    let processingVersion: Int
}

private actor PhotoIndexStore {
    private let db: Connection
    private var cachedPhotos: [String: IndexedPhoto]?

    init() {
        let manager = FileManager.default
        let root = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PhotoLibrary", isDirectory: true)
        try? manager.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("photo-index.sqlite3")
        db = try! Connection(url.path)
        try? db.execute("PRAGMA journal_mode = WAL")
        try? db.execute("PRAGMA busy_timeout = 5000")
        try? db.execute("""
            CREATE TABLE IF NOT EXISTS photo_asset (
                id TEXT PRIMARY KEY NOT NULL,
                creation_date DOUBLE,
                modification_date DOUBLE,
                thumbnail_path TEXT,
                sensor_depth_path TEXT,
                estimated_depth_path TEXT,
                source_state TEXT NOT NULL,
                sensor_depth_state TEXT NOT NULL,
                estimated_depth_state TEXT NOT NULL,
                embedding BLOB,
                categories BLOB,
                processing_version INTEGER NOT NULL DEFAULT 1
            )
            """)
        Self.migratePhotoAssetSchemaIfNeeded(db)
        try? db.execute("CREATE INDEX IF NOT EXISTS photo_asset_creation ON photo_asset(creation_date DESC)")
    }

    private nonisolated static func migratePhotoAssetSchemaIfNeeded(_ db: Connection) {
        let existingColumns = Set((try? db.prepare("PRAGMA table_info(photo_asset)"))?.compactMap { row in
            row[1] as? String
        } ?? [])

        if !existingColumns.contains("modification_date") {
            try? db.execute("ALTER TABLE photo_asset ADD COLUMN modification_date DOUBLE")
        }
        if !existingColumns.contains("processing_version") {
            try? db.execute("ALTER TABLE photo_asset ADD COLUMN processing_version INTEGER NOT NULL DEFAULT 1")
        }
    }

    func all() -> [IndexedPhoto] {
        if let cachedPhotos {
            return cachedPhotos.values.sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
        }
        let table = Table("photo_asset")
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

        let photos: [IndexedPhoto] = (try? db.prepare(table.order(creationDate.desc)))?.compactMap { row in
            let decodedCategories = row[categories].flatMap { try? JSONDecoder().decode([PhotoCategory].self, from: $0) } ?? []
            return IndexedPhoto(
                id: row[id],
                creationDate: row[creationDate].map(Date.init(timeIntervalSince1970:)),
                modificationDate: row[modificationDate].map(Date.init(timeIntervalSince1970:)),
                thumbnailPath: row[thumbnailPath],
                sensorDepthPath: row[sensorDepthPath],
                estimatedDepthPath: row[estimatedDepthPath],
                sourceState: PhotoProcessingState(rawValue: row[sourceState]) ?? .failed,
                sensorDepthState: PhotoProcessingState(rawValue: row[sensorDepthState]) ?? .unavailable,
                estimatedDepthState: PhotoProcessingState(rawValue: row[estimatedDepthState]) ?? .pending,
                embedding: row[embedding].flatMap(Self.decodeEmbedding),
                categories: decodedCategories,
                processingVersion: row[processingVersion]
            )
        } ?? []
        cachedPhotos = Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0) })
        return photos
    }

    func upsert(_ photo: IndexedPhoto) {
        let table = Table("photo_asset")
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
        let encodedCategories = try? JSONEncoder().encode(photo.categories)

        let values: [Setter] = [
            id <- photo.id,
            creationDate <- photo.creationDate?.timeIntervalSince1970,
            modificationDate <- photo.modificationDate?.timeIntervalSince1970,
            thumbnailPath <- photo.thumbnailPath,
            sensorDepthPath <- photo.sensorDepthPath,
            estimatedDepthPath <- photo.estimatedDepthPath,
            sourceState <- photo.sourceState.rawValue,
            sensorDepthState <- photo.sensorDepthState.rawValue,
            estimatedDepthState <- photo.estimatedDepthState.rawValue,
            embedding <- Self.encodeEmbedding(photo.embedding),
            categories <- encodedCategories,
            processingVersion <- photo.processingVersion
        ]
        _ = try? db.run(table.insert(or: .replace, values))
        cachedPhotos?[photo.id] = photo
    }

    func remove(ids: [String]) -> [String] {
        guard !ids.isEmpty else { return [] }
        let deletedPaths = ids.flatMap { identifier -> [String] in
            guard let photo = cachedPhotos?[identifier] else { return [] }
            return [photo.thumbnailPath, photo.sensorDepthPath, photo.estimatedDepthPath].compactMap { $0 }
        }
        let table = Table("photo_asset")
        let id = Expression<String>("id")
        for identifier in ids {
            _ = try? db.run(table.filter(id == identifier).delete())
            cachedPhotos?.removeValue(forKey: identifier)
        }
        return deletedPaths
    }

    func photo(id: String) -> IndexedPhoto? {
        if cachedPhotos == nil { _ = all() }
        return cachedPhotos?[id]
    }

    private static func encodeEmbedding(_ embedding: [Float]?) -> Data? {
        guard let embedding else { return nil }
        return embedding.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private static func decodeEmbedding(_ data: Data) -> [Float]? {
        guard data.count.isMultiple(of: MemoryLayout<Float>.stride) else { return nil }
        return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
}

@MainActor
final class PhotoLibraryService: NSObject {
    var status: PHAuthorizationStatus?
    private(set) var isIndexing = false
    private(set) var indexedCount = 0
    private(set) var pendingCount = 0

    let ml: MLService
    private let store = PhotoIndexStore()
    private let fileManager = FileManager.default
    private let changeTokenDefaultsKey = "PhotoLibraryService.currentChangeToken"
    private var indexingTask: Task<Void, Never>?
    private var observer: PhotoLibraryChangeObserver?

    var canAccess: Bool {
        status == .authorized || status == .limited
    }

    init(ml: MLService = MLService()) {
        self.ml = ml
        super.init()
    }

    func requestAccessIfNeeded() async {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if current == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        } else {
            status = current
        }
        if canAccess { registerObserver() }
    }

    func startIfAuthorized() async {
        status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard canAccess else { return }
        registerObserver()
        startIndexing()
    }

    func presentLimitedLibraryManagement() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let controller = scene.keyWindow?.rootViewController else { return }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: controller)
    }

    func startIndexing() {
        guard canAccess, indexingTask == nil else { return }
        isIndexing = true
        indexingTask = Task { [weak self] in
            guard let self else { return }
            await self.reconcileLibrary()
            self.isIndexing = false
            self.indexingTask = nil
        }
    }

    func stopIndexing() {
        indexingTask?.cancel()
        indexingTask = nil
        isIndexing = false
    }

    func categories() async -> [PhotoCategory] {
        let records = await store.all()
        let grouped = Dictionary(grouping: records.flatMap(\.categories), by: \.id)
        return grouped.values.compactMap { values in
            guard let first = values.first else { return nil }
            return PhotoCategory(id: first.id, name: first.name, probability: first.probability, count: values.count)
        }.sorted { $0.count > $1.count }
    }

    func page(query: PhotoQuery, cursor: PhotoPageCursor? = nil) async throws -> PhotoPage {
        var records = await store.all()
        let selected = query.categoryIDs
        if !selected.isEmpty {
            records = records.filter { photo in
                !selected.isDisjoint(with: photo.categories.map(\.id))
            }
        }

        if !query.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let embedding = try await ml.textEmbedding(for: query.text)
            let ranked: [(IndexedPhoto, Float)] = records.compactMap { photo in
                guard let photoEmbedding = photo.embedding,
                      let score = try? MLService.cosineSimilarity(embedding, photoEmbedding) else { return nil }
                return (photo, score)
            }
            records = ranked.sorted { $0.1 > $1.1 }.map { $0.0 }
        }

        let offset = cursor?.offset ?? 0
        let end = min(offset + query.pageSize, records.count)
        let pageRecords = offset < end ? records[offset..<end] : []
        let summaries = pageRecords.map(Self.summary)
        let next = end < records.count ? PhotoPageCursor(offset: end) : nil
        return PhotoPage(records: summaries, nextCursor: next)
    }

    func thumbnail(for record: PhotoRecordSummary) async -> UIImage? {
        guard let path = record.thumbnailPath else { return nil }
        return await loadImage(path: path)
    }

    func thumbnail(for record: PhotoRecordSummary, representation: PhotoRepresentation) async -> UIImage? {
        if representation == .source {
            return await thumbnail(for: record)
        }
        let path = representation == .sensorDepth ? record.sensorDepthPath : record.estimatedDepthPath
        guard let path else { return nil }
        return await loadImage(path: path)
    }

    func representation(for selection: PhotoPickerSelection, targetSize: CGSize) async throws -> UIImage {
        if selection.representation == .source {
            return try await getImage(identifier: selection.assetIdentifier, targetSize: targetSize)
        }
        let records = await store.all()
        guard let record = records.first(where: { $0.id == selection.assetIdentifier }) else {
            throw APIError.requestError("The selected photo is no longer indexed.")
        }
        let path = selection.representation == .sensorDepth ? record.sensorDepthPath : record.estimatedDepthPath
        guard let path, let image = await loadImage(path: path) else {
            throw APIError.requestError("That depth representation is not available yet.")
        }
        return image
    }

    private func reconcileLibrary() async {
        let currentToken = PHPhotoLibrary.shared().currentChangeToken
        let existingAtStart = await store.all()
        if let storedToken = loadChangeToken(), storedToken.isEqual(currentToken), !existingAtStart.isEmpty {
            indexedCount = existingAtStart.count
            pendingCount = 0
            return
        }

        if let storedToken = loadChangeToken(), !existingAtStart.isEmpty,
           await applyPersistentChanges(since: storedToken, currentToken: currentToken) {
            return
        }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let assets = PHAsset.fetchAssets(with: .image, options: options)
        let existing = existingAtStart
        let allowedIDs = Set((0..<assets.count).map { assets.object(at: $0).localIdentifier })
        let removedPaths = await store.remove(ids: existing.map(\.id).filter { !allowedIDs.contains($0) })
        removeDerivedFiles(at: removedPaths)
        let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })

        for index in 0..<assets.count {
            if Task.isCancelled { return }
            let asset = assets.object(at: index)
            if let existing = existingByID[asset.localIdentifier],
               existing.modificationDate == asset.modificationDate,
               existing.processingVersion == IndexedPhoto.processingVersion {
                continue
            }
            await indexAsset(asset)
            if index % 8 == 0 {
                indexedCount = index + 1
                pendingCount = max(assets.count - indexedCount, 0)
            }
        }
        indexedCount = assets.count
        pendingCount = 0
        saveChangeToken(currentToken)
    }

    /// Uses PhotoKit's durable change history between launches. A failed/expired
    /// token deliberately falls through to the full reconciliation above.
    private func applyPersistentChanges(since token: PHPersistentChangeToken, currentToken: PHPersistentChangeToken) async -> Bool {
        guard #available(iOS 16, *) else { return false }
        do {
            let changes = try PHPhotoLibrary.shared().fetchPersistentChanges(since: token)
            var changedIDs = Set<String>()
            var deletedIDs = Set<String>()
            for change in changes {
                let details = try change.changeDetails(for: .asset)
                changedIDs.formUnion(details.insertedLocalIdentifiers)
                changedIDs.formUnion(details.updatedLocalIdentifiers)
                deletedIDs.formUnion(details.deletedLocalIdentifiers)
            }
            changedIDs.subtract(deletedIDs)
            let removedPaths = await store.remove(ids: Array(deletedIDs))
            removeDerivedFiles(at: removedPaths)

            let result = PHAsset.fetchAssets(withLocalIdentifiers: Array(changedIDs), options: nil)
            for index in 0..<result.count {
                if Task.isCancelled { return false }
                await indexAsset(result.object(at: index))
                indexedCount = index + 1
                pendingCount = max(result.count - indexedCount, 0)
            }
            indexedCount = await store.all().count
            pendingCount = 0
            saveChangeToken(currentToken)
            return true
        } catch {
            return false
        }
    }

    private func loadChangeToken() -> PHPersistentChangeToken? {
        guard let data = UserDefaults.standard.data(forKey: changeTokenDefaultsKey) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: PHPersistentChangeToken.self, from: data)
    }

    private func saveChangeToken(_ token: PHPersistentChangeToken) {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) else { return }
        UserDefaults.standard.set(data, forKey: changeTokenDefaultsKey)
    }

    // Nonisolated async work runs on the cooperative executor rather than the
    // service's main actor. Only progress publication stays main-actor bound.
    private nonisolated func indexAsset(_ asset: PHAsset) async {
        let thumbnail = await requestImage(asset: asset, targetSize: CGSize(width: 220, height: 220), contentMode: .aspectFill, networkAllowed: false)
        guard let thumbnail else {
            await store.upsert(IndexedPhoto(id: asset.localIdentifier, creationDate: asset.creationDate, modificationDate: asset.modificationDate, thumbnailPath: nil, sensorDepthPath: nil, estimatedDepthPath: nil, sourceState: .deferredForDownload, sensorDepthState: .deferredForDownload, estimatedDepthState: .deferredForDownload, embedding: nil, categories: [], processingVersion: IndexedPhoto.processingVersion))
            return
        }
        let thumbnailPath = await Self.save(image: thumbnail, identifier: asset.localIdentifier, suffix: "thumbnail")
        var sensorDepthPath: String?
        var sensorDepthState: PhotoProcessingState = .unavailable
        var estimatedDepthPath: String?
        var estimatedDepthState: PhotoProcessingState = .pending
        var categories = [PhotoCategory]()
        var embedding: [Float]?

        if let image = await requestImage(asset: asset, targetSize: CGSize(width: 1024, height: 1024), contentMode: .aspectFit, networkAllowed: false) {
            if let depth = await sensorDepth(asset: asset) {
                sensorDepthPath = await Self.save(image: depth, identifier: asset.localIdentifier, suffix: "sensor-depth")
                sensorDepthState = .available
            }
            do {
                if let depth = try await ml.performDepthInference(image) {
                    estimatedDepthPath = await Self.save(image: depth, identifier: asset.localIdentifier, suffix: "estimated-depth")
                    estimatedDepthState = .available
                } else {
                    estimatedDepthState = .failed
                }
                categories = (try await ml.performClassifierInference(image) ?? [])
                    .filter { $0.probability >= 0.20 }
                    .map { PhotoCategory(id: $0.label.lowercased(), name: $0.label, probability: $0.probability, count: 0) }
                embedding = try await ml.imageEmbedding(for: image)
            } catch {
                estimatedDepthState = .failed
            }
        } else {
            estimatedDepthState = .deferredForDownload
        }

        await store.upsert(IndexedPhoto(
            id: asset.localIdentifier,
            creationDate: asset.creationDate,
            modificationDate: asset.modificationDate,
            thumbnailPath: thumbnailPath,
            sensorDepthPath: sensorDepthPath,
            estimatedDepthPath: estimatedDepthPath,
            sourceState: .available,
            sensorDepthState: sensorDepthState,
            estimatedDepthState: estimatedDepthState,
            embedding: embedding,
            categories: categories,
            processingVersion: IndexedPhoto.processingVersion
        ))
    }

    private func registerObserver() {
        guard observer == nil else { return }
        let observer = PhotoLibraryChangeObserver { [weak self] in
            self?.startIndexing()
        }
        self.observer = observer
        PHPhotoLibrary.shared().register(observer)
    }

    private static func summary(_ photo: IndexedPhoto) -> PhotoRecordSummary {
        PhotoRecordSummary(id: photo.id, creationDate: photo.creationDate, modificationDate: photo.modificationDate, thumbnailPath: photo.thumbnailPath, sensorDepthPath: photo.sensorDepthPath, estimatedDepthPath: photo.estimatedDepthPath, sourceState: photo.sourceState, sensorDepthState: photo.sensorDepthState, estimatedDepthState: photo.estimatedDepthState, categories: photo.categories)
    }

    private nonisolated func requestImage(asset: PHAsset, targetSize: CGSize, contentMode: PHImageContentMode, networkAllowed: Bool) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isSynchronous = false
            options.isNetworkAccessAllowed = networkAllowed
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            PHImageManager.default().requestImage(for: asset, targetSize: targetSize, contentMode: contentMode, options: options) { image, info in
                if let degraded = info?[PHImageResultIsDegradedKey] as? Bool, degraded { return }
                continuation.resume(returning: image)
            }
        }
    }

    private nonisolated func sensorDepth(asset: PHAsset) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isSynchronous = false
            options.isNetworkAccessAllowed = false
            options.version = .original
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                guard let data, let depth = Self.depth(imageData: data), let image = Self.image(depth: depth) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: image)
            }
        }
    }

    private nonisolated static func save(image: UIImage, identifier: String, suffix: String) async -> String? {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PhotoLibrary", isDirectory: true)
        let safeID = identifier.replacingOccurrences(of: "/", with: "_")
        var url = root.appendingPathComponent("\(safeID)-\(suffix).png")
        return await Task.detached(priority: .utility) {
            guard let data = image.pngData() else { return nil }
            do {
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                try? url.setResourceValues(values)
                return url.path
            } catch {
                return nil
            }
        }.value
    }

    private func removeDerivedFiles(at paths: [String]) {
        for path in paths {
            try? fileManager.removeItem(at: URL(fileURLWithPath: path))
        }
    }

    private nonisolated func loadImage(path: String) async -> UIImage? {
        await Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
            return UIImage(data: data)
        }.value
    }

    // Compatibility helpers used by legacy depth screens. These intentionally read the
    // same indexed records as PhotoPickerView rather than bypassing the index with PhotoKit.
    struct PhotoLibraryImage: Identifiable, Equatable, Hashable {
        var id: String
        var image: UIImage
        var depth: UIImage? = nil
        var estimatedDepth: UIImage? = nil
        var canny: UIImage? = nil
    }

    func getImages(limit: Int = 10, offset: Int = 0, size: CGSize = CGSize(width: 512, height: 512)) -> AsyncStream<PhotoLibraryImage> {
        return AsyncStream { continuation in
            let task = Task {
                defer { continuation.finish() }
                guard canAccess else { return }
                do {
                    let page = try await page(query: PhotoQuery(pageSize: offset + limit))
                    for record in page.records.dropFirst(offset).prefix(limit) {
                        guard !Task.isCancelled, let image = await thumbnail(for: record) else { continue }
                        continuation.yield(PhotoLibraryImage(id: record.id, image: image))
                    }
                } catch {
                    return
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func getImage(identifier: String, targetSize: CGSize) async throws -> UIImage {
        guard canAccess else { throw APIError.requestError("Photo library access is required to pick images.") }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = result.firstObject else { throw APIError.requestError("The selected photo is no longer available.") }
        guard let image = await requestImage(asset: asset, targetSize: targetSize, contentMode: .aspectFit, networkAllowed: true) else {
            throw APIError.requestError("Could not load the selected photo.")
        }
        return image
    }

    func getDepth(identifier: String) async -> PhotoLibraryImage? {
        guard let image = try? await getImage(identifier: identifier, targetSize: CGSize(width: 512, height: 512)) else { return nil }
        let estimated = try? await ml.performDepthInference(image)
        return PhotoLibraryImage(id: identifier, image: image, estimatedDepth: estimated)
    }

    func classify(image: UIImage) async -> [MLService.PredictionResult] {
        (try? await ml.performClassifierInference(image)) ?? []
    }

    private nonisolated static func depth(imageData: Data) -> AVDepthData? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(imageData as CFData, sourceOptions) else { return nil }
        let auxiliary = (CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeDepth) ??
            CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeDisparity)) as? [AnyHashable: Any]
        guard let auxiliary else { return nil }
        var sanitized = auxiliary
        if sanitized[kCGImageAuxiliaryDataInfoMetadata] is NSNull { sanitized[kCGImageAuxiliaryDataInfoMetadata] = [:] as CFDictionary }
        sanitized = sanitized.filter { !($0.value is NSNull) }
        return try? AVDepthData(fromDictionaryRepresentation: sanitized).converting(toDepthDataType: kCVPixelFormatType_DisparityFloat32)
    }

    private nonisolated static func image(depth: AVDepthData) -> UIImage? {
        let buffer = depth.depthDataMap
        let ciImage = CIImage(cvPixelBuffer: buffer)
        let context = CIContext()
        guard let image = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: image)
    }
}

private final class PhotoLibraryChangeObserver: NSObject, PHPhotoLibraryChangeObserver {
    private let onChange: @MainActor @Sendable () -> Void

    init(onChange: @escaping @MainActor @Sendable () -> Void) {
        self.onChange = onChange
    }

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor [onChange] in
            onChange()
        }
    }
}

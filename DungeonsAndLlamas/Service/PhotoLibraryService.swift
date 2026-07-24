//
//  PhotoLibraryService.swift
//  DungeonsAndLlamas
//

import Foundation
import Photos
import PhotosUI
import UIKit

private let photoLibraryLogger = LoggingService.shared.photoLibrary

enum PhotoRepresentation: String, CaseIterable, Codable, Hashable, Identifiable {
    case source
    case estimatedDepth

    var id: String { rawValue }

    var title: String {
        switch self {
        case .source: return "Source"
        case .estimatedDepth: return "Estimated Depth"
        }
    }

    var systemImage: String {
        switch self {
        case .source: return "photo"
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
    let sourceState: PhotoProcessingState
    let categories: [PhotoCategory]

    var representationStates: [PhotoRepresentation: PhotoProcessingState] {
        [.source: sourceState, .estimatedDepth: .available]
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
    static let processingVersion = 3
    let id: String
    let creationDate: Date?
    let modificationDate: Date?
    let sourceState: PhotoProcessingState
    let embedding: [Float]?
    let categories: [PhotoCategory]
    let processingVersion: Int

    init(
        id: String,
        creationDate: Date?,
        modificationDate: Date?,
        sourceState: PhotoProcessingState,
        embedding: [Float]?,
        categories: [PhotoCategory],
        processingVersion: Int
    ) {
        self.id = id
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.sourceState = sourceState
        self.embedding = embedding
        self.categories = categories
        self.processingVersion = processingVersion
    }

    init(_ photo: PhotoIndexModel) {
        id = photo.id
        creationDate = photo.creationDate
        modificationDate = photo.modificationDate
        sourceState = PhotoProcessingState(rawValue: photo.sourceState) ?? .failed
        embedding = photo.embedding
        categories = photo.categories
        processingVersion = photo.processingVersion
    }

    var databaseModel: PhotoIndexModel {
        PhotoIndexModel(
            id: id,
            creationDate: creationDate,
            modificationDate: modificationDate,
            sourceState: sourceState.rawValue,
            embedding: embedding,
            categories: categories,
            processingVersion: processingVersion
        )
    }
}

@MainActor
final class PhotoLibraryService: NSObject {
    var status: PHAuthorizationStatus?
    private(set) var isIndexing = false
    private(set) var indexedCount = 0
    private(set) var pendingCount = 0

    let ml: MLService
    private let database: DatabaseService
    private let changeTokenDefaultsKey = "PhotoLibraryService.currentChangeToken"
    private var indexingTask: Task<Void, Never>?
    private let searchEngine: any PhotoDistanceEngine
    private let embeddingCache = PhotoEmbeddingBufferCache()

    var canAccess: Bool {
        status == .authorized || status == .limited
    }

    init(database: DatabaseService, ml: MLService = MLService()) {
        self.database = database
        self.ml = ml
        self.searchEngine = MetalPhotoDistanceEngine()
        super.init()
    }

    deinit {
        indexingTask?.cancel()
    }

    func requestAccessIfNeeded() async {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        photoLibraryLogger.debug("Photo access check started: status=\(current.rawValue, privacy: .public)")
        if current == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        } else {
            status = current
        }
        photoLibraryLogger.info("Photo access check completed: status=\(self.status?.rawValue ?? -1, privacy: .public) canAccess=\(self.canAccess, privacy: .public)")
    }

    func startIndexing() async {
        await requestAccessIfNeeded()
        guard canAccess else {
            photoLibraryLogger.info("Photo sync not started: Photos access is unavailable (status=\(self.status?.rawValue ?? -1, privacy: .public))")
            return
        }
        startIndexingTask()
    }

    func presentLimitedLibraryManagement() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let controller = scene.keyWindow?.rootViewController else { return }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: controller)
    }

    private func startIndexingTask() {
        guard canAccess else {
            photoLibraryLogger.debug("Photo sync request ignored: Photos access is unavailable")
            return
        }
        guard indexingTask == nil else {
            photoLibraryLogger.debug("Photo sync request ignored: sync is already running")
            return
        }
        embeddingCache.invalidate()
        photoLibraryLogger.info("Photo sync started")
        isIndexing = true
        indexingTask = Task { [weak self] in
            guard let self else { return }
            await self.reconcileLibrary()
            photoLibraryLogger.info("Photo sync finished: indexed=\(self.indexedCount, privacy: .public) pending=\(self.pendingCount, privacy: .public)")
            self.isIndexing = false
            self.indexingTask = nil
        }
    }

    func stopIndexing() {
        photoLibraryLogger.info("Photo sync stopped")
        indexingTask?.cancel()
        indexingTask = nil
        isIndexing = false
        embeddingCache.invalidate()
    }

    func categories() async -> [PhotoCategory] {
        let records = database.loadPhotoIndexSummaries().map(IndexedPhoto.init)
        let grouped = Dictionary(grouping: records.flatMap(\.categories), by: \.id)
        return grouped.values.compactMap { values in
            guard let first = values.first else { return nil }
            return PhotoCategory(id: first.id, name: first.name, probability: first.probability, count: values.count)
        }.sorted { $0.count > $1.count }
    }

    func page(query: PhotoQuery, cursor: PhotoPageCursor? = nil) async throws -> PhotoPage {
        let offset = cursor?.offset ?? 0
        let pageSize = query.pageSize
        let hasSearchText = !query.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        var records: [IndexedPhoto]

        if !hasSearchText && query.categoryIDs.isEmpty {
            let page = database.loadPhotoIndexSummaryPage(limit: pageSize + 1, offset: offset)
                .map(IndexedPhoto.init)
            let hasNextPage = page.count > pageSize
            records = Array(page.prefix(pageSize))
            return PhotoPage(
                records: records.map(Self.summary),
                nextCursor: hasNextPage ? PhotoPageCursor(offset: offset + pageSize) : nil
            )
        }

        if hasSearchText, embeddingCache.isReady {
            records = database.loadPhotoIndexSummaries().map(IndexedPhoto.init)
        } else {
            records = hasSearchText
                ? database.loadPhotoIndex().map(IndexedPhoto.init)
                : database.loadPhotoIndexSummaries().map(IndexedPhoto.init)
        }
        if hasSearchText, !embeddingCache.isReady {
            embeddingCache.replace(with: records.compactMap { photo in
                guard let embedding = photo.embedding else { return nil }
                return (id: photo.id, embedding: embedding)
            })
        }
        let selected = query.categoryIDs
        if !selected.isEmpty {
            records = records.filter { photo in
                !selected.isDisjoint(with: photo.categories.map(\.id))
            }
        }

        if !query.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let embedding = try await ml.textEmbedding(for: query.text)
            let candidateRecords: [IndexedPhoto]
            let distances: [Float]
            if embeddingCache.isReady {
                candidateRecords = records.filter { embeddingCache.contains($0.id) }
                guard !candidateRecords.isEmpty else {
                    records = []
                    return PhotoPage(records: [], nextCursor: nil)
                }
                guard let candidateBuffer = embeddingCache.candidateBuffer(for: candidateRecords.map(\.id)) else {
                    throw PhotoSearchError.metalExecutionFailed("Unable to allocate cached search buffers.")
                }
                distances = try searchEngine.distances(
                    query: embedding,
                    candidateBuffer: candidateBuffer,
                    dimension: embeddingCache.dimension,
                    candidateCount: candidateRecords.count
                )
            } else {
                let candidates = records.compactMap { photo -> (IndexedPhoto, [Float])? in
                    guard let photoEmbedding = photo.embedding,
                          photoEmbedding.count == embedding.count else { return nil }
                    return (photo, photoEmbedding)
                }
                let flattenedCandidates = candidates.reduce(into: [Float]()) { result, candidate in
                    result.append(contentsOf: candidate.1)
                }
                candidateRecords = candidates.map(\.0)
                guard !candidateRecords.isEmpty else {
                    records = []
                    return PhotoPage(records: [], nextCursor: nil)
                }
                distances = try searchEngine.distances(
                    query: embedding,
                    flattenedCandidates: flattenedCandidates,
                    candidateCount: candidateRecords.count
                )
            }
            records = zip(candidateRecords, distances)
                .sorted { $0.1 < $1.1 }
                .map(\.0)
        }

        let end = min(offset + query.pageSize, records.count)
        let pageRecords = offset < end ? records[offset..<end] : []
        let summaries = pageRecords.map(Self.summary)
        let next = end < records.count ? PhotoPageCursor(offset: end) : nil
        return PhotoPage(records: summaries, nextCursor: next)
    }

    func thumbnail(for record: PhotoRecordSummary) async -> UIImage? {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [record.id], options: nil)
        guard let asset = assets.firstObject else { return nil }
        return await requestImage(
            asset: asset,
            targetSize: CGSize(width: 220, height: 220),
            contentMode: .aspectFill,
            networkAllowed: true
        )
    }

    func thumbnail(for record: PhotoRecordSummary, representation: PhotoRepresentation) async -> UIImage? {
        if representation == .source {
            return await thumbnail(for: record)
        }
        return await estimatedDepth(for: record.id)
    }

    func representation(for selection: PhotoPickerSelection, targetSize: CGSize) async throws -> UIImage {
        if selection.representation == .source {
            return try await getImage(identifier: selection.assetIdentifier, targetSize: targetSize)
        }
        guard let record = database.loadPhoto(id: selection.assetIdentifier).map(IndexedPhoto.init) else {
            throw APIError.requestError("The selected photo is no longer indexed.")
        }
        guard let image = await estimatedDepth(for: record.id) else {
            throw APIError.requestError("That depth representation is not available yet.")
        }
        return image
    }

    private func estimatedDepth(for identifier: String) async -> UIImage? {
        guard let image = try? await getImage(
            identifier: identifier,
            targetSize: CGSize(width: 1024, height: 1024)
        ) else { return nil }
        return try? await ml.performDepthInference(image)
    }

    private func reconcileLibrary() async {
        let currentToken = PHPhotoLibrary.shared().currentChangeToken
        let existingAtStart = database.loadPhotoIndexSummaries().map(IndexedPhoto.init)
        photoLibraryLogger.debug("Reconciling photo library: indexedAtStart=\(existingAtStart.count, privacy: .public)")
        if let storedToken = loadChangeToken(), storedToken.isEqual(currentToken), !existingAtStart.isEmpty {
            indexedCount = existingAtStart.count
            pendingCount = 0
            photoLibraryLogger.debug("Photo sync skipped: change token is current")
            return
        }

        if let storedToken = loadChangeToken(), !existingAtStart.isEmpty,
           await applyPersistentChanges(since: storedToken, currentToken: currentToken) {
            photoLibraryLogger.info("Photo sync completed using persistent change history")
            return
        }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let assets = PHAsset.fetchAssets(with: .image, options: options)
        let existing = existingAtStart
        photoLibraryLogger.info("Photo sync using full reconciliation: assets=\(assets.count, privacy: .public) existing=\(existing.count, privacy: .public)")
        let allowedIDs = Set((0..<assets.count).map { assets.object(at: $0).localIdentifier })
        database.removePhotos(ids: existing.map(\.id).filter { !allowedIDs.contains($0) })
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
                photoLibraryLogger.debug("Photo sync progress: indexed=\(self.indexedCount, privacy: .public) pending=\(self.pendingCount, privacy: .public)")
            }
        }
        indexedCount = assets.count
        pendingCount = 0
        saveChangeToken(currentToken)
        photoLibraryLogger.info("Full photo reconciliation complete: indexed=\(self.indexedCount, privacy: .public)")
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
            photoLibraryLogger.info("Photo change history fetched: changed=\(changedIDs.count, privacy: .public) deleted=\(deletedIDs.count, privacy: .public)")
            database.removePhotos(ids: Array(deletedIDs))

            let result = PHAsset.fetchAssets(withLocalIdentifiers: Array(changedIDs), options: nil)
            for index in 0..<result.count {
                if Task.isCancelled { return false }
                await indexAsset(result.object(at: index))
                indexedCount = index + 1
                pendingCount = max(result.count - indexedCount, 0)
                photoLibraryLogger.debug("Photo change sync progress: indexed=\(self.indexedCount, privacy: .public) pending=\(self.pendingCount, privacy: .public)")
            }
            indexedCount = database.loadPhotoIndexSummaries().count
            pendingCount = 0
            saveChangeToken(currentToken)
            return true
        } catch {
            photoLibraryLogger.error("Photo change history reconciliation failed: \(String(describing: error), privacy: .private)")
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
    private func indexAsset(_ asset: PHAsset) async {
        guard let image = await requestImage(asset: asset, targetSize: CGSize(width: 1024, height: 1024), contentMode: .aspectFit, networkAllowed: true) else {
            photoLibraryLogger.warning("Photo asset deferred: source image is not locally available")
            embeddingCache.invalidate()
            database.save(photo: IndexedPhoto(id: asset.localIdentifier, creationDate: asset.creationDate, modificationDate: asset.modificationDate, sourceState: .deferredForDownload, embedding: nil, categories: [], processingVersion: IndexedPhoto.processingVersion).databaseModel)
            return
        }
        var categories = [PhotoCategory]()
        var embedding: [Float]?

        do {
            categories = (try await ml.performClassifierInference(image) ?? [])
                .filter { $0.probability >= 0.20 }
                .map { PhotoCategory(id: $0.label.lowercased(), name: $0.label, probability: $0.probability, count: 0) }
            embedding = try await ml.imageEmbedding(for: image)
        } catch {
            photoLibraryLogger.error("Photo ML processing failed: \(String(describing: error), privacy: .private)")
        }

        embeddingCache.invalidate()
        database.save(photo: IndexedPhoto(
            id: asset.localIdentifier,
            creationDate: asset.creationDate,
            modificationDate: asset.modificationDate,
            sourceState: .available,
            embedding: embedding,
            categories: categories,
            processingVersion: IndexedPhoto.processingVersion
        ).databaseModel)
    }

    private static func summary(_ photo: IndexedPhoto) -> PhotoRecordSummary {
        PhotoRecordSummary(id: photo.id, creationDate: photo.creationDate, modificationDate: photo.modificationDate, sourceState: photo.sourceState, categories: photo.categories)
    }

    private nonisolated func requestImage(asset: PHAsset, targetSize: CGSize, contentMode: PHImageContentMode, networkAllowed: Bool) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isSynchronous = false
            options.isNetworkAccessAllowed = networkAllowed
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            PHImageManager.default().requestImage(for: asset, targetSize: targetSize, contentMode: contentMode, options: options) { image, info in
                if info?[PHImageCancelledKey] as? Bool == true || info?[PHImageErrorKey] != nil {
                    continuation.resume(returning: nil)
                    return
                }
                if let degraded = info?[PHImageResultIsDegradedKey] as? Bool, degraded { return }
                continuation.resume(returning: image)
            }
        }
    }

    // Compatibility helpers used by legacy depth screens. These intentionally read the
    // same indexed records as PhotoPickerView rather than bypassing the index with PhotoKit.
    struct PhotoLibraryImage: Identifiable, Equatable, Hashable {
        var id: String
        var image: UIImage
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

}

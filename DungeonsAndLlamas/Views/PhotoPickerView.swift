//
//  PhotoPickerView.swift
//  DungeonsAndLlamas
//

import SwiftUI
import Observation

struct PhotoPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: PhotoPickerModel

    let title: String
    let service: PhotoLibraryService
    let selectedID: String?
    let onSelect: (PhotoPickerSelection) -> Void

    init(title: String = "Choose Photo", service: PhotoLibraryService, selectedID: String? = nil, onSelect: @escaping (PhotoPickerSelection) -> Void) {
        self.title = title
        self.service = service
        self.selectedID = selectedID
        self.onSelect = onSelect
        self._model = State(initialValue: PhotoPickerModel(service: service))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                indexingControls

                if model.accessDenied {
                    accessState
                } else {
                    photoGrid
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $model.queryText, placement: .toolbar, prompt: "Search by description")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    representationMenu
                }
                ToolbarItem(placement: .topBarTrailing) {
                    categoryMenu
                }
                if model.isLimited {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Manage Photo Access", systemImage: "person.crop.circle.badge.exclamationmark") {
                            service.presentLimitedLibraryManagement()
                        }
                        .accessibilityLabel("Manage limited photo access")
                    }
                }
            }
        }
        .task {
            await model.load()
        }
        .task(id: model.querySignature) {
            await model.refreshAfterQueryChange()
        }
    }

    private var photoGrid: some View {
        ScrollView {
            if model.records.isEmpty, !model.isLoading {
                ContentUnavailableView(
                    model.hasActiveQuery ? "No matching photos" : "No photos indexed",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text(model.hasActiveQuery ? "Try a different description or filter." : "Photos will appear here as the library index is built.")
                )
                .frame(maxWidth: .infinity, minHeight: 320)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], spacing: 8) {
                    ForEach(model.records) { record in
                        PhotoPickerCell(
                            record: record,
                            representation: model.representation,
                            isSelected: selectedID == record.id,
                            service: service
                        ) {
                            let selection = PhotoPickerSelection(assetIdentifier: record.id, representation: model.representation)
                            onSelect(selection)
                            dismiss()
                        }
                        .onAppear {
                            model.loadMoreIfNeeded(current: record)
                        }
                    }

                    if model.isLoading {
                        ProgressView()
                            .frame(width: 88, height: 88)
                    }
                }
                .padding()
            }
        }
        .refreshable {
            await model.refresh()
        }
    }

    private var indexingControls: some View {
        HStack(spacing: 8) {
            if model.isIndexing {
                ProgressView()
                    .controlSize(.small)
                Text(model.pendingCount > 0 ? "Indexing photos… \(model.pendingCount) remaining" : "Indexing photos…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Photo indexing is paused")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(model.isIndexing ? "Pause" : "Start") {
                Task {
                    if model.isIndexing {
                        model.pauseIndexing()
                    } else {
                        await model.startIndexing()
                    }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.thinMaterial)
    }

    private var accessState: some View {
        ContentUnavailableView {
            Label("Photo Access Required", systemImage: "photo.badge.exclamationmark")
        } description: {
            Text("Allow access to choose photos and indexed categories.")
        } actions: {
            Button("Allow Photo Access") {
                Task { await model.requestAccess() }
            }
        }
    }

    private var representationMenu: some View {
        Menu {
            Picker("Representation", selection: $model.representation) {
                ForEach(PhotoRepresentation.allCases) { representation in
                    Label(representation.title, systemImage: representation.systemImage)
                        .tag(representation)
                }
            }
        } label: {
            Label(model.representation.title, systemImage: model.representation.systemImage)
        }
        .accessibilityLabel("Photo representation")
    }

    private var categoryMenu: some View {
        Menu {
            if model.categories.isEmpty {
                Text("Categories are still being indexed")
            } else {
                ForEach(model.categories) { category in
                    Button {
                        model.toggleCategory(category.id)
                    } label: {
                        Label {
                            Text("\(category.name) (\(category.count))")
                        } icon: {
                            Image(systemName: model.selectedCategories.contains(category.id) ? "checkmark.circle.fill" : "circle")
                        }
                    }
                }
                if !model.selectedCategories.isEmpty {
                    Divider()
                    Button("Clear Filters", role: .destructive) {
                        model.clearCategories()
                    }
                }
            }
        } label: {
            Label("Filter", systemImage: model.selectedCategories.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
        .accessibilityLabel("Filter by category")
    }
}

@MainActor
@Observable
private final class PhotoPickerModel {
    let service: PhotoLibraryService
    var records = [PhotoRecordSummary]()
    var categories = [PhotoCategory]()
    var queryText = ""
    var selectedCategories = Set<String>()
    var representation: PhotoRepresentation = .source
    var isLoading = false
    var isIndexing = false
    var pendingCount = 0
    var accessDenied = false
    var isLimited = false
    var nextCursor: PhotoPageCursor?
    var error: String?

    private var hasLoaded = false
    private var refreshTask: Task<Void, Never>?
    private var pagingTask: Task<Void, Never>?
    private var indexingMonitorTask: Task<Void, Never>?
    private var queryGeneration = 0

    init(service: PhotoLibraryService) {
        self.service = service
    }

    var hasActiveQuery: Bool {
        !queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !selectedCategories.isEmpty
    }

    var querySignature: String {
        "\(queryText)|\(selectedCategories.sorted().joined(separator: ","))"
    }

    func load() async {
        await service.requestAccessIfNeeded()
        accessDenied = !service.canAccess
        isLimited = service.status == .limited
        guard service.canAccess else { return }
        await refresh()
        categories = await service.categories()
        isIndexing = service.isIndexing
        pendingCount = service.pendingCount
        hasLoaded = true
        if isIndexing {
            monitorIndexing()
        }
    }

    func requestAccess() async {
        await service.requestAccessIfNeeded()
        accessDenied = !service.canAccess
        isLimited = service.status == .limited
        if service.canAccess {
            await refresh()
        }
    }

    func startIndexing() async {
        await service.startIndexing()
        isIndexing = service.isIndexing
        pendingCount = service.pendingCount
        if isIndexing {
            monitorIndexing()
        }
    }

    func pauseIndexing() {
        indexingMonitorTask?.cancel()
        service.stopIndexing()
        isIndexing = false
        pendingCount = service.pendingCount
    }

    private func monitorIndexing() {
        indexingMonitorTask?.cancel()
        indexingMonitorTask = Task {
            while !Task.isCancelled, service.isIndexing {
                isIndexing = service.isIndexing
                pendingCount = service.pendingCount
                try? await Task.sleep(for: .milliseconds(350))
            }
            guard !Task.isCancelled else { return }
            isIndexing = service.isIndexing
            pendingCount = service.pendingCount
            categories = await service.categories()
            await refresh()
        }
    }

    func refreshAfterQueryChange() async {
        guard hasLoaded else { return }
        queryGeneration += 1
        pagingTask?.cancel()
        refreshTask?.cancel()
        refreshTask = Task {
            try? await Task.sleep(for: .milliseconds(275))
            guard !Task.isCancelled else { return }
            await refresh()
        }
        await refreshTask?.value
    }

    func refresh() async {
        refreshTask = nil
        pagingTask?.cancel()
        nextCursor = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await service.page(query: PhotoQuery(text: queryText, categoryIDs: selectedCategories, pageSize: 60))
            records = page.records
            nextCursor = page.nextCursor
            categories = await service.categories()
            isIndexing = service.isIndexing
            pendingCount = service.pendingCount
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadMoreIfNeeded(current: PhotoRecordSummary) {
        guard current.id == records.last?.id, let nextCursor, !isLoading else { return }
        let query = PhotoQuery(text: queryText, categoryIDs: selectedCategories, pageSize: 60)
        let generation = queryGeneration
        isLoading = true
        pagingTask = Task {
            defer { isLoading = false }
            do {
                let page = try await service.page(query: query, cursor: nextCursor)
                guard !Task.isCancelled, generation == queryGeneration else { return }
                records.append(contentsOf: page.records)
                self.nextCursor = page.nextCursor
            } catch is CancellationError {
            } catch {
                guard generation == queryGeneration else { return }
                self.error = error.localizedDescription
            }
        }
    }

    func toggleCategory(_ id: String) {
        if selectedCategories.contains(id) {
            selectedCategories.remove(id)
        } else {
            selectedCategories.insert(id)
        }
    }

    func clearCategories() {
        selectedCategories.removeAll()
    }
}

private struct PhotoPickerCell: View {
    let record: PhotoRecordSummary
    let representation: PhotoRepresentation
    let isSelected: Bool
    let service: PhotoLibraryService
    let onSelect: () -> Void
    @State private var image: UIImage?
    @State private var isLoading = false

    private var state: PhotoProcessingState {
        record.representationStates[representation] ?? .unavailable
    }

    var body: some View {
        Button(action: onSelect) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        placeholder
                    }
                }
                .frame(minWidth: 88, minHeight: 88)
                .aspectRatio(1, contentMode: .fit)
                .clipped()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.accentColor)
                        .padding(5)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 3)
            }
        }
        .buttonStyle(.plain)
        .disabled(isLoading || (representation == .estimatedDepth && image == nil) || (state != .available && !(representation == .source && image != nil)))
        .accessibilityLabel(isSelected ? "Selected photo" : "Photo")
        .task(id: "\(record.id)-\(representation.rawValue)") {
            isLoading = true
            defer { isLoading = false }
            image = nil
            image = await service.thumbnail(for: record, representation: representation)
        }
    }

    @ViewBuilder
    private var placeholder: some View {
        switch state {
        case .processing, .pending:
            ProgressView()
        case .deferredForDownload:
            Image(systemName: "icloud.and.arrow.down")
                .foregroundStyle(.secondary)
        case .unavailable:
            VStack(spacing: 4) {
                Image(systemName: "slash.circle")
                Text("Unavailable")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
        case .failed:
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        case .available:
            if isLoading {
                ProgressView()
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

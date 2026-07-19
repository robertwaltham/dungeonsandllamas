//
//  ComfyUIClient.swift
//  DungeonsAndLlamas
//
//  Created by OpenAI on 2026-06-21.
//

import Foundation
import AnyCodable

actor ComfyUIClient {
    private enum Endpoint {
        case embeddings
        case extensions
        case features
        case models
        case modelsInFolder(String)
        case workflowTemplates
        case uploadImage
        case uploadMask
        case view
        case viewMetadata(String)
        case systemStats
        case prompt
        case objectInfo
        case objectInfoForNode(String)
        case history
        case historyItem(String)
        case queue
        case interrupt
        case free
        case userData(directory: String?)
        case userDataFile(String)
        case userDataMove(file: String, destination: String)
        case users
        case webSocket(clientId: String?)

        var path: String {
            switch self {
            case .embeddings:
                return "/embeddings"
            case .extensions:
                return "/extensions"
            case .features:
                return "/features"
            case .models:
                return "/models"
            case .modelsInFolder(let folder):
                return "/models/\(folder)"
            case .workflowTemplates:
                return "/workflow_templates"
            case .uploadImage:
                return "/upload/image"
            case .uploadMask:
                return "/upload/mask"
            case .view:
                return "/view"
            case .viewMetadata(let folder):
                return "/view_metadata/\(folder)"
            case .systemStats:
                return "/system_stats"
            case .prompt:
                return "/prompt"
            case .objectInfo:
                return "/object_info"
            case .objectInfoForNode(let nodeClass):
                return "/object_info/\(nodeClass)"
            case .history:
                return "/history"
            case .historyItem(let promptId):
                return "/history/\(promptId)"
            case .queue:
                return "/queue"
            case .interrupt:
                return "/interrupt"
            case .free:
                return "/free"
            case .userData(let directory):
                guard let directory, !directory.isEmpty else {
                    return "/userdata"
                }
                return "/userdata?dir=\(directory)"
            case .userDataFile(let file):
                return "/userdata/\(file)"
            case .userDataMove(let file, let destination):
                return "/userdata/\(file)/move/\(destination)"
            case .users:
                return "/users"
            case .webSocket(let clientId):
                guard let clientId, !clientId.isEmpty else {
                    return "/ws"
                }
                return "/ws?clientId=\(clientId)"
            }
        }
    }

    private enum Method: String {
        case delete = "DELETE"
        case get = "GET"
        case post = "POST"
    }

    struct PromptSubmission: Encodable, @unchecked Sendable {
        let prompt: [String: AnyCodable]
        let clientId: String?
        let promptId: String?
        let extraData: [String: AnyCodable]?

        init(prompt: [String: AnyCodable], clientId: String? = nil, promptId: String? = nil, extraData: [String: AnyCodable]? = nil) {
            self.prompt = prompt
            self.clientId = clientId
            self.promptId = promptId
            self.extraData = extraData
        }
    }

    struct PromptResponse: Decodable, @unchecked Sendable {
        let promptId: String?
        let number: Int?
        let error: AnyCodable?
        let nodeErrors: [String: AnyCodable]?
    }

    struct ImageUploadResponse: Decodable {
        let name: String
        let subfolder: String
        let type: String
    }

    struct UploadedImage: Encodable {
        let image: String
        let subfolder: String?
        let type: String?
    }

    enum ViewImageType: String, Codable, Sendable {
        case input
        case output
        case temp
    }

    struct HistoryEntry: Decodable, Sendable {
        let outputs: [String: NodeOutput]
    }

    struct HistoryRecord: Decodable, Sendable {
        let prompt: PromptRecord
        let outputs: [String: NodeOutput]
        let status: HistoryStatus

        struct PromptRecord: Decodable, Sendable {
            let number: Int
            let promptId: String
            let workflow: [String: WorkflowNode]
            let clientId: String?
            let createTime: Int64?

            init(from decoder: Decoder) throws {
                var container = try decoder.unkeyedContainer()
                number = try container.decode(Int.self)
                promptId = try container.decode(String.self)
                workflow = try container.decode([String: WorkflowNode].self)
                let metadata = try container.decode([String: JSONValue].self)
                clientId = metadata["client_id"]?.stringValue
                createTime = metadata["create_time"]?.int64Value
            }
        }

        struct WorkflowNode: Decodable, Sendable {
            let classType: String
            let inputs: [String: JSONValue]
        }

        struct HistoryStatus: Decodable, Sendable {
            let statusStr: String
            let completed: Bool
            let messages: [[JSONValue]]
        }

        indirect enum JSONValue: Decodable, Sendable {
            case string(String)
            case number(Double)
            case bool(Bool)
            case object([String: JSONValue])
            case array([JSONValue])
            case null

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if container.decodeNil() {
                    self = .null
                } else if let value = try? container.decode(String.self) {
                    self = .string(value)
                } else if let value = try? container.decode(Bool.self) {
                    self = .bool(value)
                } else if let value = try? container.decode(Double.self) {
                    self = .number(value)
                } else if let value = try? container.decode([String: JSONValue].self) {
                    self = .object(value)
                } else {
                    self = .array(try container.decode([JSONValue].self))
                }
            }

            var stringValue: String? {
                guard case .string(let value) = self else { return nil }
                return value
            }

            var int64Value: Int64? {
                guard case .number(let value) = self else { return nil }
                return Int64(value)
            }
        }
    }

    struct NodeOutput: Decodable, Sendable {
        let images: [ImageReference]?
    }

    struct ImageReference: Decodable, Sendable {
        let filename: String
        let subfolder: String
        let type: ViewImageType
    }

    struct ConnectionInfo: Sendable {
        let url: String
        let statusCode: Int
        let connected: Bool
    }

    struct SystemStatus: Decodable, Sendable {
        let system: SystemInfo
        let devices: [Device]

        struct SystemInfo: Decodable, Sendable {
            let os: String
            let ramTotal: Int64
            let ramFree: Int64
            let comfyuiVersion: String
            let requiredFrontendVersion: String
            let installedTemplatesVersion: String
            let requiredTemplatesVersion: String
            let comfyPackageVersions: [PackageVersion]
            let pythonVersion: String
            let pytorchVersion: String
            let embeddedPython: Bool
            let deployEnvironment: String
            let argv: [String]
        }

        struct PackageVersion: Decodable, Sendable {
            let name: String
            let installed: String
            let required: String
        }

        struct Device: Decodable, Sendable {
            let name: String
            let type: String
            let index: Int
            let vramTotal: Int64
            let vramFree: Int64
            let torchVramTotal: Int64
            let torchVramFree: Int64
        }
    }

    struct QueueOperation: Encodable {
        let clear: Bool?
        let delete: [String]?

        init(clear: Bool? = nil, delete: [String]? = nil) {
            self.clear = clear
            self.delete = delete
        }
    }

    struct FreeMemoryRequest: Encodable {
        let unloadModels: Bool?
        let freeMemory: Bool?

        init(unloadModels: Bool? = nil, freeMemory: Bool? = nil) {
            self.unloadModels = unloadModels
            self.freeMemory = freeMemory
        }
    }

    struct HistoryOperation: Encodable {
        let clear: Bool?
        let delete: [String]?

        init(clear: Bool? = nil, delete: [String]? = nil) {
            self.clear = clear
            self.delete = delete
        }
    }

    struct WebSocketEvent: Decodable, @unchecked Sendable {
        let type: String
        let data: AnyCodable?

        var knownType: KnownWebSocketEventType? {
            KnownWebSocketEventType(rawValue: type)
        }

        func isExecutionComplete(for promptId: String) -> Bool {
            guard knownType == .executing,
                  let data = data?.value as? [String: Any],
                  data["prompt_id"] as? String == promptId.lowercased(),
                  data["node"] is NSNull else {
                return false
            }
            return true
        }
    }

    enum KnownWebSocketEventType: String {
        case status
        case executionStart = "execution_start"
        case executionCached = "execution_cached"
        case executing
        case progress
        case executed
        case executionError = "execution_error"
        case executionInterrupted = "execution_interrupted"
    }

    enum WebSocketMessage: Sendable {
        case event(WebSocketEvent)
        case text(String)
        case data(Data)
    }

    private let session: URLSession
    private(set) var latestSystemStats: (connection: ConnectionInfo, status: SystemStatus)?

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }

    private var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .iso8601
        return e
    }

    init() {
        session = URLSession(configuration: .default, delegate: nil, delegateQueue: nil)
    }

    func testConnection() async throws -> Bool {
        try await systemStats().connection.connected
    }

    func embeddings() async throws -> [String] {
        try await get(.embeddings)
    }

    func extensions() async throws -> [String] {
        try await get(.extensions)
    }

    func features() async throws -> [String: AnyCodable] {
        try await get(.features)
    }

    func modelFolders() async throws -> [String] {
        try await get(.models)
    }

    func models(in folder: String) async throws -> [String] {
        try await get(.modelsInFolder(folder))
    }

    func workflowTemplates() async throws -> [String: AnyCodable] {
        try await get(.workflowTemplates)
    }

    func generateImageFlux2KleinImageEdit(prompt: String, seed: Int64, imageFilename: String, clientId: String, promptId: String) async throws -> [String: [String]] {
        let clientId = clientId.lowercased()
        let promptId = promptId.lowercased()
        let messageStream = try messages(clientId: clientId)
        _ = try await submitImageFlux2KleinImageEdit(
            prompt: prompt,
            seed: seed,
            imageFilename: imageFilename,
            clientId: clientId,
            promptId: promptId
        )

        for try await message in messageStream {
            guard case .event(let event) = message, event.isExecutionComplete(for: promptId) else {
                continue
            }
            break
        }

        return try await imageOutputPaths(promptId: promptId)
    }

    func submitImageFlux2KleinImageEdit(prompt: String, seed: Int64, imageFilename: String, clientId: String, promptId: String) async throws -> PromptResponse {
        let workflowPrompt = try ComfyUIClient.imageFlux2KleinImageEditWorkflow(prompt: prompt, seed: seed, imageFilename: imageFilename)
        return try await submitPrompt(PromptSubmission(prompt: workflowPrompt, clientId: clientId.lowercased(), promptId: promptId.lowercased()))
    }

    func submitImageFlux2Klein2ImageEdit(prompt: String, seed: Int64, firstImageFilename: String, secondImageFilename: String, clientId: String, promptId: String) async throws -> PromptResponse {
        let workflowPrompt = try ComfyUIClient.imageFlux2Klein2ImageEditWorkflow(
            prompt: prompt,
            seed: seed,
            firstImageFilename: firstImageFilename,
            secondImageFilename: secondImageFilename
        )
        return try await submitPrompt(PromptSubmission(prompt: workflowPrompt, clientId: clientId.lowercased(), promptId: promptId.lowercased()))
    }

    func imageOutputPaths(promptId: String) async throws -> [String: [String]] {
        let promptId = promptId.lowercased()
        let history = try await promptHistory(promptId: promptId)
        guard let entry = history[promptId] else {
            throw APIError.requestError("no history for prompt id \(promptId)")
        }

        var outputImages = [String: [String]]()
        for (nodeId, output) in entry.outputs {
            var imagePaths = [String]()
            for imageReference in output.images ?? [] {
                let imagePath = try await image(named: imageReference.filename, type: imageReference.type)
                imagePaths.append(imagePath)
            }
            outputImages[nodeId] = imagePaths
        }
        return outputImages
    }

    func systemStats() async throws -> (connection: ConnectionInfo, status: SystemStatus) {
        let request = try ComfyUIClient.request(endpoint: .systemStats, method: .get)
        let (data, response) = try await self.data(for: request)
        try ComfyUIClient.validate(response: response, data: data)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.requestError("no request")
        }

        let connection = ConnectionInfo(
            url: response.url?.absoluteString ?? request.url?.absoluteString ?? "n/a",
            statusCode: httpResponse.statusCode,
            connected: (200...299).contains(httpResponse.statusCode)
        )
        let status = try decoder.decode(SystemStatus.self, from: data)
        let result = (connection, status)
        latestSystemStats = result
        return result
    }

    func queueStatus() async throws -> [String: AnyCodable] {
        try await get(.prompt)
    }

    func submitPrompt(_ submission: PromptSubmission) async throws -> PromptResponse {
        try await post(.prompt, body: submission)
    }

    func objectInfo() async throws -> [String: AnyCodable] {
        try await get(.objectInfo)
    }

    func objectInfo(for nodeClass: String) async throws -> [String: AnyCodable] {
        try await get(.objectInfoForNode(nodeClass))
    }

    func history() async throws -> [String: AnyCodable] {
        try await get(.history)
    }

    func typedHistory() async throws -> [String: HistoryRecord] {
        let rawRecords = try await history()
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        var records = [String: HistoryRecord]()

        for (key, rawRecord) in rawRecords {
            guard let data = try? JSONEncoder().encode(rawRecord),
                  let record = try? decoder.decode(HistoryRecord.self, from: data),
                  key.lowercased() == record.prompt.promptId.lowercased() else {
                continue
            }
            records[key] = record
        }
        return records
    }

    func history(promptId: String) async throws -> [String: AnyCodable] {
        try await get(.historyItem(promptId))
    }

    func updateHistory(_ operation: HistoryOperation) async throws {
        let _: EmptyResponse = try await post(.history, body: operation)
    }

    func queue() async throws -> [String: AnyCodable] {
        try await get(.queue)
    }

    func updateQueue(_ operation: QueueOperation) async throws {
        let _: EmptyResponse = try await post(.queue, body: operation)
    }

    func interrupt() async throws {
        let _: EmptyResponse = try await post(.interrupt, body: EmptyRequest())
    }

    func freeMemory(_ request: FreeMemoryRequest) async throws {
        let _: EmptyResponse = try await post(.free, body: request)
    }

    func userData(directory: String? = nil) async throws -> [String: AnyCodable] {
        try await get(.userData(directory: directory))
    }

    func userDataFile(_ file: String) async throws -> Data {
        let request = try ComfyUIClient.request(endpoint: .userDataFile(file), method: .get)
        let (data, response) = try await self.data(for: request)
        try ComfyUIClient.validate(response: response, data: data)
        return data
    }

    func uploadUserDataFile(_ data: Data, file: String, mimeType: String = "application/octet-stream") async throws -> [String: AnyCodable] {
        var request = try ComfyUIClient.request(endpoint: .userDataFile(file), method: .post)
        request.addValue(mimeType, forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        let (responseData, response) = try await self.data(for: request)
        try ComfyUIClient.validate(response: response, data: responseData)
        return try decoder.decode([String: AnyCodable].self, from: responseData)
    }

    func deleteUserDataFile(_ file: String) async throws {
        let request = try ComfyUIClient.request(endpoint: .userDataFile(file), method: .delete)
        let (data, response) = try await self.data(for: request)
        try ComfyUIClient.validate(response: response, data: data)
    }

    func moveUserDataFile(_ file: String, to destination: String) async throws {
        let _: EmptyResponse = try await post(.userDataMove(file: file, destination: destination), body: EmptyRequest())
    }

    func users() async throws -> [String: AnyCodable] {
        try await get(.users)
    }

    func uploadImage(_ data: Data, filename: String, subfolder: String? = nil, type: ViewImageType? = nil, overwrite: Bool? = nil) async throws -> ImageUploadResponse {
        try await upload(data, filename: filename, mimeType: "image/png", endpoint: .uploadImage, subfolder: subfolder, type: type, overwrite: overwrite)
    }

    func uploadMask(_ data: Data, filename: String, originalReference: UploadedImage? = nil, subfolder: String? = nil, overwrite: Bool? = nil) async throws -> ImageUploadResponse {
        var multipart = multipartUpload(data, filename: filename, mimeType: "image/png", subfolder: subfolder, overwrite: overwrite)
        if let originalReference {
            let referenceData = try encoder.encode(originalReference)
            if let reference = String(data: referenceData, encoding: .utf8) {
                multipart.add(key: "original_ref", value: reference)
            }
        }

        return try await performMultipartUpload(multipart, endpoint: .uploadMask)
    }

    func image(named filename: String, type: ViewImageType = .output) async throws -> String {
        let queryItems = [
            URLQueryItem(name: "filename", value: filename),
            URLQueryItem(name: "type", value: type.rawValue)
        ]

        var request = try ComfyUIClient.request(endpoint: .view, method: .get, queryItems: queryItems)
        request.addValue("image/*", forHTTPHeaderField: "Accept")
        let (data, response) = try await self.data(for: request)
        try ComfyUIClient.validate(response: response, data: data)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.requestError("no request")
        }
        guard let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type"), contentType.lowercased().hasPrefix("image/") else {
            throw APIError.requestError("expected image response, got \(httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "no content type")")
        }

        return try ComfyUIClient.saveTemporaryImage(data: data, filename: filename, contentType: contentType)
    }

    func imageData(named filename: String, subfolder: String = "", type: ViewImageType = .output) async throws -> Data {
        let queryItems = [
            URLQueryItem(name: "filename", value: filename),
            URLQueryItem(name: "subfolder", value: subfolder),
            URLQueryItem(name: "type", value: type.rawValue)
        ]
        let request = try ComfyUIClient.request(endpoint: .view, method: .get, queryItems: queryItems)
        let (data, response) = try await self.data(for: request)
        try ComfyUIClient.validate(response: response, data: data)
        guard let httpResponse = response as? HTTPURLResponse,
              let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type"),
              contentType.lowercased().hasPrefix("image/") else {
            throw APIError.requestError("expected image response")
        }
        return data
    }

    func metadata(folderName: String, filename: String) async throws -> [String: AnyCodable] {
        try await get(.viewMetadata(folderName), queryItems: [URLQueryItem(name: "filename", value: filename)])
    }

    func messages(clientId: String? = nil) throws -> AsyncThrowingStream<WebSocketMessage, Error> {
        let request = try ComfyUIClient.webSocketRequest(endpoint: .webSocket(clientId: clientId))
        let socket = session.webSocketTask(with: request)
        let decoder = decoder
        socket.resume()

        return AsyncThrowingStream<WebSocketMessage, Error> { continuation in
            let task = Task {
                do {
                    while !Task.isCancelled {
                        let message = try await socket.receive()
                        switch message {
                        case .data(let data):
                            continuation.yield(.data(data))
                        case .string(let string):
                            if let data = string.data(using: .utf8), let event = try? decoder.decode(WebSocketEvent.self, from: data) {
                                continuation.yield(.event(event))
                            } else {
                                continuation.yield(.text(string))
                            }
                        @unknown default:
                            throw APIError.requestError("unsupported websocket message")
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
                socket.cancel(with: .goingAway, reason: nil)
            }
        }
    }

    private func promptHistory(promptId: String) async throws -> [String: HistoryEntry] {
        try await get(.historyItem(promptId))
    }

    private func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let (data, response) = try await session.data(for: request, delegate: DelegateToSupressWarning())
        ComfyUIClient.debugPrintResponse(request: request, response: response, data: data)
        return (data, response)
    }

    private func get<T: Decodable>(_ endpoint: Endpoint, queryItems: [URLQueryItem] = []) async throws -> T {
        let request = try ComfyUIClient.request(endpoint: endpoint, method: .get, queryItems: queryItems)
        let (data, response) = try await self.data(for: request)
        try ComfyUIClient.validate(response: response, data: data)
        return try decoder.decode(T.self, from: data)
    }

    private func post<Body: Encodable, Response: Decodable>(_ endpoint: Endpoint, body: Body) async throws -> Response {
        var request = try ComfyUIClient.request(endpoint: endpoint, method: .post)
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        let (data, response) = try await self.data(for: request)
        try ComfyUIClient.validate(response: response, data: data)
        let responseData = data.isEmpty ? Data("{}".utf8) : data
        return try decoder.decode(Response.self, from: responseData)
    }

    private func upload(_ data: Data, filename: String, mimeType: String, endpoint: Endpoint, subfolder: String?, type: ViewImageType? = nil, overwrite: Bool?) async throws -> ImageUploadResponse {
        let multipart = multipartUpload(data, filename: filename, mimeType: mimeType, subfolder: subfolder, type: type, overwrite: overwrite)
        return try await performMultipartUpload(multipart, endpoint: endpoint)
    }

    private func multipartUpload(_ data: Data, filename: String, mimeType: String, subfolder: String?, type: ViewImageType? = nil, overwrite: Bool?) -> MultipartRequest {
        var multipart = MultipartRequest()
        multipart.add(key: "image", fileName: filename, fileMimeType: mimeType, fileData: data)
        if let subfolder {
            multipart.add(key: "subfolder", value: subfolder)
        }
        if let type {
            multipart.add(key: "type", value: type.rawValue)
        }
        if let overwrite {
            multipart.add(key: "overwrite", value: String(overwrite))
        }
        return multipart
    }

    private func performMultipartUpload(_ multipart: MultipartRequest, endpoint: Endpoint) async throws -> ImageUploadResponse {
        var request = try ComfyUIClient.request(endpoint: endpoint, method: .post)
        request.setValue(multipart.httpContentTypeHeadeValue, forHTTPHeaderField: "Content-Type")
        request.httpBody = multipart.httpBody
        let (data, response) = try await self.data(for: request)
        try ComfyUIClient.validate(response: response, data: data)
        return try decoder.decode(ImageUploadResponse.self, from: data)
    }

    private static func request(endpoint: Endpoint, method: Method, timeout: TimeInterval = 120.0, queryItems: [URLQueryItem] = []) throws -> URLRequest {
        guard var components = URLComponents(string: "\(Secrets.host)\(endpoint.path)") else {
            throw APIError.badURL(endpoint.path)
        }
        if !queryItems.isEmpty {
            components.queryItems = (components.queryItems ?? []) + queryItems
        }
        guard let url = components.url else {
            throw APIError.badURL(endpoint.path)
        }

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method.rawValue
        request.addValue(basicAuthorization, forHTTPHeaderField: "Authorization")
        debugPrintCurl(for: request)
        return request
    }

    private static func imageFlux2KleinImageEditWorkflow(prompt: String, seed: Int64, imageFilename: String) throws -> [String: AnyCodable] {
        let data = try workflowData(named: "image_flux2_klein_image_edit_4b_distilled", extension: "json")
        guard var workflow = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var loadImageNode = workflow["76"] as? [String: Any],
              var loadImageInputs = loadImageNode["inputs"] as? [String: Any],
              var textNode = workflow["75:74"] as? [String: Any],
              var textInputs = textNode["inputs"] as? [String: Any],
              var seedNode = workflow["75:73"] as? [String: Any],
              var seedInputs = seedNode["inputs"] as? [String: Any] else {
            throw APIError.requestError("invalid image edit workflow")
        }

        loadImageInputs["image"] = imageFilename
        loadImageNode["inputs"] = loadImageInputs
        workflow["76"] = loadImageNode

        textInputs["text"] = prompt
        textNode["inputs"] = textInputs
        workflow["75:74"] = textNode

        seedInputs["noise_seed"] = seed
        seedNode["inputs"] = seedInputs
        workflow["75:73"] = seedNode

        return workflow.mapValues { AnyCodable($0) }
    }

    private static func imageFlux2Klein2ImageEditWorkflow(prompt: String, seed: Int64, firstImageFilename: String, secondImageFilename: String) throws -> [String: AnyCodable] {
        let data = try workflowData(named: "image_flux2_klein_2_image_edit_4b_distilled", extension: "json")
        guard var workflow = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var firstLoadImageNode = workflow["76"] as? [String: Any],
              var firstLoadImageInputs = firstLoadImageNode["inputs"] as? [String: Any],
              var secondLoadImageNode = workflow["81"] as? [String: Any],
              var secondLoadImageInputs = secondLoadImageNode["inputs"] as? [String: Any],
              var textNode = workflow["92:109"] as? [String: Any],
              var textInputs = textNode["inputs"] as? [String: Any],
              var seedNode = workflow["92:106"] as? [String: Any],
              var seedInputs = seedNode["inputs"] as? [String: Any] else {
            throw APIError.requestError("invalid two image edit workflow")
        }

        firstLoadImageInputs["image"] = firstImageFilename
        firstLoadImageNode["inputs"] = firstLoadImageInputs
        workflow["76"] = firstLoadImageNode

        secondLoadImageInputs["image"] = secondImageFilename
        secondLoadImageNode["inputs"] = secondLoadImageInputs
        workflow["81"] = secondLoadImageNode

        textInputs["text"] = prompt
        textNode["inputs"] = textInputs
        workflow["92:109"] = textNode

        seedInputs["noise_seed"] = seed
        seedNode["inputs"] = seedInputs
        workflow["92:106"] = seedNode

        return workflow.mapValues { AnyCodable($0) }
    }

    private static func workflowData(named name: String, extension fileExtension: String) throws -> Data {
        let candidates = [
            Bundle.main.url(forResource: name, withExtension: fileExtension)
        ]

        guard let url = candidates.compactMap({ $0 }).first else {
            throw APIError.badURL("missing workflow \(name).\(fileExtension)")
        }
        return try Data(contentsOf: url)
    }

    private static func saveTemporaryImage(data: Data, filename: String, contentType: String) throws -> String {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ComfyUIImages", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let sanitizedFilename = URL(fileURLWithPath: filename).lastPathComponent
        let baseName = URL(fileURLWithPath: sanitizedFilename).deletingPathExtension().lastPathComponent
        let fileExtension = imageFileExtension(for: contentType)
        let outputFilename = "\(baseName)-\(UUID().uuidString).\(fileExtension)"
        let fileURL = directory.appendingPathComponent(outputFilename)
        try data.write(to: fileURL)
        return fileURL.path()
    }

    private static func imageFileExtension(for contentType: String) -> String {
        switch contentType.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased() {
        case "image/jpeg", "image/jpg":
            return "jpg"
        case "image/webp":
            return "webp"
        case "image/gif":
            return "gif"
        default:
            return "png"
        }
    }

    private static func debugPrintResponse(request: URLRequest, response: URLResponse, data: Data) {
//        let url = response.url ?? request.url
//        let statusCode = (response as? HTTPURLResponse)?.statusCode
//        let responseText = String(data: data, encoding: .utf8) ?? "<\(data.count) bytes>"
//
//        print("ComfyUI response url: \(url?.absoluteString ?? "n/a")")
//        print("ComfyUI response status: \(statusCode.map(String.init) ?? "n/a")")
//        print("ComfyUI response body: \(responseText)")
    }

    private static func debugPrintCurl(for request: URLRequest) {
//        guard let url = request.url else {
//            return
//        }
//
//        var components = ["curl"]
//        components.append("-X \(request.httpMethod ?? "GET")")
//
//        for (field, value) in request.allHTTPHeaderFields ?? [:] {
//            components.append("-H '\(shellEscaped("\(field): \(value)"))'")
//        }
//
//        if let httpBody = request.httpBody, let body = String(data: httpBody, encoding: .utf8) {
//            components.append("--data '\(shellEscaped(body))'")
//        }
//
//        components.append("'\(shellEscaped(url.absoluteString))'")
//        print(components.joined(separator: " "))
    }

    private static func shellEscaped(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "'\\''")
    }

    private static func webSocketRequest(endpoint: Endpoint) throws -> URLRequest {
        guard var components = URLComponents(string: "\(Secrets.host)\(endpoint.path)") else {
            throw APIError.badURL(endpoint.path)
        }
        switch components.scheme {
        case "https":
            components.scheme = "wss"
        case "http":
            components.scheme = "ws"
        default:
            break
        }
        guard let url = components.url else {
            throw APIError.badURL(endpoint.path)
        }

        var request = URLRequest(url: url)
        request.addValue(basicAuthorization, forHTTPHeaderField: "Authorization")
        return request
    }

    private static var basicAuthorization: String {
        let credentials = "\(Secrets.username):\(Secrets.password)"
        let encodedCredentials = Data(credentials.utf8).base64EncodedString()
        return "Basic \(encodedCredentials)"
    }

    private static func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.requestError("no request")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.requestError("status code: \(httpResponse.statusCode)\n\(String(data: data, encoding: .utf8) ?? "")")
        }
    }
}

private struct EmptyRequest: Encodable {}

private struct EmptyResponse: Decodable {}

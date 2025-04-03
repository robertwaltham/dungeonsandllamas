//
//  APIClient.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2024-03-26.
//

import Foundation

actor LargeLangageModelClient {
    
    private enum Endpoint: String {
        case test = ""
        case generate = "/api/generate"
        case models = "/api/tags"
        case modelDetail = "/api/show"
    }
    
    private enum APIMethod: String {
        case get = "GET"
        case post = "POST"
    }
    
    struct Result: Codable {
        var model: String
        var createdAt: String // not actually an iso8601 date
        var response: String
        var done: Bool
    }
    
    struct ModelDetails: Codable, Hashable {
        var format: String
        var family: String
        var families: [String]? // not sure if this is an array or not
        var parameterSize: String
        var quantizationLevel: String
    }
    
    struct Model: Codable, Identifiable, Hashable {
        
        var id: String {
            digest
        }
        var name: String
        var modifiedAt: String // date but ehhh
        var size: Int
        var digest: String // hash
        var details: ModelDetails
    }
    
    struct ModelResponse: Codable {
        var models: [Model]
    }
    
    struct ModelInfo: Codable {
        var license: String
        var modelfile: String
        var parameters: String
        var template: String
        var details: ModelDetails
    }
    
    //MARK: - Private Vars
    
    private let session: URLSession
    
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
    
    //MARK: - Init
    
    init () {
        session = URLSession(configuration: URLSessionConfiguration.default, delegate: nil, delegateQueue: nil)
    }
    
    private static func request(endpoint: Endpoint, method: APIMethod, timeout: TimeInterval = 120.0) throws -> URLRequest {
        guard let url = URL(string: "\(Secrets.host)\(endpoint.rawValue)") else {
            throw APIError.badURL(endpoint.rawValue)
        }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method.rawValue
        request.addValue(Secrets.authorization, forHTTPHeaderField: "Authorization")
        
        return request
    }
    
    //MARK: - Test
    
    func testConnection() async throws -> Bool {
        let request = try LargeLangageModelClient.request(endpoint: .test, method: .get, timeout: 2.0)
        
        let (_, response) = try await session.data(for: request, delegate: DelegateToSupressWarning())
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.requestError("no request")
        }
        guard httpResponse.statusCode == 200 else {
            throw APIError.requestError("status code: \(httpResponse.statusCode)")
        }
        
        return httpResponse.statusCode == 200
    }
    
    //MARK: - Requests
    
    func getLocalModels() async throws -> [Model] {
        
        let request = try LargeLangageModelClient.request(endpoint: .models, method: .get)
        
        let (data, response) = try await session.data(for: request, delegate: DelegateToSupressWarning())
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.requestError("no request")
        }
        guard httpResponse.statusCode == 200 else {
            throw APIError.requestError("status code: \(httpResponse.statusCode)")
        }
        
        return try decoder.decode(ModelResponse.self, from: data).models
    }
    
    func getDetail(model: Model) async throws -> ModelInfo {
        var request = try LargeLangageModelClient.request(endpoint: .modelDetail, method: .post)
        
        request.httpBody = try encoder.encode(["name": model.name])
        
        let (data, response) = try await self.session.data(for: request, delegate: DelegateToSupressWarning())
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.requestError("no request")
        }
        guard httpResponse.statusCode == 200 else {
            throw APIError.requestError("status code: \(httpResponse.statusCode)")
        }
        
        return try decoder.decode(ModelInfo.self, from: data)
    }
    
    func asyncStreamGenerate(prompt: String, model: Model) -> AsyncThrowingStream<Result, Error> {
        
        struct Payload: Encodable {
            let model: String
            let prompt: String
            let stream: Bool
        }
        
        return AsyncThrowingStream<Result, Error> { continuation in
            Task.detached {
                var request = try LargeLangageModelClient.request(endpoint: .generate, method: .post)
                
                request.httpBody = try await self.encoder.encode(Payload(model: model.name, prompt: prompt, stream: true))
                
                do {
                    let (bytes, response) = try await self.session.bytes(for: request, delegate: DelegateToSupressWarning())
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw APIError.requestError("no request")
                    }
                    guard httpResponse.statusCode == 200 else {
                        //                        print(String(bytes: bytes, encoding: .utf8))
                        for try await line in bytes.lines {
                            print(line)
                        }
                        
                        throw APIError.requestError("status code: \(httpResponse.statusCode)")
                    }
                    for try await line in bytes.lines {
                        do {
                            let obj = try await self.decoder.decode(Result.self, from: line.data(using: .utf8)!)
                            print(obj.response)
                            continuation.yield(obj)
                        } catch {
                            print(error)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    func asyncStreamGenerate(prompt: String, base64Image: String, model: Model) -> AsyncThrowingStream<Result, Error> {
        struct Payload: Encodable {
            let model: String
            let prompt: String
            let stream: Bool
            let images: [String]
        }
        return AsyncThrowingStream<Result, Error> { continuation in
            Task.init {
                var request = try LargeLangageModelClient.request(endpoint: .generate, method: .post)
                
                request.httpBody = try encoder.encode(Payload(model: model.name, prompt: prompt, stream: true, images: [base64Image]))
                
                do {
                    let (bytes, response) = try await session.bytes(for: request, delegate: DelegateToSupressWarning())
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw APIError.requestError("no request")
                    }
                    guard httpResponse.statusCode == 200 else {
                        for try await line in bytes.lines {
                            print(line)
                        }
                        throw APIError.requestError("status code: \(httpResponse.statusCode)")
                    }
                    for try await line in bytes.lines {
                        do {
                            let obj = try decoder.decode(Result.self, from: line.data(using: .utf8)!)
                            print(obj.response)
                            continuation.yield(obj)
                        } catch {
                            print(error)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}


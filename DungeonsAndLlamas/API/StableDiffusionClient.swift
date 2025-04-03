//
//  StableDiffusionClient.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2024-04-29.
//

import Foundation

actor StableDiffusionClient {
    
    private enum Endpoint: String {
        case test = "/sd/sdapi/v1/memory"
        case generateSDtxt2img = "/sd/sdapi/v1/txt2img"
        case generateSDimg2img = "/sd/sdapi/v1/img2img"
        case progress = "/sd/sdapi/v1/progress"
        case options = "/sd/sdapi/v1/options"
        case sdModels = "/sd/sdapi/v1/sd-models"
        case loras = "/sd/sdapi/v1/loras"
        case samplers = "/sd/sdapi/v1/samplers"
        case interrogate = "/sd/sdapi/v1/interrogate"
    }
    
    private enum Method: String {
        case get = "GET"
        case post = "POST"
    }
    
    struct GenerationOptions: Codable {
        var prompt: String
        var negativePrompt: String
        var width: Int
        var height: Int
        var steps: Int
        var batchSize: Int
        var seed: Int?
        var samplerName: String
        var initImages: [String]?
        
        init(prompt: String, negativePrompt: String = "", size: Int = 512, steps: Int = 20, batchSize: Int = 1, sampler: Sampler = StableDiffusionClient.defaultSampler, initImages: [String]? = nil) {
            self.prompt = prompt
            self.negativePrompt = negativePrompt
            self.width = size
            self.height = size
            self.steps = steps
            self.batchSize = batchSize
            self.samplerName = sampler.name
            self.initImages = initImages
        }
    }

    struct ModelOptions: Codable {
        var sdModelCheckpoint: String
        var sdCheckpointHash: String
    }

    struct Progress: Codable {
        var progress: Double
        var etaRelative: Double
        var state: State
        var currentImage: String?
        
        struct State: Codable {
            var interrupted: Bool
            var job: String
            var jobCount: Int
            var jobNo: Int
            var jobTimestamp: String
            var samplingStep: Int
            var samplingSteps: Int
            var skipped: Bool
            var stoppingGeneration: Bool
            
            static func initial() -> Progress.State {
                return State(interrupted: false, job: "", jobCount: 0, jobNo: 0, jobTimestamp: "", samplingStep: 0, samplingSteps: 0, skipped: false, stoppingGeneration: false)
            }
        }
    }

    struct Model: Codable, Identifiable, Hashable {
        var id: String {
            sha256 ?? modelName
        }
        
        var title: String
        var modelName: String
        var hash: String?
        var sha256: String?
        var filename: String
    }

    struct Lora: Codable, Identifiable, Hashable {
        var id: String {
            name
        }
        
        var name: String
        var alias: String
    }

    struct Sampler: Codable, Identifiable, Hashable {
        var id: String {
            name
        }
        var name: String
        var aliases: [String]
        var options: [String: String]
    }
    
    static let defaultSampler = Sampler(name: "DPM++ 2M", aliases: ["k_dpmpp_2m"], options: ["scheduler":"karras"])
    
    // MARK: - Private Vars
    
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
    
    //MARK: - Requests
    
    private static func request(endpoint: Endpoint, method: Method, timeout: TimeInterval = 120.0) throws -> URLRequest {
        guard let url = URL(string: "\(Secrets.host)\(endpoint.rawValue)") else {
            throw APIError.badURL(endpoint.rawValue)
        }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method.rawValue
        request.addValue(Secrets.authorization, forHTTPHeaderField: "Authorization")
        
        return request
    }
    
    func testConnection() async throws -> Bool {
        let request = try StableDiffusionClient.request(endpoint: .test, method: .get)
        let (_, response) = try await session.data(for: request, delegate: DelegateToSupressWarning())
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.requestError("no request")
        }
        guard httpResponse.statusCode == 200 else {
            throw APIError.requestError("status code: \(httpResponse.statusCode)")
        }
        
        return httpResponse.statusCode == 200
    }
    
    func generateBase64EncodedImages(_ options: GenerationOptions) async throws -> [String] {
        print(options.prompt)
        let endpoint: Endpoint = options.initImages != nil ? .generateSDimg2img : .generateSDtxt2img
        var request = try StableDiffusionClient.request(endpoint: endpoint, method: .post, timeout: 600)
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(options)
                
        let (data, response) = try await session.data(for: request, delegate: DelegateToSupressWarning())
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.requestError("no request")
        }
        guard httpResponse.statusCode == 200 else {
            throw APIError.requestError("status code: \(httpResponse.statusCode)\n\(String(data: data, encoding: .utf8) ?? "")")
        }
        
        let responseObject = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let images = responseObject?["images"] as? [String] else {
            throw APIError.requestError("no images")
        }
        
        return images
    }
    
    func imageGenerationProgress() async throws -> Progress {
        var request = try StableDiffusionClient.request(endpoint: .progress, method: .get)
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await session.data(for: request, delegate: DelegateToSupressWarning())
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.requestError("no request")
        }
        guard httpResponse.statusCode == 200 else {
            throw APIError.requestError("status code: \(httpResponse.statusCode)\n\(String(data: data, encoding: .utf8) ?? "")")
        }
        
        return try decoder.decode(Progress.self, from: data)
    }
    
    func imageGenerationOptions() async throws -> ModelOptions {
        var request = try StableDiffusionClient.request(endpoint: .options, method: .get)
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await session.data(for: request, delegate: DelegateToSupressWarning())
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.requestError("no request")
        }
        guard httpResponse.statusCode == 200 else {
            throw APIError.requestError("status code: \(httpResponse.statusCode)\n\(String(data: data, encoding: .utf8) ?? "")")
        }
        return try decoder.decode(ModelOptions.self, from: data)
    }
    
    func imageGenerationModels() async throws -> [Model] {
        var request = try StableDiffusionClient.request(endpoint: .sdModels, method: .get)
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await session.data(for: request, delegate: DelegateToSupressWarning())
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.requestError("no request")
        }
        guard httpResponse.statusCode == 200 else {
            throw APIError.requestError("status code: \(httpResponse.statusCode)\n\(String(data: data, encoding: .utf8) ?? "")")
        }
        return try decoder.decode([Model].self, from: data)
    }
    
    func setImageGenerationModel(model: Model) async throws {
        var request = try StableDiffusionClient.request(endpoint: .options, method: .post)
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        request.httpBody = try encoder.encode([
            "sd_model_checkpoint": model.title
        ])
        
        let (data, response) = try await session.data(for: request, delegate: DelegateToSupressWarning())
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.requestError("no request")
        }
        guard httpResponse.statusCode == 200 else {
            throw APIError.requestError("status code: \(httpResponse.statusCode)\n\(String(data: data, encoding: .utf8) ?? "")")
        }
    }
    
    func loras() async throws -> [Lora] {
        var request = try StableDiffusionClient.request(endpoint: .loras, method: .get)
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await session.data(for: request, delegate: DelegateToSupressWarning())
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.requestError("no request")
        }
        guard httpResponse.statusCode == 200 else {
            throw APIError.requestError("status code: \(httpResponse.statusCode)\n\(String(data: data, encoding: .utf8) ?? "")")
        }
        return try decoder.decode([Lora].self, from: data)
    }
    
    func samplers() async throws -> [Sampler] {
        var request = try StableDiffusionClient.request(endpoint: .samplers, method: .get)
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await session.data(for: request, delegate: DelegateToSupressWarning())
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.requestError("no request")
        }
        guard httpResponse.statusCode == 200 else {
            throw APIError.requestError("status code: \(httpResponse.statusCode)\n\(String(data: data, encoding: .utf8) ?? "")")
        }
        return try decoder.decode([Sampler].self, from: data)
    }
    
    func interrogate(base64EncodedImage: String) async throws -> String {
        
        var request = try StableDiffusionClient.request(endpoint: .interrogate, method: .post, timeout: 300)
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode([
            "image": base64EncodedImage,
            "model": "clip"
        ])
                
        let (data, response) = try await session.data(for: request, delegate: DelegateToSupressWarning())
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.requestError("no request")
        }
        guard httpResponse.statusCode == 200 else {
            throw APIError.requestError("status code: \(httpResponse.statusCode)\n\(String(data: data, encoding: .utf8) ?? "")")
        }
        
        return try decoder.decode([String: String].self, from: data)["caption"] ?? "n/a"
    }
    
}

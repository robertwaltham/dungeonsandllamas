//
//  APIClient.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2024-03-26.
//

import Foundation

actor APIClient {
    
    enum APIError: Error {
        case requestError(String)
    }
    
    enum APIEndpoint: String {
        
        // OLLama LLM
        case test = ""
        case generate = "/api/generate"
        case models = "/api/tags"
        case modelDetail = "/api/show"
        
        // Stable Diffusion
        case testSD = "/sd/sdapi/v1/memory"
        case generateSDtxt2img = "/sd/sdapi/v1/txt2img"
        case generateSDimg2img = "/sd/sdapi/v1/img2img"
        case progress = "/sd/sdapi/v1/progress"
        case options = "/sd/sdapi/v1/options"
        case sdModels = "/sd/sdapi/v1/sd-models"
        case loras = "/sd/sdapi/v1/loras"
        case samplers = "/sd/sdapi/v1/samplers"
    }
    
    enum APIMethod: String {
        case get = "GET"
        case post = "POST"
    }
    
    enum Service {
        case stableDiffusion
        case largeLanguageModel
    }
    
    let session: URLSession
    var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }
    
    static let defaultSampler = StableDiffusionSampler(name: "DPM++ 2M Karras", aliases: ["k_dpmpp_2m_ka"], options: [:])
    
    //MARK: - Init
    
    init () {
        session = URLSession(configuration: URLSessionConfiguration.default, delegate: nil, delegateQueue: nil)
    }
    
    //MARK: - Test
    
    func testConnection(service: Service) async throws -> Bool {
        let request = switch service {
        case .stableDiffusion:
            APIClient.request(endpoint: .testSD, method: .get, timeout: 2.0)
        case .largeLanguageModel:
            APIClient.request(endpoint: .test, method: .get, timeout: 2.0)
        }
        
        let (_, response) = try await session.data(for: request, delegate: DelegateToSupressWarning())
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.requestError("no request")
        }
        guard httpResponse.statusCode == 200 else {
            throw APIError.requestError("status code: \(httpResponse.statusCode)")
        }
        
        return httpResponse.statusCode == 200
    }
    
    //MARK: - LLM
    
    func getLocalModels() async throws -> [LLMModel] {
        
        let request = APIClient.request(endpoint: .models, method: .get)
        
        let (data, response) = try await session.data(for: request, delegate: DelegateToSupressWarning())
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.requestError("no request")
        }
        guard httpResponse.statusCode == 200 else {
            throw APIError.requestError("status code: \(httpResponse.statusCode)")
        }
        
        return try decoder.decode(LLMModelResponse.self, from: data).models
    }
    
    func getDetail(model: LLMModel) async throws -> LLMModelInformation {
        var request = APIClient.request(endpoint: .modelDetail, method: .post)
        
        request.httpBody = """
            {
              "name": "\(model.name)"
            }
            """.data(using: .utf8)
        
        let (data, response) = try await self.session.data(for: request, delegate: DelegateToSupressWarning())
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.requestError("no request")
        }
        guard httpResponse.statusCode == 200 else {
            throw APIError.requestError("status code: \(httpResponse.statusCode)")
        }
        
        return try decoder.decode(LLMModelInformation.self, from: data)
    }
 
    func asyncStreamGenerate(prompt: String) -> AsyncThrowingStream<OllamaResult, Error> {
        return AsyncThrowingStream<OllamaResult, Error> { continuation in
            Task.detached {
                var request = APIClient.request(endpoint: .generate, method: .post)
                request.httpBody = """
                {
                    "model": "llama2",
                    "prompt": "\(prompt)",
                    "stream": true
                }
                """.data(using: .utf8)
                
                do {
                    let (bytes, response) = try await self.session.bytes(for: request, delegate: DelegateToSupressWarning())
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw APIError.requestError("no request")
                    }
                    guard httpResponse.statusCode == 200 else {
                        throw APIError.requestError("status code: \(httpResponse.statusCode)")
                    }
                    for try await line in bytes.lines {
                        do {
                            let obj = try await self.decoder.decode(OllamaResult.self, from: line.data(using: .utf8)!)
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
    
    func asyncStreamGenerate(prompt: String, base64Image: String) -> AsyncThrowingStream<OllamaResult, Error> {
        return AsyncThrowingStream<OllamaResult, Error> { continuation in
            Task.init {
                var request = APIClient.request(endpoint: .generate, method: .post)
                request.httpBody = """
                {
                    "model": "llava",
                    "prompt": "\(prompt)",
                    "stream": true,
                    "images": ["\(base64Image)"]
                }
                """.data(using: .utf8)
                
                do {
                    let (bytes, response) = try await session.bytes(for: request, delegate: DelegateToSupressWarning())
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw APIError.requestError("no request")
                    }
                    guard httpResponse.statusCode == 200 else {
                        throw APIError.requestError("status code: \(httpResponse.statusCode)")
                    }
                    for try await line in bytes.lines {
                        do {
                            let obj = try decoder.decode(OllamaResult.self, from: line.data(using: .utf8)!)
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
    
    //MARK: - Stable Diffusion
    
    func generateBase64EncodedImages(_ options: StableDiffusionGenerationOptions) async throws -> [String] {
        
        var request = APIClient.request(endpoint: .generateSDtxt2img, method: .post, timeout: 300)
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = stableRequestBody(options).data(using: .utf8)
                
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
    
    func generateBase64EncodedImages(_ options: StableDiffusionGenerationOptions, base64EncodedSourceImages: [String]) async throws -> [String] {
        
        var request = APIClient.request(endpoint: .generateSDimg2img, method: .post, timeout: 300)
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = stableRequestBody(options, base64EncodedSourceImages: base64EncodedSourceImages).data(using: .utf8)

        let (data, response) = try await session.data(for: request, delegate: DelegateToSupressWarning())
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.requestError("no request")
        }
        guard httpResponse.statusCode == 200 else {
            print(String(data: data, encoding: .utf8) ?? "")
            throw APIError.requestError("status code: \(httpResponse.statusCode)")
        }
        
        let responseObject = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let images = responseObject?["images"] as? [String] else {
            throw APIError.requestError("no images")
        }
        
        return images
    }
    
    func imageGenerationProgress() async throws -> StableDiffusionProgress {
        var request = APIClient.request(endpoint: .progress, method: .get)
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await session.data(for: request, delegate: DelegateToSupressWarning())
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.requestError("no request")
        }
        guard httpResponse.statusCode == 200 else {
            throw APIError.requestError("status code: \(httpResponse.statusCode)\n\(String(data: data, encoding: .utf8) ?? "")")
        }
        
        return try decoder.decode(StableDiffusionProgress.self, from: data)
    }
    
    func imageGenerationOptions() async throws -> StableDiffusionOptions {
        var request = APIClient.request(endpoint: .options, method: .get)
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await session.data(for: request, delegate: DelegateToSupressWarning())
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.requestError("no request")
        }
        guard httpResponse.statusCode == 200 else {
            throw APIError.requestError("status code: \(httpResponse.statusCode)\n\(String(data: data, encoding: .utf8) ?? "")")
        }
        return try decoder.decode(StableDiffusionOptions.self, from: data)
    }
    
    func imageGenerationModels() async throws -> [StableDiffusionModel] {
        var request = APIClient.request(endpoint: .sdModels, method: .get)
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await session.data(for: request, delegate: DelegateToSupressWarning())
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.requestError("no request")
        }
        guard httpResponse.statusCode == 200 else {
            throw APIError.requestError("status code: \(httpResponse.statusCode)\n\(String(data: data, encoding: .utf8) ?? "")")
        }
        return try decoder.decode([StableDiffusionModel].self, from: data)
    }
    
    func setImageGenerationModel(model: StableDiffusionModel) async throws {
        var request = APIClient.request(endpoint: .options, method: .post)
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = """
        {
            "sd_model_checkpoint": "\(model.title)"
        }
        """.data(using: .utf8)
        
        let (data, response) = try await session.data(for: request, delegate: DelegateToSupressWarning())
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.requestError("no request")
        }
        guard httpResponse.statusCode == 200 else {
            throw APIError.requestError("status code: \(httpResponse.statusCode)\n\(String(data: data, encoding: .utf8) ?? "")")
        }
    }
    
    func loras() async throws -> [StableDiffusionLora] {
        var request = APIClient.request(endpoint: .loras, method: .get)
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await session.data(for: request, delegate: DelegateToSupressWarning())
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.requestError("no request")
        }
        guard httpResponse.statusCode == 200 else {
            throw APIError.requestError("status code: \(httpResponse.statusCode)\n\(String(data: data, encoding: .utf8) ?? "")")
        }
        return try decoder.decode([StableDiffusionLora].self, from: data)
    }
    
    func samplers() async throws -> [StableDiffusionSampler] {
        var request = APIClient.request(endpoint: .samplers, method: .get)
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await session.data(for: request, delegate: DelegateToSupressWarning())
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.requestError("no request")
        }
        guard httpResponse.statusCode == 200 else {
            throw APIError.requestError("status code: \(httpResponse.statusCode)\n\(String(data: data, encoding: .utf8) ?? "")")
        }
        return try decoder.decode([StableDiffusionSampler].self, from: data)
    }
    
    //MARK: - Helpers
    
    private static func request(endpoint: APIEndpoint, method: APIMethod, timeout: TimeInterval = 120.0) -> URLRequest {
        guard let url = URL(string: "\(Secrets.host)\(endpoint.rawValue)") else {
            fatalError("can't create url")
        }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method.rawValue
        request.addValue(Secrets.authorization, forHTTPHeaderField: "Authorization")
        
        return request
    }
    
    private func stableRequestBody(_ options: StableDiffusionGenerationOptions) -> String {
        return """
        {
            "init_images": [],
            "resize_mode": 0,
            "denoising_strength": 0.75,
            "image_cfg_scale": 0,
            "mask_blur": 0,
            "mask_blur_x": 0,
            "mask_blur_y": 0,
            "inpainting_fill": 0,
            "inpaint_full_res": true,
            "inpaint_full_res_padding": 0,
            "inpainting_mask_invert": 0,
            "initial_noise_multiplier": 0,
            "prompt": "\(options.prompt)",
            "styles": [],
            "seed": -1,
            "subseed": -1,
            "subseed_strength": 0,
            "seed_resize_from_h": -1,
            "seed_resize_from_w": -1,
            "sampler_name": "",
            "batch_size": \(options.batchSize),
            "n_iter": 1,
            "steps": \(options.steps),
            "cfg_scale": 7,
            "width": \(options.size),
            "height": \(options.size),
            "restore_faces": false,
            "tiling": false,
            "do_not_save_samples": false,
            "do_not_save_grid": false,
            "negative_prompt": "\(options.negativePrompt)",
            "eta": 0,
            "s_min_uncond": 0,
            "s_churn": 0,
            "s_tmax": 0,
            "s_tmin": 0,
            "s_noise": 1,
            "override_settings": {},
            "override_settings_restore_afterwards": true,
            "script_args": [],
            "sampler_index": "DPM2",
            "include_init_images": false,
            "script_name": "",
            "send_images": true,
            "save_images": true,
            "alwayson_scripts": {}
        }
        """
    }
    
    private func stableRequestBody(_ options: StableDiffusionGenerationOptions, base64EncodedSourceImages: [String]) -> String {
//        return """
//        {
//            "init_images": [
//            "\(base64EncodedSourceImages.joined(separator: "\",\""))"
//            ],
//            "resize_mode": 0,
//            "denoising_strength": 0.75,
//            "image_cfg_scale": 0,
//            "mask_blur": 0,
//            "mask_blur_x": 0,
//            "mask_blur_y": 0,
//            "inpainting_fill": 0,
//            "inpaint_full_res": true,
//            "inpaint_full_res_padding": 0,
//            "inpainting_mask_invert": 0,
//            "initial_noise_multiplier": 0,
//            "prompt": "\(options.prompt)",
//            "styles": [],
//            "seed": -1,
//            "subseed": -1,
//            "subseed_strength": 0,
//            "seed_resize_from_h": -1,
//            "seed_resize_from_w": -1,
//            "sampler_name": "",
//            "batch_size": \(options.batchSize),
//            "n_iter": 1,
//            "steps": \(options.steps),
//            "cfg_scale": 7,
//            "width": \(options.size),
//            "height": \(options.size),
//            "restore_faces": false,
//            "tiling": false,
//            "do_not_save_samples": false,
//            "do_not_save_grid": false,
//            "negative_prompt": "\(options.negativePrompt)",
//            "eta": 0,
//            "s_min_uncond": 0,
//            "s_churn": 0,
//            "s_tmax": 0,
//            "s_tmin": 0,
//            "s_noise": 1,
//            "override_settings": {},
//            "override_settings_restore_afterwards": true,
//            "script_args": [],
//            "sampler_index": "DPM2",
//            "include_init_images": false,
//            "script_name": "",
//            "send_images": true,
//            "save_images": true,
//            "alwayson_scripts": {}
//        }
//        """
        
        let seed = options.seed != nil ? options.seed! : -1
        
        return """
        {
          "prompt": "\(options.prompt)",
          "negative_prompt": "\(options.negativePrompt)",
          "batch_size": \(options.batchSize),
          "steps": \(options.steps),
          "width": \(options.size),
          "height": \(options.size),
          "init_images": [
            "\(base64EncodedSourceImages.joined(separator: "\",\""))"
          ],
          "sampler_name": "DPM++ 2M Karras",
          "seed": "\(seed)"
        }
        """
    }
}

//MARK: - Structs

struct OllamaResult: Codable {
    var model: String
    var createdAt: String // not actually an iso8601 date
    var response: String
    var done: Bool
}

struct StableDiffusionGenerationOptions {
    var prompt: String
    var negativePrompt: String
    var size: Int
    var steps: Int
    var batchSize: Int
    var seed: Int?
    var sampler: StableDiffusionSampler
    
    init(prompt: String, negativePrompt: String = "", size: Int = 512, steps: Int = 20, batchSize: Int = 1, sampler: StableDiffusionSampler = APIClient.defaultSampler) {
        self.prompt = prompt
        self.negativePrompt = negativePrompt
        self.size = size
        self.steps = steps
        self.batchSize = batchSize
        self.sampler = sampler
    }
}

struct StableDiffusionOptions: Codable {
    var sdModelCheckpoint: String
    var sdCheckpointHash: String
}

struct StableDiffusionProgress: Codable {
    var progress: Double
    var etaRelative: Double
    var state: StableDiffusionState
    var currentImage: String?
    
    struct StableDiffusionState: Codable {
        var interrupted: Bool
        var job: String
        var jobCount: Int
        var jobNo: Int
        var jobTimestamp: String
        var samplingStep: Int
        var samplingSteps: Int
        var skipped: Bool
        var stoppingGeneration: Bool
        
        static func initial() -> StableDiffusionProgress.StableDiffusionState {
            return StableDiffusionState(interrupted: false, job: "", jobCount: 0, jobNo: 0, jobTimestamp: "", samplingStep: 0, samplingSteps: 0, skipped: false, stoppingGeneration: false)
        }
    }
}

struct StableDiffusionModel: Codable, Identifiable, Hashable {
    var id: String {
        sha256
    }
    
    var title: String
    var modelName: String
    var hash: String
    var sha256: String
    var filename: String
}

struct StableDiffusionLora: Codable, Identifiable, Hashable {
    var id: String {
        name
    }
    
    var name: String
    var alias: String
}

struct StableDiffusionSampler: Codable, Identifiable, Hashable {
    var id: String {
        name
    }
    var name: String
    var aliases: [String]
    var options: [String: String]
}

struct LLMModelDetails: Codable, Hashable {
    var format: String
    var family: String
    var families: [String]? // not sure if this is an array or not
    var parameterSize: String
    var quantizationLevel: String
}

struct LLMModel: Codable, Identifiable, Hashable {

    var id: String {
        digest
    }
    var name: String
    var modifiedAt: String // date but ehhh
    var size: Int
    var digest: String // hash
    var details: LLMModelDetails
}

struct LLMModelResponse: Codable {
    var models: [LLMModel]
}

struct LLMModelInformation: Codable {
    var license: String
    var modelfile: String
    var parameters: String
    var template: String
    var details: LLMModelDetails
}

// (any URLSessionTaskDelegate)? is not sendable??? use this to surpress warning
final class DelegateToSupressWarning: NSObject, URLSessionTaskDelegate, Sendable {}

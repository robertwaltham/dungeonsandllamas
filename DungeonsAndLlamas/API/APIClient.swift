//
//  APIClient.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2024-03-26.
//

import Foundation

class APIClient {
    static let shared = APIClient()
    
    enum APIError: Error {
        case requestError(String)
    }
    
    enum APIEndpoint: String {
        case test = ""
        case testSD = "/sd"
        case generate = "/api/generate"
        case generateSD = "/sd/sdapi/v1/txt2img"
        case promptStyles = "/sd/sdapi/v1/prompt-styles"
    }
    
    enum APIMethod: String {
        case get = "GET"
        case post = "POST"
    }
    
    let delegate: TaskDelegate
    let session: URLSession
    var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        
        d.dateDecodingStrategy = .iso8601
        return d
    }
    
    fileprivate var dataResponse: ((_ result: Result<String, Error>) -> Void)?
    fileprivate var completion: ((_ result: Error?) -> Void)?
    
    init () {
        delegate = TaskDelegate()
        session = URLSession(configuration: URLSessionConfiguration.default, delegate: delegate, delegateQueue: nil)
    }
    
    static func request(endpoint: APIEndpoint, method: APIMethod) -> URLRequest {
        guard let url = URL(string: "\(Secrets.host)\(endpoint.rawValue)") else {
            fatalError("can't create url")
        }
        
        print(url.description)
        
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.addValue(Secrets.authorization, forHTTPHeaderField: "Authorization")
        
        return request
    }
    
    func setHandlers(dataResponse: @escaping (_ result: Result<String, Error>) -> Void, completion: @escaping (_ result: Error?) -> Void) {
        delegate.client = self
        self.dataResponse = dataResponse
        self.completion = completion
    }
    
    func testConnection(completion: @escaping (_ success: Bool) -> Void) {
        let request = APIClient.request(endpoint: .test, method: .get)
        
        let task = session.dataTask(with: request) { data, response, error in
            
            guard let response = response as? HTTPURLResponse else {
                print("No response: \(String(describing: error))")
                completion(false)
                return
            }
            if let data = data {
                print("Data: \(String(data: data, encoding: .utf8) ?? "none")")
            } else {
                print("No data in response: \(String(describing: error))")
            }
            
            completion(response.statusCode == 200)
            
        }
        task.resume()
    }
    
    func testSDConnection(completion: @escaping (_ success: Bool) -> Void) {
        let request = APIClient.request(endpoint: .testSD, method: .get)
        
        let task = session.dataTask(with: request) { data, response, error in
            
            guard let response = response as? HTTPURLResponse else {
                print("No response: \(String(describing: error))")
                completion(false)
                return
            }
            if let data = data {
                print("Data: \(String(data: data, encoding: .utf8) ?? "none")")
            } else {
                print("No data in response: \(String(describing: error))")
            }
            
            completion(response.statusCode == 200)
            
        }
        task.resume()
    }
    
    func generate(prompt: String) {
        var request = APIClient.request(endpoint: .generate, method: .post)
        request.httpBody = """
        {
            "model": "llama2",
            "prompt": "\(prompt)",
            "stream": false
        }
        """.data(using: .utf8)
        
        let task = session.dataTask(with: request)
        task.resume()
    }
    
    func streamGenerate(prompt: String) {
        var request = APIClient.request(endpoint: .generate, method: .post)
        request.httpBody = """
        {
            "model": "llama2",
            "prompt": "\(prompt)",
            "stream": true
        }
        """.data(using: .utf8)
        
        let task = session.dataTask(with: request)
        task.resume()
    }
    
    func streamGenerate(prompt: String, base64Image: String) {
        var request = APIClient.request(endpoint: .generate, method: .post)
        request.httpBody = """
        {
            "model": "llava",
            "prompt": "\(prompt)",
            "stream": true,
            "images": ["\(base64Image)"]
        }
        """.data(using: .utf8)
        
        let task = session.dataTask(with: request)
        task.resume()
    }
    
    
    func asyncStreamGenerate(prompt: String) -> AsyncThrowingStream<OllamaResult, Error> {
        return AsyncThrowingStream<OllamaResult, Error> { continuation in
            Task.init {
                var request = APIClient.request(endpoint: .generate, method: .post)
                request.httpBody = """
                {
                    "model": "llama2",
                    "prompt": "\(prompt)",
                    "stream": true
                }
                """.data(using: .utf8)
                
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                        throw APIError.requestError("api error")
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
                    print("done")
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
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                        throw APIError.requestError("api error")
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
                    print("done")
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    func generateImage(_ options: StableDiffusionOptions) async throws -> [String] {
        
        var request = APIClient.request(endpoint: .generateSD, method: .post)
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = stableRequestBody(options).data(using: .utf8)
                
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.requestError("api error")
        }
        
        let responseObject = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let images = responseObject?["images"] as? [String] else {
            throw APIError.requestError("no images")
        }
        
        return images
        
    }
    
    func imagePromptStyles() {
        
        let request = APIClient.request(endpoint: .promptStyles, method: .get)
//        request.httpBody =  """
//        {
//          "prompt": "\(prompt)",
//          "negative_prompt": "\(negative)",
//          "styles": [
//            "string"
//          ]
//        }
//        """.data(using: .utf8)
        
        let task = session.dataTask(with: request)
        task.resume()
    }
    

    
    private func stableRequestBody(_ options: StableDiffusionOptions) -> String {
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
    
    
    class TaskDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, URLSessionDataDelegate {
        
        weak var client: APIClient?
        
        func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
            if let task = task as? URLSessionDataTask {
                print("\(task.originalRequest?.description ?? "none")")
            }
        }
        
        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            
            guard let string = String(data: data, encoding: .utf8) else {
                client?.dataResponse?(.failure(APIError.requestError("failed to decode")))
                return
            }
            client?.dataResponse?(.success(string))
        }
        
        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if let response = task.response as? HTTPURLResponse {
                print(response.statusCode)
                
                if response.statusCode == 200 {
                    client?.completion?(nil)
                } else {
                    client?.completion?(APIError.requestError("got status code: \(response.statusCode.description)"))
                }
                
            } else {
                client?.completion?(error)
            }
        }
    }
}


struct OllamaResult: Codable {
    var model: String
    var createdAt: String // not actually an iso8601 date
    var response: String
    var done: Bool
}

struct StableDiffusionOptions {
    let prompt: String
    let negativePrompt: String
    let size: Int
    let steps: Int
    let batchSize: Int
    
    init(prompt: String, negativePrompt: String = "", size: Int = 512, steps: Int = 20, batchSize: Int = 1) {
        self.prompt = prompt
        self.negativePrompt = negativePrompt
        self.size = size
        self.steps = steps
        self.batchSize = batchSize
    }
}

//
//  StableDiffusionClient.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2024-04-29.
//

import Foundation
import UIKit

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
        case scriptInfo = "/sd/sdapi/v1/script-info"
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
        var mask: String?
        var alwaysonScripts: [String: [String: [SoftInpaintingOptions]]]? = nil
        
        init(prompt: String,
             negativePrompt: String = "",
             size: Int = 512,
             steps: Int = 20,
             batchSize: Int = 1,
             sampler: Sampler = StableDiffusionClient.defaultSampler,
             initImages: [String]? = nil,
             mask: String? = nil,
             inPaintingOptions: SoftInpaintingOptions? = nil) {
            
            self.prompt = prompt
            self.negativePrompt = negativePrompt
            self.width = size
            self.height = size
            self.steps = steps
            self.batchSize = batchSize
            self.samplerName = sampler.name
            self.initImages = initImages
            self.mask = mask
            
            if let inPaintingOptions {
                self.alwaysonScripts = [
                    "soft inpainting": [
                        "args": [
                            inPaintingOptions
                        ]
                    ]
                ]
            }
        }
    }
    
    /*
     {
         "Soft inpainting": True,
         "Schedule bias": 1,
         "Preservation strength": 0.5,
         "Transition contrast boost": 4,
         "Mask influence": 0,
         "Difference threshold": 0.5,
         "Difference contrast": 2,
     },
     */
    struct SoftInpaintingOptions: Codable {
        var softInpainting = true
        var scheduleBias = 1.0 // 1-8 step 0.1
        var preservationStrength = 0.5 // 1-8 step 0.05
        var transitionContrastBoost = 4.0 // 1-32 step 0.5
        var maskInfluence = 0.0 // 0-1 step 0.05
        var differenceThreshold = 0.5 // 0-8 step 0.25
        var differenceContrast = 2.0 // 0-8 step 0.25
        
        private enum CodingKeys : String, CodingKey {
            case softInpainting = "Soft inpainting"
            case scheduleBias = "Schedule bias"
            case preservationStrength = "Preservation strength"
            case transitionContrastBoost = "Transition contrast boost"
            case maskInfluence = "Mask influence"
            case differenceThreshold = "Difference threshold"
            case differenceContrast = "Difference contrast"
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
        
        struct Metadata: Codable, Hashable {
            var ssSdModelName: String?
            var ssBaseModelVersion: String?
            var ssResolution: String?
            var ssOutputName: String?
            var ssTagFrequency: [String: [String: Int]]?
            var modelSpecTitle: String?
            var modelSpecArchitecture: String?
            
            private enum CodingKeys : String, CodingKey {
                case ssSdModelName
                case ssBaseModelVersion
                case ssResolution
                case ssOutputName
                case modelSpecTitle = "modelspec.title"
                case modelSpecArchitecture = "modelspec.architecture"
                case ssTagFrequency
            }
        }
        
        var metadata: Metadata
        
        var activation: String? {
            switch name {
                
//                add-detail-xl
//                add_detail
//            case "aidma-Image Upgrader-SD1.5-V0.1":
//                return ""
//                Digital_Impressionist_SD1.5
//                epi_noiseoffset2
//                Ghibli_v6
//                Hyper-SD15-2steps-lora
//                Hyper-SD15-8steps-lora
            case "Ink scenery":
                return "ink"
//                more_details
//                pixel-art-xl-v1.1
            case "ral-frctlgmtry-sd15":
                return "ral-frctlgmtry"
            case "to8contrast-1-5":
                return "to8contrast style"
            case "watercolor":
                return "watercolor"
            case "WatercolorSD1V2":
                return "watercolor"
//                xl_more_art-full_v1
                
            case "lora": // for testing
                return "actiation"
                
            default:
                    return nil
            }
            
        }
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
    
    private var customEncoder: JSONEncoder {
        
        struct AnyKey: CodingKey {
            var stringValue: String
            var intValue: Int?
            
            init?(stringValue: String) {
                self.stringValue = AnyKey.camelCaseToSnakeCase(stringValue)
                self.intValue = nil
            }
            
            init?(intValue: Int) {
                self.stringValue = String(intValue)
                self.intValue = intValue
            }
            
            //https://www.codespeedy.com/convert-camel-case-to-snake-case-in-swift/
            // default camel->snake lowercases the whole string, and the API needs first char uppercase
            // see: https://github.com/AUTOMATIC1111/stable-diffusion-webui/discussions/15138
            static func camelCaseToSnakeCase(_ input: String) -> String {
                let pattern = "([a-z0-9])([A-Z])"
                let regex = try! NSRegularExpression(pattern: pattern, options: [])
                let range = NSRange(location: 0, length: input.utf16.count)
                let result = regex.stringByReplacingMatches(in: input, options: [], range: range, withTemplate: "$1_$2")
                return String(result.prefix(1)) + String(result.suffix(result.count - 1)).lowercased()
            }
        }
        
        let e = JSONEncoder()
        e.keyEncodingStrategy = .custom { codingPath in
            if codingPath.last?.intValue != nil {
                return codingPath.last!
            } else {
                return AnyKey(stringValue: codingPath.last!.stringValue)!
            }
        }
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
    
    func scriptInfo() async throws {
        let request = try StableDiffusionClient.request(endpoint: .scriptInfo, method: .get)
        let (data, response) = try await session.data(for: request, delegate: DelegateToSupressWarning())
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.requestError("no request")
        }
        guard httpResponse.statusCode == 200 else {
            throw APIError.requestError("status code: \(httpResponse.statusCode)")
        }
        
        print(String(data: data, encoding: .utf8) ?? "no data")
    }
    
    func generateBase64EncodedImages(_ options: GenerationOptions) async throws -> [String] {
        let endpoint: Endpoint = options.initImages != nil ? .generateSDimg2img : .generateSDtxt2img
        var request = try StableDiffusionClient.request(endpoint: endpoint, method: .post, timeout: 600)
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try customEncoder.encode(options)
        
//        var printableOptions = options
//        printableOptions.initImages = ["images"]
//        printableOptions.mask = "mask"
//        print(String(data: try customEncoder.encode(printableOptions), encoding: .utf8) ?? "")
                
        let (data, response) = try await session.data(for: request, delegate: DelegateToSupressWarning())
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.requestError("no request")
        }
        guard httpResponse.statusCode == 200 else {
            throw APIError.requestError("status code: \(httpResponse.statusCode)\n\(String(data: data, encoding: .utf8) ?? "")")
        }
        
        let responseObject = try JSONSerialization.jsonObject(with: data) as? [String: Any]
//        var printableResponse = responseObject!
//        printableResponse["images"] = ["image"]
//        print(printableResponse)
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
    
    func upload(image: UIImage, filename: String) async throws -> String? {
        var multipart = MultipartRequest()
        
        guard let imageData = image.pngData() else {
            return nil
        }
        
        multipart.add(
            key: "file",
            fileName: filename,
            fileMimeType: "image/png",
            fileData: imageData
        )
        
        guard let url = URL(string: "http://192.168.1.71:8000/uploadfile") else {
            return nil
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(multipart.httpContentTypeHeadeValue, forHTTPHeaderField: "Content-Type")
        request.httpBody = multipart.httpBody
        
        do {
          let (responseData, response) = try await  URLSession.shared.data(for: request)
          print((response as! HTTPURLResponse).statusCode)
          return String(data: responseData, encoding: .utf8)!
        } catch {
          print ("Error")
            return nil
        }
    }
}

// from https://raagpc.hashnode.dev/how-to-upload-files-with-a-multipart-request-in-swift
public struct MultipartRequest {

    public let boundary: String

    private let separator: String = "\r\n"
    private var data: NSMutableData

    public init(boundary: String = UUID().uuidString) {
        self.boundary = boundary
        self.data = .init()
    }

    private mutating func appendBoundarySeparator() {
        data.appendString("--\(boundary)\(separator)")
    }

    private mutating func appendSeparator() {
        data.appendString(separator)
    }

    private func disposition(_ key: String) -> String {
        "Content-Disposition: form-data; name=\"\(key)\""
    }

    public mutating func add(
        key: String,
        value: String
    ) {
        appendBoundarySeparator()
        data.appendString(disposition(key) + separator)
        appendSeparator()
        data.appendString(value + separator)
    }

    public mutating func add(
        key: String,
        fileName: String,
        fileMimeType: String,
        fileData: Data
    ) {
        appendBoundarySeparator()
        data.appendString(disposition(key) + "; filename=\"\(fileName)\"" + separator)
        data.appendString("Content-Type: \(fileMimeType)" + separator + separator)
        data.append(fileData)
        appendSeparator()
    }

    public var httpContentTypeHeadeValue: String {
        "multipart/form-data; boundary=\(boundary)"
    }

    public var httpBody: Data {
        data.appendString("--\(boundary)--")
        return data as Data
    }
}

extension NSMutableData {
    func appendString(_ string: String) {
        if let data = string.data(using: .utf8) {
            self.append(data)
        }
    }
}

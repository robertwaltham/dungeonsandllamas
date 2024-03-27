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
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
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

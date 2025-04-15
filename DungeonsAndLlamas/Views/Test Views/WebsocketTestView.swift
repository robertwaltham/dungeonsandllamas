//
//  WebsocketTestView.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2025-04-14.
//

import SwiftUI
import Observation

struct WebsocketTestView: View {
    var viewModel = WebsocketTestViewModel()
    
    var body: some View {
        VStack {
            HStack {
                Button {
                    viewModel.connect()
                } label: {
                    Text("Connect")
                }
                
                Button {
                    viewModel.send()
                } label: {
                    Text("Load")
                }

            }
            .padding()
            if let message = viewModel.message {
                Text(message)
            }
            if let error = viewModel.error {
                Text(error)
                    .foregroundColor(.red)
            }
        }

    }
}

@Observable
@MainActor
class WebsocketTestViewModel {
    var socket: URLSessionWebSocketTask?
    var error: String?
    var message: String?
    
    func connect() {
        print("connecting")
        error = nil
        guard let url = URL(string: "ws://192.168.1.71:8000/ws") else {
            error = "no url"
            return
        }
        socket = URLSession.shared.webSocketTask(with: url)
        
        guard let socket else {
            error = "no socket"
            return
        }
        
        message = "connected"
        
        socket.resume()
        
        Task.init {
            do {
                while self.error == nil {
                    let message = try await self.socket?.receive()
                    switch message {
                        
                    case .none:
                        self.error = "no message"
                    case .some(let content):
                        switch content {
                            
                        case .data(_):
                            self.message = "data"
                        case .string(let string):
                            self.message = string
                        @unknown default:
                            fatalError()
                        }
                    }
                }

            } catch {
                self.error = error.localizedDescription
                print(error)
            }
        }
    }
    
    func send() {
        guard let socket else {
            print("no socket")
            error = "no socket"
            return
        }
        
        print("sent")
        
        Task.init {
            try await socket.send(.string("a cat in a fancy hat \(Float.random(in: 0..<1))"))
        }
        
    }
}


#Preview {
    WebsocketTestView()
}

## Dungeons and Llamas
##### A Generative Journey

This is a project to explore the capabilties of modern LLM and Stable Diffusion AI as part of an iOS app using a "Bring your own cloud" approach. 

<img width="400" alt="IMG_0206" src="https://github.com/user-attachments/assets/5f2d0d60-3a3a-4257-a08f-33380e649072" />
<img width="300" alt="IMG_4454" src="https://github.com/user-attachments/assets/65e8ba40-2bc3-4960-8d5e-6c9856de3677" />

### App Architecture

The app is designed to leverage modern App development patterns including
- SwiftUI + Observation
- Swift Concurrency
- Coordinator pattern for navigation

### Service Architecture

Goals
- Run LLM/Stable Diffusion models on my desktop PC as a service
- Enable apps running on remote devices to access those services
- Do so in a way that is secure 
- Optimize for cost

Features
- SSH tunnel to provide a secure connection from a home PC to a remote server, in a way that penetrates the local NAT
- Authorization to the remote server via HTTP Basic authorization + HTTPS encryption 

<img width="783" alt="Screenshot 2024-04-06 at 8 44 44 PM" src="https://github.com/robertwaltham/dungeonsandllamas/assets/438673/aec1c92f-8634-4b66-af39-2bbeb88c4048">

### Building

Define /API/Secrets.swift

```
class Secrets {
    static let host = "https://website.tld"
    static let authorization = "Bearer [token]"
    static let username = "username"
    static let password = "password"
}
```

Download models from huggingface to the Models folder
- https://huggingface.co/apple/coreml-depth-anything-small#download
- https://huggingface.co/apple/MobileCLIP2-S2
- https://huggingface.co/apple/coreml-FastViT-T8
- https://huggingface.co/apple/coreml-FastViT-MA36

Convert MobileCLIP2-S2 to an .aipackage using [CoreAI](https://developer.apple.com/documentation/coreai)

### Running

Set up ComfyUI
- This uses the default [Flux2-Klein](https://docs.comfy.org/tutorials/flux/flux-2-klein) workflow

Set up Routing using a cloud instance + nginx as a proxy
- https://website.tld/ -> ComfyUI 

A sample nginx config for a server can be found at [here](sample.conf)

Setting up SSH tunnel on the host machine running the AI models
- `ssh -R N:localhost:K yourdomain`
- N = remote port
- K = port of your service


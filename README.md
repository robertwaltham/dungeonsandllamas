## Dungeons and Llamas
##### A Generative Journey

This is a project to explore the capabilties of modern LLM and Stable Diffusion AI as part of an iOS app using a "Bring your own cloud" approach. 

The goal of the app is to build a Dungeon Master's companion that enables the generation of artwork and descriptions for characters, items, maps, etc by leveraging AI tools. 

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

<img width="783" alt="Screenshot 2024-04-06 at 8 44 44 PM" src="https://github.com/robertwaltham/dungeonsandllamas/assets/438673/aec1c92f-8634-4b66-af39-2bbeb88c4048">

### Building

Define /API/Secrets.swift

```
class Secrets {
    static let host = "https://website.tld"
    static let authorization = "Bearer [token]"
}
```

### Running

This requires two services running on the target machine (or however your service is set up) on the following paths

- https://website.tld/ -> [Ollama](https://ollama.com/) 
- https://website.tld/sd/ -> [stable-diffusion-webui](https://github.com/AUTOMATIC1111/stable-diffusion-webui)

A sample nginx config for a server can be found at [here](sample.conf)

Setting up SSH tunnel on the host machine running the AI models
- `ssh -R N:localhost:K yourdomain`
- N = remote port
- K = port of your service


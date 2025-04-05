//
//  LoraView.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2025-04-04.
//

import SwiftUI

struct LoraView: View {
    let lora: StableDiffusionClient.Lora
    
    var body: some View {
        VStack {
            Text(lora.name)
                .font(.title)
            HStack(spacing: 20) {
                Text("alias")
                Text(lora.alias)
            }
            Spacer()
                .frame(maxHeight: 30)
            
            Text("Metadata")
                .font(.title)
            
            if let modelName = lora.metadata.ssSdModelName {
                HStack(spacing: 20) {
                    Text("ssSdModelName")
                    Text(modelName)
                }
            }
            
            if let ssBaseModelVersion = lora.metadata.ssBaseModelVersion {
                HStack(spacing: 20) {
                    Text("ssBaseModelVersion")
                    Text(ssBaseModelVersion)
                }
            }
            
            if let ssResolution = lora.metadata.ssResolution {
                HStack(spacing: 20) {
                    Text("ssResolution")
                    Text(ssResolution)
                }
            }
            
            if let ssOutputName = lora.metadata.ssOutputName {
                HStack(spacing: 20) {
                    Text("ssOutputName")
                    Text(ssOutputName)
                }
            }
            
            if let modelSpecTitle = lora.metadata.modelSpecTitle {
                HStack(spacing: 20) {
                    Text("modelSpecTitle")
                    Text(modelSpecTitle)
                }
            }
            
            if let modelSpecArchitecture = lora.metadata.modelSpecArchitecture {
                HStack(spacing: 20) {
                    Text("modelSpecArchitecture")
                    Text(modelSpecArchitecture)
                }
            }
            
            if let actiation = lora.activation {
                Spacer()
                    .frame(maxHeight: 30)
                Text("Activation")
                    .font(.title)
                Text(actiation)
                

            }
            
            if let tags = lora.metadata.ssTagFrequency {
                Spacer()
                    .frame(maxHeight: 30)
                Text("Tags")
                    .font(.title)
                ScrollView {
                    
                    
                    let tagArray: [String] = Array(tags.keys)
                    ForEach(tagArray, id:\.self) { category in
                        
                        VStack {
                            Text(category)
                                .font(.title2)
                            if let keys = tags[category]?.keys {
                                let array: [String] = Array(keys)
                                ForEach(array, id:\.self) { key in
                                    HStack {
                                        Text(key)
                                        if let value = tags[category]?[key] {
                                            Text("\(value)")
                                        }
                                    }
                                }

                            }
                        }
             
                    }
                }.frame(maxHeight: 500)
  
            }

        }
    }
}

#Preview {
//    var ssSdModelName: String?
//    var ssBaseModelVersion: String?
//    var ssResolution: String?
//    var ssOutputName: String?
//    var modelSpecTitle: String?
    let metadata = StableDiffusionClient.Lora.Metadata(ssSdModelName: "name",
                                                       ssBaseModelVersion: "version",
                                                       ssResolution: "resolution",
                                                       ssOutputName: "output name",
                                                       ssTagFrequency: ["aaa": [
                                                        "tag1": 5,
                                                        "tag2": 6
                                                       ]],
                                                       modelSpecTitle: "a title",
                                                       modelSpecArchitecture: "stable-diffusion-v1/lora",
                                                    )
    let lora = StableDiffusionClient.Lora(name: "lora",
                                          alias: "a lora",
                                          metadata: metadata)
    return LoraView(lora: lora)
}

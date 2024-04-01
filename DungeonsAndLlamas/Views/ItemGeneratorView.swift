//
//  ItemGeneratorView.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2024-03-27.
//

import SwiftUI
import Observation

struct ItemGeneratorView: View {
    @State var flowState: ContentFlowState
    @State var viewModel = ItemGeneratorViewModel()

    var body: some View {
        
        VStack {
            HStack {
                Picker("Weapon Type", selection: $viewModel.weaponType) {
                    ForEach(WeaponType.allCases, id: \.self) { weapon in
                        Text(weapon.rawValue)
                    }
                }.onChange(of: viewModel.weaponType) {
                    viewModel.updatePrompt()
                }
                
                Picker("Quality Type", selection: $viewModel.quality) {
                    ForEach(Quality.allCases, id: \.self) { quality in
                        Text(quality.rawValue)
                    }
                }.onChange(of: viewModel.quality) {
                    viewModel.updatePrompt()
                }
                
                Button("Generate") {
                    viewModel.generateImages()
                }.buttonStyle(.bordered)
                
                Spacer()
                if viewModel.loading {
                    ProgressView().padding(EdgeInsets(top: 5, leading: 5, bottom: 5, trailing: 10))
                }
            }
            
            VStack {
                TextField("Prompt", text: $viewModel.prompt, prompt: Text("Generated Prompt"))
                    .frame(minHeight: 100)
                    .padding()
                    .background(Color(white: 0.9))
            }
            
            ScrollView(.horizontal) {
                HStack {
                    ForEach(viewModel.images, id: \.self) { image in
                        Image(uiImage: image).onTapGesture {
                            viewModel.describe(image: image)
                        }
                    }
                }
            }
            .frame(minHeight: 512)
            .background(Color(white: 0.9))
            
            VStack {
                TextField("Description", text: $viewModel.itemDescription, prompt: Text("Item Description"))
                    .frame(minHeight: 100)
                    .padding()
                    .background(Color(white: 0.9))
            }

            
        }
    }
}

@Observable
class ItemGeneratorViewModel {
    var prompt = "A cat in a fancy hat"
    var itemDescription = ""
    var weaponType: WeaponType = .club
    var quality: Quality = .decent
    var images = [UIImage]()
    let client = APIClient()
    var loading = false
    
    func updatePrompt() {
        prompt = "((\(weaponType.rawValue))), ((\(quality.rawValue) quality)), fantasy"
    }
    
    func generateImages()  {
        images = []
        guard prompt.count > 0, !loading else {
            return
        }
        loading = true
        Task.init {
            do {
                let size = 256
                let options = StableDiffusionOptions(prompt: prompt, size: size, steps: 30, batchSize: 3)

                let strings = try await client.generateImage(options)
                
                for string in strings {
                    if let data = Data(base64Encoded: string), let image = UIImage(data: data), Int(image.size.width) <= size {
                        images.append(image)
                    }
                }
                loading = false
            } catch {
                print(error)
                loading = false
            }
        }
    }
    
    func describe(image: UIImage) {
        guard !loading else {
            return
        }
        loading = true
        itemDescription = ""
        guard let imageData = image.jpegData(compressionQuality: 0.8)?.base64EncodedString() else {
            return
        }
        Task.init {
            do {
                for try await obj in client.asyncStreamGenerate(prompt: "Describe the item in this image in 50 words or less", base64Image: imageData){
                    if !obj.done {
                        itemDescription += obj.response
                    }
                }
            } catch {
                print(error)
            }
            loading = false
        }
        
    }
}

enum ItemType: String {
    case weapon = "Weapon"
    case ammunition = "Ammunition"
}

enum WeaponType: String, CaseIterable {
    case club = "Club"
    case dagger = "Dagger"
    case greatclub = "Greatclub"
    case handaxe = "Handaxe"
    case javelin = "Javelin"
    case lightHammer = "Light Hammer"
    case mace = "Mace"
    case quarterstaff = "Quarterstaff"
    case sickle = "Sickle"
    case spear = "Spear"
}

enum Quality: String, CaseIterable {
    case broken = "Broken"
    case shoddy = "Shoddy"
    case poorQuality = "Poor"
    case middlingQuality = "Middling"
    case decent = "Decent"
    case wellMade = "Well Made"
    case highQualty = "High"
    case masterwork = "Masterwork"
    case legendary = "Legendary"
}

#Preview {
    let flowState = ContentFlowState()
    return ContentFlowCoordinator(flowState: flowState) {
        ItemGeneratorView(flowState: flowState)
    }
}

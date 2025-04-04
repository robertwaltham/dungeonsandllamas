//
//  DatabaseTestView.swift
//  DungeonsAndLlamas
//
//  Created by Robert Waltham on 2025-04-04.
//

import SwiftUI
import Observation

struct DatabaseTestView: View {
    @State var viewModel: DatabaseTestViewModel
    
    var body: some View {
        
        VStack {

            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]) {
                    ForEach(viewModel.history) { entry in
                        if let filepath = entry.outputFilePath {
                            ZStack {
                                Image(uiImage: viewModel.fs.loadImage(path: filepath))
                                    .resizable()
                                    .scaledToFit()
                                VStack {
                                    Text(entry.id)
                                    Text(entry.sequence.description)
                                    Text(entry.session)
                                }
                            }
                        } else {
                            Rectangle()
                                .background(.gray)
                        }
                    }
                }
            }
        }
    }
}

@Observable
class DatabaseTestViewModel {
    let db: DatabaseService
    let fs: FileService
    var history: [ImageHistoryModel] = []
    
    init(db: DatabaseService, fs: FileService) {
        self.db = db
        self.fs = fs
    }
    
    func load() {
        history = db.loadHistory()
    }
}

#Preview {
    let db = DatabaseService()
    let fs = FileService()
    db.setupForTesting(fileService: fs)
    let vm = DatabaseTestViewModel(db: db, fs: fs)
    vm.load()
    return DatabaseTestView(viewModel: vm)
}

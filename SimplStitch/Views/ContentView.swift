//
//  ContentView.swift
//  SimplStitch
//
//  Created by Marc Brechbühl on 29.07.2026.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        NavigationSplitView {
            List {
                Text("sidebar.noProjects")
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            Text("detail.selectProject")
        }
    }
}

#Preview {
    ContentView()
}

import SwiftUI

struct LogView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "No Logs",
                systemImage: "text.alignleft",
                description: Text("Protocol and device events will appear here.")
            )
            .navigationTitle("Logs")
        }
    }
}

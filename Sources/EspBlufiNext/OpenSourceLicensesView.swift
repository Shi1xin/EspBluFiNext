import Foundation
import SwiftUI

struct OpenSourceLicensesView: View {
    private let notices: String

    init() {
        if let url = Bundle.main.url(forResource: "THIRD-PARTY-NOTICES", withExtension: "md"),
           let data = try? Data(contentsOf: url) {
            notices = String(decoding: data, as: UTF8.self)
        } else {
            notices = "Third-party notices are unavailable in this build. See the source repository for the complete notice file."
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Open Source Licenses")
                    .font(.title3.weight(.semibold))

                Text("License and attribution information for this app's bundled dependencies.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(notices)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
        .navigationTitle("Open Source Licenses")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Open Source Licenses") {
    NavigationStack {
        OpenSourceLicensesView()
    }
}

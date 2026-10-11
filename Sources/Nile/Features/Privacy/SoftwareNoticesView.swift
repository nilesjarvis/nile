import SwiftUI

struct SoftwareNoticesView: View {
    private let notices = [
        ("Nile and bundled software", "Nile-Attributions"),
        ("Roboto and Droid Sans Mono", "Roboto-LICENSE"),
        ("FreeType", "FreeType-FTL"),
        ("HarfBuzz", "HarfBuzz-COPYING"),
    ]

    var body: some View {
        List {
            ForEach(notices, id: \.1) { title, resource in
                NavigationLink(title) {
                    ScrollView {
                        Text(Self.text(resource: resource))
                            .font(NileTypography.bodySmall)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                    }
                    .background(NileColors.background)
                    .navigationTitle(title)
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(NileColors.background)
        .foregroundStyle(NileColors.text)
        .navigationTitle("Software Notices")
        .navigationBarTitleDisplayMode(.inline)
    }

    private static func text(resource: String) -> String {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return "This software notice could not be loaded." }
        return text
    }
}

import SwiftUI

struct PreferencesView: View {
    @Environment(Preferences.self) private var preferences
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                Toggle("Aggressive PDF Compression", isOn: .init(
                    get: { preferences.useAggressivePDFCompression },
                    set: { preferences.useAggressivePDFCompression = $0 }
                ))

                Text("Aggressive mode significantly reduces file size for scanned documents and image-heavy PDFs, but text will no longer be selectable or searchable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 350, height: 160)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }
}

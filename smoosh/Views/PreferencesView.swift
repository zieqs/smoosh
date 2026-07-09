import SwiftUI

struct PreferencesView: View {
    @Environment(Preferences.self) private var preferences
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("PDF Quality")
                        .font(.headline)

                    Picker("Quality", selection: .init(
                        get: { preferences.pdfQuality },
                        set: { preferences.pdfQuality = $0 }
                    )) {
                        ForEach(PDFQuality.allCases, id: \.self) { quality in
                            Text(quality.displayName).tag(quality)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text("Low (96 DPI) — smallest file, visible quality loss. Medium (150 DPI) — balanced. High (300 DPI) — near-original quality.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Video Quality")
                        .font(.headline)

                    Picker("Quality", selection: .init(
                        get: { preferences.videoQuality },
                        set: { preferences.videoQuality = $0 }
                    )) {
                        ForEach(VideoQuality.allCases, id: \.self) { quality in
                            Text(quality.displayName).tag(quality)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text("Audio is preserved. Resolution unchanged.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 350, height: 280)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }
}

import SwiftUI

struct TipJarButton: View {
    var body: some View {
        Button {
            if let url = URL(string: "https://ko-fi.com/zieqs") {
                NSWorkspace.shared.open(url)
            }
        } label: {
            Label("Support the Developer ☕", systemImage: "cup.and.saucer.fill")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

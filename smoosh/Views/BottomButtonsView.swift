import SwiftUI

struct BottomButtonsView: View {
    var body: some View {
        VStack(spacing: 0) {
            Button {
                //Open Preference View Here
            } label: {
                Label("Preferences ", systemImage: "gear")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            
            Divider()
                .frame(height: 20)
            
            Button {
                if let url = URL(string: "https://buymeacoffee.com/zieqs") { //"https://ko-fi.com/zieqs"
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("Support the Developer ", systemImage: "cup.and.saucer.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            
            Divider()
                .frame(height: 20)
            
            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit App", systemImage: "power")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var vm: CompassViewModel
    @ObservedObject private var log = Log.shared

    var body: some View {
        List {
            Section("Location") {
                LabeledContent("Authorization", value: vm.locationAuthDescription)
                Button("Request \"Always\" access") { vm.requestAlwaysLocation() }
                Text("\"Always\" makes findable mode much more reliable when the phone is locked. If no prompt appears, grant it manually: Settings → Locompass → Location → Always.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section {
                ShareLink(item: log.fileURL) {
                    Label("Export log as text file", systemImage: "square.and.arrow.up")
                }
                Button(role: .destructive) { log.clear() } label: {
                    Label("Clear log", systemImage: "trash")
                }
            } header: {
                Text("Debug log (\(log.lines.count) lines, newest first)")
            }

            Section {
                ForEach(Array(log.lines.suffix(300).enumerated()).reversed(), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 11, design: .monospaced))
                        .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 4))
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

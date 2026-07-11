import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var vm: CompassViewModel
    @ObservedObject private var log = Log.shared
    @State private var nameDraft = ""

    var body: some View {
        List {
            Section("Your name") {
                HStack {
                    TextField("Your name", text: $nameDraft)
                        .submitLabel(.done)
                        .onSubmit { vm.setDisplayName(nameDraft) }
                    Button {
                        nameDraft = NameGenerator.random()
                        vm.setDisplayName(nameDraft)
                    } label: {
                        Image(systemName: "dice")
                    }
                    .buttonStyle(.borderless)
                }
                Text("This is how friends see you. Changing it reconnects and starts a fresh identity — old chats and last-seen entries stay under the previous name.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("Findable") {
                Toggle("Findable while locked", isOn: $vm.findableMode)
                Text("Friends can find and message you while this phone is locked — as long as Locompass stays open in the background. Don't swipe it away.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

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
        .onAppear { nameDraft = vm.displayName }
    }
}

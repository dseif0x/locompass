import SwiftUI

struct ChatsListView: View {
    @EnvironmentObject var vm: CompassViewModel

    private var partners: [String] {
        let convos = vm.chats.keys.sorted {
            (vm.chats[$0]?.last?.ts ?? .distantPast) > (vm.chats[$1]?.last?.ts ?? .distantPast)
        }
        let others = vm.known.map(\.name).filter { !vm.chats.keys.contains($0) }
        return convos + others
    }

    var body: some View {
        List {
            if partners.isEmpty {
                Text("No one to message yet — connect to a friend first.")
                    .foregroundStyle(.secondary)
            }
            ForEach(partners, id: \.self) { name in
                NavigationLink { ChatView(name: name) } label: {
                    HStack {
                        Circle().fill(vm.isLive(name) ? Color.green : Color.gray)
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name).bold()
                            if let last = vm.chats[name]?.last {
                                Text((last.outgoing ? "You: " : "") + last.text)
                                    .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                            } else {
                                Text("Say hi").font(.footnote).foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                        if let n = vm.unread[name], n > 0 {
                            Text("\(n)")
                                .font(.caption2).bold().foregroundStyle(.white)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Color.red, in: Capsule())
                        }
                    }
                }
            }
        }
        .navigationTitle("Messages")
    }
}

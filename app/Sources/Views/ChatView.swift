import SwiftUI

struct ChatView: View {
    let name: String
    @EnvironmentObject var vm: CompassViewModel
    @State private var draft = ""

    private var messages: [ChatMessage] { vm.chats[name] ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(messages) { m in bubble(m) }
                    }
                    .padding(10)
                }
                .onChange(of: messages.count) { _ in
                    if let last = messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
                .onAppear {
                    if let last = messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }

            if !vm.isLive(name) {
                Text("\(name) isn't reachable right now — messages are queued and delivered when you're back in range.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12).padding(.top, 4)
            }

            HStack(spacing: 8) {
                TextField("Message…", text: $draft, axis: .vertical)
                    .lineLimit(1...3)
                    .textFieldStyle(.roundedBorder)
                Button {
                    vm.sendChat(draft, to: name)
                    draft = ""
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                }
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(10)
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { vm.openChat(name) }
        .onDisappear { vm.closeChat(name) }
    }

    @ViewBuilder private func bubble(_ m: ChatMessage) -> some View {
        HStack {
            if m.outgoing { Spacer(minLength: 48) }
            VStack(alignment: m.outgoing ? .trailing : .leading, spacing: 2) {
                Text(m.text)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(m.outgoing ? Color.blue : Color(.systemGray5),
                                in: RoundedRectangle(cornerRadius: 16))
                    .foregroundStyle(m.outgoing ? Color.white : Color.primary)
                if m.outgoing {
                    Text(m.acked ? "delivered" : "sending…")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            if !m.outgoing { Spacer(minLength: 48) }
        }
        .id(m.id)
    }
}

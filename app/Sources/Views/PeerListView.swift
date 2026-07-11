import SwiftUI

struct PeerListView: View {
    @EnvironmentObject var vm: CompassViewModel
    @State private var nameDraft = ""

    var body: some View {
        List {
            Section("You") {
                TextField("Your name", text: $nameDraft)
                    .submitLabel(.done)
                    .onSubmit { vm.setDisplayName(nameDraft) }
                Toggle("Findable while locked", isOn: $vm.findableMode)
                if vm.findableMode {
                    Text("Friends can find you while this phone is locked — as long as Locompass stays open in the background. Don't swipe it away.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }

            if !vm.uwbSupported {
                Section {
                    Label("This device has no UWB — GPS arrow only.",
                          systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }

            Section("Friends nearby") {
                ForEach(vm.people) { person in
                    if person.connected {
                        NavigationLink { CompassView(name: person.name) } label: { row(person) }
                    } else {
                        row(person).foregroundStyle(.secondary)
                    }
                }
                if vm.people.isEmpty {
                    Text("Looking for friends… they need the app open (or findable mode on).")
                        .foregroundStyle(.secondary)
                }
            }

            if !vm.known.isEmpty {
                Section("Last seen") {
                    ForEach(vm.known) { person in
                        NavigationLink { PersonMapView(name: person.name) } label: {
                            HStack {
                                Image(systemName: "mappin.circle")
                                    .foregroundStyle(person.lat != nil ? Color.blue : Color.secondary)
                                Text(person.name)
                                Spacer()
                                Text(seenText(person)).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { vm.forget(at: $0) }
                }
            }
        }
        .onAppear { nameDraft = vm.displayName }
    }

    private func seenText(_ p: KnownPerson) -> String {
        if vm.isLive(p.name) { return "Now" }
        return RelativeDateTimeFormatter().localizedString(for: p.seenAt, relativeTo: Date())
    }

    private func row(_ person: Person) -> some View {
        HStack {
            Circle().fill(person.connected ? .green : .gray).frame(width: 8, height: 8)
            Text(person.name)
            Spacer()
            if person.mpc?.connected == true {
                Image(systemName: "wifi") // local link: UWB-capable
                    .font(.caption).foregroundStyle(.secondary)
            }
            if person.ble?.connected == true {
                Image(systemName: "antenna.radiowaves.left.and.right") // findable beacon
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !person.connected {
                Text("connecting…").font(.footnote).foregroundStyle(.secondary)
            } else if let d = vm.nav(for: person.name).distance {
                Text(String(format: "%.0f m", d)).foregroundStyle(.secondary)
            }
        }
    }
}

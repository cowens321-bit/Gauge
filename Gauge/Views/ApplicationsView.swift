import SwiftUI

struct ApplicationsView: View {
    @Environment(MonitorModel.self) private var model
    @Environment(\.byteUnits) private var units
    @Environment(\.cpuNormalization) private var norm
    @AppStorage(Pref.listScope) private var scope = ListScope.userApps
    @AppStorage(Pref.defaultSort) private var defaultSort = SortKey.cpu
    @AppStorage(Pref.perAppNetwork) private var perAppNetwork = false
    @State private var query = ""
    @State private var sort = SortSpec(column: .cpu, ascending: false)
    @State private var selection: String?
    @State private var showInspector = false

    var body: some View {
        let groups = model.snapshot?.groups ?? []
        let rows = AppFilter.apply(groups, scope: scope, query: query).sorted(using: sort.comparators)
        VStack(spacing: 14) {
            OverviewHeader().padding(.horizontal, 20).padding(.top, 6)
            VStack(spacing: 0) {
                table(rows)
                Divider().opacity(0.4)
                footer(total: groups.count, shown: rows.count)
            }
            .clipShape(.rect(cornerRadius: 28))
            .glassCard(radius: 28, padding: 0)
            .padding(.horizontal, 20).padding(.bottom, 18)
        }
        .inspector(isPresented: $showInspector) {
            Group {
                if let id = selection, let g = model.group(id: id) {
                    AppInspector(group: g).transition(.blurReplace)
                } else if let id = selection {
                    ContentUnavailableView("Application Quit", systemImage: "xmark.circle",
                                           description: Text("“\(id.split(separator: "/").last.map(String.init) ?? id)” is no longer running."))
                } else {
                    ContentUnavailableView("Select an Application", systemImage: "sidebar.trailing",
                                           description: Text("Choose an app to see its processes, history and actions."))
                }
            }
            .animation(.smooth, value: selection)
            .inspectorColumnWidth(min: 320, ideal: 360, max: 500)
        }
        .searchable(text: $query, placement: .toolbar, prompt: "Search apps, bundle IDs or PIDs")
        .toolbar {
            ToolbarItem {
                Picker("Show", selection: $scope) {
                    ForEach(ListScope.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .help("Apps: Dock and user apps · All Apps: includes system apps · Everything: adds background services")
            }
            ToolbarSpacer(.fixed)
            ToolbarItem {
                Button { withAnimation(.smooth) { showInspector.toggle() } } label: { Label("Inspector", systemImage: "sidebar.trailing") }
            }
        }
        .onAppear { sort = SortSpec(column: AppColumn(defaultSort), ascending: defaultSort == .name) }
        .onChange(of: defaultSort) { _, new in sort = SortSpec(column: AppColumn(new), ascending: new == .name) }
        .onChange(of: selection) { _, new in if new != nil { showInspector = true } }
        .onChange(of: groups.count) { _, _ in
            // Developer convenience: `-launchInspectTop YES` selects the busiest app once data arrives.
            if selection == nil, UserDefaults.standard.bool(forKey: "launchInspectTop"), let first = rows.first { selection = first.id }
        }
        .alert(item: Binding(get: { model.pending }, set: { model.pending = $0 })) { p in alert(for: p) }
    }

    // MARK: List
    private func table(_ rows: [GroupSnapshot]) -> some View {
        AppList(rows: rows, selection: $selection, sort: $sort, showNetwork: perAppNetwork,
                onOpen: { _ in withAnimation(.smooth) { showInspector = true } })
            .overlay {
                if model.snapshot == nil || model.snapshot?.hasProcessData == false {
                    if model.interval == 0 {
                        ContentUnavailableView("Monitoring Paused", systemImage: "pause.circle", description: Text("Choose a refresh interval to resume."))
                    } else { ProgressView("Sampling processes…") }
                } else if rows.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
    }

    private func footer(total: Int, shown: Int) -> some View {
        HStack(spacing: 12) {
            if let d = model.snapshot?.diagnostics {
                Text("\(shown) of \(total) groups · \(d.processCount) processes")
                if d.unreadableProcessCount > 0 {
                    Text("\(d.unreadableProcessCount) protected by macOS").help("Processes owned by other users/root cannot be measured without elevated privileges. Their metrics are omitted, never estimated.")
                }
                Text(String(format: "sample %.1f ms", d.sampleDurationMs))
                if !d.responsibilityAPIAvailable { Text("responsible-process lookup unavailable") }
            }
            Spacer()
            Text(norm == .perCore ? "CPU: 100% = one core" : "CPU: 100% = all cores")
        }
        .font(.caption).foregroundStyle(.secondary)
        .padding(.horizontal, 18).padding(.vertical, 8)
    }

    // MARK: Alerts
    private func alert(for p: PendingAction) -> Alert {
        switch p.kind {
        case .quit:
            return Alert(title: Text("Quit “\(p.group.name)”?"),
                         message: Text("The app will be asked to quit and may prompt you to save unsaved work."),
                         primaryButton: .default(Text("Quit")) { _ = ProcessController.quit(p.group) },
                         secondaryButton: .cancel())
        case .forceQuit:
            return Alert(title: Text("Force Quit “\(p.group.name)”?"),
                         message: Text("The app and its \(p.group.processCount) process(es) will end immediately. Any unsaved work will be lost."),
                         primaryButton: .destructive(Text("Force Quit")) { _ = ProcessController.forceQuit(p.group) },
                         secondaryButton: .cancel())
        case .killProcess(let proc, let force):
            return Alert(title: Text(force ? "Force kill “\(proc.name)” (PID \(proc.pid))?" : "Quit process “\(proc.name)” (PID \(proc.pid))?"),
                         message: Text(force ? "The process is killed immediately and cannot clean up. Unsaved work in it will be lost." : "The process is sent a termination signal (SIGTERM)."),
                         primaryButton: .destructive(Text(force ? "Force Kill" : "Quit Process")) { _ = ProcessController.terminate(process: proc, force: force) },
                         secondaryButton: .cancel())
        }
    }
}

/// Shared context-menu / inspector actions.
struct GroupActions: View {
    @Environment(MonitorModel.self) private var model
    let group: GroupSnapshot

    var body: some View {
        let blocked = ProcessProtection.reasonProtected(group: group)
        Button("Reveal in Finder", systemImage: "folder") { ProcessController.revealInFinder(group) }
            .disabled(group.bundlePath == nil && group.processes.first?.path == nil)
        Divider()
        Button("Copy Process IDs", systemImage: "number") {
            ProcessController.copy(group.processes.map { String($0.pid) }.joined(separator: ", "))
        }
        if let b = group.bundleID { Button("Copy Bundle Identifier", systemImage: "doc.on.doc") { ProcessController.copy(b) } }
        Divider()
        Button("Quit", systemImage: "power") { model.pending = PendingAction(kind: .quit, group: group) }
            .disabled(blocked != nil)
        Button("Force Quit…", systemImage: "exclamationmark.octagon") { model.pending = PendingAction(kind: .forceQuit, group: group) }
            .disabled(blocked != nil)
    }
}




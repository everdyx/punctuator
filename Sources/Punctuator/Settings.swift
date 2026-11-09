import AppKit
import SwiftUI

// Device-specific modifier bits distinguish the right key from the left key.
enum TriggerKey: String, Codable, CaseIterable, Identifiable {
    case rightShift, rightOption, rightControl
    var id: String { rawValue }
    var title: String {
        switch self {
        case .rightShift: return "右侧 Shift ⇧"
        case .rightOption: return "右侧 Option ⌥"
        case .rightControl: return "右侧 Control ⌃"
        }
    }
    var keyCode: CGKeyCode {
        switch self {
        case .rightShift: return 60
        case .rightOption: return 61
        case .rightControl: return 62
        }
    }
    var deviceMask: UInt64 {
        switch self {
        case .rightShift: return 0x00000004
        case .rightOption: return 0x00000040
        case .rightControl: return 0x00002000
        }
    }
}

struct SymbolMapping: Codable, Identifiable, Equatable {
    var id = UUID()
    var source: String
    var replacement: String
}

struct AppSettings: Codable, Equatable {
    var triggerKey: TriggerKey = .rightShift
    var mappings: [SymbolMapping] = defaultMappings

    static let defaultMappings: [SymbolMapping] = [
        ("。", "."), ("，", ","), ("、", "\\"), ("？", "?"), ("！", "!"),
        ("：", ":"), ("；", ";"), ("（", "("), ("）", ")"), ("【", "["),
        ("】", "]"), ("《", "<"), ("》", ">"), ("“", "\""), ("”", "\""),
        ("‘", "'"), ("’", "'")
    ].map { SymbolMapping(source: $0.0, replacement: $0.1) }

    var validationError: String? {
        var seen = Set<String>()
        for (index, mapping) in mappings.enumerated() {
            if mapping.source.count != 1 || mapping.source.contains(where: { $0.isNewline }) {
                return "第 \(index + 1) 行：原符号必须是一个字符。"
            }
            if mapping.replacement.isEmpty || mapping.replacement.contains(where: { $0.isNewline }) {
                return "第 \(index + 1) 行：替换内容不能为空或包含换行。"
            }
            if !seen.insert(mapping.source).inserted {
                return "第 \(index + 1) 行：原符号「\(mapping.source)」重复了。"
            }
        }
        return nil
    }

    var punctuationMap: [String: String] {
        Dictionary(mappings.map { ($0.source, $0.replacement) }, uniquingKeysWith: { _, last in last })
    }
}

final class SettingsStore {
    private let defaults: UserDefaults
    private let key = "punctuator.settings.v1"
    private(set) var current: AppSettings

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let settings = try? JSONDecoder().decode(AppSettings.self, from: data),
           settings.validationError == nil {
            current = settings
        } else {
            current = AppSettings()
        }
    }

    func save(_ settings: AppSettings) throws {
        if let error = settings.validationError {
            throw NSError(domain: "Punctuator.Settings", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: error])
        }
        defaults.set(try JSONEncoder().encode(settings), forKey: key)
        current = settings
    }
}

final class SettingsWindowController: NSWindowController {
    init(settings: AppSettings, onSave: @escaping (AppSettings) throws -> Void) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 590, height: 640),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Punctuator 设置"
        window.minSize = NSSize(width: 530, height: 470)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentView = NSHostingView(rootView: SettingsView(settings: settings, onSave: onSave,
                                                                 onClose: { [weak window] in window?.close() }))
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private struct SettingsView: View {
    @State var settings: AppSettings
    let onSave: (AppSettings) throws -> Void
    let onClose: () -> Void
    @State private var saveError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("触发按键").font(.headline)
            Picker("轻按以下按键转换光标前的符号", selection: $settings.triggerKey) {
                ForEach(TriggerKey.allCases) { key in Text(key.title).tag(key) }
            }
            Text("所选按键由 Punctuator 接管；启用期间将不再执行原来的修饰键功能。")
                .font(.caption).foregroundColor(.secondary)
            Divider()
            HStack {
                Text("符号对应关系").font(.headline)
                Spacer()
                Button("添加") { settings.mappings.append(SymbolMapping(source: "", replacement: "")) }
            }
            HStack {
                Text("原符号（一个字符）").frame(maxWidth: .infinity, alignment: .leading)
                Text("替换为").frame(maxWidth: .infinity, alignment: .leading)
                Spacer().frame(width: 48)
            }.font(.caption).foregroundColor(.secondary)
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach($settings.mappings) { $mapping in
                        HStack {
                            TextField("例如：。", text: $mapping.source)
                                .accessibilityLabel("原符号")
                            Image(systemName: "arrow.right").foregroundColor(.secondary)
                            TextField("例如：.", text: $mapping.replacement)
                                .accessibilityLabel("替换内容")
                            Button("删除") { settings.mappings.removeAll { $0.id == mapping.id } }
                        }
                    }
                }.padding(2)
            }
            Text("替换内容可以是一个或多个字符；保存后立即生效，并在重启后保留。")
                .font(.caption).foregroundColor(.secondary)
            if let error = settings.validationError ?? saveError {
                Text(error).font(.callout).foregroundColor(.red)
            }
            Divider()
            HStack {
                Button("恢复默认") { settings = AppSettings(); saveError = nil }
                Spacer()
                Button("取消", action: onClose).keyboardShortcut(.cancelAction)
                Button("保存") {
                    do { try onSave(settings); onClose() }
                    catch { saveError = error.localizedDescription }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(settings.validationError != nil)
            }
        }.padding(24).frame(minWidth: 480, minHeight: 420)
    }
}

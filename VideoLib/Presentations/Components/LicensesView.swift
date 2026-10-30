import LicensesList
import SwiftUI

/// «Лицензии»: first the app itself and what ships inside it besides Swift packages (the upstream MIT notice, aria2,
/// Inter, the license-list code), then every Swift package found at build time. Each row unfolds its full text.
struct LicensesView: View {
    private let groups: [LicenseGroup] = [
        LicenseGroup(title: "Приложение и встроенные компоненты", entries: LicenseEntry.bundled),
        LicenseGroup(title: "Пакеты Swift", entries: Library.libraries.map(LicenseEntry.init)),
    ]

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 22) {
                ForEach(groups) { group in
                    if !group.entries.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(verbatim: group.title)
                                .font(KP.font(13, .semibold))
                                .foregroundStyle(KP.fg55)
                                .padding(.leading, 2)

                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(group.entries) { entry in
                                    LicenseView(entry: entry)

                                    if group.entries.last != entry {
                                        Divider()
                                    }
                                }
                            }
                            .padding(.horizontal, 15)
                            .background(.quinary, in: .rect(cornerRadius: 6))
                            .overlay(.tertiary, in: .rect(cornerRadius: 6).stroke(lineWidth: 1))
                        }
                    }
                }
            }
            .padding(25)
            .background(.background)
        }
        .scrollIndicators(.visible, axes: .vertical)
        .viewModifier { view in
            if #available(macOS 26, *) {
                view.scrollEdgeEffectStyle(.soft, for: .all)
            } else {
                view
            }
        }
        .navigationTitle("key.licenses")
        .frame(width: 700, height: 400)
    }

    private struct LicenseView: View {
        private let entry: LicenseEntry

        @State private var showLicense = false

        init(entry: LicenseEntry) {
            self.entry = entry
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(entry.name)
                        .font(.title)
                        .textSelection(.enabled)

                    if let version = entry.version {
                        Text(version)
                            .textSelection(.enabled)
                            .foregroundStyle(.secondary)
                    } else if let branch = entry.branch {
                        Text("library.branch-\(branch)")
                            .textSelection(.enabled)
                            .foregroundStyle(.secondary)
                    }
                }

                if let note = entry.note {
                    Text(verbatim: note)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                if let url = entry.url {
                    Link(destination: url) {
                        Text(url.absoluteString)
                    }
                }

                Button {
                    withAnimation(.easeInOut) {
                        showLicense.toggle()
                    }
                } label: {
                    Label(showLicense ? String(localized: "key.license.hide") : String(localized: "key.license.show"), systemImage: showLicense ? "chevron.up" : "chevron.down")
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)

                if showLicense {
                    Text(attributedString(entry.licenseBody))
                        .multilineTextAlignment(.leading)
                        .textSelection(.enabled)
                        .padding()
                }
            }
            .padding(.vertical, 10)
        }

        private func attributedString(_ input: String) -> AttributedString {
            var attributedString = AttributedString(input)

            guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
                return attributedString
            }

            let matches = detector.matches(in: input, options: [], range: NSRange(location: 0, length: input.utf16.count))

            for match in matches {
                guard let range = Range(match.range, in: input),
                      let attributedRange = Range(match.range, in: attributedString),
                      let url = URL(string: String(input[range]))
                else {
                    continue
                }

                attributedString[attributedRange].link = url
            }

            return attributedString
        }
    }
}

/// A heading and its rows in the Licenses window.
private struct LicenseGroup: Identifiable {
    let title: String
    let entries: [LicenseEntry]

    var id: String {
        title
    }
}

/// One row of the Licenses window: a Swift package listed at build time, or a component that ships in the app
/// without being one (its text comes from VideoLib/Resources/Licenses and Fonts).
struct LicenseEntry: Identifiable, Hashable {
    let id: String
    let name: String
    let version: String?
    let branch: String?
    /// What it is and under which license, in a line under the name (bundled components only).
    let note: String?
    let url: URL?
    let licenseBody: String

    init(_ library: Library) {
        id = "package:\(library.name)"
        name = library.name
        version = library.version
        branch = library.branch
        note = nil
        url = library.url
        licenseBody = library.licenseBody
    }

    private init(name: String, version: String? = nil, note: String, url: URL?, licenseBody: String) {
        id = "bundled:\(name)"
        self.name = name
        self.version = version
        branch = nil
        self.note = note
        self.url = url
        self.licenseBody = licenseBody
    }

    /// The app (MIT, with the upstream author's notice kept as the license asks), aria2 (GPL: where its source is),
    /// Inter (OFL) and the code behind this list (MIT). The same list as THIRD_PARTY_NOTICES.md in the repository.
    static var bundled: [LicenseEntry] {
        [
            LicenseEntry(
                name: AppInfo.name,
                note: "Лицензия MIT. Основано на открытом проекте voidboost: его уведомление об авторских правах сохранено.",
                url: AppLinks.repository,
                licenseBody: text("KinoPohuy-MIT")
            ),
            LicenseEntry(
                name: "aria2",
                version: "1.37.0",
                note: "Загрузчик файлов (aria2c), GNU GPL версии 2 или новее. Собран из официального архива без изменений "
                    + "скриптом scripts/aria2/build.sh из репозитория приложения; архив приложен к каждому релизу на GitHub "
                    + "и лежит по ссылке ниже. Внутри — UTF-8-декодер Бьёрна Хёрманна (MIT), его текст — под GPL.",
                url: URL(string: "https://github.com/aria2/aria2/releases/tag/release-1.37.0"),
                licenseBody: "aria2 1.37.0 — Copyright (C) 2006, 2019 Tatsuhiro Tsujikawa\n\n" + text("GPL-2.0") + "\n\n" + text("aria2-utf8-decoder-MIT")
            ),
            LicenseEntry(
                name: "Inter",
                note: "Шрифт интерфейса, SIL Open Font License 1.1.",
                url: URL(string: "https://github.com/rsms/inter"),
                licenseBody: text("Inter-OFL")
            ),
            LicenseEntry(
                name: "LicenseList",
                note: "Основа этого окна: список лицензий пакетов Swift, лицензия MIT, © 2022 Cybozu. Код изменён для приложения.",
                url: URL(string: "https://github.com/cybozu/LicenseList"),
                licenseBody: text("LicenseList-MIT")
            ),
        ]
    }

    /// A bundled text file's contents (a dash if it's missing, which only a broken build could cause).
    private static func text(_ resource: String) -> String {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "txt"),
              let body = try? String(contentsOf: url, encoding: .utf8)
        else {
            return "—"
        }

        return body
    }
}

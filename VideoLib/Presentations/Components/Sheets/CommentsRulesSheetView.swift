import Defaults
import SwiftUI

struct CommentsRulesSheetView: View {
    @Environment(\.dismiss) private var dismiss

    @Environment(CookiesManager.self) private var cookiesManager

    var body: some View {
        VStack(alignment: .center, spacing: 25) {
            VStack(alignment: .center, spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(KP.sun)

                Text("key.rules")
                    .font(KP.font(24, .heavy))
                    .foregroundStyle(KP.fg)

                Text("key.rules.description")
                    .font(KP.font(14, .medium))
                    .foregroundStyle(KP.fg55)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.center)
            }

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("key.rules.prohibited")

                    HStack(alignment: .top, spacing: 5) {
                        Image(systemName: "seal.fill")
                            .padding(.top, 3)
                            .font(KP.font(12, .medium))
                            .foregroundStyle(KP.sun)

                        Text(String(localized: "key.rules.inciting").lowercased())
                    }

                    HStack(alignment: .top, spacing: 5) {
                        Image(systemName: "seal.fill")
                            .padding(.top, 3)
                            .font(KP.font(12, .medium))
                            .foregroundStyle(KP.sun)

                        Text(String(localized: "key.rules.insulting").lowercased())
                    }

                    HStack(alignment: .top, spacing: 5) {
                        Image(systemName: "seal.fill")
                            .padding(.top, 3)
                            .font(KP.font(12, .medium))
                            .foregroundStyle(KP.sun)

                        Text(String(localized: "key.rules.obscene").lowercased())
                    }

                    HStack(alignment: .top, spacing: 5) {
                        Image(systemName: "seal.fill")
                            .padding(.top, 3)
                            .font(KP.font(12, .medium))
                            .foregroundStyle(KP.sun)

                        Text(String(localized: "key.rules.spoiler").lowercased())
                    }

                    HStack(alignment: .top, spacing: 5) {
                        Image(systemName: "seal.fill")
                            .padding(.top, 3)
                            .font(KP.font(12, .medium))
                            .foregroundStyle(KP.sun)

                        Text(String(localized: "key.rules.leave").lowercased())
                    }

                    HStack(alignment: .top, spacing: 5) {
                        Image(systemName: "seal.fill")
                            .padding(.top, 3)
                            .font(KP.font(12, .medium))
                            .foregroundStyle(KP.sun)

                        Text(String(localized: "key.rules.questions").lowercased())
                    }

                    HStack(alignment: .top, spacing: 5) {
                        Image(systemName: "seal.fill")
                            .padding(.top, 3)
                            .font(KP.font(12, .medium))
                            .foregroundStyle(KP.sun)

                        Text(String(localized: "key.rules.resources").lowercased())
                    }

                    HStack(alignment: .top, spacing: 5) {
                        Image(systemName: "seal.fill")
                            .padding(.top, 3)
                            .font(KP.font(12, .medium))
                            .foregroundStyle(KP.sun)

                        Text(String(localized: "key.rules.mention").lowercased())
                    }

                    HStack(alignment: .top, spacing: 5) {
                        Image(systemName: "seal.fill")
                            .padding(.top, 3)
                            .font(KP.font(12, .medium))
                            .foregroundStyle(KP.sun)

                        Text(String(localized: "key.rules.problems").lowercased())
                    }
                }
                .multilineTextAlignment(.leading)
                .font(KP.font(14))
                .padding(10)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.visible, axes: .vertical)
            .frame(maxWidth: .infinity)
            .frame(height: 200)
            .kpField()

            VStack(alignment: .center, spacing: 10) {
                Button {
                    cookiesManager.allowComments()

                    dismiss()
                } label: {
                    Text("key.accept")
                }
                .buttonStyle(KPSheetButtonStyle(primary: true))

                Button {
                    dismiss()
                } label: {
                    Text("key.cancel")
                }
                .buttonStyle(KPSheetButtonStyle())
            }
        }
        .padding(.horizontal, 35)
        .padding(.top, 35)
        .padding(.bottom, 25)
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 520)
        .background(KP.bg)
    }
}

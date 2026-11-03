import ComposableArchitecture
import RecommenderCore
import SwiftUI

/// «Что хочется сегодня?»: the field, what was understood as removable chips, «Своё ↔ Микс ↔ Открытия», then the pick
/// (poster, why, ratings, the buttons) with two «Или:» beside it, and the critique buttons at the bottom. ⏎ plays the
/// pick (or sends the words, while typing), Space is «Другое», Esc closes.
struct PickForMeView: View {
    @Bindable var store: StoreOf<PickForMeFeature>

    @FocusState private var fieldFocused: Bool
    /// The sheet itself holds the keyboard when the field doesn't, so Space and ⏎ reach it.
    @FocusState private var sheetFocused: Bool

    var body: some View {
        KPSheet(title: "Что хочется сегодня?", subtitle: subtitle, symbol: "die.face.5", width: 760) {
            VStack(alignment: .leading, spacing: 14) {
                field
                if !store.turns.isEmpty || store.note != nil {
                    conversation
                }
                chips
                controls

                Divider().overlay(KP.line)

                pickArea
                    .frame(minHeight: 236, alignment: .top)

                Divider().overlay(KP.line)

                critiques
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($sheetFocused)
        .onKeyPress(.space) {
            // Typing a space in the field is just a space.
            guard !fieldFocused, store.result?.main != nil else { return .ignored }
            store.send(.other)
            return .handled
        }
        .onChange(of: store.focusRequests) {
            fieldFocused = true
        }
        .onAppear {
            store.send(.onAppear)
            if store.focusText {
                fieldFocused = true
            } else {
                sheetFocused = true
            }
        }
    }

    private var subtitle: String {
        if let main = store.result?.main, main.reason.kind == .canStart || main.reason.kind == .bookmark {
            return "Из вашего: закладки и начатое"
        }
        switch store.pool {
        case .own: return "Только своё: закладки, начатое, следующие части"
        case .mix: return "Своё и то, что точно в вашем вкусе"
        case .discover: return "Открытия: то, до чего вы сами не дошли бы"
        }
    }

    // MARK: Request

    private var field: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.bubble")
                .foregroundStyle(KP.fg38)
            TextField(
                "",
                text: $store.text,
                prompt: Text(verbatim: "Например: лёгкое на полтора часа, смотрим вдвоём").foregroundStyle(KP.fg38)
            )
            .textFieldStyle(.plain)
            .font(KP.font(15, .medium))
            .foregroundStyle(KP.fg)
            .focused($fieldFocused)
            .onSubmit { store.send(.submit) }
            if !store.text.isEmpty {
                Text(verbatim: "⏎")
                    .font(KP.font(13, .semibold))
                    .foregroundStyle(KP.fg38)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .kpField()
    }

    private var conversation: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(store.turns) { turn in
                HStack(spacing: 6) {
                    Text(verbatim: "Вы: \(turn.you)")
                        .foregroundStyle(KP.fg55)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(KP.fg38)
                    Text(verbatim: turn.reply)
                        .foregroundStyle(KP.fg70)
                }
                .font(KP.font(12.5, .medium))
                .lineLimit(1)
            }
            if let note = store.note {
                Label {
                    Text(verbatim: note)
                } icon: {
                    Image(systemName: "info.circle")
                }
                .font(KP.font(12.5, .semibold))
                .foregroundStyle(KP.sun)
                .lineLimit(2)
            }
        }
        .transition(.opacity)
    }

    private var chips: some View {
        HStack(spacing: 8) {
            Text(verbatim: store.chips.isEmpty ? "Без пожеланий" : "Понял так:")
                .font(KP.font(12.5, .semibold))
                .foregroundStyle(KP.fg55)
                .fixedSize()

            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(store.chips) { chip in
                        Button {
                            store.send(.removeChip(chip), animation: .snappy(duration: 0.2))
                        } label: {
                            HStack(spacing: 5) {
                                Text(verbatim: chip.label)
                                Image(systemName: "xmark")
                                    .font(.system(size: 8.5, weight: .heavy))
                                    .opacity(0.55)
                            }
                            .font(KP.font(12.5, .semibold))
                            .foregroundStyle(KP.fg)
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(Capsule().fill(KP.chip))
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("Убрать «\(chip.label)»")
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                    }
                }
            }
            .scrollIndicators(.never)

            addMenu
        }
    }

    private var addMenu: some View {
        Menu {
            Section("Что") {
                Button("Всё равно") { store.send(.setKinds(nil)) }
                Button("Фильм") { store.send(.setKinds([.film])) }
                Button("Сериал") { store.send(.setKinds([.series])) }
                Button("Мультфильм") { store.send(.setKinds([.cartoon])) }
                Button("Аниме") { store.send(.setKinds([.anime])) }
            }
            Section("Сколько времени") {
                Button("До 90 минут") { store.send(.setTime(.maxMinutes(90))) }
                Button("Фильм на вечер") { store.send(.setTime(.filmNight)) }
                Button("Серия на 20–45 минут") { store.send(.setTime(.episode(20 ... 45))) }
                Button("Сериал на выходные") { store.send(.setTime(.weekendSeries)) }
            }
            Section("Настроение") {
                Button("Посмеяться") { store.send(.setMood(.laugh)) }
                Button("Напряжение") { store.send(.setMood(.tension)) }
                Button("Подумать") { store.send(.setMood(.think)) }
                Button("Уютное") { store.send(.setMood(.cozy)) }
                Button("Погрустить") { store.send(.setMood(.cry)) }
                Button("Пострашнее") { store.send(.setMood(.scare)) }
            }
            Section("С кем") {
                Button("Один") { store.send(.setCompany(.solo)) }
                Button("Вдвоём") { store.send(.setCompany(.couple)) }
                Button("Всей семьёй") { store.send(.setCompany(.family)) }
                Button("С друзьями") { store.send(.setCompany(.friends)) }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(KP.fg80)
                .frame(width: 26, height: 26)
                .background(Circle().fill(KP.chip))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Добавить пожелание")
    }

    private var controls: some View {
        HStack(spacing: 14) {
            Picker("", selection: $store.pool) {
                Text(verbatim: "Своё").tag(PickPool.own)
                Text(verbatim: "Микс").tag(PickPool.mix)
                Text(verbatim: "Открытия").tag(PickPool.discover)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 260)

            Toggle(isOn: $store.highRating) {
                Text(verbatim: "КП или IMDb от 7")
                    .font(KP.font(12.5, .medium))
                    .foregroundStyle(KP.fg70)
            }
            .toggleStyle(.checkbox)

            Spacer()

            if store.isPicking {
                ProgressView().controlSize(.small)
            }
        }
    }

    // MARK: The pick

    @ViewBuilder
    private var pickArea: some View {
        if let question = store.result?.question, store.result?.main == nil || store.skips == 0 {
            questionView(question)
        }

        if let result = store.result, let main = result.main, let title = store.titles[main.titleId] {
            if result.showGrid {
                grid(result)
            } else {
                HStack(alignment: .top, spacing: 18) {
                    mainCard(main, title)
                    if !result.alternatives.isEmpty {
                        alternatives(result.alternatives)
                    }
                }
                .id(main.titleId)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            }
            if let prompt = store.ratePrompt {
                ratePrompt(prompt)
            }
            if result.suggestRefine {
                refine
            }
        } else if store.result != nil, !store.isPicking {
            nothing
        } else {
            HStack(alignment: .top, spacing: 18) {
                KPSkeleton(width: 132, height: 198, radius: KP.posterRadius)
                VStack(alignment: .leading, spacing: 10) {
                    KPSkeleton(width: 280, height: 22)
                    KPSkeleton(width: 220, height: 13)
                    KPSkeleton(width: 320, height: 13)
                    KPSkeleton(width: 180, height: 24, radius: 6)
                }
            }
        }
    }

    private func mainCard(_ main: Recommendation, _ title: TitleFeatures) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Button {
                store.send(.open(main.titleId))
            } label: {
                KPRemoteImage(url: title.poster, downsample: KP.cardPosterPixels())
                    .frame(width: 132, height: 198)
                    .clipShape(RoundedRectangle(cornerRadius: KP.posterRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Открыть страницу")

            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: title.name)
                    .font(KP.font(21, .heavy))
                    .foregroundStyle(KP.fg)
                    .lineLimit(2)
                if !title.recFacts.isEmpty {
                    Text(verbatim: title.recFacts.joined(separator: " · "))
                        .font(KP.font(12.5, .medium))
                        .foregroundStyle(KP.fg55)
                        .lineLimit(1)
                }
                if !main.reason.long.isEmpty {
                    Label {
                        Text(verbatim: main.reason.long)
                    } icon: {
                        Image(systemName: "sparkles")
                    }
                    .font(KP.font(13, .semibold))
                    .foregroundStyle(KP.sun)
                    .lineLimit(2)
                }
                if !title.recRatings.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(title.recRatings.enumerated()), id: \.offset) { _, rating in
                            KPRatingChip(source: rating.source, value: rating.value)
                        }
                    }
                }
                if let synopsis = title.synopsis, !synopsis.isEmpty {
                    Text(verbatim: synopsis)
                        .font(KP.font(12.5))
                        .foregroundStyle(KP.fg55)
                        .lineLimit(2)
                }

                Spacer(minLength: 2)

                HStack(spacing: 8) {
                    Button {
                        store.send(.watch(main.titleId))
                    } label: {
                        Label("Смотреть", systemImage: "play.fill")
                    }
                    .buttonStyle(KPPrimaryButtonStyle(size: 13))
                    .keyboardShortcut(.defaultAction)

                    Button {
                        store.send(.other)
                    } label: {
                        Label("Другое", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(KPSecondaryButtonStyle(size: 13))
                    .help("Пробел")

                    Menu {
                        Button("Не сегодня") { store.send(.notToday) }
                        Button("Не моё") { store.send(.notMe) }
                        Button("Уже смотрел") { store.send(.alreadySeen) }
                        Divider()
                        Button("Подробнее") { store.send(.open(main.titleId)) }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(KP.fg80)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(KP.chip))
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Не сегодня, не моё, уже смотрел")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func alternatives(_ items: [Recommendation]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: "Или:")
                .font(KP.font(12, .bold))
                .foregroundStyle(KP.fg55)
            ForEach(items.prefix(2), id: \.titleId) { item in
                if let title = store.titles[item.titleId] {
                    Button {
                        store.send(.promote(item.titleId), animation: .smooth(duration: 0.3))
                    } label: {
                        HStack(spacing: 10) {
                            KPRemoteImage(url: title.poster, downsample: KP.cardPosterPixels())
                                .frame(width: 52, height: 78)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(verbatim: title.name)
                                    .font(KP.font(12.5, .semibold))
                                    .foregroundStyle(KP.fg)
                                    .lineLimit(2)
                                Text(verbatim: item.reason.short.isEmpty ? (title.cardSubtitle ?? "") : item.reason.short)
                                    .font(KP.font(11.5, .medium))
                                    .foregroundStyle(KP.fg55)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(KP.chip.opacity(0.5)))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Сделать главным")
                }
            }
        }
        .frame(width: 210)
    }

    private func grid(_ result: PickResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: "Тогда из этих трёх:")
                .font(KP.font(13, .semibold))
                .foregroundStyle(KP.fg70)
            HStack(alignment: .top, spacing: 16) {
                ForEach(([result.main] + result.alternatives).compactMap { $0 }.prefix(3), id: \.titleId) { item in
                    if let title = store.titles[item.titleId] {
                        Button {
                            store.send(.watch(item.titleId))
                        } label: {
                            KPPosterCard(title: title.name, subtitle: item.reason.short.isEmpty ? title.cardSubtitle : item.reason.short, rating: title.cornerRating.map(KP.ratingText), ratingColor: title.cornerRating.map(KP.ratingColor) ?? .black.opacity(0.62), width: 132) {
                                KPRemoteImage(url: title.poster, downsample: KP.cardPosterPixels())
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Смотреть")
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func questionView(_ question: ClarifyingQuestion) -> some View {
        HStack(spacing: 10) {
            Text(verbatim: question.text)
                .font(KP.font(13.5, .semibold))
                .foregroundStyle(KP.fg)
            ForEach(question.options, id: \.label) { option in
                Button(option.label) {
                    store.send(.answer(option))
                }
                .buttonStyle(KPSecondaryButtonStyle(size: 13))
            }
        }
        .padding(.bottom, 4)
    }

    private func ratePrompt(_ prompt: PickForMeFeature.RatePrompt) -> some View {
        HStack(spacing: 8) {
            Text(verbatim: "Как вам «\(RecText.short(prompt.name, 30))»?")
                .font(KP.font(12.5, .semibold))
                .foregroundStyle(KP.fg70)
            Button("Не моё") { store.send(.rateSeen(-2)) }
            Button("Нравится") { store.send(.rateSeen(1)) }
            Button("Обожаю") { store.send(.rateSeen(2)) }
            Button("Позже") { store.send(.rateSeen(nil)) }
        }
        .buttonStyle(KPSecondaryButtonStyle(size: 13))
        .transition(.opacity)
    }

    private var refine: some View {
        HStack(spacing: 8) {
            Text(verbatim: "Уточнить настроение?")
                .font(KP.font(12.5, .semibold))
                .foregroundStyle(KP.fg70)
            ForEach([(Mood.laugh, "Посмеяться"), (.tension, "Напряжение"), (.cozy, "Уютное"), (.think, "Подумать")], id: \.0) { mood, label in
                Button(label) { store.send(.setMood(mood)) }
            }
        }
        .buttonStyle(KPSecondaryButtonStyle(size: 13))
    }

    private var nothing: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: "Ничего подходящего не нашлось")
                .font(KP.font(16, .bold))
                .foregroundStyle(KP.fg)
            Text(verbatim: store.chips.isEmpty
                ? "Каталог ещё собирается: откройте несколько тайтлов или оцените просмотренное — и попробуйте снова."
                : "Попробуйте убрать что-нибудь из «Понял так» или переключиться на «Микс».")
                .font(KP.font(13, .medium))
                .foregroundStyle(KP.fg55)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 160, alignment: .leading)
    }

    // MARK: Critique

    private var critiques: some View {
        HStack(spacing: 6) {
            critique("Полегче", .lighter)
            critique("Помрачнее", .darker)
            critique("Покороче", .shorter)
            critique("Поновее", .newer)
            critique("Постарше", .older)
            if let genres = store.main?.genres, !genres.isEmpty {
                Menu {
                    ForEach(genres, id: \.self) { genre in
                        Button(genre) {
                            store.send(.critique(.notAbout(genre), label: "Не \(genre.lowercased())"))
                        }
                    }
                } label: {
                    Text(verbatim: "Не про…")
                        .font(KP.font(12.5, .semibold))
                        .foregroundStyle(KP.fg80)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(Capsule().fill(KP.chip))
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            critique("Ещё такое же", .moreLikeThis)
            Spacer(minLength: 0)
        }
        .disabled(store.result?.main == nil)
    }

    private func critique(_ label: String, _ critique: Critique) -> some View {
        Button(label) {
            store.send(.critique(critique, label: label))
        }
        .buttonStyle(KPSecondaryButtonStyle(size: 12))
    }
}

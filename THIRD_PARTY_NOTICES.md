# Сторонние компоненты и лицензии

«КиноПохуй» распространяется под лицензией [MIT](LICENSE). В приложение входят чужие компоненты, у каждого своя лицензия. Ниже перечислены все. Те же тексты есть в приложении: **О программе → Лицензии**.

## Исходный проект

| Компонент | Лицензия | Где |
|---|---|---|
| Открытый код voidboost | MIT, Copyright (c) 2025 voidboost | Основа кода приложения |

«КиноПохуй» вырос из этого кода: его переименовали, переработали и сильно изменили. MIT требует сохранять уведомление об авторских правах во всех копиях. Поэтому строка «Copyright (c) 2025 voidboost» стоит в [LICENSE](LICENSE) рядом с нашей и показывается в окне «Лицензии».

## Встроено в приложение

### aria2 1.37.0

- Что это: загрузчик файлов. Приложение запускает его как отдельную программу (`aria2c`) для раздела «Загрузки».
- Файлы: `VideoLib/Resources/aria2c-arm64` и `VideoLib/Resources/aria2c-x86_64`, в готовом приложении `Contents/Resources/`.
- Лицензия: GNU General Public License версии 2 или (на ваш выбор) любой более поздней версии. Полный текст: [`VideoLib/Resources/Licenses/GPL-2.0.txt`](VideoLib/Resources/Licenses/GPL-2.0.txt).
- Авторы: Copyright (C) 2006, 2019 Tatsuhiro Tsujikawa и участники проекта aria2.
- Сборка: собран этим проектом скриптом [`scripts/aria2/build.sh`](scripts/aria2/build.sh) из официального архива `aria2-1.37.0.tar.xz` (SHA-256 `60a420ad7085eb616cb6e2bdf0a7206d68ff3d37fb5a956dc44242eb2f79b66b`), без изменений в коде. Использует только системные библиотеки macOS: AppleTLS (Security.framework) и libz. BitTorrent, Metalink, SFTP, XML-RPC и WebSocket выключены, сторонних библиотек внутри нет. В самом коде aria2 (`src/util.cc`) есть UTF-8-декодер Бьёрна Хёрманна под MIT: [`VideoLib/Resources/Licenses/aria2-utf8-decoder-MIT.txt`](VideoLib/Resources/Licenses/aria2-utf8-decoder-MIT.txt).
- Исходный код: тот же архив `aria2-1.37.0.tar.xz` приложен к каждому релизу на GitHub (раздел Releases этого репозитория) и лежит у проекта aria2: <https://github.com/aria2/aria2/releases/tag/release-1.37.0>. Сценарий сборки — `scripts/aria2/build.sh`.
- Контрольные суммы SHA-256 собранных файлов:
  - `aria2c-arm64`: `5501a80a9f0103e931c6e8ede4b41c03c00ab0fbbc9ce5db519cde53c8968f58`
  - `aria2c-x86_64`: `9c452304bb577c4b68bcf5663d128ca0989a6182121dabd95bcb1cca311a4656`

Код «КиноПохуй» с aria2 не компонуется: он общается с отдельным процессом `aria2c` по локальному JSON-RPC. Поэтому лицензия MIT основного кода не меняется.

### Inter

- Что это: шрифт интерфейса.
- Файлы: `VideoLib/Resources/Fonts/InterVariable.ttf`.
- Лицензия: SIL Open Font License 1.1, Copyright (c) 2016 The Inter Project Authors. Полный текст: [`VideoLib/Resources/Fonts/Inter-OFL.txt`](VideoLib/Resources/Fonts/Inter-OFL.txt).
- Источник: <https://github.com/rsms/inter>

### LicenseList

- Что это: код окна «Лицензии», который при сборке собирает тексты лицензий всех пакетов Swift. Лежит в папке `LicensesList/`.
- Основан на [cybozu/LicenseList](https://github.com/cybozu/LicenseList) и изменён для этого проекта.
- Лицензия: MIT, Copyright (c) 2022 Cybozu. Полный текст: [`LicensesList/LICENSE`](LicensesList/LICENSE).

## Пакеты Swift

Пакеты подключаются через Swift Package Manager, точные версии зафиксированы в `VideoLib.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`. Их исходники в репозиторий не входят. Полные тексты лицензий окно «Лицензии» берёт прямо из скачанных пакетов во время сборки.

**Входят в приложение**

| Пакет | Версия | Лицензия |
|---|---|---|
| [Alamofire](https://github.com/Alamofire/Alamofire) | 5.12.2 | MIT |
| [Defaults](https://github.com/sindresorhus/Defaults) | 9.0.9 | MIT |
| [GRDB.swift](https://github.com/groue/GRDB.swift) | 7.11.1 | MIT |
| [Kingfisher](https://github.com/onevcat/Kingfisher) | 8.14.0 | MIT |
| [LRUCache](https://github.com/nicklockwood/LRUCache) | 1.3.0 | MIT |
| [Pow](https://github.com/EmergeTools/Pow) | 1.0.6 | MIT |
| [Sparkle](https://github.com/sparkle-project/Sparkle) | 2.10.1 | MIT и лицензии включённых в него компонентов (см. его LICENSE) |
| [SwiftSoup](https://github.com/scinfu/SwiftSoup) | 2.14.3 | MIT |
| [SwiftUI-Flow](https://github.com/tevelee/SwiftUI-Flow) | 3.5.5 | MIT |
| [sqlite-data](https://github.com/pointfreeco/sqlite-data) | 1.12.1 | MIT |
| [swift-composable-architecture](https://github.com/pointfreeco/swift-composable-architecture) | 1.26.2 | MIT |
| [swift-dependencies](https://github.com/pointfreeco/swift-dependencies) | 1.17.1 | MIT |
| [swift-sharing](https://github.com/pointfreeco/swift-sharing) | 2.10.1 | MIT |
| [swift-structured-queries](https://github.com/pointfreeco/swift-structured-queries) | 0.39.2 | MIT |
| [swift-navigation](https://github.com/pointfreeco/swift-navigation) | 2.11.2 | MIT |
| [swift-perception](https://github.com/pointfreeco/swift-perception) | 2.0.12 | MIT |
| [swift-case-paths](https://github.com/pointfreeco/swift-case-paths) | 1.10.0 | MIT |
| [swift-clocks](https://github.com/pointfreeco/swift-clocks) | 1.1.1 | MIT |
| [combine-schedulers](https://github.com/pointfreeco/combine-schedulers) | 1.2.2 | MIT |
| [swift-concurrency-extras](https://github.com/pointfreeco/swift-concurrency-extras) | 1.4.3 | MIT |
| [swift-custom-dump](https://github.com/pointfreeco/swift-custom-dump) | 1.7.3 | MIT |
| [swift-identified-collections](https://github.com/pointfreeco/swift-identified-collections) | 1.1.1 | MIT |
| [swift-issue-reporting](https://github.com/pointfreeco/swift-issue-reporting) | 2.1.2 | MIT |
| [swift-collections](https://github.com/apple/swift-collections) | 1.7.5 | Apache 2.0 с Runtime Library Exception |
| [swift-algorithms](https://github.com/apple/swift-algorithms) | 1.2.1 | Apache 2.0 с Runtime Library Exception |
| [swift-numerics](https://github.com/apple/swift-numerics) | 1.1.1 | Apache 2.0 с Runtime Library Exception |

**Скачиваются при сборке, но в приложение не попадают** (макросы и тестовые зависимости других пакетов)

| Пакет | Версия | Лицензия |
|---|---|---|
| [swift-syntax](https://github.com/swiftlang/swift-syntax) | 604.0.0 | Apache 2.0 с Runtime Library Exception |
| [swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing) | 1.19.7 | MIT |

Если вы меняете зависимости, обновите эту таблицу. Окно «Лицензии» обновится само при следующей сборке.

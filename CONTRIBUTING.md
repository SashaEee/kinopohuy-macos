# Как помочь проекту

Спасибо, что заглянули! Ошибки и идеи присылайте через [Issues](https://github.com/SashaEee/kinopohuy-macos/issues/new/choose), код — через pull request.

## Сборка

- Для сборки: macOS 15.6 или новее, Xcode 26 или новее (проверено на Xcode 27.2). Готовое приложение работает на macOS 15 и новее. Аккаунт разработчика Apple не нужен.
- Проект: `VideoLib.xcodeproj`, схема `VideoLib`. `VideoLib` — внутреннее имя, приложение называется «КиноПохуй» (`KinoPohuy.app`, bundle id `com.kinopohuy.mac`).
- Из командной строки:

  ```bash
  ./build-mac.sh --no-launch    # Release для этого Mac, установка в /Applications/КиноПохуй.app
  ```

  Или вручную, без подписи разработчика:

  ```bash
  xcodebuild -project VideoLib.xcodeproj -scheme VideoLib -configuration Debug \
    CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
    -skipMacroValidation -skipPackagePluginValidation build
  ```

- При первом запуске приложение попросит адрес сайта. Он хранится только в настройках на вашем Mac.

## Как устроен код

- Swift 6, SwiftUI, [The Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture).
- `VideoLib/Core` — общие вещи: адрес сайта, ссылки проекта (`AppLinks.swift`), загрузки, обновления.
- `VideoLib/Data` — сеть и разбор страниц сайта, `VideoLib/Domain` — модели, протоколы репозиториев и сценарии (use cases).
- `VideoLib/Presentations` — экраны. Общий вид: `Presentations/Theme` (цвета `KP`, шрифт `KP.font`, размеры `KPMetrics`, кнопки и листы `KP…`).

## Правила

- **Никаких адресов сайта в коде, коммитах, скриншотах и Issues.** Адрес вводит пользователь, в репозитории его быть не должно. По умолчанию в коде стоит заглушка `https://example.invalid/`.
- Не добавляйте аналитику, трекеры и любой сбор данных.
- Тексты интерфейса — на русском. Новые экраны собирайте из компонентов `Presentations/Theme`, чтобы приложение выглядело цельно.
- Комментарии к коду короткие: что видит пользователь и почему так.
- Один pull request — одна задача. Перед отправкой убедитесь, что проект собирается без ошибок и новых предупреждений.
- Меняете зависимости — обновите [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Релизы

Релизы собирает мейнтейнер скриптом `scripts/release.sh ВЕРСИЯ`: universal-сборка, DMG, архив для Sparkle и подпись ленты обновлений. Описание шагов — в начале скрипта. Встроенный загрузчик `aria2c` собирается отдельно скриптом `scripts/aria2/build.sh` из официального архива aria2; чужие готовые сборки в репозиторий не кладём.

Отправляя код, вы соглашаетесь, что он распространяется под лицензией [MIT](LICENSE).

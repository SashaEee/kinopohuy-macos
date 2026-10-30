import Foundation

/// The site's address as the user types it: cleaned up to `https://host/` and asked once whether it answers, before
/// it's saved (the first-run screen and Settings → «Основное»).
enum SiteAddressCheck {
    enum Outcome: Equatable, Sendable {
        case reachable
        /// Why it didn't answer, in Russian, with what to try.
        case failed(String)
    }

    /// «site.example», «https://site.example/films/» → «https://site.example/»; nil when it isn't a web address (or
    /// is the built-in placeholder). The scheme the user typed stays; https when there was none.
    static func normalize(_ input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if !text.contains("://") {
            text = "https://" + text
        }

        guard let components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = components.host?.lowercased(), host.isValidHost,
              !SiteAddress.isPlaceholder(host: host)
        else { return nil }

        var clean = URLComponents()
        clean.scheme = scheme
        clean.host = host
        clean.port = components.port
        clean.path = "/"

        return clean.url
    }

    /// One plain request to the address (headers only, nothing is downloaded or remembered): any answer short of a
    /// server error counts, since the site may turn away an unknown client with 403 yet work in the app. A redirect to
    /// a different host is reported, so the user can check the address.
    static func check(_ url: URL, userAgent: String) async -> Outcome {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 10)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }

        do {
            let (bytes, response) = try await session.bytes(for: request)
            bytes.task.cancel()

            guard let http = response as? HTTPURLResponse else {
                return .failed("По этому адресу отвечает не сайт. Проверьте адрес.")
            }

            if let host = url.host()?.lowercased(),
               let finalHost = http.url?.host()?.lowercased(),
               finalHost != host, !finalHost.hasSuffix("." + host), !host.hasSuffix("." + finalHost)
            {
                return .failed("Адрес ведёт на другой сайт (\(finalHost)). Проверьте адрес.")
            }

            if http.statusCode >= 500 {
                return .failed("Сайт ответил ошибкой \(http.statusCode). Попробуйте позже.")
            }

            return .reachable
        } catch let error as URLError {
            return .failed(message(for: error))
        } catch {
            return .failed("Не удалось открыть сайт. Проверьте адрес.")
        }
    }

    private static func message(for error: URLError) -> String {
        switch error.code {
        case .cannotFindHost, .dnsLookupFailed:
            "Такой адрес не найден. Проверьте, нет ли опечатки."
        case .cannotConnectToHost, .networkConnectionLost, .secureConnectionFailed:
            "Не удалось подключиться к сайту по этому адресу. Проверьте адрес и подключение к интернету."
        case .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot:
            "У сайта недействительный сертификат. Проверьте адрес."
        case .timedOut:
            "Сайт слишком долго не отвечает. Попробуйте ещё раз позже."
        case .notConnectedToInternet, .dataNotAllowed:
            "Нет подключения к интернету."
        default:
            "Не удалось открыть сайт. Проверьте адрес."
        }
    }
}

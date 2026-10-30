import Alamofire
import Foundation

extension Error {
    /// What to tell the viewer, in Russian, with what to do about it. The site's own explanations (already
    /// Russian) pass through; a system message in English becomes a plain sentence.
    var kpMessage: String {
        var underlying: Error = self
        if let afError = self as? AFError, let inner = afError.underlyingError {
            underlying = inner
        }
        if let urlError = underlying as? URLError {
            switch urlError.code {
            case .cannotFindHost, .dnsLookupFailed, .cannotConnectToHost, .secureConnectionFailed, .badServerResponse:
                return "Сайт не открывается по этому адресу. Проверьте адрес в настройках (⌘,)."
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                // An unreachable address shows up this way too, not only a dead network.
                return "Не удалось соединиться с сайтом. Проверьте интернет или адрес сайта в настройках (⌘,)."
            case .timedOut:
                return "Сайт долго не отвечает. Попробуйте ещё раз."
            default:
                break
            }
        }
        let text = (underlying as NSError).localizedDescription
        return text.range(of: "[а-яА-ЯёЁ]", options: .regularExpression) != nil ? text : "Что-то пошло не так. Попробуйте ещё раз."
    }
}

import Alamofire
import Defaults
import Foundation

final class CustomInterceptor: RequestInterceptor {
    /// Until the user enters the site's address, a request to the built-in placeholder fails at once (with «Укажите
    /// адрес сайта…») instead of going out.
    func adapt(_ urlRequest: URLRequest, for _: Session, completion: @escaping (Result<URLRequest, any Error>) -> Void) {
        if SiteAddress.isPlaceholder(host: urlRequest.url?.host()) {
            completion(.failure(VideoLibError.siteNotConfigured))
        } else {
            completion(.success(urlRequest))
        }
    }

    func retry(_ request: Request, for _: Session, dueTo _: any Error, completion: @escaping (RetryResult) -> Void) {
        if request.retryCount < 1, request.response?.statusCode == 403 {
            Defaults[.useHeaders].toggle()

            completion(.retry)
        } else {
            completion(.doNotRetry)
        }
    }
}

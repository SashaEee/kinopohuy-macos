import Alamofire
import AVFoundation
import Defaults
import Dependencies
import Foundation
import SwiftSoup

extension SwiftSoup.Document {
    func checker() throws -> SwiftSoup.Document {
        let body = try body().orThrow()

        guard try body.select("#check-form").isEmpty() else {
            throw VideoLibError.loginRequired(Defaults[.mirror])
        }

        guard try !body.select("#wrapper").isEmpty() else {
            throw VideoLibError.mirrorBanned(Defaults[.mirror])
        }

        Defaults[.isUserPremium] = try Int(body.select(".b-tophead-premuser b").text().trimmingCharacters(in: .decimalDigits.inverted))

        return self
    }
}

extension String {
    var id: String? {
        URL(string: self)?.id
    }

    var cleanPath: String? {
        URL(string: self)?.cleanPath
    }

    var isNumber: Bool {
        CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: self))
    }

    private static let shortNumberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.decimalSeparator = "."
        formatter.allowsFloats = true
        formatter.minimumIntegerDigits = 1
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter
    }()

    private static let shortNumberAbbreviations: [(threshold: Double, suffix: String)] = [
        (1_000_000_000, "B"),
        (1_000_000, "M"),
        (1000, "K"),
    ]

    var shortNumber: String {
        guard let number = Int(String(unicodeScalars.filter(CharacterSet.decimalDigits.contains))) else {
            return "0"
        }

        let value = Double(number)
        let (divisor, suffix) = Self.shortNumberAbbreviations.first { value >= $0.threshold } ?? (1, "")

        return (Self.shortNumberFormatter.string(from: NSNumber(value: value / divisor)) ?? "0") + suffix
    }

    func page(_ page: Int) -> String {
        if page > 1 {
            appending("page/\(page)/")
        } else {
            self
        }
    }

    func substringBefore(_ separator: String, includeSeparator: Bool = false) -> String {
        if let range = range(of: separator) {
            if includeSeparator {
                String(self[..<range.upperBound])
            } else {
                String(self[..<range.lowerBound])
            }
        } else {
            self
        }
    }

    func substringBeforeLast(_ separator: String, includeSeparator: Bool = false) -> String {
        if let range = range(of: separator, options: .backwards) {
            if includeSeparator {
                String(self[..<range.upperBound])
            } else {
                String(self[..<range.lowerBound])
            }
        } else {
            self
        }
    }

    func substringAfter(_ separator: String, includeSeparator: Bool = false) -> String {
        if let range = range(of: separator) {
            if includeSeparator {
                String(self[range.lowerBound...])
            } else {
                String(self[range.upperBound...])
            }
        } else {
            self
        }
    }

    func substringAfterLast(_ separator: String, includeSeparator: Bool = false) -> String {
        if let range = range(of: separator, options: .backwards) {
            if includeSeparator {
                String(self[range.lowerBound...])
            } else {
                String(self[range.upperBound...])
            }
        } else {
            self
        }
    }
}

extension Optional {
    func orThrow(
        functionName: String = #function,
        lineNumber: Int = #line,
        columnNumber: Int = #column
    ) throws -> Wrapped {
        guard let self else {
            throw VideoLibError.null(functionName, lineNumber, columnNumber)
        }

        return self
    }
}

func handleError(_ error: Error) -> Error {
    @Dependency(\.appRouter) var appRouter

    if error is CancellationError || error.asAFError?.isExplicitlyCancelledError == true {
        return CancellationError()
    } else if let notConfigured = error.asAFError?.underlyingError as? VideoLibError, case .siteNotConfigured = notConfigured {
        return notConfigured
    } else if let avError = error as? AVError {
        logError(avError)

        return avError
    } else if let afError = error.asAFError {
        if afError.responseCode != nil || afError.isSessionTaskError {
            if let code = afError.responseCode, code == 403 {
                appRouter.present(.signIn)

                return VideoLibError.loginRequired(Defaults[.mirror])
            }

            return afError
        }

        logError(afError)

        return afError
    } else if let videolibError = error as? VideoLibError {
        if case .mirrorBanned = videolibError {
            return videolibError
        } else if case .loginRequired = videolibError {
            appRouter.present(.signIn)

            return videolibError
        } else if case .site = videolibError {
            return videolibError
        } else if case .siteNotConfigured = videolibError {
            return videolibError
        }

        logError(videolibError)

        return videolibError
    } else if let exception = error as? Exception, case let .Error(type, message) = exception {
        let videolibError = VideoLibError.swiftsoup("\(type)", message)

        logError(videolibError)

        return videolibError
    }

    return error
}

/// Unexpected errors go to the Xcode console in debug builds; release builds keep them on this Mac only.
private func logError(_ error: Error) {
    #if DEBUG
        print(error)
    #endif
}

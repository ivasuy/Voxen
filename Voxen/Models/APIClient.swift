import Foundation

struct APIHTTPError: LocalizedError {
    let service: String
    let statusCode: Int
    let retryAt: Date?

    init(service: String, response: HTTPURLResponse, now: Date = Date()) {
        self.service = service
        statusCode = response.statusCode
        var dates: [Date] = []
        if let value = response.value(forHTTPHeaderField: "Retry-After") {
            if let seconds = Double(value), seconds.isFinite, seconds >= 0 {
                dates.append(now.addingTimeInterval(seconds))
            } else {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
                if let date = formatter.date(from: value) { dates.append(date) }
            }
        }
        if let value = response.value(forHTTPHeaderField: "X-RateLimit-Reset"),
           let epoch = Double(value), epoch.isFinite, epoch > 0 {
            dates.append(Date(timeIntervalSince1970: epoch > 100_000_000_000 ? epoch / 1000 : epoch))
        }
        retryAt = dates.filter { $0 > now }.max()
    }

    var errorDescription: String? {
        let hint: String
        switch statusCode {
        case 401, 403: hint = "Check the API key and account access in Settings."
        case 402: hint = "The account balance or key credit limit is blocking requests, even to free models. Check your provider account."
        case 404 where service == "OpenRouter": hint = "This model is unavailable or has no providers matching the price or privacy policy. Choose another model in Settings."
        case 429: hint = "Rate limit reached. Wait before trying again."
        default: hint = "Check the model setting and service availability, then try again."
        }
        return "\(service) error (HTTP \(statusCode)). \(hint)"
    }
}

struct APIClient {
    let session: URLSession

    init(session: URLSession? = nil) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.urlCache = nil
        config.httpCookieStorage = nil
        self.session = session ?? URLSession(configuration: config)
    }

    func send(_ request: URLRequest, service: String) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw RouterError.message("\(service) returned an invalid response.")
            }
            guard (200..<300).contains(response.statusCode) else {
                // Do not surface raw provider bodies: they can echo private input.
                throw APIHTTPError(service: service, response: response)
            }
            return data
        } catch is CancellationError { throw CancellationError() }
        catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw RouterError.message("\(service) connection failed or timed out. Check your network and retry.")
        }
    }
}

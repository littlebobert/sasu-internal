import Foundation
import OSLog

struct BackendClient {
    private static let logger = Logger(subsystem: "dev.sasu.Sasu", category: "BackendClient")
    private static let defaultSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 90
        return URLSession(configuration: configuration)
    }()

    private let session: URLSession

    init(session: URLSession = BackendClient.defaultSession) {
        self.session = session
    }

    func redeemInvite(code: String, backendBaseURL: URL) async throws -> InviteRedemption {
        let endpoint = backendBaseURL.appendingPathComponent("v1/invites/redeem")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(InviteRedemptionRequest(code: code))

        Self.logger.info("Redeeming invite with backend. endpoint=\(endpoint.absoluteString, privacy: .public)")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendError.invalidResponse
        }

        let decoder = JSONDecoder()
        if !(200..<300).contains(httpResponse.statusCode) {
            let message = Self.errorMessage(from: data, decoder: decoder)
            throw BackendError.apiError(statusCode: httpResponse.statusCode, message: message)
        }

        do {
            let body = try decoder.decode(InviteRedemptionResponse.self, from: data)
            return InviteRedemption(accessToken: body.accessToken, label: body.label)
        } catch {
            throw BackendError.decodingFailed(error.localizedDescription)
        }
    }

    private static func errorMessage(from data: Data, decoder: JSONDecoder) -> String {
        if let response = try? decoder.decode(BackendErrorResponse.self, from: data), !response.detail.isEmpty {
            return response.detail
        }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown backend error."
    }
}

struct InviteRedemption {
    let accessToken: String
    let label: String
}

private struct InviteRedemptionRequest: Encodable {
    let code: String
}

private struct InviteRedemptionResponse: Decodable {
    let accessToken: String
    let label: String

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case label
    }
}

struct BackendErrorResponse: Decodable {
    let detail: String
}

enum BackendError: LocalizedError {
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return String(localized: "Sasu's invite server returned an invalid response.")
        case .apiError(let statusCode, let message):
            if statusCode == 401 {
                return String(localized: "This invite link is invalid, expired, or has already been used.")
            }
            return String(localized: "Sasu's invite server returned HTTP \(statusCode): \(message)")
        case .decodingFailed(let message):
            return String(localized: "Sasu could not read the invite server response: \(message).")
        }
    }
}

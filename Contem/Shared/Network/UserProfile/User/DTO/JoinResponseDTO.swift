import Foundation

struct JoinResponseDTO: Decodable, Sendable {
    let userId: String
    let nick: String
    let accessToken: String
    let refreshToken: String

    private enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case nick
        case accessToken
        case refreshToken
    }
}

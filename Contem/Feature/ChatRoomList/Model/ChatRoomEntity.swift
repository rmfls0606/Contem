import Foundation


struct ChatRoomListEntity {
    let roomList: [ChatRoomEntity]
    
    init(from dto: ChatRoomResponseListDTO) {
        self.roomList = dto.data.map { ChatRoomEntity(from: $0) }
    }
}

struct ChatRoomEntity: Identifiable {
    let id: String
    let partnerId: String
    let partnerName: String
    let partnerProfileImage: URL?
    let lastChatContent: String
    let lastMessageTime: Date

    init(
        id: String,
        partnerId: String,
        partnerName: String,
        partnerProfileImage: URL?,
        lastChatContent: String,
        lastMessageTime: Date
    ) {
        self.id = id
        self.partnerId = partnerId
        self.partnerName = partnerName
        self.partnerProfileImage = partnerProfileImage
        self.lastChatContent = lastChatContent
        self.lastMessageTime = lastMessageTime
    }

    init(from dto: ChatRoomDTO) {
        self.id = dto.roomId
        self.lastChatContent = dto.lastChat?.content ?? ""
        self.lastMessageTime = ISO8601DateFormatter().date(from: dto.updatedAt) ?? Date()

        let myId = (try? KeychainManager.shared.read(.userId)) ?? ""
        if let partner = dto.participants.first(where: { $0.userId != myId }) {
            self.partnerName = partner.nick
            self.partnerId = partner.userId
            if let urlString = partner.profileImage {
                if urlString.hasPrefix("mock://") || urlString.hasPrefix("file://") {
                    self.partnerProfileImage = URL(string: urlString)
                } else {
                    self.partnerProfileImage = URL(string: APIConfig.baseURL + urlString)
                }
            } else {
                self.partnerProfileImage = nil
            }
        } else {
            self.partnerName = dto.participants.first?.nick ?? "알 수 없음"
            self.partnerProfileImage = nil
            self.partnerId = ""
        }
    }
}

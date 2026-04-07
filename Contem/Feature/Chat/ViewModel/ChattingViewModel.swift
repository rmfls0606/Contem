//
//  ChattingViewModel.swift
//  Contem
//
//  Created by 이상민 on 11/27/25.
//

import Foundation
import Combine
import Realm
import RealmSwift

private actor PendingChatBuffer {
    private var isInitialSyncCompleted = false
    private var bufferedMessages: [String: ChatResponseDTO] = [:]

    func reset() {
        isInitialSyncCompleted = false
        bufferedMessages.removeAll()
    }

    func buffer(_ message: ChatResponseDTO) {
        bufferedMessages[message.chatId] = message
    }

    func shouldBuffer() -> Bool {
        !isInitialSyncCompleted
    }

    func completeInitialSync() -> [ChatResponseDTO] {
        isInitialSyncCompleted = true
        let pending = bufferedMessages.values.sorted { $0.createdAt < $1.createdAt }
        bufferedMessages.removeAll()
        return pending
    }
}

final class ChattingViewModel: ViewModelType {
    private var coordinator: AppCoordinator
    
    //MARK: -  Properties
    var cancellables = Set<AnyCancellable>()
    
    var input = Input()
    @Published var output = Output()
    
    struct Input {
        let appear = PassthroughSubject<Void, Never>()
        let sendMessage = PassthroughSubject<(String, [Data]?), Never>()
        let dismissButtonTapped = PassthroughSubject<Void, Never>()
    }
    
    struct Output {
        var messages: Results<ChatMessageObject>?
        var currentUserId: String?
        var opponentNickname: String?
        var opponentProfileImage: URL?
        var error: Error?
    }
    
    private let opponentId: String
    private var roomId: String?
    private var notificationToken: NotificationToken?
    private lazy var currentUserId = (try? KeychainManager.shared.read(.userId)) ?? ""
    private let pendingChatBuffer = PendingChatBuffer()

    init(opponentId: String, coordinator: AppCoordinator) {
        self.coordinator = coordinator
        self.opponentId = opponentId
        transform()
    }
    
    deinit {
        notificationToken?.invalidate()
        ChatSocketService.shared.disconnect()
    }
    
    func transform() {
        input.appear
            .sink { [weak self] in
                self?.initializeChatSession()
            }
            .store(in: &cancellables)
        
        input.sendMessage
            .sink { [weak self] (content, filesData) in
                self?.sendMessage(content: content, filesData: filesData)
            }
            .store(in: &cancellables)
        
        input.dismissButtonTapped
            .withUnretained(self)
            .sink { owner, _ in
                ChatSocketService.shared.disconnect()
                owner.coordinator.pop()
            }.store(in: &cancellables)
    }
    
    private func initializeChatSession() {
        Task {
            await pendingChatBuffer.reset()

            do {
                let chatRoomResponse = try await NetworkService.shared.callRequest(
                    router: ChatRequest.chatRoom(opponentId: opponentId),
                    type: ChatRoomDTO.self
                )

                let roomId = chatRoomResponse.roomId
                self.roomId = roomId
                let messages = RealmManager.shared.getMessages(for: roomId)
                let latestLocalMessageDate = messages.last?.createdAt
                let cursor = latestLocalMessageDate.map(Self.isoString) ?? ""
                let opponentProfile = chatRoomResponse.participants.first { $0.userId != self.currentUserId }
                let profileURL = Self.resolveProfileURL(from: opponentProfile?.profileImage)

                await MainActor.run {
                    self.output.currentUserId = self.currentUserId
                    self.output.opponentNickname = opponentProfile?.nick
                    self.output.opponentProfileImage = profileURL
                    self.output.messages = messages
                }

                notificationToken?.invalidate()
                notificationToken = messages.observe { [weak self] _ in
                    self?.objectWillChange.send()
                }

                try await configureSocket(roomId: roomId)

                let historyResponse = try await NetworkService.shared.callRequest(
                    router: ChatRequest.fetchMessage(roomId: roomId, cursor_date: cursor),
                    type: ChatListDTO.self
                )

                let realmObjects = historyResponse.data.map { $0.toRealmObject() }
                if !realmObjects.isEmpty {
                    try RealmManager.shared.write(realmObjects, update: .modified)
                }

                let bufferedMessages = await pendingChatBuffer.completeInitialSync()
                if !bufferedMessages.isEmpty {
                    let bufferedRealmObjects = bufferedMessages.map { $0.toRealmObject() }
                    try RealmManager.shared.write(bufferedRealmObjects, update: .modified)
                }
            } catch {
                await MainActor.run {
                    self.output.error = error
                }
            }
        }
    }

    private func configureSocket(roomId: String) async throws {
        ChatSocketService.shared.onChatReceived = { [weak self] result in
            guard let self else { return }

            Task {
                switch result {
                case .success(let response):
                    do {
                        if await self.pendingChatBuffer.shouldBuffer() {
                            await self.pendingChatBuffer.buffer(response)
                        } else {
                            try RealmManager.shared.write(response.toRealmObject(), update: .modified)
                        }
                    } catch {
                        await MainActor.run {
                            self.output.error = error
                        }
                    }
                case .failure(let error):
                    await MainActor.run {
                        self.output.error = error
                    }
                }
            }
        }

        ChatSocketService.shared.onSocketError = { [weak self] error in
            Task { @MainActor in
                self?.output.error = error
            }
        }

        guard let token = await TokenStorage.shared.getAccessToken(), !token.isEmpty else { return }
        try ChatSocketService.shared.connect(roomId: roomId, token: token)
    }

    private func sendMessage(content: String, filesData: [Data]?) {
        guard let roomId = roomId else { return }

        Task {
            do {
                let uploadedFiles = try await uploadFilesIfNeeded(roomId: roomId, filesData: filesData)
                let response = try await NetworkService.shared.callRequest(
                    router: ChatRequest.sendMessage(
                        roomId: roomId,
                        content: content,
                        files: uploadedFiles
                    ),
                    type: ChatResponseDTO.self
                )
                try RealmManager.shared.write(response.toRealmObject(), update: .modified)
            } catch {
                await MainActor.run {
                    self.output.error = error
                }
            }
        }
    }

    private func uploadFilesIfNeeded(roomId: String, filesData: [Data]?) async throws -> [String] {
        guard let filesData, !filesData.isEmpty else { return [] }
        let response = try await NetworkService.shared.callRequest(
            router: ChatRequest.chatFiles(roomId: roomId, files: filesData),
            type: PostFilesDTO.self
        )
        return response.files
    }

    private static func isoString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func resolveProfileURL(from profileImage: String?) -> URL? {
        guard let profileImage, !profileImage.isEmpty else { return nil }
        if profileImage.hasPrefix("mock://") || profileImage.hasPrefix("file://") || profileImage.hasPrefix("http://") || profileImage.hasPrefix("https://") {
            return URL(string: profileImage)
        }
        return URL(string: APIConfig.baseURL + "/" + profileImage)
    }
}

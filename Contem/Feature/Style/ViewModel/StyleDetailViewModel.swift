//
//  StyleDetailViewModel.swift
//  Contem
//
//  Created by 이상민 on 11/17/25.
//

import Foundation
import Combine

final class StyleDetailViewModel: ViewModelType{
    
    //MARK: - Properties
    var cancellables = Set<AnyCancellable>()
    
    var input = Input()
    @Published var output: Output = Output()
    
    struct Input{
        let appear = PassthroughSubject<Void, Never>()
        let profileTapped = PassthroughSubject<Void,Never>()
        let likebuttonTapped = PassthroughSubject<Void,Never>()
        let commentButtonTapped = PassthroughSubject<Void, Never>()
        let shopTheLookTapped = PassthroughSubject<String, Never>()
        let dismissButtonTapped = PassthroughSubject<Void, Never>()
    }
    
    struct Output{
        var style: StyleEntity?
        var isStyleLiked: Bool = false
        var isLoading: Bool = false
        var errorMessage: String?
        var tags: [Int: [StyleTag]] = [:]
        var shopTheLookProducts: [StyleTag] = []
    }
    
    private let postId: String
    private weak var coordinator: AppCoordinator?
    private var currentUserId: String? //캐싱된 UserID
    private var likeDebounceTask: Task<Void, Never>?
    private var latestLikeRequestID = 0
    private var confirmedIsLiked = false

    init(postId: String, coordinator: AppCoordinator) {
        self.postId = postId
        self.coordinator = coordinator
        Task{
            self.currentUserId = await TokenStorage.shared.getUserId()
        }

        transform()
    }

    func transform() {
        input.appear
            .sink { [weak self] _ in
                guard let self else { return }
                Task{
                    await self.fetchStyleDetail()
                }
            }
            .store(in: &cancellables)
        
        input.profileTapped
            .sink { [weak self] _ in
                guard let self,
                let userId = output.style?.creator.userId else { return }
                self.coordinator?.push(.profile(userId: userId))
            }
            .store(in: &cancellables)
        
        input.likebuttonTapped
            .sink { [weak self] _ in
                guard let self else { return }
                self.handleLikeTap()
            }
            .store(in: &cancellables)
        
        input.commentButtonTapped
            .sink { [weak self] _ in
                guard let self else { return }
                self.coordinator?.present(sheet: .comment(postId: self.postId))
            }.store(in: &cancellables)
        
        input.shopTheLookTapped
            .sink { [weak self] postId in
                guard let self else { return }
                self.coordinator?.push(.shoppingDetail(id: postId))
            }
            .store(in: &cancellables)
        
        input.dismissButtonTapped
            .withUnretained(self)
            .sink { owner, _ in
                owner.coordinator?.pop()
            }.store(in: &cancellables)
    }
    
    //MARK: - Functions
    private func handleLikeTap() {
        guard let userId = currentUserId else {
            output.errorMessage = "로그인 후 이용 가능합니다."
            return
        }

        self.handleOptimisticLike()

        guard let isLiked = output.style?.likes.contains(userId) else { return }

        latestLikeRequestID += 1
        let requestID = latestLikeRequestID

        likeDebounceTask?.cancel()
        likeDebounceTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(300))
            } catch {
                return
            }

            guard let self else { return }
            await self.postLikeToServer(postId: self.postId, isLiked: isLiked, requestID: requestID)
        }
    }

    //좋아요 UI 즉시 업데이트(낙관적 업데이트)
    private func handleOptimisticLike(){
        guard let userId = currentUserId,
              var style = output.style else {
            output.errorMessage = "로그인 후 이용 가능합니다."
            return
        }
        
        style.toggleLike(userId: userId)
        
        output.style = style
        output.isStyleLiked.toggle()
    }
    
    //롤백 함수
    private func rollbackLikeState(){
        guard let userId = currentUserId,
              var style = output.style else { return }
        let currentlyLiked = style.likes.contains(userId)
        guard currentlyLiked != confirmedIsLiked else { return }
        style.toggleLike(userId: userId)
        output.style = style
        output.isStyleLiked = confirmedIsLiked
    }
    
    //좋아요 서버 요청
    private func postLikeToServer(postId: String, isLiked: Bool, requestID: Int) async{
        do{
            _ = try await NetworkService.shared.callRequest(router: PostRequest.like(postId: postId, isLiked: isLiked), type: PostLikeDTO.self)
            guard latestLikeRequestID == requestID else { return }
            confirmedIsLiked = isLiked
        }catch let error as NetworkError{
            guard latestLikeRequestID == requestID,
                  let userId = currentUserId,
                  let style = output.style,
                  style.likes.contains(userId) == isLiked else {
                return
            }

            self.rollbackLikeState()
            
            if case .statusCodeError(let type) = error {
                if type == .refreshTokenExpired() || type == .forbidden() || type == .unauthorized(){
                    currentUserId = nil
                }
            }
            
            output.errorMessage = error.errorDescription
        }catch{
            guard latestLikeRequestID == requestID,
                  let userId = currentUserId,
                  let style = output.style,
                  style.likes.contains(userId) == isLiked else {
                return
            }

            self.rollbackLikeState()
            output.errorMessage = NetworkError.unknown(error).errorDescription
        }
    }

    private func preParseAllTags(entity: StyleEntity) {
        let values = [
            entity.value1,
            entity.value2,
            entity.value3,
            entity.value4,
            entity.value5
        ]

        var dict: [Int: [StyleTag]] = [:]

        for (idx, raw) in values.enumerated(){
            guard let raw, !raw.isEmpty else { continue }
            dict[idx] = parseTagString(raw)
        }

        output.tags = dict
    }

    // Tag Parser
    func parseTagString(_ raw: String) -> [StyleTag] {
        let components = raw.split(separator: ":")
        var result: [StyleTag] = []
        
        for component in components {
            guard !component.isEmpty else { continue }
            
            var part = Substring(component)
            
            // "x" 제거
            if part.hasPrefix("x") {
                part = part.dropFirst()
            }
            
            guard let yRange = part.range(of: "y"),
                  let postIdRange = part.range(of: "postId") else {
                continue
            }
            
            let xStr = part[..<yRange.lowerBound]
            let yStr = part[yRange.upperBound..<postIdRange.lowerBound]
            let postId = String(part[postIdRange.upperBound...])
            
            guard let x = Double(xStr),
                  let y = Double(yStr) else {
                continue
            }
            
            let newTag = StyleTag(relX: CGFloat(x), relY: CGFloat(y), postId: postId)
            result.append(newTag)
        }
        
        return result
    }
    
    private func fetchProductDetailsForTags() async {
        var newTags = output.tags

        for (pageIndex, tags) in output.tags {
            for (tagIndex, tag) in tags.enumerated() {
                let response = await MockStyleDataStore.shared.productDTO(postId: tag.postId)
                let updatedTag = StyleTag(
                    relX: tag.relX,
                    relY: tag.relY,
                    postId: tag.postId,
                    title: response.title,
                    price: response.price?.description,
                    imageURL: response.imageURLs.first
                )
                newTags[pageIndex]?[tagIndex] = updatedTag
            }
        }

        await MainActor.run {
            self.output.tags = newTags
            self.output.shopTheLookProducts = newTags
                .keys
                .sorted()
                .compactMap { newTags[$0] }
                .flatMap { $0 }
        }
    }
    
    //MARK: - Network
    func fetchStyleDetail() async{
        await MainActor.run {
            output.isLoading = true
            output.errorMessage = nil
        }

        let response = await MockStyleDataStore.shared.styleDetailDTO(postId: postId)
        let entity = response.toEntity()

        await MainActor.run {
            output.style = entity
            preParseAllTags(entity: entity)
            if let userId = currentUserId {
                output.isStyleLiked = entity.likes.contains(userId)
            } else {
                output.isStyleLiked = false
            }
            confirmedIsLiked = output.isStyleLiked
        }

        await fetchProductDetailsForTags()

        await MainActor.run {
            output.isLoading = false
        }
    }
}

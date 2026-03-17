//
//  ProfileViewModel.swift
//  Contem
//
//  Created by 이상민 on 11/26/25.
//

import Foundation
import Combine

final class ProfileViewModel: ViewModelType{
    
    //MARK: - Properties
    var cancellables = Set<AnyCancellable>()
    
    var input = Input()
    @Published var output: Output = Output()
    
    struct Input{
        let appear = PassthroughSubject<Void, Never>()
        let followButtonTapped = PassthroughSubject<Void, Never>()
        let messageButtonTapped = PassthroughSubject<Void, Never>()
        let logoutTapped = PassthroughSubject<Void, Never>()
        let dmButtonTapped = PassthroughSubject<Void, Never>()
        let textLogoutTapped = PassthroughSubject<Void, Never>()
        let dismissButtonTapped = PassthroughSubject<Void, Never>()
        let postTapped = PassthroughSubject<String, Never>()
    }
    
    struct Output{
        var profile: ProfileEntity?
        var isLoading: Bool = false
        var isFollowing: Bool = false
        var errorMessage: String?
        var isMyProfile: Bool = false
        var userFeeds: [UserFeed] = []
    }
    
    private let userId: String
    private var currentUserId: String? {
        didSet {
            Task { @MainActor in
                self.output.isMyProfile = (self.currentUserId == self.userId)
                
            }
        }
    }
    private var followDebounceTask: Task<Void, Never>?
    private var latestFollowRequestID = 0
    weak private var coordinator: AppCoordinator?
    
    init(userId: String, coordinator: AppCoordinator){
        self.userId = userId
        self.coordinator = coordinator
        
        Task{
            self.currentUserId = await TokenStorage.shared.getUserId()
        }
        transform()
    }
    
    func transform() {
        input.appear
            .withUnretained(self)
            .sink { owner, _ in
                Task{
                    await owner.fetchProfile()
                    await owner.fetchUserFeeds()
                }
            }
            .store(in: &cancellables)
        
        input.followButtonTapped
            .sink { [weak self] _ in
                guard let self else { return }
                self.handleFollowTap()
            }
            .store(in: &cancellables)
        
        input.messageButtonTapped
            .sink { [weak self] _ in
                guard let opponentId = self?.output.profile?.userId else { return }
                print("유저 아이디 \(opponentId)")
                self?.coordinator?.push(.creatorChat(opponentId: opponentId))
            }
            .store(in: &cancellables)
        
        input.logoutTapped
            .withUnretained(self)
            .sink { owner, _ in
                Task {
                    // 1. 키체인에서 토큰 삭제
                    await TokenStorage.shared.clear()
                    
                    // 2. 메인 스레드에서 코디네이터를 통해 로그인 화면으로 이동
                    await MainActor.run {
                        self.coordinator?.logout()
                    }
                }
            }.store(in: &cancellables)
        
        input.dmButtonTapped
            .withUnretained(self)
            .sink { owner, _ in
                owner.coordinator?.push(.chatRoomList)
            }.store(in: &cancellables)
        
        input.textLogoutTapped
            .withUnretained(self)
            .sink { owner, _ in
                owner.coordinator?.logout()
            }.store(in: &cancellables)
        
        input.dismissButtonTapped
            .withUnretained(self)
            .sink { owner, _ in
                owner.coordinator?.pop()
            }.store(in: &cancellables)
        
        input.postTapped
            .sink { [weak self] postId in
                self?.coordinator?.push(.styleDetail(postId: postId))
            }
            .store(in: &cancellables)
    }
    
    private func handleFollowTap() {
        guard currentUserId != nil,
              output.profile != nil else {
            output.errorMessage = "로그인 후 이용 가능합니다."
            return
        }

        self.handleOptimisticFollow()

        latestFollowRequestID += 1
        let requestID = latestFollowRequestID
        let isFollowing = output.isFollowing

        followDebounceTask?.cancel()
        followDebounceTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(300))
            } catch {
                return
            }

            await self?.postFollowToServer(isFollowing: isFollowing, requestID: requestID)
        }
    }

    private func handleOptimisticFollow(){
        guard let _ = self.currentUserId,
              var _ = output.profile else{
            output.errorMessage = "로그인 후 이용 가능합니다."
            return
        }
        
        let newFollowingState = !output.isFollowing

        output.isFollowing = newFollowingState
    }
    
    private func rollbackFollowState(){
        guard let _ = self.currentUserId,
              var _ = output.profile else { return }
        
        let rolledBackState = !output.isFollowing
        
        output.isFollowing = !output.isFollowing
        
        self.output.isFollowing = rolledBackState
    }
    
    private func postFollowToServer(isFollowing: Bool, requestID: Int) async{
        do{
            _ = try await NetworkService.shared.callRequest(
                router: FollowRequest
                    .follow(userId: userId, isFollow: isFollowing),
                type: FollowDTO.self
            )
        }catch let error as NetworkError{
            guard latestFollowRequestID == requestID,
                  output.isFollowing == isFollowing else {
                return
            }

            self.rollbackFollowState()
            
            if case .statusCodeError(let type) = error {
                if type == .refreshTokenExpired() || type == .forbidden() || type == .unauthorized(){
                    currentUserId = nil
                }
            }
            
            output.errorMessage = error.errorDescription
        }catch{
            guard latestFollowRequestID == requestID,
                  output.isFollowing == isFollowing else {
                return
            }

            self.rollbackFollowState()
            output.errorMessage = NetworkError.unknown(error).errorDescription
        }
    }
    
    func fetchProfile(isSlient: Bool = false) async{
        if !isSlient{
            output.isLoading = true
        }
        
        Task{
            do{
                let response = try await NetworkService.shared.callRequest(router: UserProfileRequest.getOtherProfile(userId: userId), type: OtherProfileDTO.self)
                
                let entity = response.toEntity()
                output.profile = entity
//                output.isFollowing = entity.isFollowing(userId: currentUserId)
            }catch let error as NetworkError{
                output.errorMessage = error.errorDescription
                print("프로필 에러\(error.localizedDescription)")
            }
            
            output.isLoading = false
        }
    }
    
    private func fetchUserFeeds() async {
        do {
            let router = PostRequest.userPostList(userId: userId, next: nil, limit: "30", category: "style_feed")
            let result = try await NetworkService.shared.callRequest(router: router, type: PostListDTO.self)
            print("유저 피드 >>>>>>>>>>> \(result)")
            let userFeeds = UserFeedList(from: result)
            
            
            
            
            await MainActor.run {
                output.userFeeds = userFeeds.userFeedList
            }
            
           
            
        } catch {
            print("네트워크 에러 >>> \(error.localizedDescription)")
        }
    }
}

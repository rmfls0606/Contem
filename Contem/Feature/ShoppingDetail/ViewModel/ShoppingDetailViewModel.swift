import SwiftUI
import Combine
import iamport_ios
internal import Then


@MainActor
final class ShoppingDetailViewModel: ViewModelType {

    private weak var coordinator: AppCoordinator?

    private let postId: String
    private var likeDebounceTask: Task<Void, Never>?
    private var latestLikeRequestID = 0
    private var confirmedIsLiked = false
    
    var cancellables = Set<AnyCancellable>()
    
    var input = Input()
    
    @Published var output = Output()

    struct Input {
        let viewDidLoad = PassthroughSubject<Void, Never>()
        let likeButtonTapped = PassthroughSubject<String, Never>()
        let shareButtonTapped = PassthroughSubject<Void, Never>()
        let sizeSelectionTapped = PassthroughSubject<Void, Never>()
        let sizeSelected = PassthroughSubject<String, Never>()
        let purchaseButtonTapped = PassthroughSubject<String, Never>()
        let followButtonTapped = PassthroughSubject<Void, Never>()
        let backButtonTapped = PassthroughSubject<Void, Never>()
        let inquireButtonTapped = PassthroughSubject<String, Never>()
    }

    struct Output {
        var detailInfo: ShoppingDetailInfo?
        var isLoading = false
        var errorMessage: String?
        var isLiked = false
        var isFollowing = false
        var selectedSize: String?
        var showSizeSheet = false
        var showPurchaseAlert = false
        var showShareAlert = false
    }

    init(
        coordinator: AppCoordinator,
        postId: String
    ) {
        self.coordinator = coordinator
        self.postId = postId
        transform()
    }

    func transform() {
        // View Did Load - API 호출
        input.viewDidLoad
            .withUnretained(self)
            .sink { owner, _ in
                owner.fetchDetail()
            }
            .store(in: &cancellables)

        // Like Button
        input.likeButtonTapped
            .sink { [weak self] postId in
                guard let self = self else { return }
                self.handleLikeTap(postId: postId)
            }
            .store(in: &cancellables)
        

        // Share Button
        input.shareButtonTapped
            .sink { [weak self] in
                guard let self = self else { return }
                output.showShareAlert = true
            }
            .store(in: &cancellables)

        // Size Selection
        input.sizeSelectionTapped
            .sink { [weak self] in
                guard let self = self else { return }
                output.showSizeSheet = true
            }
            .store(in: &cancellables)

        input.sizeSelected
            .sink { [weak self] size in
                guard let self = self else { return }
                output.selectedSize = size
                output.showSizeSheet = false
            }
            .store(in: &cancellables)

        // Purchase Button
        input.purchaseButtonTapped
            .withUnretained(self)
            .sink { owner, price in
                let paymentData = owner.createPaymentData(price: price)
                owner.coordinator?.present(sheet: .payment(paymentData: paymentData, completion: { [weak owner] response in
                    owner?.handlePaymentResult(response)
                }))
            }
            .store(in: &cancellables)

        // Follow Button
        input.followButtonTapped
            .sink { [weak self] in
                guard let self = self else { return }
                output.isFollowing.toggle()
            }
            .store(in: &cancellables)

        // Back Button - Coordinator 사용
        input.backButtonTapped
            .sink { [weak self] in
                guard let self = self else { return }
                coordinator?.pop()
            }
            .store(in: &cancellables)
        
        input.inquireButtonTapped
            .sink { [weak self] userId in
                guard let self = self else { return }
//                coordinator?.present(fullScreen: .brandInquireChat(opponentId: userId))
                coordinator?.push(.creatorChat(opponentId: userId))
            }.store(in: &cancellables)
    }

    private func handleLikeTap(postId: String) {
        output.isLiked.toggle()

        latestLikeRequestID += 1
        let requestID = latestLikeRequestID
        let isLiked = output.isLiked

        likeDebounceTask?.cancel()
        likeDebounceTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch {
                return
            }

            await self?.postLike(postId: postId, isLiked: isLiked, requestID: requestID)
        }
    }

    // 상품 상세 정보 불러오기
    private func fetchDetail() {
        output.isLoading = true
        output.errorMessage = nil

        Task { [weak self] in
            guard let self = self else { return }
            let detailInfo = ShoppingDetailInfo.mock(postId: self.postId)
            await MainActor.run {
                self.output.detailInfo = detailInfo
                self.output.isLiked = detailInfo.isLiked
                self.confirmedIsLiked = detailInfo.isLiked
                self.output.isLoading = false
            }
        }
    }
    
    private func postLike(postId: String, isLiked: Bool, requestID: Int) async {
        do {
            let router = PostRequest.like(postId: postId, isLiked: isLiked)
            let _ = try await NetworkService.shared.callRequest(router: router, type: PostLikeDTO.self)
            guard latestLikeRequestID == requestID else { return }
            confirmedIsLiked = isLiked
        } catch {
            guard latestLikeRequestID == requestID,
                  output.isLiked == isLiked else {
                return
            }

            output.isLiked = confirmedIsLiked
        }
    }

    // MARK: - Helper Methods

    func closeSizeSheet() {
        output.showSizeSheet = false
    }

    func closePurchaseAlert() {
        output.showPurchaseAlert = false
    }

    func closeShareAlert() {
        output.showShareAlert = false
    }
    
    // 결제 데이터 생성 로직
    private func createPaymentData(price: String) -> IamportPayment {
        return IamportPayment(
            pg: PG.html5_inicis.makePgRawName(pgId: "INIpayTest"),
            merchant_uid: "mid_\(Int(Date().timeIntervalSince1970*1000))",
            amount: price
        ).then {
            $0.pay_method = PayMethod.card.rawValue
            $0.name = "상품명 예시 옷 입니다"
            $0.buyer_name = "박도원"
            $0.app_scheme = "contem"
        }
    }
    
    func handlePaymentResult(_ response: IamportResponse?) {
        // 아임포트 결제 성공 여부 확인
        guard let response = response, let isSuccess = response.success, isSuccess,
              let impUid = response.imp_uid else {
            print("결제 실패 또는 취소됨: \(String(describing: response?.error_msg))")
            // 필요 시 에러 Alert 표시 로직 추가 (output.errorMessage 등)
            return
        }
        
        // 결제 성공 시 서버로 검증 요청
        requestPaymentValidation(impUid: impUid)
    }
    
    private func requestPaymentValidation(impUid: String) {
        Task { [weak self] in
            guard let self = self else { return }
            do {
                let router = PaymentRequest.paymentValid(uid: impUid, postId: self.postId)
                let result = try await NetworkService.shared.callRequest(router: router, type: PaymentValidationDTO.self)
                print("서버 검증 성공: \(result)")
                await MainActor.run {
                    self.output.showPurchaseAlert = true
                }
            } catch {
                await MainActor.run {
                    self.output.errorMessage = "결제 검증에 실패했습니다."
                }
            }
        }
    }
}

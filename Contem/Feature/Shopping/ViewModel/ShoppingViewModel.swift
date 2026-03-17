import Foundation
import Combine

@MainActor
final class ShoppingViewModel: ViewModelType {
    private weak var coordinator: AppCoordinator?
    private var likeDebounceTasks: [String: Task<Void, Never>] = [:]
    private var latestLikeRequestIDs: [String: Int] = [:]
    
    var cancellables = Set<AnyCancellable>()
    var input = Input()
    @Published var output = Output()
    
    struct Input {
        let onAppear = PassthroughSubject<Void, Never>()
        let selectMainCategory = CurrentValueSubject<TabCategory, Never>(.outer)
        let selectSubCategory = CurrentValueSubject<SubCategory, Never>(OuterSubCategory.padding)
        let onTappedProduct = PassthroughSubject<String, Never>()
        let likeButtonTapped = PassthroughSubject<String, Never>()
        let loadMoreTrigger = PassthroughSubject<Void, Never>()
    }
    
    struct Output {
        var banners: [Banner] = []
        var currentBannerIndex: Int = 1
        var infiniteBanners: [Banner] = []
        var displayBannerIndex: Int = 1
        var currentSubCategories: [String] = []
        var products: [ShoppingProduct] = []
        var currentCategory = TabCategory.outer
        var currentSubCategory: SubCategory = OuterSubCategory.padding
        var nextCursor: String? = nil
        var canLoadMore: Bool = true
    }
    
    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        transform()
    }
    
    func transform() {
        
        input.onAppear
            .sink { [weak self] _ in
                guard let self = self else { return }
                
                let initMain = TabCategory.outer
                let initSub = OuterSubCategory.padding
                
                output.currentCategory = initMain
                output.currentSubCategory = initSub
                output.currentSubCategories = initMain.subCategories.map { $0.displayName }
                
                Task { await self.fetchBanner(body: ["category": initMain.apiValue]) }
                
                self.updateProducts(main: initMain, sub: initSub)
                
            }.store(in: &cancellables)
        
        input.selectMainCategory
            .sink { [weak self] selectedMain in
                guard let self = self else { return }
                
                let firstSub = selectedMain.subCategories[0]
                
                output.currentCategory = selectedMain
                output.currentSubCategory = firstSub
                output.currentSubCategories = selectedMain.subCategories.map { $0.displayName }
                output.currentBannerIndex = 1
                output.displayBannerIndex = 1
                
                if selectedMain == .outer {
                    Task { await self.fetchBanner(body: ["category": selectedMain.apiValue]) }
                }
                self.updateProducts(main: selectedMain, sub: firstSub)
                
            }.store(in: &cancellables)
        
        input.selectSubCategory
            .sink { [weak self] selectedSub in
                guard let self = self else { return }
                
                output.currentSubCategory = selectedSub
                self.updateProducts(main: self.output.currentCategory, sub: selectedSub)
                
            }.store(in: &cancellables)
        
        input.onTappedProduct
            .sink { [weak self] id in
                self?.coordinator?.push(.shoppingDetail(id: id))
            }.store(in: &cancellables)
        
        input.likeButtonTapped
            .sink { [weak self] postId in
                guard let self = self else { return }
                self.handleLikeTap(postId: postId)
            }.store(in: &cancellables)
            
        input.loadMoreTrigger
            .sink { [weak self] _ in
                guard let self = self else { return }
                
                if self.isServerTarget(main: output.currentCategory, sub: output.currentSubCategory) {
                    Task { await self.loadMoreProducts() }
                }
            }.store(in: &cancellables)
    }
}

// MARK: - Logic Extension
extension ShoppingViewModel {
    private func handleLikeTap(postId: String) {
        guard let index = output.products.firstIndex(where: { $0.id == postId }) else { return }

        output.products[index].toggleLike()
        let isLiked = output.products[index].isLiked
        let requestID = (latestLikeRequestIDs[postId] ?? 0) + 1
        latestLikeRequestIDs[postId] = requestID

        likeDebounceTasks[postId]?.cancel()
        likeDebounceTasks[postId] = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch {
                return
            }

            await self?.postLike(postId: postId, isLiked: isLiked, requestID: requestID)
        }
    }
    
   
    private func isServerTarget(main: TabCategory, sub: SubCategory) -> Bool {
        return main == .outer && sub.apiValue == OuterSubCategory.padding.apiValue
    }


    private func updateProducts(main: TabCategory, sub: SubCategory) {
        
    
        if isServerTarget(main: main, sub: sub) {
            Task {
                await self.fetchProducts(body: ["category": sub.apiValue])
            }
        }
     
        else {
            output.products = self.generateMockProducts(main: main, sub: sub)
            output.canLoadMore = false
            output.nextCursor = nil
        }
    }
    

    private func generateMockProducts(main: TabCategory, sub: SubCategory) -> [ShoppingProduct] {
        switch main {
        case .outer:
            // Outer 내에서도 Padding이 아닌 경우(Coat, Jacket 등) 목업 데이터 리턴
            if sub.apiValue == OuterSubCategory.coat.apiValue {
                return [
                    ShoppingProduct(thumbnailUrl: "coat_1", brandName: "Burberry", productName: "캐시미어 코트", price: 2500000, likes: []),
                    ShoppingProduct(thumbnailUrl: "coat_2", brandName: "Lemaire", productName: "싱글 브레스트 코트", price: 1800000, likes: [])
                ]
            } else {
                return [
                    ShoppingProduct(thumbnailUrl: "jacket_1", brandName: "Barbour", productName: "왁스 자켓", price: 500000, likes: [])
                ]
            }
            
        case .top:
            return [
                ShoppingProduct(thumbnailUrl: "image_1", brandName: "Stussy", productName: "월드 투어 티셔츠 화이트", price: 68000, likes: []),
                ShoppingProduct(thumbnailUrl: "image_2", brandName: "Nike", productName: "NRG 솔로 스우시 후드 블랙", price: 129000, likes: []),
                ShoppingProduct(thumbnailUrl: "image_3", brandName: "IAB Studio", productName: "아이앱 피그먼트 티셔츠", price: 58000, likes: []),
                ShoppingProduct(thumbnailUrl: "image_4", brandName: "Adidas", productName: "파이어버드 트랙 팬츠 그린", price: 109000, likes: []),
                ShoppingProduct(thumbnailUrl: "image_5", brandName: "Supreme", productName: "박스 로고 크루넥 그레이", price: 520000, likes: []),
                ShoppingProduct(thumbnailUrl: "image_6", brandName: "Palace", productName: "트라이 퍼그 후드 네이비", price: 280000, likes: []),
                ShoppingProduct(thumbnailUrl: "image_7", brandName: "Carhartt WIP", productName: "디트로이트 자켓 블랙", price: 248000, likes: []),
                ShoppingProduct(thumbnailUrl: "image_8", brandName: "Nike", productName: "NRG 솔로 스우시 후드 블랙", price: 129000, likes: []),
                ShoppingProduct(thumbnailUrl: "image_9", brandName: "Stussy", productName: "베이직 스투시 티셔츠 화이트", price: 68000, likes: []),
                ShoppingProduct(thumbnailUrl: "image_10", brandName: "Adidas", productName: "파이어버드 트랙 탑 그린", price: 109000, likes: []),
                ShoppingProduct(thumbnailUrl: "image_11", brandName: "The North Face", productName: "1996 에코 눕시 자켓", price: 339000, likes: []),
                ShoppingProduct(thumbnailUrl: "image_12", brandName: "IAB Studio", productName: "아이앱 후드티 그레이", price: 156000, likes: []),
                ShoppingProduct(thumbnailUrl: "image_13", brandName: "Matin Kim", productName: "로고 크롭 티셔츠 블랙", price: 48000, likes: []),
                ShoppingProduct(thumbnailUrl: "image_14", brandName: "New Balance", productName: "993 메이드 인 USA 그레이", price: 259000, likes: []),
                ShoppingProduct(thumbnailUrl: "image_15", brandName: "Asics", productName: "젤 카야노 14 크림 블랙", price: 169000, likes: []),
                ShoppingProduct(thumbnailUrl: "image_16", brandName: "Supreme", productName: "박스 로고 크루넥", price: 520000, likes: []),
                ShoppingProduct(thumbnailUrl: "image_17", brandName: "Palace", productName: "트라이 퍼그 후드", price: 280000, likes: []),
                ShoppingProduct(thumbnailUrl: "image_18", brandName: "Arcteryx", productName: "베타 LT 자켓 블랙", price: 650000, likes: []),
                ShoppingProduct(thumbnailUrl: "image_19", brandName: "Polo Ralph Lauren", productName: "코튼 치노 베이스볼 캡", price: 89000, likes: []),
                ShoppingProduct(thumbnailUrl: "image_20", brandName: "Maison Kitsune", productName: "더블 폭스 헤드 패치 티셔츠", price: 135000, likes: []),
                ShoppingProduct(thumbnailUrl: "image_21", brandName: "Ami", productName: "스몰 하트 로고 가디건", price: 430000, likes: []),
                ShoppingProduct(thumbnailUrl: "image_22", brandName: "A.P.C.", productName: "다니엘라 데님 에코백", price: 110000, likes: []),
                ShoppingProduct(thumbnailUrl: "image_23", brandName: "Patagonia", productName: "레트로 X 후리스 자켓", price: 299000, likes: []),
                ShoppingProduct(thumbnailUrl: "image_24", brandName: "Stone Island", productName: "와펜 패치 맨투맨", price: 450000, likes: []),
                ShoppingProduct(thumbnailUrl: "image_25", brandName: "Gentle Monster", productName: "릴리트 01 선글라스", price: 269000, likes: []),
                ShoppingProduct(thumbnailUrl: "image_26", brandName: "Human Made", productName: "하트 로고 티셔츠", price: 150000, likes: []),
                ShoppingProduct(thumbnailUrl: "image_27", brandName: "Needles", productName: "HD 트랙 팬츠", price: 320000, likes: []),
                ShoppingProduct(thumbnailUrl: "image_28", brandName: "Salomon", productName: "XT-6 어드밴스드 화이트", price: 260000, likes: []),
                ShoppingProduct(thumbnailUrl: "image_29", brandName: "Hoka", productName: "본다이 8 블랙", price: 199000, likes: []),
                ShoppingProduct(thumbnailUrl: "image_30", brandName: "Cos", productName: "퀼티드 미니 백", price: 79000, likes: [])
            ]
            
        case .bottom:
            return [
                ShoppingProduct(thumbnailUrl: "bottom_1", brandName: "Levis", productName: "501 오리지널", price: 109000, likes: []),
                ShoppingProduct(thumbnailUrl: "bottom_2", brandName: "Diesel", productName: "데님 팬츠", price: 340000, likes: [])
            ]
            
        default:
            return [
                ShoppingProduct(thumbnailUrl: "default_1", brandName: "Brand", productName: "\(main.rawValue) 추천 아이템", price: 100000, likes: []),
                ShoppingProduct(thumbnailUrl: "default_2", brandName: "Brand", productName: "인기 상품", price: 200000, likes: [])
            ]
        }
    }
    
    private func loadBanners(for category: TabCategory) -> [Banner] {
        return [
            Banner(title: "\(category.rawValue) 기획전", subtitle: "최대 50% 할인", thumbnail: "mock_banner_1"),
            Banner(title: "신규 입고", subtitle: "NEW ARRIVAL", thumbnail: "mock_banner_2")
        ]
    }
    
    private func calculateInfiniteBanners(from banners: [Banner]) -> [Banner] {
        guard let first = banners.first, let last = banners.last else { return banners }
        return [last] + banners + [first]
    }
    
    private func calculateDisplayIndex() -> Int {
        if output.currentBannerIndex == 0 {
            return output.banners.count
        } else if output.currentBannerIndex == output.infiniteBanners.count - 1 {
            return 1
        } else {
            return output.currentBannerIndex
        }
    }
    
    func updateBannerIndex(to newIndex: Int) {
        output.currentBannerIndex = newIndex
        output.displayBannerIndex = calculateDisplayIndex()
    }
    
    func calculateNewBannerIndex(dragTranslation: CGFloat, cardWidth: CGFloat) -> Int {
        let threshold = cardWidth * 0.25
        var newIndex = output.currentBannerIndex
        
        if dragTranslation < -threshold {
            if output.currentBannerIndex < output.infiniteBanners.count - 1 {
                newIndex = output.currentBannerIndex + 1
            }
        } else if dragTranslation > threshold {
            if output.currentBannerIndex > 0 {
                newIndex = output.currentBannerIndex - 1
            }
        }
        return newIndex
    }
    
    func shouldPerformInfiniteScroll(for index: Int) -> Int? {
        if index == 0 && output.currentBannerIndex == 0 {
            return output.banners.count
        } else if index == output.infiniteBanners.count - 1 && output.currentBannerIndex == output.infiniteBanners.count - 1 {
            return 1
        }
        return nil
    }
}

// MARK: - Network Logic
extension ShoppingViewModel {
    
    private func fetchBanner(body: [String: String]) async {
         do {
             let router = PostRequest.postList(category: ["banner_outer"])
             let result = try await NetworkService.shared.callRequest(router: router, type: PostListDTO.self)
             let bannerList = BannerList(from: result)
             output.banners = bannerList.banners
             output.infiniteBanners = calculateInfiniteBanners(from: bannerList.banners)
         } catch {
             print("에러 발생\(error)")
         }
    }
     
    private func fetchProducts(body: [String: String]) async {
         output.products = []
         output.nextCursor = nil
         output.canLoadMore = true
         
         do {
             let router = PostRequest.postList(limit: "10", category: [output.currentSubCategory.apiValue])
             let result = try await NetworkService.shared.callRequest(router: router, type: PostListDTO.self)
             
             let productList = ShoppingProductList(from: result)
             output.products = productList.products
             output.nextCursor = result.nextCursor
             output.canLoadMore = result.nextCursor != "0"
         } catch {
             print("에러 발생 \(error)")
         }
    }
    
    private func loadMoreProducts() async {
        guard output.canLoadMore, let nextCursor = output.nextCursor else {
            return
        }
        
        do {
            let router = PostRequest.postList(next: nextCursor, limit: "10", category: [output.currentSubCategory.apiValue])
            let result = try await NetworkService.shared.callRequest(router: router, type: PostListDTO.self)
            let productList = ShoppingProductList(from: result)
            output.products.append(contentsOf: productList.products)
            output.nextCursor = result.nextCursor
            output.canLoadMore = result.nextCursor != "0"
        } catch {
            print("에러 발생 \(error)")
        }
    }
    
    private func postLike(postId: String, isLiked: Bool, requestID: Int) async {
        do {
            let router = PostRequest.like(postId: postId, isLiked: isLiked)
            let _ = try await NetworkService.shared.callRequest(router: router, type: PostLikeDTO.self)
        } catch {
            guard latestLikeRequestIDs[postId] == requestID,
                  let index = output.products.firstIndex(where: { $0.id == postId }),
                  output.products[index].isLiked == isLiked else {
                return
            }

            output.products[index].toggleLike()
        }
    }
}

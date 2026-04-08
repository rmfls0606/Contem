import SwiftUI
import Combine
import iamport_ios

final class AppCoordinator: CoordinatorProtocol, ObservableObject {

    private var cancellables = Set<AnyCancellable>()
    
    var currentUserId: String {
        return (try? KeychainManager.shared.read(.userId)) ?? ""
    }
    
    enum Route: Hashable {
        case tabView
        case signin
        case join
        case shopping
        case shoppingDetail(id: String)
        case createStyle
        case style
        case styleDetail(postId: String)
        case profile(userId: String)
        case creatorChat(opponentId: String)
        case chatRoomList
    }
    
    enum SheetRoute: Identifiable {
        case comment(postId: String)
        case payment(paymentData: IamportPayment, completion: (IamportResponse?) -> Void)
        
        var id: String {
            switch self {
            case .comment(let postId): return "comment-\(postId)"
            case .payment: return "payment"
            }
        }
    }
    
    enum FullScreenSheetRoute: Hashable, Identifiable {
        case brandInquireChat(opponentId: String)
        
        var id: Self { self }
        
    }
    
    @Published var rootRoute: Route = .signin
    
    @Published var sheetRoute: SheetRoute?
    
    @Published var fullScreenSheetRoute: FullScreenSheetRoute?
    
    @Published var navigationPath = NavigationPath()
    
    init () {
        bind()
    }
    
    private func bind() {
//        Task { @MainActor in
//            for await _ in NetworkService.shared.sessionExpiredSubject.values {
//                self.logout()
//            }
//        }
        NetworkService.shared.sessionExpiredSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                logout()
            }.store(in: &cancellables)
    }
    
    func checkToken() async {
        let hasToken = await TokenStorage.shared.hasValidAccessToken()
        rootRoute = hasToken ? .tabView : .signin
    }
    
    @ViewBuilder
    func build(route: Route) -> some View {
        switch route {
        case .tabView:
            MainTabView(coordinator: self)
        case .signin:
            SignInView(coordinator: self)
        case .join:
            JoinView(coordinator: self)
        case .shopping:
            let vm = ShoppingViewModel(coordinator: self)
            ShoppingView(viewModel: vm)
        case .shoppingDetail(let postId):
            ShoppingDetailView(coordinator: self, postId: postId)
        case .createStyle:
            CreateStyleView()
        case .style:
            let vm = StyleViewModel(coordinator: self)
            StyleView(viewModel: vm)
        case .styleDetail(let postId):
            StyleDetailView(postId: postId, coordinator: self)
        case .profile(let userId):
            Profileview(userId: userId, coordinator: self)
        case .creatorChat(let opponentId):
            let vm = ChattingViewModel(opponentId: opponentId, coordinator: self)
            ChattingView(viewModel: vm)
        case .chatRoomList:
            ChatRoomListView(coordinator: self)
        }
    }
    
    @ViewBuilder
    func buildSheet(route: SheetRoute) -> some View {
        switch route {
        case .comment(let postId):
            let vm = CommentViewModel(coordinator: self, postId: postId)
            CommentView(viewModel: vm)
        case .payment(let data, let completion):
            PaymentBridge(paymentData: data) { [weak self] response in
                self?.sheetRoute = nil
                completion(response)
            }
        }
    }
    
    @ViewBuilder
    func buildFullScreen(route: FullScreenSheetRoute) -> some View {
        switch route {
        case .brandInquireChat(let opponentId):
            BrandInquireView(coordinator: self, userId: opponentId)
        }
    }
    
    
    func login() {
        navigationPath = NavigationPath()
        rootRoute = .tabView
    }
    
    func logout() {
        navigationPath = NavigationPath()
        rootRoute = .signin
        
    }
    
    func push(_ route: Route) {
        navigationPath.append(route)
    }
    
    func pop() {
        navigationPath.removeLast()
    }
    
    func popToRoot() {
        navigationPath.removeLast(navigationPath.count)
    }
    
    func present(sheet: SheetRoute) {
        sheetRoute = sheet
    }
    
    func dismissSheet() {
        self.sheetRoute = nil
    }
    
    func present(fullScreen: FullScreenSheetRoute) {
        fullScreenSheetRoute = fullScreen
    }
    
    func dismissFullScreen() {
        fullScreenSheetRoute = nil
    }
}

import SwiftUI
import KakaoSDKAuth
import Combine

extension String {
    var isValidEmail: Bool {
        let emailRegEx = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPred = NSPredicate(format:"SELF MATCHES %@", emailRegEx)
        return emailPred.evaluate(with: self)
    }
}

final class SignInViewModel: ViewModelType {
  
    private weak var coordinator: AppCoordinator?
    var cancellables = Set<AnyCancellable>()
    
    // MARK: - Dependencies (DI)
    private let appleService: AppleAuthServiceType
    private let authRepository: AuthRepositoryType
    
    var input = Input()
    
    @Published
    var output = Output()

    struct Input {
        let loginButtonTapped = PassthroughSubject<Void, Never>()
        let signUpButtonTapped = PassthroughSubject<Void, Never>()
        let appleLoginButtonTapped = PassthroughSubject<Void, Never>()
        let kakaoLoginButtonTapped = PassthroughSubject<String?, Never>()
    }

    struct Output {
        var email: String = ""
        var password: String = ""
        var showAlert = false
        var alertMessage = ""
        var isLoading = false
        var isLoginEnabled: Bool {
            return email.isValidEmail && password.count >= 4
        }
    }
    
    
    init(
        coordinator: AppCoordinator,
        appleService: AppleAuthServiceType = AppleAuthService(),
        authRepository: AuthRepositoryType = AuthRepository()
    ) {
        self.appleService = appleService
        self.authRepository = authRepository
        self.coordinator = coordinator
        transform()
    }

    func transform() {
        // 로그인 버튼 탭 처리
        input.loginButtonTapped
            .withUnretained(self)
            .sink { owner, _ in
                Task{
                    await self.signin()
                }
            }
            .store(in: &cancellables)

        input.signUpButtonTapped
            .sink { [weak self] _ in
                self?.coordinator?.push(.join)
            }
            .store(in: &cancellables)
        
        input.appleLoginButtonTapped
            .throttle(for: .seconds(1), scheduler: RunLoop.main, latest: false) // 중복 탭 방지
            .sink { [weak self] _ in
                Task { await self?.processLogin() }
            }
            .store(in: &cancellables)
        
        input.kakaoLoginButtonTapped
            .compactMap{$0}
            .throttle(for: .seconds(1), scheduler: RunLoop.main, latest: false) // 중복 탭 방지
            .sink { [weak self] accessToken in
                Task{
                    await self?.kakaoLogin(token: accessToken)
                }
            }
            .store(in: &cancellables)

    }
    
    private func signin() async{
        do{
            let response = try await NetworkService.shared.callRequest(
                router: UserRequest.login(email: output.email, password: output.password),
                type: LoginDTO.self
            )
            
            try await TokenStorage.shared.storeTokens(access: response.accessToken, refresh: response.refreshToken, userId: response.userID)
            
            coordinator?.rootRoute = .tabView
        }catch{
            output.alertMessage = error.localizedDescription
            output.showAlert = true
        }
    }
    
    private func kakaoLogin(token: String) async{
        do{
            let response = try await NetworkService.shared
                .callRequest(
                    router: UserRequest.kakaoLogin(token: token),
                    type: LoginDTO.self
                )
            
            try await TokenStorage.shared
                .storeTokens(
                    access: response.accessToken,
                    refresh: response.refreshToken,
                    userId: response.userID
                )
        }catch{
            print(error.localizedDescription)
            output.alertMessage = error.localizedDescription
        }
    }
}

@MainActor
final class JoinViewModel: ViewModelType {

    private weak var coordinator: AppCoordinator?
    var cancellables = Set<AnyCancellable>()

    var input = Input()

    @Published
    var output = Output()

    struct Input {
        let submitButtonTapped = PassthroughSubject<Void, Never>()
        let backButtonTapped = PassthroughSubject<Void, Never>()
    }

    struct Output {
        var email = ""
        var password = ""
        var passwordConfirm = ""
        var nick = ""
        var name = ""
        var introduction = ""
        var phoneNum = ""
        var hashTagsText = ""
        var showAlert = false
        var alertMessage = ""
        var isSuccessAlert = false
        var isSubmitting = false

        var isJoinEnabled: Bool {
            email.isValidEmail &&
            password.count >= 4 &&
            password == passwordConfirm &&
            !nick.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !phoneNum.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        transform()
    }

    func transform() {
        input.backButtonTapped
            .sink { [weak self] _ in
                self?.coordinator?.pop()
            }
            .store(in: &cancellables)

        input.submitButtonTapped
            .sink { [weak self] _ in
                guard let self = self else { return }
                Task {
                    await self.join()
                }
            }
            .store(in: &cancellables)
    }

    func handleAlertDismiss() {
    }

    private func join() async {
        guard output.isJoinEnabled else {
            output.alertMessage = "필수 정보를 모두 올바르게 입력해주세요."
            output.isSuccessAlert = false
            output.showAlert = true
            return
        }

        output.isSubmitting = true

        let hashTags = output.hashTagsText
            .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\n" })
            .map { rawTag in
                let trimmed = String(rawTag).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return "" }
                return trimmed.hasPrefix("#") ? trimmed : "#\(trimmed)"
            }
            .filter { !$0.isEmpty }

        do {
            let response = try await NetworkService.shared.callRequest(
                router: UserRequest.join(
                    email: output.email,
                    password: output.password,
                    nick: output.nick,
                    name: output.name,
                    introduction: output.introduction,
                    phoneNum: output.phoneNum,
                    hashTags: hashTags,
                    deviceToken: ""
                ),
                type: JoinResponseDTO.self
            )

            try await TokenStorage.shared.storeTokens(
                access: response.accessToken,
                refresh: response.refreshToken,
                userId: response.userId
            )

            coordinator?.rootRoute = .tabView
        } catch {
            output.alertMessage = error.localizedDescription
            output.isSuccessAlert = false
            output.showAlert = true
        }

        output.isSubmitting = false
    }
}

// MARK: - 로그인
extension SignInViewModel {
    @MainActor
    private func processLogin() async {
        output.isLoading = true
        
        do {
            // 1. 애플 서버 통신 (Identity Token 획득)
            let idToken = try await appleService.signIn()
            print("✅ Apple Token: \(idToken.prefix(10))...")
            
            // 2. 백엔드 서버 통신 (NetworkService 사용)
            let result = try await authRepository.loginWithApple(idToken: idToken)
            print("✅ Server Login Success: \(result.accessToken)")
            
            try await TokenStorage.shared.storeTokens(access: result.accessToken, refresh: result.refreshToken, userId: result.userID)
            
            coordinator?.rootRoute = .tabView
            
            // 3. 토큰 저장 (TokenStorage 활용)
            // TokenStorage.shared.save(accessToken: result.accessToken, ...)
            
            // 4. 화면 전환 (Coordinator Delegate 호출 등)
            // coordinator?.didFinishLogin()
            
        } catch {
            print("❌ Login Failed: \(error)")
        }
        
        output.isLoading = false
    }
}

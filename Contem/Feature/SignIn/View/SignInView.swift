import SwiftUI
import KakaoSDKUser
import Combine
import AuthenticationServices
import KakaoSDKCommon
import KakaoSDKAuth

struct SignInView: View {
    
    @StateObject private var viewModel: SignInViewModel
    
    init(coordinator: AppCoordinator) {
        _viewModel = StateObject(
            wrappedValue: SignInViewModel(coordinator: coordinator)
        )
    }
    
    
    var body: some View {
        VStack(spacing: .spacing16) {
            
            Image("contem_logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 80)
                .padding(.bottom, 20)
            
            Spacer().frame(height: 32)
            
            TextField("이메일을 입력해주세요", text: $viewModel.output.email)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .keyboardType(.emailAddress)
                .padding()
                .overlay(
                    RoundedRectangle(cornerRadius: .spacing16)
                        .stroke(.gray300, lineWidth: 1)
                )
            
            SecureField("비밀번호를 입력해주세요", text: $viewModel.output.password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .padding()
                .overlay(
                    RoundedRectangle(cornerRadius: .spacing16)
                        .stroke(.gray300, lineWidth: 1)
                )
            
            Button(action: {
                viewModel.input.loginButtonTapped.send()
            }) {
                Text("로그인")
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(viewModel.output.isLoginEnabled ? Color.primary100 : Color.gray300)
                    .cornerRadius(.spacing16)
            }
            .disabled(!viewModel.output.isLoginEnabled)

            Button(action: {
                viewModel.input.signUpButtonTapped.send()
            }) {
                Text("회원가입")
                    .font(.bodyMedium)
                    .foregroundColor(.gray700)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, .spacing12)
                    .overlay(
                        RoundedRectangle(cornerRadius: .spacing16)
                            .stroke(.gray300, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            
            // 구분 선
            HStack {
                
                VStack { Divider() }
                
                Text("또는")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.horizontal, 8)
                
                VStack { Divider() }
            }
            HStack(spacing: .spacing16) {
                Button {
                    if UserApi.isKakaoTalkLoginAvailable() {
                        UserApi.shared.loginWithKakaoTalk { (oauthToken, error) in
                            if let error = error {
                                print(error)
                            } else {
                                viewModel.input.kakaoLoginButtonTapped.send(oauthToken?.accessToken)
                            }
                        }
                    } else {
                        UserApi.shared.loginWithKakaoAccount { (oauthToken, error) in
                            if let error = error {
                                print(error)
                            } else {
                                viewModel.input.kakaoLoginButtonTapped.send(oauthToken?.accessToken)
                            }
                        }
                    }
                } label: {
                    SocialCircleButton(
                        backgroundColor: .kakao,
                        foregroundColor: .primary100,
                        systemImage: "message.fill"
                    )
                }
                .buttonStyle(.plain)

                Button {
                    viewModel.input.appleLoginButtonTapped.send(())
                } label: {
                    SocialCircleButton(
                        backgroundColor: .black,
                        foregroundColor: .white,
                        systemImage: "apple.logo"
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.top, .spacing8)
        }
        .padding(.horizontal, .spacing16)
        .alert("알림", isPresented: $viewModel.output.showAlert) {
            Button("확인", role: .cancel) { }
        } message: {
            Text(viewModel.output.alertMessage)
        }
        .onOpenURL { url in
            if (AuthApi.isKakaoTalkLoginUrl(url)){
                _ = AuthController.handleOpenUrl(url: url)
            }
        }
            
            
            // Apple 로그인 버튼
//            SignInWithAppleButton(
//                onRequest: { _ in },
//                onCompletion: { _ in }
//            )
//            .frame(height: 44)
//            .cornerRadius(10)
//            .overlay {
//                // 버튼의 기본 제스처를 막고 ViewModel의 Input을 트리거
//                Color.black.opacity(0.001)
//                    .onTapGesture {
//                        viewModel.input.appleLoginButtonTapped.send(())
//                    }
//            }
//        }
//        .padding(.horizontal, .spacing16)
//        .alert("알림", isPresented: $viewModel.output.showAlert) {
//            Button("확인", role: .cancel) { }
//        } message: {
//            Text(viewModel.output.alertMessage)
//        }
    }
    
}

private struct SocialCircleButton: View {
    let backgroundColor: Color
    let foregroundColor: Color
    let systemImage: String
    
    var body: some View {
        ZStack {
            Circle()
                .fill(backgroundColor)
                .frame(width: 56, height: 56)
                .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
            
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(foregroundColor)
        }
    }
}

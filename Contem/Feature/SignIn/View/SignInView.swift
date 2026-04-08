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

struct JoinView: View {

    @StateObject private var viewModel: JoinViewModel
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case email
        case password
        case passwordConfirm
        case nick
        case name
        case phoneNum
        case hashTags
        case introduction
    }

    init(coordinator: AppCoordinator) {
        _viewModel = StateObject(
            wrappedValue: JoinViewModel(coordinator: coordinator)
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: .spacing16) {
                header

                Group {
                    lineField("이메일", text: $viewModel.output.email, prompt: "example@contem.com", keyboardType: .emailAddress, field: .email)
                    secureLineField("비밀번호", text: $viewModel.output.password, prompt: "비밀번호를 입력해주세요", field: .password)
                    secureLineField("비밀번호 확인", text: $viewModel.output.passwordConfirm, prompt: "비밀번호를 다시 입력해주세요", field: .passwordConfirm)
                    lineField("닉네임", text: $viewModel.output.nick, prompt: "사용할 닉네임을 입력해주세요", field: .nick)
                    lineField("이름", text: $viewModel.output.name, prompt: "이름을 입력해주세요", field: .name)
                    lineField("전화번호", text: $viewModel.output.phoneNum, prompt: "01012345678", keyboardType: .phonePad, field: .phoneNum)
                    lineField("관심 태그", text: $viewModel.output.hashTagsText, prompt: "예: #미니멀 #스트릿 #데일리", field: .hashTags)
                }

                introductionField

                Button {
                    viewModel.input.submitButtonTapped.send()
                } label: {
                    HStack {
                        if viewModel.output.isSubmitting {
                            ProgressView()
                                .tint(.primary0)
                        }

                        Text(viewModel.output.isSubmitting ? "가입 중..." : "회원가입 완료")
                            .font(.bodyMedium)
                    }
                    .foregroundColor(.primary0)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, .spacing16)
                    .background(viewModel.output.isJoinEnabled ? Color.primary100 : Color.gray300)
                    .clipShape(RoundedRectangle(cornerRadius: .spacing16))
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.output.isJoinEnabled || viewModel.output.isSubmitting)
                .padding(.top, .spacing8)
            }
            .padding(.horizontal, .spacing16)
            .padding(.vertical, .spacing24)
        }
        .background(Color.primary0.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .scrollDismissesKeyboard(.interactively)
        .contentShape(Rectangle())
        .onTapGesture {
            focusedField = nil
        }
        .alert("알림", isPresented: $viewModel.output.showAlert) {
            Button("확인", role: .cancel) {
                viewModel.handleAlertDismiss()
            }
        } message: {
            Text(viewModel.output.alertMessage)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: .spacing12) {
            Button {
                viewModel.input.backButtonTapped.send()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.bodyMedium)
                    .foregroundColor(.primary100)
                    .frame(width: 40, height: 40)
                    .background(Color.gray25)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: .spacing8) {
                Text("회원가입")
                    .font(.titleLarge)
                    .foregroundColor(.primary100)

                Text("기본 정보와 취향 태그를 입력하고 Contem을 시작해보세요.")
                    .font(.bodyMedium)
                    .foregroundColor(.gray700)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, .spacing8)
        }
    }

    private var introductionField: some View {
        VStack(alignment: .leading, spacing: .spacing8) {
            Text("소개")
                .font(.bodyMedium)
                .foregroundColor(.gray700)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: .spacing16)
                    .stroke(.gray300, lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: .spacing16)
                            .fill(Color.primary0)
                    )
                    .frame(minHeight: 120)

                if viewModel.output.introduction.isEmpty {
                    Text("간단한 소개를 작성해주세요")
                        .font(.bodyMedium)
                        .foregroundColor(.gray300)
                        .padding(.horizontal, .spacing16)
                        .padding(.vertical, .spacing16)
                }

                TextEditor(text: $viewModel.output.introduction)
                    .font(.bodyMedium)
                    .foregroundColor(.primary100)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, .spacing12)
                    .padding(.vertical, .spacing8)
                    .frame(minHeight: 120)
                    .focused($focusedField, equals: .introduction)
            }
        }
    }

    private func lineField(
        _ title: String,
        text: Binding<String>,
        prompt: String? = nil,
        keyboardType: UIKeyboardType = .default,
        field: Field
    ) -> some View {
        VStack(alignment: .leading, spacing: .spacing8) {
            Text(title)
                .font(.bodyMedium)
                .foregroundColor(.gray700)

            TextField(prompt ?? "\(title)을 입력해주세요", text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .keyboardType(keyboardType)
                .focused($focusedField, equals: field)
                .submitLabel(.done)
                .padding()
                .overlay(
                    RoundedRectangle(cornerRadius: .spacing16)
                        .stroke(.gray300, lineWidth: 1)
                )
        }
    }

    private func secureLineField(
        _ title: String,
        text: Binding<String>,
        prompt: String,
        field: Field
    ) -> some View {
        VStack(alignment: .leading, spacing: .spacing8) {
            Text(title)
                .font(.bodyMedium)
                .foregroundColor(.gray700)

            SecureField(prompt, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .focused($focusedField, equals: field)
                .submitLabel(.done)
                .padding()
                .overlay(
                    RoundedRectangle(cornerRadius: .spacing16)
                        .stroke(.gray300, lineWidth: 1)
                )
        }
    }
}

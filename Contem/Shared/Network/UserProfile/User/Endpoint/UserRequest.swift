//
//  UserRequest.swift
//  Contem
//
//  Created by 이상민 on 11/18/25.
//

import Foundation

enum UserRequest: TargetTypeProtocol {
    // MARK: - Case
    case login(email: String, password: String)
    case join(
        email: String,
        password: String,
        nick: String,
        name: String,
        introduction: String,
        phoneNum: String,
        hashTags: [String],
        deviceToken: String
    )
    case appleLogin(token: String)
    case kakaoLogin(token: String)
    
    // MARK: - Path
    var path: String {
        switch self {
        case .login:
            return "/users/login"
        case .join:
            return "/users/join"
        case .appleLogin:
            return "/users/login/apple"
        case .kakaoLogin:
            return "/users/login/kakao"
        }
    }
    
    // MARK: - Method
    var method: HTTPMethod {
        switch self {
        case .login, .join, .appleLogin, .kakaoLogin:
            return .post
        }
    }
    
    // MARK: - Headers
    var headers: [String : String] {
        return [
            "SeSACKey": APIConfig.sesacKey,
            "ProductId": APIConfig.productID
        ]
    }
    
    // MARK: - Parameters
    var parameters: [String : Any] {
        switch self {
        case .login(let email, let password):
            ["email": email, "password": password]
        case .join(let email, let password, let nick, let name, let introduction, let phoneNum, let hashTags, let deviceToken):
            [
                "email": email,
                "password": password,
                "nick": nick,
                "name": name,
                "introduction": introduction,
                "phoneNum": phoneNum,
                "hashTags": hashTags,
                "deviceToken": deviceToken
            ]
        case .appleLogin(let token):
            ["idToken":token]
        case .kakaoLogin(let token):
            ["oauthToken": token]
        }
    }
    
    var hasAuthorization: Bool{
        switch self {
        case .login, .join, .appleLogin, .kakaoLogin:
            return false
        }
    }
    
    var multipartFiles: [MultipartFile]?{
        switch self {
        case .login, .join, .appleLogin, .kakaoLogin:
            nil
        }
    }
}

//
//  ChatHeaderView.swift
//  Contem
//
//  Created by 이상민 on 11/29/25.
//

import SwiftUI

struct ChatHeaderView: View {
    let nickname: String?
    let profileImage: URL?
    
    var body: some View {
        VStack(spacing: .spacing16) {
            ChatImageView(url: profileImage, contentMode: .fill)
                .frame(width: 96, height: 96)
                .background(Color.gray50)
                .clipShape(.circle)
                .overlay(Circle().stroke(Color.primary0, lineWidth: 3))
                .shadow(color: .black.opacity(0.08), radius: 18, x: 0, y: 12)

            VStack(spacing: .spacing8) {
                Text(nickname ?? "Loading...")
                    .font(.titleMedium)

                Text("브랜드 협업 디렉션을 실시간으로 조율하는 대화")
                    .font(.captionRegular)
                    .foregroundStyle(.gray500)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, .spacing28)
        .background(
            RoundedRectangle(cornerRadius: .radiusLarge, style: .continuous)
                .fill(Color.primary0.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: .radiusLarge, style: .continuous)
                .stroke(Color.gray100.opacity(0.7), lineWidth: 1)
        )
    }
}

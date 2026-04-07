//
//  MessageRowView.swift
//  Contem
//
//  Created by 이상민 on 11/29/25.
//

import SwiftUI

struct MessageRowView: View {
    let message: ChatMessageObject
    let isMyMessage: Bool
    var onImageLoaded: (() -> Void)? = nil
    var onImageTap: ((Int, [URL]) -> Void)? = nil
    
    var body: some View {
        HStack(alignment: .bottom, spacing: .spacing8) {
            if !isMyMessage {
                VStack(alignment: .leading, spacing: .spacing4) {
                    Text(message.sender?.nick ?? "알 수 없음")
                        .font(.captionRegular)
                        .foregroundColor(.gray700)

                    messageContent
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .trailing, spacing: .spacing4) {
                    Text("나")
                        .font(.captionRegular)
                        .foregroundColor(.gray700)
                    messageContent
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
    
    private var messageContent: some View {
        HStack(alignment: .bottom, spacing: .spacing8) {
            if isMyMessage {
                timestamp
            }
            
            VStack(
                alignment: isMyMessage ? .trailing : .leading,
                spacing: .spacing8
            ) {
                if let content = message.content, !content.isEmpty {
                    Text(content)
                        .font(.bodyRegular)
                        .multilineTextAlignment(isMyMessage ? .trailing : .leading)
                }
                
                if !message.fileURLs.isEmpty {
                    ForEach(Array(message.fileURLs.enumerated()), id: \.element) { index, url in
                        Button {
                            onImageTap?(index, message.fileURLs)
                        } label: {
                            ChatImageView(url: url, contentMode: .fill)
                                .frame(width: 210, height: 210)
                                .clipShape(RoundedRectangle(cornerRadius: .radiusMedium, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: .radiusMedium, style: .continuous)
                                        .stroke(Color.primary0.opacity(isMyMessage ? 0.18 : 0), lineWidth: 1)
                                )
                                .onAppear {
                                    if url == message.fileURLs.last {
                                        onImageLoaded?()
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .contentShape(RoundedRectangle(cornerRadius: .radiusMedium, style: .continuous))
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(isMyMessage ? Color.primary100 : Color.primary0.opacity(0.96))
            .foregroundColor(isMyMessage ? .primary0 : .primary100)
            .clipShape(RoundedRectangle(cornerRadius: .radiusLarge, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: .radiusLarge, style: .continuous)
                    .stroke(isMyMessage ? Color.clear : Color.gray100.opacity(0.8), lineWidth: 1)
            )
            .shadow(color: .black.opacity(isMyMessage ? 0 : 0.04), radius: 8, x: 0, y: 4)
            
            if !isMyMessage {
                timestamp
            }
        }
        .frame(maxWidth: .infinity, alignment: isMyMessage ? .trailing : .leading)
    }
    
    private var timestamp: some View {
        Text(message.createdAt, style: .time)
            .font(.captionSmall)
            .foregroundColor(.gray700)
            .padding(.bottom, 4)
    }
}

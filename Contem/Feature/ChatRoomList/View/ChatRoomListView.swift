import SwiftUI
import Combine
import Kingfisher

struct ChatRoomListView: View {
    @StateObject private var viewModel: ChatRoomListViewModel
    
    init(coordinator: AppCoordinator) {
        _viewModel = StateObject(
            wrappedValue: ChatRoomListViewModel(
                coordinator: coordinator,
            )
        )
    }
    
    var body: some View {
        ZStack {
            Color.primary0.ignoresSafeArea()

            if !viewModel.output.chatRoomList.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.output.chatRoomList) { room in
                            Button {
                                viewModel.input.chatRoomTapped.send(room.partnerId)
                            } label: {
                                ChatRoomRow(chatRoom: room)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, .spacing8)
                    .padding(.bottom, .spacing24)
                }
                .refreshable { }
            } else {
                Text("대화중인 상대방이 없습니다.")
            }
        }
        .onAppear {
            viewModel.input.onAppearTrigger.send(())
        }
        .navigationTitle("채팅방 목록")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.light, for: .navigationBar)
        .toolbarBackground(Color.primary0, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    viewModel.input.dismissButtonTapped.send(())
                } label: {
                    Image(systemName: "chevron.left")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 12, height: 20)
                        .foregroundStyle(.primary100)
                }
            }
        }
    }
}

struct ChatRoomRow: View {
    let chatRoom: ChatRoomEntity
    
    var body: some View {
        HStack(alignment: .top, spacing: .spacing12) {
            avatarView

            VStack(alignment: .leading, spacing: .spacing4) {
                Text(chatRoom.partnerName)
                    .font(.titleSmall)
                    .foregroundStyle(.primary100)

                Text(chatRoom.lastChatContent)
                    .font(.bodyRegular)
                    .foregroundStyle(.gray700)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(formattedTime)
                .font(.captionRegular)
                .foregroundStyle(.gray500)
                .lineLimit(1)
                .frame(width: 56, alignment: .trailing)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, .spacing16)
        .padding(.vertical, .spacing4)
        .frame(height: 88)
        .background(Color.primary0)
        .contentShape(Rectangle())
    }

    private var avatarView: some View {
        Group {
            if let assetName = MockImageURL.assetName(from: chatRoom.partnerProfileImage) {
                Image(assetName)
                    .resizable()
            } else if chatRoom.partnerProfileImage != nil {
                KFImage(chatRoom.partnerProfileImage)
                    .requestModifier(MyImageDownloadRequestModifier())
                    .resizable()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.gray300)
            }
        }
        .scaledToFill()
        .frame(width: 56, height: 56)
        .clipShape(Circle())
    }

    private var formattedTime: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(chatRoom.lastMessageTime) {
            return chatRoom.lastMessageTime.formatted(date: .omitted, time: .shortened)
        }
        return chatRoom.lastMessageTime.formatted(.dateTime.month().day())
    }
}

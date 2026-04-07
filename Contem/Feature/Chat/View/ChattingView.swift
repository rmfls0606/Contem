//
//  ChattingView.swift
//  Contem
//
//  Created by 이상민 on 11/27/25.
//

import SwiftUI
import Combine
import PhotosUI

// 이미지 프리뷰를 위한 Identifiable 래퍼
struct IdentifiableImageData: Identifiable, Equatable { // Equatable 추가
    let id = UUID() // Truly unique ID for the IdentifiableImageData struct itself
    let data: Data
    let photosPickerItem: PhotosPickerItem
    
    // Equatable 구현 (Data 비교는 오버헤드가 크므로 id만 비교)
    static func == (lhs: IdentifiableImageData, rhs: IdentifiableImageData) -> Bool {
        lhs.id == rhs.id
    }
}

private enum GalleryImageSource: Identifiable, Equatable {
    case data(IdentifiableImageData)
    case url(URL)

    var id: String {
        switch self {
        case .data(let image):
            return image.id.uuidString
        case .url(let url):
            return url.absoluteString
        }
    }
}

private struct ImageGalleryState: Identifiable {
    let id = UUID()
    let items: [GalleryImageSource]
    let initialIndex: Int
}

struct ChattingView: View {
    @ObservedObject private var viewModel: ChattingViewModel
    
    @State private var scrollWorkItem: DispatchWorkItem?
    @State private var galleryState: ImageGalleryState?
    
    init(viewModel: ChattingViewModel) {
        self.viewModel = viewModel
    }
    
    var body: some View {
        VStack(spacing: 0) {
            messageListView
            MessageInputView(viewModel: viewModel, galleryState: $galleryState)
                .background(Color.gray25.ignoresSafeArea(edges: .bottom))
        }
        .navigationTitle(viewModel.output.opponentNickname ?? "채팅")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.light, for: .navigationBar)
        .toolbarBackground(Color.primary0, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear {
            viewModel.input.appear.send(())
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    // 뒤로가기 액션
                    // 만약 Coordinator로 pop 처리를 한다면:
                    viewModel.input.dismissButtonTapped.send(())
                } label: {
                    Image(systemName: "chevron.left") // 화살표 이미지
                        .resizable()
                        .scaledToFit()
                        .frame(width: 12, height: 20) // 적절한 크기 조절
                        .foregroundStyle(.black)      // 검정색 설정
                }
            }
        }
        .alert(isPresented: .constant(viewModel.output.error != nil)) {
            Alert(
                title: Text("Error"),
                message: Text(viewModel.output.error?.localizedDescription ?? "An unknown error occurred."),
                dismissButton: .default(Text("OK"))
            )
        }
        .background(Color.gray25)
        .contentShape(Rectangle())
        .onTapGesture {
            hideKeyboard()
        }
        .fullScreenCover(item: $galleryState) { state in
            PreviewGalleryViewer(state: state)
        }
    }
    
    private var messageListView: some View {
        ScrollView {
            ScrollViewReader { scrollViewProxy in
                LazyVStack(spacing: .spacing16) {
                    if let messages = viewModel.output.messages {
                        ForEach(messages) { message in
                            MessageRowView(
                                message: message,
                                isMyMessage: message.sender?.userId == viewModel.output.currentUserId,
                                onImageLoaded: {
                                    // 이미지가 로드되면 항상 디바운스 스크롤 호출
                                    debounceScroll(proxy: scrollViewProxy)
                                },
                                onImageTap: { selectedIndex, urls in
                                    galleryState = ImageGalleryState(
                                        items: urls.map { .url($0) },
                                        initialIndex: selectedIndex
                                    )
                                }
                            )
                            .id(message.id)
                        }
                    } else {
                        ProgressView()
                    }
                    
                    // 하단 패딩을 위한 Spacer 추가 (높이 1로 설정)
                    Spacer().frame(height: 1).id("bottom-content-padding")
                }
                .padding(.horizontal, .spacing16)
                .padding(.top, .spacing12)
                .padding(.bottom, .spacing24)
                .onAppear {
                    // 뷰가 나타날 때, 컨텐츠가 있을 수 있으므로 디바운스 스크롤 호출
                    debounceScroll(proxy: scrollViewProxy)
                }
                .onChange(of: viewModel.output.messages?.last?.id, perform: { newLastId in
                    // 새 메시지가 도착했을 때
                    if let lastMessage = viewModel.output.messages?.last, lastMessage.id == newLastId {
                        if lastMessage.files.isEmpty {
                            // 새 메시지에 이미지가 없으면 즉시 스크롤
                            withAnimation {
                                scrollToBottom(proxy: scrollViewProxy)
                            }
                        } else {
                            // 새 메시지에 이미지가 있으면, onImageLoaded가 처리하도록 디바운스 스크롤 호출
                            debounceScroll(proxy: scrollViewProxy)
                        }
                    } else {
                        // 메시지가 없거나 lastMessage.id가 newLastId와 다를 경우 (e.g., 메시지 삭제 시)
                        // 이 경우에도 스크롤 위치를 조정해야 할 수 있음.
                        // 일단은 debounceScroll을 호출하여 안전하게 처리
                        debounceScroll(proxy: scrollViewProxy)
                    }
                })
            }
        }
        .background(Color.clear)
    }
    
    // 스크롤 대상을 변경
    private func scrollToBottom(proxy: ScrollViewProxy) {
        // 맨 아래 패딩 Spacer의 ID를 타겟으로 스크롤
        proxy.scrollTo("bottom-content-padding", anchor: .bottom)
    }

    private func debounceScroll(proxy: ScrollViewProxy) {
        self.scrollWorkItem?.cancel()
        
        let workItem = DispatchWorkItem {
            withAnimation {
                self.scrollToBottom(proxy: proxy)
            }
        }
        
        self.scrollWorkItem = workItem
        // 딜레이를 0.5초로 늘려 이미지 로딩 시간을 더 확보
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }
}

// 추출된 개별 이미지 미리보기 뷰 (삭제 버튼 로직 제거)
private struct ImagePreviewItemView: View {
    let identifiableImage: IdentifiableImageData
    
    var body: some View {
        if let uiImage = UIImage(data: identifiableImage.data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct MessageInputView: View {
    @ObservedObject var viewModel: ChattingViewModel
    @Binding var galleryState: ImageGalleryState?
    @State private var messageText: String = ""
    @State private var selectedImages: [PhotosPickerItem] = []
    @State private var previewImages: [IdentifiableImageData] = []
    @State private var imagesDataToSend: [Data] = []
    
    var body: some View {
        VStack(spacing: 0) {
            imagePreviewSection
            inputBarSection
        }
        .padding(.top, CGFloat.spacing16)
        .padding(.bottom, .spacing12)
        .background(.primary0)
        .onChange(of: selectedImages) { newItems in
            Task {
                var newPreview: [IdentifiableImageData] = []
                var newImagesDataToSend: [Data] = []
                
                for item in newItems {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        newPreview.append(IdentifiableImageData(data: data, photosPickerItem: item))
                        newImagesDataToSend.append(data)
                    }
                }
                
                await MainActor.run {
                    previewImages = newPreview
                    imagesDataToSend = newImagesDataToSend
                }
            }
        }
    }
    
    private var imagePreviewSection: some View {
        Group {
            if !previewImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: .spacing8) {
                        ForEach(previewImages) { identifiableImage in
                            ImagePreviewItemView(identifiableImage: identifiableImage)
                                .padding(.spacing8)
                                .overlay(alignment: .topTrailing) {
                                    Button {
                                        withAnimation {
                                            let updatedPreviewImages = previewImages.filter { $0.id != identifiableImage.id }
                                            previewImages = updatedPreviewImages
                                            selectedImages = updatedPreviewImages.map { $0.photosPickerItem }
                                            imagesDataToSend = updatedPreviewImages.map { $0.data }
                                        }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.black, .white)
                                            .font(.system(size: 16))
                                    }
                                }
                                .transition(.scale)
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(height: 70)
                .padding(.bottom, .spacing16)
            }
        }
    }
    
    private var inputBarSection: some View {
        HStack(spacing: 12) {
            PhotosPicker(selection: $selectedImages, maxSelectionCount: 5, matching: .images) {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 24))
                    .foregroundColor(.gray)
            }
            
            ZStack(alignment: .leading) {
                if messageText.isEmpty {
                    Text("메시지를 입력해주세요...")
                        .font(.system(size: 14))
                        .foregroundStyle(.gray700)
                        .padding(.horizontal, 12)
                }

                TextField("", text: $messageText)
                    .font(.system(size: 14))
                    .foregroundStyle(.primary100)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .frame(height: 40)
            .background(Color(red: 0.91, green: 0.91, blue: 0.93))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            
            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .resizable()
                    .frame(width: 32, height: 32)
                    .foregroundStyle((messageText.isEmpty && previewImages.isEmpty) ? Color.gray : Color.primary100)
            }
            .disabled(messageText.isEmpty && previewImages.isEmpty)
        }
        .padding(.horizontal, 16)
    }
    
    private func sendMessage() {
        viewModel.input.sendMessage.send((messageText, imagesDataToSend.isEmpty ? nil : imagesDataToSend))
        messageText = ""
        selectedImages = []
        previewImages = []
        imagesDataToSend = []
    }
}

private struct PreviewGalleryViewer: View {
    let state: ImageGalleryState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIndex: Int

    init(state: ImageGalleryState) {
        self.state = state
        _selectedIndex = State(initialValue: state.initialIndex)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            TabView(selection: $selectedIndex) {
                ForEach(Array(state.items.enumerated()), id: \.element.id) { index, item in
                    previewContent(for: item)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: state.items.count > 1 ? .automatic : .never))

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary0)
                    .frame(width: 40, height: 40)
                    .background(Color.primary100.opacity(0.45))
                    .clipShape(Circle())
            }
            .padding(.top, .spacing20)
            .padding(.trailing, .spacing16)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func previewContent(for item: GalleryImageSource) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let maxHeight = proxy.size.height * 0.82

            ZStack {
        switch item {
        case .data(let image):
            if let uiImage = UIImage(data: image.data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: width)
                    .frame(maxHeight: maxHeight)
            }
        case .url(let url):
            ChatImageView(url: url, contentMode: .fit)
                .frame(width: width)
                        .frame(maxHeight: maxHeight)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

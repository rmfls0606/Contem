import SwiftUI
import Kingfisher
import UIKit

struct ChatImageView: View {
    let url: URL?
    let contentMode: SwiftUI.ContentMode

    var body: some View {
        Group {
            if let assetName = MockImageURL.assetName(from: url) {
                Image(assetName)
                    .resizable()
            } else if let fileURL = url, fileURL.isFileURL, let uiImage = UIImage(contentsOfFile: fileURL.path) {
                Image(uiImage: uiImage)
                    .resizable()
            } else {
                KFImage(url)
                    .requestModifier(MyImageDownloadRequestModifier())
                    .resizable()
            }
        }
        .aspectRatio(contentMode: contentMode)
    }
}

import SwiftUI
import UIKit

struct ImageDocumentView: View {
    private let image: UIImage?
    @State private var scale: CGFloat = 1
    @GestureState private var gestureScale: CGFloat = 1

    init(url: URL) { image = UIImage(contentsOfFile: url.path) }

    var body: some View {
        if let image {
            GeometryReader { geometry in
                ScrollView([.horizontal, .vertical]) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .scaleEffect(scale * gestureScale)
                        .frame(width: geometry.size.width * scale * gestureScale,
                               height: geometry.size.height * scale * gestureScale)
                }
                .gesture(MagnificationGesture()
                    .updating($gestureScale) { value, state, _ in state = value }
                    .onEnded { scale = min(max(scale * $0, 1), 5) })
                .onTapGesture(count: 2) { scale = scale == 1 ? 2 : 1 }
            }
            .clipped()
        } else {
            ViewerErrorView(message: "画像を読み込めません。ファイルが破損している可能性があります。")
        }
    }
}

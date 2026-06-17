import SafariServices
import SwiftUI

struct ArticleDetailSafariPresentation: Identifiable, Equatable {
    let id: String
    let url: URL

    init(request: ArticleDetailOriginalArticleRequest) {
        self.id = "\(request.itemID)-\(request.url.absoluteString)"
        self.url = request.url
    }
}

struct ArticleDetailSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context _: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_: SFSafariViewController, context _: Context) {}
}

import SwiftUI

struct RootView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var items: [FeedItem] = []
    @State private var isDrawerOpen = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .leading) {
                timeline
                    .disabled(isDrawerOpen)
                    .offset(x: isDrawerOpen ? 280 : 0)

                if isDrawerOpen {
                    Color.black.opacity(0.32)
                        .ignoresSafeArea()
                        .onTapGesture { isDrawerOpen = false }
                }

                DrawerView()
                    .frame(width: 280)
                    .offset(x: isDrawerOpen ? 0 : -300)
            }
            .animation(.snappy, value: isDrawerOpen)
            .navigationTitle("すべての新着")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isDrawerOpen.toggle()
                    } label: {
                        Image(systemName: "line.3.horizontal")
                    }
                    .accessibilityLabel("メニュー")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel("検索")
                }
            }
            .task {
                items = (try? await environment.feedRepository.crossFeedItems()) ?? []
            }
        }
    }

    private var timeline: some View {
        List(items) { item in
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(item.feedTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if item.isStarred {
                        Image(systemName: "star.fill")
                            .foregroundStyle(FeedmanTheme.star)
                    }
                }
                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(item.isRead ? .secondary : .primary)
                Text(item.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(.vertical, 6)
        }
        .listStyle(.plain)
    }
}

private struct DrawerView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(FeedmanTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                Text("Feedman")
                    .font(.title3.bold())
            }
            .padding(.top, 24)

            Label("すべての新着", systemImage: "sparkles")
            Label("お気に入り", systemImage: "star")

            Divider()

            Text("フィード")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            Label("Publickey", systemImage: "p.circle.fill")
            Label("Zenn トレンド", systemImage: "z.circle.fill")

            Spacer()

            Label("アカウント", systemImage: "person")
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(FeedmanTheme.background)
    }
}

#Preview {
    RootView()
        .environmentObject(AppEnvironment.preview)
}


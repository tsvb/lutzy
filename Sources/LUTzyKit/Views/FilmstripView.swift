import SwiftUI

/// Horizontal thumbnail strip for browsing imported images.
struct FilmstripView: View {
    let collection: ImageCollection
    let onSelect: (Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(Array(collection.items.enumerated()), id: \.element.id) { index, item in
                        FilmstripThumbnail(
                            item: item,
                            isSelected: index == collection.selectedIndex
                        )
                        .id(item.id)
                        .onTapGesture {
                            onSelect(index)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(.bar)
            .onChange(of: collection.selectedIndex) { _, newIndex in
                guard collection.items.indices.contains(newIndex) else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(collection.items[newIndex].id, anchor: .center)
                }
            }
        }
    }
}

struct FilmstripThumbnail: View {
    let item: ImageCollection.Item
    let isSelected: Bool

    var body: some View {
        ZStack {
            if let thumbnail = item.thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 64, height: 64)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 64, height: 64)
                    .overlay {
                        ProgressView()
                            .scaleEffect(0.5)
                    }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .padding(3)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .accessibilityLabel(item.displayName)
    }
}

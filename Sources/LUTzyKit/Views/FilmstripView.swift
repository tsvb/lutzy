import SwiftUI

/// Horizontal thumbnail strip for browsing imported images.
struct FilmstripView: View {
    @ObservedObject var collection: ImageCollection
    let onSelect: (Int) -> Void

    /// Set when the selection changed because the user clicked a thumbnail, so
    /// the strip does not then scroll itself.
    @State private var selectedByClick = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(Array(collection.items.enumerated()), id: \.element.id) { index, item in
                        // A Button rather than `.onTapGesture`. Inside a scroll
                        // view a tap gesture is lost whenever the pointer moves
                        // a pixel between press and release — the scroll view
                        // claims it as a drag — which is exactly what happens
                        // when someone clicks quickly through a set. A button's
                        // hit testing does not have that problem.
                        Button {
                            selectedByClick = true
                            onSelect(index)
                        } label: {
                            FilmstripThumbnail(
                                item: item,
                                isSelected: index == collection.selectedIndex
                            )
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .id(item.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(.bar)
            .onChange(of: collection.selectedIndex) { _, newIndex in
                guard collection.items.indices.contains(newIndex) else { return }
                // Never scroll in response to a click. The thumbnail that was
                // clicked is on screen by definition, and recentring it drags
                // the whole strip out from under the pointer — so the next
                // click in a quick run lands on a different picture, or on the
                // gap between two. Keyboard stepping still scrolls, since there
                // the next image may well be off screen.
                guard selectedByClick == false else {
                    selectedByClick = false
                    return
                }
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
        VStack(spacing: 4) {
            ZStack {
                if let thumbnail = item.thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 72, height: 72)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.15))
                        .frame(width: 72, height: 72)
                        .overlay {
                            ProgressView()
                                .scaleEffect(0.5)
                        }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2.5)
            )

            Text(item.displayName)
                .font(.system(size: 9))
                .foregroundColor(isSelected ? .primary : .secondary)
                .lineLimit(1)
                .frame(width: 72)
        }
    }
}

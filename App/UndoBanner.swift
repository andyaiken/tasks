import SwiftUI

/// A banner offering to undo the last action for a few seconds (SPEC §3, "retracted").
private struct UndoBanner: ViewModifier {
    @Environment(Store.self) private var store

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let undo = store.undo {
                HStack {
                    Text(undo.message)
                        .lineLimit(1)
                    Spacer()
                    Button("Undo") {
                        withAnimation { store.undoLast() }
                    }
                    .bold()
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(.regularMaterial, in: .capsule)
                .shadow(radius: 4, y: 2)
                .padding(.horizontal)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: undo.id) {
                    try? await Task.sleep(for: .seconds(6))
                    withAnimation { store.dismissUndo(undo.id) }
                }
            }
        }
        .animation(.default, value: store.undo)
    }
}

extension View {
    func undoBanner() -> some View {
        modifier(UndoBanner())
    }
}

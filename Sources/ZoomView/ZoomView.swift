//
//  ZoomView.swift
//  ImageViewer
//
//  Created by Gerald Burke on 11/19/24.
//

import SwiftUI

// TODO: Gather comments and really document the type instead with a readme-style header.

public struct ZoomView<Item: Hashable, Content: View>: View {
    /// An item represented by the zoomed view. Nil means no content is zoomed.
    @Binding var item: Item?
    /// A builder for the ZoomView‘s content.
    @ViewBuilder let content: (Item) -> Content
    /// The phase of the presentation animation.
    @State private var phase: ZoomViewPhase = .inactive

    public init(item: Binding<Item?>, content: @escaping (Item) -> Content) {
        _item = item
        self.content = content
    }

    public var body: some View {
        let view = item.map(content)
        ZStack {
            // TODO: Include an init arg () -> some View to define background at call site.
            /// A dimmed background for the presentation.
            Rectangle().fill(item == nil ? .clear : .black.opacity(0.7))
                .ignoresSafeArea()
                .allowsHitTesting(phase != .inactive)
                // TODO: Mimic the tap-to-dismiss behavior installed on the ZoomableScrollView.
            /// The content.
            switch phase {
            case .inactive:
                /// I thought EmptyView would work here but it didn‘t seem to?
                Rectangle().fill(.clear)
                    .allowsHitTesting(false)
            case .transitioning:
                /// Just render the content as a View.
                view
            case .presented:
                /// Embed the content in ZoomableScrollView.
                ZoomableScrollView(zoomPhase: $phase) {
                    view
                }
            }
        }
        /// Setting item to a non-nil value activates presentation.
        .onChange(of: item) { newValue in
            if newValue != nil {
                // TODO: Make animation type configurable.
                // FIXME: Completion handler has noticeable delay from animation end to tappable.
                /// The .removed completion criteria prevents premature presentation of the
                /// ZoomableScrollView that made the transition animation look janky.
                withAnimation(.bouncy, completionCriteria: .removed) {
                    phase = .transitioning
                } completion: {
                    /// Transition complete, show the ZoomableScrollView.
                    self.phase = .presented
                }
            } else {
                /// Dismiss the presentation.
                withAnimation {
                    self.phase = .inactive
                }
            }
        }
        /// This happens if the user dismisses the presentation by, for example, tapping outside the
        /// content in ZoomableScrollView.
        .onChange(of: phase) { newValue in
            if case .inactive = phase, item != nil {
                withAnimation {
                    item = nil
                }
            }
        }
    }
}
/// A simple matched geometry effect is not enough to get a smooth animation. Views contained in
/// UIHostingController instances don‘t seem to obey the transition APIs. In order to get the look
/// right, I had to make a "transition" state that just shows the content during the presentation
/// animation. When the animation is complete, I reveal the ZoomableScrollView with the content
/// embedded.
enum ZoomViewPhase: Animatable {
    case inactive
    case transitioning
    case presented
}

/// A type to leverage UIScrollView‘s zooming behavior in SwiftUI.
struct ZoomableScrollView<Content: View>: UIViewRepresentable {
    /// The underlying scroll view that provides the good zoom and bounce behavior SwiftUI does not.
    private let scrollView = UIScrollView(frame: .zero)
    /// Whether the ZoomView is currently visible.
    // TODO: Consider replacing with Item and letting ZoomView manage phase privately.
    let zoomPhase: Binding<ZoomViewPhase>
    /// The zoomable content of the ZoomView.
    @ViewBuilder let content: () -> Content

    // MARK: - UIViewRepresentable
    
    func makeCoordinator() -> Coordinator {
        Coordinator(zoomPhase: zoomPhase, scrollView: scrollView, content: content)
    }

    func makeUIView(context: Context) -> UIScrollView {
        return scrollView
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {

    }

    class Coordinator: NSObject, UIScrollViewDelegate {
        private let zoomPhase: Binding<ZoomViewPhase>
        private let scrollView: UIScrollView
        private let content: () -> Content
        private var zoomableContentView: UIView?
        private let maxVerticalScrollDistance: CGFloat = 60.0
        private let escapeVelocity: CGFloat = 1000
        private let maxZoomScale: CGFloat = 2.5

        init(
            zoomPhase: Binding<ZoomViewPhase>,
            scrollView: UIScrollView,
            content: @escaping () -> Content,
            zoomableContentView: UIView? = nil
        ) {
            self.zoomPhase = zoomPhase
            self.scrollView = scrollView
            self.content = content
            self.zoomableContentView = zoomableContentView
            super.init()
            configureScrollView()
        }

        private func configureScrollView() {
            /// Configure scroll view.
            { [maxZoomScale] in
                $0.delegate = self
                $0.alwaysBounceHorizontal = true
                $0.alwaysBounceVertical = true
                $0.showsVerticalScrollIndicator = false
                $0.showsHorizontalScrollIndicator = false
                $0.maximumZoomScale = maxZoomScale
                $0.zoomScale = 1.0
            }(scrollView)

            /// Add double-tap to zoom feature.
            addTapGesture(to: scrollView, requiredTaps: 2)
            /// Add single tap to revert zoom or dismiss.
            addTapGesture(to: scrollView, requiredTaps: 1)
            /// Show the content.
            addHostView()
        }

        private func addHostView() {
            /// Create host view to present SwiftUI content.
            let host = UIHostingController(rootView: content())
            /// Add host view to scroll view and configure.
            host.view.map { [scrollView] in
                scrollView.addSubview($0)
                $0.backgroundColor = .clear
                $0.translatesAutoresizingMaskIntoConstraints = false
                /// Constrain host view aspect ratio, filling scroll view width.
                // TODO: Constrain max width so content is not giant on iPad.
                let multiplier = $0.intrinsicContentSize.height / $0.intrinsicContentSize.width
                NSLayoutConstraint.activate([
                    $0.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
                    $0.heightAnchor.constraint(equalTo: $0.widthAnchor, multiplier: multiplier),
                    $0.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
                    $0.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
                ])
            }
            /// Retain view for zooming.
            zoomableContentView = host.view
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            /// Adjust the inset to keep the content edges and position correct while zoomed.
            zoomableContentView.map {
                let contentSize = $0.intrinsicContentSize

                /// Get the height of the content, scaled down to fit in the scroll view bounds.
                let contentHeight =
                    contentSize.width > contentSize.height
                    ? contentSize.height * ($0.bounds.width / contentSize.width)
                    : contentSize.height * ($0.bounds.height / contentSize.height)

                /// We do a little magic number.
                // TODO: Get this actually right with no magic numbers.
                let denominator: CGFloat = contentSize.width > contentSize.height ? 3 : 2
                let marginHeight: CGFloat = scrollView.frame.size.height - contentHeight
                let extent: CGFloat = marginHeight / denominator

                /// The actual edge inset value to apply.
                let inset =
                    scrollView.zoomScale > 1
                    ? UIEdgeInsets(top: -extent, left: 0, bottom: extent, right: 0)
                    : UIEdgeInsets.zero

                /// Animate the change so it doesn't flicker or stutter.
                UIView.animate(withDuration: 0.1) {
                    scrollView.contentInset = inset
                }
            }
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard dragShouldDismiss() else {
                return
            }
            withAnimation(.bouncy) {
                zoomPhase.wrappedValue = .inactive
            }
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            zoomableContentView
        }

        private func dragShouldDismiss() -> Bool {
            guard
                scrollView.zoomScale == 1,
                scrollView.panGestureRecognizer.state == .ended,
                zoomPhase.wrappedValue != .inactive
            else {
                return false
            }
            let velocity = scrollView.panGestureRecognizer.velocity(in: scrollView).y
            let offset = abs(scrollView.contentOffset.y)
            return velocity > escapeVelocity || offset > maxVerticalScrollDistance
        }

        private func addTapGesture(to view: UIView, requiredTaps: Int) {
            let tap = UITapGestureRecognizer()
            tap.numberOfTapsRequired = requiredTaps
            tap.addTarget(self, action: #selector(handleGesture))
            view.addGestureRecognizer(tap)
        }

        @objc private func handleGesture(_ gesture: UIGestureRecognizer) {
            if let tap = gesture as? UITapGestureRecognizer {
                switch tap.numberOfTapsRequired {
                case 1:
                    // Single tap is only handled outside of the content‘s bounds.
                    // If zoomed in, zoom out to default. Otherwise, dismiss.
                    if let hostView = scrollView.subviews.first, !hostView.contains(tap) {
                        if scrollView.zoomScale > 1 {
                            scrollView.setZoomScale(1, animated: true)
                        } else {
                            withAnimation(.snappy) {
                                zoomPhase.wrappedValue = .inactive
                            }
                        }
                    }
                case 2:
                    let newZoom = scrollView.zoomScale == 1 ? maxZoomScale : 1
                    scrollView.setZoomScale(newZoom, animated: true)
                default:
                    break
                }
            }
        }
    }
}

extension UIView {
    fileprivate func contains(_ gesture: UIGestureRecognizer) -> Bool {
        let location = gesture.location(in: self)
        return (0..<bounds.maxY).contains(location.y) && (0..<bounds.maxX).contains(location.x)
    }
}

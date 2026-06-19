import SwiftUI
import MapKit
import WebKit

enum StreetViewProvider: String, CaseIterable {
    case apple = "Apple"
    case google = "Google"
}

struct LookAroundSheet: View {
    @Binding var coordinate: CLLocationCoordinate2D
    let title: String
    @Environment(\.dismiss) private var dismiss
    @State private var scene: MKLookAroundScene?
    @State private var isAppleLoading = true
    @State private var appleAvailable = false
    @State private var selectedProvider: StreetViewProvider = .apple

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Street View")
                    .font(.obsidianSubheadline)
                    .foregroundColor(.textPrimary)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.obsidianCaption)
                        .foregroundColor(.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(Color.obsidianElevated)
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 10)

            // Provider toggle
            HStack(spacing: 0) {
                ForEach(StreetViewProvider.allCases, id: \.self) { provider in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedProvider = provider
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: provider == .apple ? "apple.logo" : "globe")
                                .font(.obsidianSmall)
                            Text(provider.rawValue)
                                .font(.obsidianCaption)
                        }
                        .foregroundColor(selectedProvider == provider ? .white : .textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            selectedProvider == provider
                                ? Color.electricViolet
                                : Color.clear
                        )
                        .cornerRadius(10)
                    }
                }
            }
            .padding(3)
            .background(Color.obsidianSurface)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.obsidianBorder, lineWidth: 0.5)
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            // Content
            if selectedProvider == .apple {
                appleView
            } else {
                googleView
            }
        }
        .background(Color.obsidianBlack)
        .presentationBackground(Color.obsidianBlack)
        .onAppear {
            // Always load on appear — the task(id:) only fires on coordinate CHANGES
            Task { await loadAppleScene() }
        }
        .onChange(of: coordinate.latitude) { _, _ in
            Task { await loadAppleScene() }
        }
        .onChange(of: coordinate.longitude) { _, _ in
            Task { await loadAppleScene() }
        }
    }

    // MARK: - Apple Look Around

    @ViewBuilder
    private var appleView: some View {
        if isAppleLoading {
            Spacer()
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.electricViolet)
                Text("Checking Apple coverage...")
                    .font(.obsidianFootnote)
                    .foregroundColor(.textMuted)
            }
            Spacer()
        } else if let scene = scene {
            LookAroundRepresentable(scene: scene)
                .cornerRadius(16)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
        } else {
            Spacer()
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.statusNotHome.opacity(0.12))
                        .frame(width: 56, height: 56)
                    Image(systemName: "eye.slash")
                        .font(.system(size: 24))
                        .foregroundColor(.statusNotHome)
                }
                Text("No Apple coverage here")
                    .font(.obsidianBody)
                    .foregroundColor(.textSecondary)
                Button {
                    withAnimation { selectedProvider = .google }
                } label: {
                    Text("Switch to Google")
                        .font(.obsidianFootnote)
                        .foregroundColor(.electricViolet)
                }
            }
            Spacer()
        }
    }

    // MARK: - Google Street View

    private var googleView: some View {
        GoogleStreetWebView(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        .cornerRadius(16)
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    // MARK: - Load Apple Scene

    private func loadAppleScene() async {
        let target = coordinate
        guard target.latitude != 0 || target.longitude != 0 else { return }

        isAppleLoading = true
        scene = nil
        appleAvailable = false
        let request = MKLookAroundSceneRequest(coordinate: target)
        do {
            scene = try await request.scene
            appleAvailable = scene != nil
        } catch {
            scene = nil
            appleAvailable = false
        }
        isAppleLoading = false

        // Auto-switch to Google if Apple isn't available
        if !appleAvailable {
            withAnimation { selectedProvider = .google }
        }
    }
}

// MARK: - Google Street View WebView

private struct GoogleStreetWebView: UIViewRepresentable {
    let latitude: Double
    let longitude: Double

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        loadStreetView(in: webView)
        context.coordinator.lastLatitude = latitude
        context.coordinator.lastLongitude = longitude
        return webView
    }


    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastLatitude != latitude || context.coordinator.lastLongitude != longitude {
            loadStreetView(in: webView)
            context.coordinator.lastLatitude = latitude
            context.coordinator.lastLongitude = longitude
        }
    }

    private func loadStreetView(in webView: WKWebView) {
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>
                * { margin: 0; padding: 0; }
                body { background: #000; overflow: hidden; }
                iframe { width: 100vw; height: 100vh; border: none; }
            </style>
        </head>
        <body>
            <iframe src="https://www.google.com/maps/@\(latitude),\(longitude),3a,75y,0h,90t/data=!3m4!1e1!3m2!1s!2e0" allowfullscreen></iframe>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.google.com"))
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var lastLatitude: Double = 0
        var lastLongitude: Double = 0

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            if let url = navigationAction.request.url,
               url.host?.contains("google") == true || navigationAction.navigationType == .other {
                return .allow
            }
            return navigationAction.navigationType == .linkActivated ? .cancel : .allow
        }
    }
}

// MARK: - Look Around Representable

private struct LookAroundRepresentable: UIViewControllerRepresentable {
    let scene: MKLookAroundScene

    func makeUIViewController(context: Context) -> MKLookAroundViewController {
        let vc = MKLookAroundViewController()
        vc.scene = scene
        vc.isNavigationEnabled = true
        return vc
    }

    func updateUIViewController(_ vc: MKLookAroundViewController, context: Context) {
        vc.scene = scene
    }
}

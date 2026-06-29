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
            header

            VStack(spacing: 14) {
                locationSummaryCard
                providerPicker
                previewSection
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .frame(maxHeight: .infinity, alignment: .top)
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

    private var header: some View {
        HStack(spacing: 12) {
            ObsidianIconTile(icon: "binoculars.fill", tint: Color.statusInterested, size: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.obsidianTitle)
                    .foregroundColor(Color.textPrimary)

                Text("Preview the property before you walk up.")
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            ObsidianCompactIconButton(
                icon: "xmark",
                accessibilityLabel: "Close street view",
                accentColor: Color.textSecondary
            ) {
                dismiss()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    private var locationSummaryCard: some View {
        HStack(spacing: 12) {
            ObsidianIconTile(icon: "mappin.circle.fill", tint: Color.electricViolet, size: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text("Selected location")
                    .font(.obsidianCaption)
                    .foregroundColor(Color.textSecondary)

                Text(coordinateLabel)
                    .font(.obsidianCallout)
                    .foregroundColor(Color.textPrimary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.obsidianSurface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.obsidianBorder.opacity(0.65), lineWidth: 0.7)
        )
    }

    private var providerPicker: some View {
        HStack(spacing: 4) {
            ForEach(StreetViewProvider.allCases, id: \.self) { provider in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedProvider = provider
                    }
                } label: {
                    Label(provider.rawValue, systemImage: provider == .apple ? "apple.logo" : "globe")
                        .font(.obsidianFootnote)
                        .foregroundColor(selectedProvider == provider ? .white : Color.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(selectedProvider == provider ? Color.electricViolet : Color.clear)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(4)
        .background(Color.obsidianSurface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.obsidianBorder.opacity(0.65), lineWidth: 0.7)
        )
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: selectedProvider == .apple ? "viewfinder.circle.fill" : "globe.americas.fill")
                    .font(.obsidianCallout)
                    .foregroundColor(Color.statusInterested)

                Text(selectedProvider == .apple ? "Apple Look Around" : "Google Street View")
                    .font(.obsidianHeadline)
                    .foregroundColor(Color.textPrimary)

                Spacer()
            }

            Group {
                if selectedProvider == .apple {
                    appleView
                } else {
                    googleView
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 420)
        }
        .padding(16)
        .background(Color.obsidianSurface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.obsidianBorder.opacity(0.7), lineWidth: 0.7)
        )
    }

    private var coordinateLabel: String {
        String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
    }

    // MARK: - Apple Look Around

    @ViewBuilder
    private var appleView: some View {
        if isAppleLoading {
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.electricViolet)
                Text("Checking Apple coverage...")
                    .font(.obsidianFootnote)
                    .foregroundColor(.textMuted)
            }
            .frame(maxWidth: .infinity, minHeight: 420)
        } else if let scene = scene {
            LookAroundRepresentable(scene: scene)
                .frame(minHeight: 420)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.obsidianBorder.opacity(0.65), lineWidth: 0.7)
                )
        } else {
            VStack(spacing: 16) {
                ObsidianIconTile(icon: "eye.slash", tint: Color.statusNotHome, size: 56)
                Text("No Apple coverage here")
                    .font(.obsidianHeadline)
                    .foregroundColor(Color.textPrimary)

                Text("Google Street View may still have coverage for this pin.")
                    .font(.obsidianFootnote)
                    .foregroundColor(Color.textSecondary)
                    .multilineTextAlignment(.center)

                Button {
                    withAnimation { selectedProvider = .google }
                } label: {
                    Label("Switch to Google", systemImage: "globe")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ObsidianSecondaryButtonStyle())
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, minHeight: 420)
            .padding(18)
            .background(Color.obsidianElevated)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    // MARK: - Google Street View

    private var googleView: some View {
        GoogleStreetWebView(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        .frame(minHeight: 420)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.obsidianBorder.opacity(0.65), lineWidth: 0.7)
        )
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

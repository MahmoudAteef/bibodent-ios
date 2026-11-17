import UIKit
import WebKit
import Network

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Bibodent", sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.tintColor = .bibodentBlue
        window.rootViewController = WebsiteViewController()
        window.makeKeyAndVisible()
        self.window = window
    }
}

private extension UIFont {
    func bold() -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(.traitBold) else { return self }
        return UIFont(descriptor: descriptor, size: 0)
    }
}

private extension UIColor {
    static let bibodentBlue = UIColor(red: 7 / 255, green: 116 / 255, blue: 187 / 255, alpha: 1)
}

final class WebsiteViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    private var currentURL = URL(string: "https://bibodent.com")!
    private let webView = WKWebView()
    private let refreshControl = UIRefreshControl()
    private let errorStack = UIStackView()
    private let loadingOverlay = UIView()
    private let progressBubble = UIView()
    private let splashView = UIView()
    private let pathMonitor = NWPathMonitor()
    private var isOnline = true
    private var isError = false
    private var activeNavigation: WKNavigation?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        webView.scrollView.alwaysBounceVertical = true
        webView.scrollView.refreshControl = refreshControl
        refreshControl.addTarget(self, action: #selector(refreshPage), for: .valueChanged)
        configureLayout()
        configureSplash()
        startNetworkMonitor()
        loadWebsite()
    }

    // MARK: Layout

    private func configureLayout() {
        let iconConfig = UIImage.SymbolConfiguration(pointSize: 56, weight: .regular)
        let icon = UIImageView(image: UIImage(systemName: "wifi.slash", withConfiguration: iconConfig))
        icon.tintColor = .tertiaryLabel

        let title = UILabel()
        title.text = "No Internet"
        title.font = .preferredFont(forTextStyle: .title2).bold()
        title.adjustsFontForContentSizeCategory = true
        title.textColor = .label

        let subtitle = UILabel()
        subtitle.text = "Please check your internet connection."
        subtitle.font = .preferredFont(forTextStyle: .body)
        subtitle.adjustsFontForContentSizeCategory = true
        subtitle.textColor = .secondaryLabel
        subtitle.textAlignment = .center
        subtitle.numberOfLines = 0

        var config = UIButton.Configuration.filled()
        config.title = "Try Again"
        config.cornerStyle = .capsule
        config.buttonSize = .large
        let retryButton = UIButton(configuration: config)
        retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)

        errorStack.axis = .vertical
        errorStack.alignment = .center
        errorStack.spacing = 8
        errorStack.addArrangedSubview(icon)
        errorStack.setCustomSpacing(16, after: icon)
        errorStack.addArrangedSubview(title)
        errorStack.addArrangedSubview(subtitle)
        errorStack.setCustomSpacing(24, after: subtitle)
        errorStack.addArrangedSubview(retryButton)
        errorStack.isHidden = true

        loadingOverlay.backgroundColor = .clear
        loadingOverlay.isUserInteractionEnabled = false
        loadingOverlay.isHidden = true
        // Apple-style HUD: a blurred system material card with a native spinner and a soft pulse.
        progressBubble.backgroundColor = .clear
        progressBubble.layer.cornerRadius = 18
        progressBubble.clipsToBounds = true
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))
        blur.frame = CGRect(x: 0, y: 0, width: 80, height: 80)
        blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        let spinner = UIActivityIndicatorView(style: .large)
        spinner.startAnimating()
        spinner.center = CGPoint(x: 40, y: 40)
        progressBubble.addSubview(blur)
        progressBubble.addSubview(spinner)

        let safeArea = view.safeAreaLayoutGuide
        for element in [webView, errorStack, loadingOverlay, progressBubble] as [UIView] {
            element.translatesAutoresizingMaskIntoConstraints = false
        }
        view.addSubview(webView)
        view.addSubview(errorStack)
        view.addSubview(loadingOverlay)
        loadingOverlay.addSubview(progressBubble)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: safeArea.topAnchor),
            webView.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor),
            errorStack.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor),
            errorStack.centerYAnchor.constraint(equalTo: safeArea.centerYAnchor),
            errorStack.leadingAnchor.constraint(greaterThanOrEqualTo: safeArea.leadingAnchor, constant: 24),
            loadingOverlay.topAnchor.constraint(equalTo: safeArea.topAnchor),
            loadingOverlay.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor),
            loadingOverlay.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor),
            loadingOverlay.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor),
            progressBubble.centerXAnchor.constraint(equalTo: loadingOverlay.centerXAnchor),
            progressBubble.centerYAnchor.constraint(equalTo: loadingOverlay.centerYAnchor),
            progressBubble.widthAnchor.constraint(equalToConstant: 80),
            progressBubble.heightAnchor.constraint(equalToConstant: 80)
        ])
    }

    // MARK: Splash (3 seconds, like Android)

    private func configureSplash() {
        splashView.backgroundColor = .systemBackground
        splashView.frame = view.bounds
        splashView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        let logo = UIImageView(image: UIImage(named: "SplashLogo"))
        logo.contentMode = .scaleAspectFit
        logo.translatesAutoresizingMaskIntoConstraints = false
        splashView.addSubview(logo)
        NSLayoutConstraint.activate([
            logo.centerXAnchor.constraint(equalTo: splashView.centerXAnchor),
            logo.centerYAnchor.constraint(equalTo: splashView.centerYAnchor),
            logo.widthAnchor.constraint(equalToConstant: 200),
            logo.heightAnchor.constraint(equalToConstant: 200)
        ])
        view.addSubview(splashView)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self = self else { return }
            UIView.animate(withDuration: 0.25, animations: { self.splashView.alpha = 0 }) { _ in
                self.splashView.removeFromSuperview()
            }
        }
    }

    // MARK: Pulsing loader

    private func startPulse() {
        progressBubble.layer.removeAllAnimations()
        progressBubble.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        progressBubble.alpha = 0.85
        UIView.animate(
            withDuration: 0.7, delay: 0,
            options: [.repeat, .autoreverse, .curveEaseInOut, .allowUserInteraction]
        ) {
            self.progressBubble.transform = .identity
            self.progressBubble.alpha = 1.0
        }
    }

    private func setLoading(_ loading: Bool) {
        loadingOverlay.isHidden = !loading
        if loading { startPulse() } else { progressBubble.layer.removeAllAnimations() }
    }

    // MARK: Network

    private func startNetworkMonitor() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            self.isOnline = path.status == .satisfied
            if self.isOnline && self.isError { self.loadWebsite() }
        }
        pathMonitor.start(queue: .main)
    }

    private func showToast(_ text: String) {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        let pill = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
        pill.layer.cornerRadius = 18
        pill.clipsToBounds = true
        pill.translatesAutoresizingMaskIntoConstraints = false
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        pill.contentView.addSubview(label)
        view.addSubview(pill)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: pill.contentView.topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: pill.contentView.bottomAnchor, constant: -10),
            label.leadingAnchor.constraint(equalTo: pill.contentView.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: pill.contentView.trailingAnchor, constant: -16),
            pill.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pill.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            pill.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24)
        ])
        UIView.animate(withDuration: 0.3, delay: 2.2, options: []) {
            pill.alpha = 0
        } completion: { _ in
            pill.removeFromSuperview()
        }
    }

    // MARK: Loading

    private func loadWebsite() {
        guard isOnline else {
            showOfflineScreen()
            showToast("Please check your internet connection.")
            return
        }
        isError = false
        errorStack.isHidden = true
        webView.isHidden = false
        activeNavigation = webView.load(URLRequest(url: currentURL))
    }

    private func showOfflineScreen() {
        isError = true
        webView.isHidden = true
        errorStack.isHidden = false
        setLoading(false)
        refreshControl.endRefreshing()
    }

    @objc private func retryTapped() {
        loadWebsite()
    }

    @objc private func refreshPage() {
        guard isOnline else {
            refreshControl.endRefreshing()
            showToast("Please check your internet connection.")
            return
        }
        isError = false
        errorStack.isHidden = true
        setLoading(true)
        if webView.url == nil {
            activeNavigation = webView.load(URLRequest(url: currentURL))
        } else {
            activeNavigation = webView.reload()
        }
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        activeNavigation = navigation
        isError = false
        errorStack.isHidden = true
        setLoading(true)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard navigation === activeNavigation else { return }
        finishLoading()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showLoadError(for: navigation, error: error)
    }

    func webView(
        _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error
    ) {
        showLoadError(for: navigation, error: error)
    }

    private func showLoadError(for navigation: WKNavigation?, error: Error) {
        guard navigation === activeNavigation else { return }
        finishLoading()
        let navigationError = error as NSError
        guard navigationError.domain == NSURLErrorDomain,
              navigationError.code != NSURLErrorCancelled else { return }
        showOfflineScreen()
    }

    private func finishLoading() {
        activeNavigation = nil
        setLoading(false)
        refreshControl.endRefreshing()
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url,
              let scheme = url.scheme?.lowercased() else {
            decisionHandler(.cancel)
            return
        }
        if ["http", "https", "about", "blob", "data"].contains(scheme) {
            if navigationAction.targetFrame?.isMainFrame ?? true, scheme.hasPrefix("http") {
                currentURL = url
            }
            decisionHandler(.allow)
            return
        }
        let externalSchemes = ["tel", "mailto", "sms", "facetime", "whatsapp", "maps", "itms-apps", "itms-appss"]
        if externalSchemes.contains(scheme) {
            UIApplication.shared.open(url)
        }
        decisionHandler(.cancel)
    }

    // MARK: WKUIDelegate

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        guard view.window != nil, presentedViewController == nil else {
            completionHandler(nil)
            return
        }
        let alert = UIAlertController(title: "Bibodent", message: prompt, preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            completionHandler(alert.textFields?.first?.text)
        })
        present(alert, animated: true)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        guard view.window != nil, presentedViewController == nil else {
            completionHandler()
            return
        }
        let alert = UIAlertController(title: "Bibodent", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        present(alert, animated: true)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        guard view.window != nil, presentedViewController == nil else {
            completionHandler(false)
            return
        }
        let alert = UIAlertController(title: "Bibodent", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        present(alert, animated: true)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }
}

# Bibodent for iOS

1. Unzip the archive on a Mac and open `Bibodent.xcodeproj` in Xcode.
2. Select the Bibodent scheme and run it on an iPhone simulator. The deployment target is iOS 15.
3. For device testing and distribution, select your team under Signing & Capabilities. The default bundle identifier is `com.bibodent.app`. Set it to the identifier registered for the iOS app in your Apple Developer account.
4. For distribution, choose a generic iOS device destination, then Product > Archive.

The app loads https://bibodent.com in WKWebView. Test website navigation and any sign-in or file flows on an iPhone before submitting. The project contains source code and was packaged on Windows. Build and runtime verification require Xcode.

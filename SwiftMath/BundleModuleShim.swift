import Foundation

// SwiftMath was written as a Swift Package and references `Bundle.module` to
// locate its `mathFonts.bundle` resource. This project compiles SwiftMath's
// sources directly with `swiftc` (no SPM), so the SPM-generated `Bundle.module`
// accessor does not exist. This shim redirects it to the app's main bundle,
// where the build scripts copy `mathFonts.bundle` into Contents/Resources.
extension Bundle {
    static var module: Bundle { Bundle.main }
}

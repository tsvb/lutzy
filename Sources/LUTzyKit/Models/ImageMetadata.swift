import Foundation
import ImageIO
import CoreGraphics

/// Photographic metadata pulled from a file's EXIF/TIFF/GPS dictionaries via
/// ImageIO, formatted for display in the info inspector.
///
/// This is a superset of `RecipeReport.CameraInfo` (which keeps only the few
/// tags the derive report cares about). Both read from the same
/// `CGImageSourceCopyPropertiesAtIndex` source — this one just surfaces the
/// common capture settings a photographer wants to see while grading.
struct ImageMetadata: Equatable {

    // MARK: Camera & lens
    var make: String?
    var model: String?
    var lens: String?

    // MARK: Exposure
    var aperture: String?       // "ƒ/2.8"
    var shutterSpeed: String?   // "1/250 s"
    var iso: String?            // "ISO 400"
    var exposureBias: String?   // "+0.3 EV"
    var focalLength: String?    // "35 mm"
    var focalLength35: String?  // "52 mm" (35 mm-equivalent)
    var exposureProgram: String?
    var meteringMode: String?
    var flash: String?
    var whiteBalance: String?

    // MARK: Image
    var pixelWidth: Int?
    var pixelHeight: Int?
    var colorModel: String?     // "RGB"
    var colorProfile: String?   // "sRGB IEC61966-2.1", "Display P3", …
    var bitDepth: Int?          // bits per component

    // MARK: Capture
    var dateTaken: String?
    var software: String?

    // MARK: Location
    var coordinates: String?    // "37.7749° N, 122.4194° W"

    // `hasCameraInfo` and `isEmpty` stood here with no caller in either target — the "Unused API"
    // bullet in docs/CODE_REVIEW.md §2. Removed rather than kept: `InfoInspectorView` asks
    // `metadata.sections.isEmpty` directly, which is the same question one indirection shorter, and
    // an accessor nobody calls is an accessor nobody has checked.

    // MARK: - Display sections

    struct Row: Identifiable, Equatable {
        var id: String { label }
        let label: String
        let value: String
    }

    struct Section: Identifiable, Equatable {
        var id: String { title }
        let title: String
        let rows: [Row]
    }

    /// Grouped, display-ready rows. Empty sections are dropped so the inspector
    /// only renders what the file actually carries.
    var sections: [Section] {
        var result: [Section] = []

        func section(_ title: String, _ pairs: [(String, String?)]) {
            let rows = pairs.compactMap { label, value in
                value.map { Row(label: label, value: $0) }
            }
            if !rows.isEmpty { result.append(Section(title: title, rows: rows)) }
        }

        let cameraName: String? = {
            let combined = [make, model].compactMap { $0 }.joined(separator: " ")
            return combined.isEmpty ? nil : combined
        }()

        section("Camera & Lens", [
            ("Camera", cameraName),
            ("Lens", lens),
        ])
        section("Exposure", [
            ("Aperture", aperture),
            ("Shutter", shutterSpeed),
            ("ISO", iso),
            ("Exp. Bias", exposureBias),
            ("Focal Length", focalLength),
            ("35mm Equiv.", focalLength35),
            ("Program", exposureProgram),
            ("Metering", meteringMode),
            ("Flash", flash),
            ("White Balance", whiteBalance),
        ])
        section("Image", [
            ("Dimensions", dimensionsLabel),
            ("Color Model", colorModel),
            ("Color Profile", colorProfile),
            ("Bit Depth", bitDepth.map { "\($0)-bit" }),
        ])
        section("Capture", [
            ("Date", dateTaken),
            ("Software", software),
        ])
        section("Location", [
            ("Coordinates", coordinates),
        ])

        return result
    }

    private var dimensionsLabel: String? {
        guard let w = pixelWidth, let h = pixelHeight, w > 0, h > 0 else { return nil }
        let mp = Double(w * h) / 1_000_000
        return "\(w) × \(h)  (\(String(format: "%.1f", mp)) MP)"
    }
}

// MARK: - Reading

extension ImageMetadata {

    /// Read metadata from a file URL.
    static func read(from url: URL) -> ImageMetadata {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return ImageMetadata()
        }
        return read(from: source)
    }

    /// Read metadata from in-memory image data (Photos imports, etc.).
    static func read(from data: Data) -> ImageMetadata {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return ImageMetadata()
        }
        return read(from: source)
    }

    private static func read(from source: CGImageSource) -> ImageMetadata {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return ImageMetadata()
        }

        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let gps  = props[kCGImagePropertyGPSDictionary]  as? [CFString: Any] ?? [:]

        var m = ImageMetadata()

        // Camera & lens
        m.make  = trimmed(tiff[kCGImagePropertyTIFFMake] as? String)
        m.model = trimmed(tiff[kCGImagePropertyTIFFModel] as? String)
        m.lens  = trimmed(exif[kCGImagePropertyExifLensModel] as? String)
            ?? trimmed(exif[kCGImagePropertyExifLensMake] as? String)

        // Exposure
        if let f = exif[kCGImagePropertyExifFNumber] as? Double, f > 0 {
            m.aperture = "ƒ/\(trimNumber(f))"
        }
        if let t = exif[kCGImagePropertyExifExposureTime] as? Double, t > 0 {
            m.shutterSpeed = formatShutter(t)
        }
        if let isoArray = exif[kCGImagePropertyExifISOSpeedRatings] as? [Int], let iso = isoArray.first {
            m.iso = "ISO \(iso)"
        } else if let iso = exif[kCGImagePropertyExifISOSpeedRatings] as? Int {
            m.iso = "ISO \(iso)"
        }
        if let bias = exif[kCGImagePropertyExifExposureBiasValue] as? Double {
            m.exposureBias = abs(bias) < 0.05 ? "0 EV" : String(format: "%+.1f EV", bias)
        }
        if let fl = exif[kCGImagePropertyExifFocalLength] as? Double, fl > 0 {
            m.focalLength = "\(trimNumber(fl)) mm"
        }
        if let fl35 = exif[kCGImagePropertyExifFocalLenIn35mmFilm] as? Int, fl35 > 0 {
            m.focalLength35 = "\(fl35) mm"
        }
        m.exposureProgram = exposureProgramLabel(exif[kCGImagePropertyExifExposureProgram] as? Int)
        m.meteringMode    = meteringModeLabel(exif[kCGImagePropertyExifMeteringMode] as? Int)
        m.flash           = flashLabel(exif[kCGImagePropertyExifFlash] as? Int)
        m.whiteBalance    = whiteBalanceLabel(exif[kCGImagePropertyExifWhiteBalance] as? Int)

        // Image. ImageIO reports the *stored* buffer dimensions; orientations
        // 5-8 are quarter-turns, so display dimensions are the transpose. The
        // app renders images upright (see ImageDecoder.orientedLoadOptions),
        // so report what the user actually sees.
        let orientation = (props[kCGImagePropertyOrientation] as? Int)
            ?? (tiff[kCGImagePropertyTIFFOrientation] as? Int)
            ?? 1
        let storedWidth = (props[kCGImagePropertyPixelWidth] as? Int)
            ?? (exif[kCGImagePropertyExifPixelXDimension] as? Int)
        let storedHeight = (props[kCGImagePropertyPixelHeight] as? Int)
            ?? (exif[kCGImagePropertyExifPixelYDimension] as? Int)
        let isQuarterTurned = (5...8).contains(orientation)
        m.pixelWidth  = isQuarterTurned ? storedHeight : storedWidth
        m.pixelHeight = isQuarterTurned ? storedWidth : storedHeight
        m.colorModel   = props[kCGImagePropertyColorModel] as? String
        m.colorProfile = props[kCGImagePropertyProfileName] as? String
        m.bitDepth     = props[kCGImagePropertyDepth] as? Int

        // Capture
        m.dateTaken = formatDate(exif[kCGImagePropertyExifDateTimeOriginal] as? String)
            ?? formatDate(tiff[kCGImagePropertyTIFFDateTime] as? String)
        m.software  = trimmed(tiff[kCGImagePropertyTIFFSoftware] as? String)

        // Location
        m.coordinates = formatGPS(gps)

        return m
    }

    // MARK: - Formatting helpers

    private static func trimmed(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }

    /// Drop a trailing ".0" so 8.0 → "8" but 2.8 stays "2.8".
    private static func trimNumber(_ value: Double) -> String {
        if value == value.rounded() {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }

    private static func formatShutter(_ seconds: Double) -> String {
        if seconds >= 1 {
            return "\(trimNumber(seconds)) s"
        }
        let denom = Int((1.0 / seconds).rounded())
        return "1/\(denom) s"
    }

    /// EXIF dates are "yyyy:MM:dd HH:mm:ss"; reformat to something readable.
    private static func formatDate(_ raw: String?) -> String? {
        guard let raw = trimmed(raw) else { return nil }
        let parser = DateFormatter()
        parser.dateFormat = "yyyy:MM:dd HH:mm:ss"
        parser.locale = Locale(identifier: "en_US_POSIX")
        guard let date = parser.date(from: raw) else { return raw }
        let out = DateFormatter()
        out.dateStyle = .medium
        out.timeStyle = .short
        return out.string(from: date)
    }

    private static func formatGPS(_ gps: [CFString: Any]) -> String? {
        guard let lat = gps[kCGImagePropertyGPSLatitude] as? Double,
              let lon = gps[kCGImagePropertyGPSLongitude] as? Double else { return nil }
        let latRef = (gps[kCGImagePropertyGPSLatitudeRef] as? String) ?? (lat >= 0 ? "N" : "S")
        let lonRef = (gps[kCGImagePropertyGPSLongitudeRef] as? String) ?? (lon >= 0 ? "E" : "W")
        return String(format: "%.5f° %@, %.5f° %@", abs(lat), latRef, abs(lon), lonRef)
    }

    private static func exposureProgramLabel(_ v: Int?) -> String? {
        switch v {
        case 1: return "Manual"
        case 2: return "Program AE"
        case 3: return "Aperture Priority"
        case 4: return "Shutter Priority"
        case 5: return "Creative"
        case 6: return "Action"
        case 7: return "Portrait"
        case 8: return "Landscape"
        default: return nil
        }
    }

    private static func meteringModeLabel(_ v: Int?) -> String? {
        switch v {
        case 1: return "Average"
        case 2: return "Center-weighted"
        case 3: return "Spot"
        case 4: return "Multi-spot"
        case 5: return "Multi-segment"
        case 6: return "Partial"
        default: return nil
        }
    }

    private static func flashLabel(_ v: Int?) -> String? {
        guard let v else { return nil }
        return (v & 0x1) == 1 ? "Fired" : "Did not fire"
    }

    private static func whiteBalanceLabel(_ v: Int?) -> String? {
        switch v {
        case 0: return "Auto"
        case 1: return "Manual"
        default: return nil
        }
    }
}

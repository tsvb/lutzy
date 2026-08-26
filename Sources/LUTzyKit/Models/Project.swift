import Foundation

/// A named piece of work, with its own images.
///
/// The LUT library is global — LUTs are a collection you build once and use
/// everywhere, like fonts. Images are not: the frames you judge film
/// simulations on have nothing to do with the shoot you are grading, and
/// mixing them means every project starts by wading through the last one's
/// pictures.
///
/// So a project owns its images and its state, and borrows the LUT library.
/// That also covers the three ways this app gets used without inventing three
/// kinds of project: one where the images are reference frames and the work is
/// comparing LUTs; one where they are a shoot and the work is applying a LUT to
/// all of them; one where they are what a new LUT is being built against. Same
/// container, different contents.
struct Project: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var name: String
    var createdAt: Date
    var lastOpenedAt: Date
    /// What the user was doing when they last left. Restored on reopen, which
    /// is the whole reason a project is a place rather than just a folder.
    var session: Session

    init(id: UUID = UUID(), name: String, createdAt: Date = Date(), lastOpenedAt: Date = Date(), session: Session = Session()) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.lastOpenedAt = lastOpenedAt
        self.session = session
    }

    /// Everything worth putting back exactly as it was.
    ///
    /// Deliberately *not* the whole `EditDocument`: develop settings and
    /// adjustments belong to an image, and restoring the previous image's
    /// exposure onto a different one would be worse than restoring nothing.
    /// This is the workspace, not the edit.
    struct Session: Codable, Equatable, Sendable {
        var section: AppSection = .viewer
        var layout: ComparisonLayout = .split
        /// Durable catalog record identity. Legacy file-path values remain
        /// readable so sessions from before the catalog migration still open.
        var selectedLUT: String?
        var cellLUTs: [String?] = []
        /// The image's file name within the project, not a path: the project
        /// folder can move (a new machine, a restored backup) and the images
        /// move with it.
        var imageName: String?
        /// New global Media Library identity. `imageName` remains solely for
        /// one-time migration of old project sessions.
        var mediaRecordID: String?
        var tagFilter: [String] = []
        var browsedCategory: String?
        var showingFavouritesOnly = false
        var sourceSpace: SourceSpace = .auto

        /// Older project files predate most of these; a missing field means
        /// "the default", never a failure to open the project.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            section = try container.decodeIfPresent(AppSection.self, forKey: .section) ?? .viewer
            layout = try container.decodeIfPresent(ComparisonLayout.self, forKey: .layout) ?? .split
            selectedLUT = try container.decodeIfPresent(String.self, forKey: .selectedLUT)
            cellLUTs = try container.decodeIfPresent([String?].self, forKey: .cellLUTs) ?? []
            imageName = try container.decodeIfPresent(String.self, forKey: .imageName)
            mediaRecordID = try container.decodeIfPresent(String.self, forKey: .mediaRecordID)
            tagFilter = try container.decodeIfPresent([String].self, forKey: .tagFilter) ?? []
            browsedCategory = try container.decodeIfPresent(String.self, forKey: .browsedCategory)
            showingFavouritesOnly = try container.decodeIfPresent(Bool.self, forKey: .showingFavouritesOnly) ?? false
            sourceSpace = try container.decodeIfPresent(SourceSpace.self, forKey: .sourceSpace) ?? .auto
        }

        init() {}
    }
}

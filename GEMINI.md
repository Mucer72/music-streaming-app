# Personal Music Host Project - GEMINI Context

## 1. Project Overview
**Personal Music Host** is a personal music hosting and streaming application developed for the Apple ecosystem (primarily macOS, with iOS compatibility). The application acts as a personal music server, allowing users to manage, convert, upload, and stream music from their private cloud storage (Google Drive integrated with Firebase).

- **Bundle ID:** `com.rwd-studio.musicstreaming`
- **Firebase Project ID:** `musicstreaming-m21rwd`
- **Firestore Database ID:** `(default)` · Location: `asia-southeast1`
- **Google OAuth Client ID:** `86113541365-tsdjndti62vghc481f54idsvm6221lj8.apps.googleusercontent.com`

---

## 2. Tech Stack

| Component | Technology |
|---|---|
| Platform | macOS 13+ / iOS 16+ (Swift) |
| UI Framework | SwiftUI |
| Architecture | MVVM + Clean Architecture + SOLID |
| Audio Processing | AVFoundation (`AVAssetReader`/`AVAssetWriter`) + FFmpeg (via `FFmpegService`) |
| File Storage | Google Drive API v3 |
| Database | Firebase Firestore |
| Authentication | Firebase Auth (Google Sign-In + Apple Sign-In) |
| Image Loading | `SecureDriveImage` (custom View + `NSCache`) |
| Config | `AppEnvironment` struct reading from `Info.plist` / `Secrets.xcconfig` |

**Firebase Auth — Enabled Only:** Google Sign-In, Apple Sign-In.  
**Disabled Entirely:** Email/Password, Phone, Anonymous, MFA.

---

## 3. Project Directory Structure

```
PersonalMusicHost/
├── Models/
│   ├── AppModels.swift          # AppRoute enum, AudioTrack struct, DriveUploadResult
│   ├── FirestoreModels.swift    # TrackRecord, AlbumRecord, UserRecord, GenreRecord,
│   │                            #   LikeRecord, PlaylistRecord, PlaylistType enum
│   └── Environment.swift        # AppEnvironment — reads config from Info.plist
│
├── ViewModels/
│   ├── AuthViewModel.swift      # AuthStatus enum, manages Google + Firebase sessions
│   ├── PlayerViewModel.swift    # Playback state + library data + like state manager
│   ├── DatabaseViewModel.swift  # CRUD operations for track/album/playlist (Database screen)
│   ├── PipelineViewModel.swift  # Upload & Convert pipeline state manager
│   ├── PlaylistManagerViewModel.swift  # CRUD operations for AddToPlaylist sheet
│   └── ProfileViewModel.swift   # User profile data manager
│
├── Services/
│   ├── FirebaseDatabaseService.swift  # All Firestore operations (singleton)
│   ├── FirebaseAuthService.swift      # Firebase Auth wrapper (singleton)
│   ├── GoogleDriveService.swift       # Google Drive API v3 wrapper (singleton)
│   ├── AudioPipelineService.swift     # AVFoundation: reads metadata & encodes AAC/ALAC
│   ├── AudioPlayerEngine.swift        # AVPlayer streaming engine (ObservableObject)
│   ├── LocalFileService.swift         # File picker & local directory operations
│   ├── FFmpegService.swift            # FFmpeg CLI wrapper (optional pipeline step)
│   └── SecureDriveImage.swift         # SwiftUI View: loads & caches Drive cover art
│
├── Views/
│   ├── App/
│   │   └── MainAppView.swift          # Root app shell: NavigationStack + EnvironmentObject injection
│   ├── Login/
│   │   └── LoginView.swift            # Login screen (Google/Apple Sign-In)
│   ├── Common/                        # Reusable components across multiple screens
│   │   ├── SectionView.swift          # Generic section container (title + content)
│   │   └── PanelButtons.swift         # PanelBackButton + PanelCloseButton
│   ├── Dashboard/
│   │   ├── MusicDashboardView.swift   # Main view: 2-column layout (library | detail/player)
│   │   ├── Components/
│   │   │   ├── DashboardTopBar.swift  # Search bar + navigation buttons
│   │   │   ├── LibraryView.swift      # Library home page (playlists, top 10, albums, genres)
│   │   │   ├── SearchResultsView.swift
│   │   │   ├── GenreResultsView.swift
│   │   │   ├── TrackCard.swift        # Horizontal card (thumbnail + rank badge)
│   │   │   ├── AlbumCard.swift
│   │   │   ├── PlaylistCard.swift
│   │   │   ├── TrackRow.swift         # Vertical row in lists
│   │   │   └── AlbumRow.swift
│   │   └── Panels/
│   │       ├── TrackDetailPanelView.swift   # Right panel: track details & actions
│   │       └── AlbumDetailPanelView.swift   # Right panel: album details + track list
│   ├── Player/
│   │   ├── TurntableCDView.swift      # Spinning vinyl CD player + progress ring + scrub gestures
│   │   ├── TrackCarouselView.swift    # Horizontal queue layout with drag-to-reorder support
│   │   └── MiniPlayerView.swift       # Mini playback bar at the bottom when player is collapsed
│   ├── Ingestion/
│   │   ├── IngestionView.swift        # Upload & convert screen orchestrator
│   │   └── Components/
│   │       ├── IngestionHeaderView.swift    # Progress indicators + start buttons
│   │       ├── ControlPanelView.swift       # Mode selector, file picker, format toggles
│   │       ├── AlbumGlobalInfoView.swift    # Album metadata editor for album upload mode
│   │       ├── TrackListQueueView.swift     # Inline metadata editor for queued tracks
│   │       └── ConsoleView.swift            # Terminal-style execution log panel
│   ├── Database/
│   │   ├── DatabaseManagementView.swift    # Cloud database CRUD manager screen
│   │   ├── EditTrackView.swift
│   │   ├── EditAlbumView.swift
│   │   ├── EditPlaylistView.swift
│   │   └── Components/
│   │       ├── DatabaseToolbar.swift        # Toolbar + mode picker + bulk delete
│   │       ├── TrackRowView.swift
│   │       ├── AlbumRowView.swift
│   │       └── PlaylistRowView.swift
│   ├── Playlist/
│   │   ├── PlaylistDetailView.swift    # Playlist detail viewer & player sheet
│   │   └── AddToPlaylistSheet.swift    # Target playlist selector sheet
│   └── Profile/
│       ├── ProfileView.swift           # User profile page (avatar, stats, sign-out)
│       └── Components/
│           └── StatCard.swift          # Statistics dashboard indicator card
│
├── ContentView.swift    # Root entry point: switches between LoginView / MainAppView based on AuthStatus
└── PersonalMusicHostApp.swift  # App entry point, configures FirebaseApp
```

---

## 4. Data Models (Firestore)

### `TrackRecord` — collection `tracks`
```swift
struct TrackRecord: Identifiable, Codable {
    @DocumentID var id: String?
    var title: String
    var artist: String
    var duration: Double
    var albumId: String?
    var trackNumber: Int
    var releaseYear: Int?
    var description: String?
    var streamCount: Int           // Automatically increments after 15% playback
    var coverDriveID: String?      // Google Drive File ID of the cover image
    var genreId: String?
    var contributor: String        // UID of the uploader
    var isPublic: Bool?
    var googleDriveALACID: String? // Drive File ID of the ALAC file
    var googleDriveAACID: String?  // Drive File ID of the AAC file
    @ServerTimestamp var createdAt: Timestamp?
}
```

### `AlbumRecord` — collection `albums`
```swift
struct AlbumRecord: Identifiable, Codable {
    @DocumentID var id: String?
    var title: String
    var artist: String
    var releaseYear: Int
    var description: String?
    var totalTracks: Int
    var coverDriveID: String       // Cover art is mandatory for albums
    var genreId: String?
    var contributor: String
    var isPublic: Bool?
    @ServerTimestamp var createdAt: Timestamp?
}
```

### `PlaylistRecord` — collection `playlists`
```swift
struct PlaylistRecord: Identifiable, Codable {
    @DocumentID var id: String?
    var title: String
    var description: String?
    var ownerUID: String
    var trackIds: [String]
    var isPublic: Bool
    var coverDriveID: String?
    var type: PlaylistType    // .custom | .systemLiked | .systemRecommended
    @ServerTimestamp var createdAt: Timestamp?
}
```

### Auxiliary Collections
- `users` — `UserRecord`: uid, email, displayName, photoURL, respectCount
- `genres` — `GenreRecord`: name, order
- `likes` — `LikeRecord`: userId, trackId, itemType, contributorId

### Required Composite Index
Collection `tracks`: `albumId` ASC → `trackNumber` ASC → `__name__` ASC

---

## 5. Core Workflows

### 5.1 Auth Flow
```
ContentView (observes AuthViewModel.status)
  ├─ .undetermined → splash screen / loading indicator
  ├─ .signedOut    → LoginView (Google Sign-In → Firebase Auth → status = .signedIn)
  └─ .signedIn     → MainAppView
       └─ injects: PlayerViewModel, DatabaseViewModel, PipelineViewModel
```

**Session Restoration:** `AuthViewModel.init()` → `restorePreviousSession()` → `GIDSignIn.restorePreviousSignIn()` → Firebase re-authentication → avoids redundant login prompts on app startup.

### 5.2 Ingestion & Audio Pipeline Flow
```
IngestionView (managed by PipelineViewModel)
  ├─ Choose files/folders (LocalFileService.selectFiles)
  ├─ AVFoundation extracts metadata (AudioPipelineService)
  ├─ Transcode → AAC .m4a / ALAC .m4a (AVAssetReader + AVAssetWriter)
  ├─ Optional FFmpeg fallback encoding
  ├─ Upload to Google Drive (GoogleDriveService)
  │    └─ Folder structure: root/ → album_name/ → track_files/
  │                                → covers/
  └─ Write metadata to Firestore (FirebaseDatabaseService.saveTrack/saveAlbum)
       └─ Post notification "LibraryNeedsRefresh" → PlayerViewModel.refreshLibrary()
```

**Pipeline Start Validation Constraints:**
- `tracks` queue must not be empty.
- At least one output format (AAC or ALAC) must be selected.
- Output destination (local directory and/or Google Drive) must be checked.
- If uploading to Drive → auth status must be `.signedIn`.
- Album Mode → `globalGenreId` must not be empty.
- Single Mode → all queued tracks must have a valid `genreId`.

### 5.3 Playback Flow
```
MusicDashboardView (PlayerViewModel injected as EnvironmentObject)
  ├─ Initialization: loadLibraryData() → fetches tracks, albums, topTracks, likedTracks, genres in parallel
  ├─ User interacts with a track → playTrack(track)
  │    ├─ Identifies isOwner → retrieves accessToken if true, uses public webURL if false
  │    ├─ AudioPlayerEngine.startStream(fileID, accessToken, useWebURL)
  │    └─ preloadNextTrack() → AudioPlayerEngine.queueNext(...)
  ├─ Engine completes current track → NotificationCenter "TrackDidNeedNext" → handleNextTrackNotification()
  ├─ Stream count tracking: increments after 15% duration playback (optimistic UI update + Firestore increment)
  └─ Likes: optimistic UI update → toggles like on server → reverts on failure or synchronizes on skew
```

**Playback Modes:** `.queue` | `.loopAll` | `.loopOne` | `.random`

### 5.4 Dashboard UI State Machine
```
MusicDashboardView
  ├─ searchText.isEmpty && selectedGenre == nil  → LibraryView (default home)
  ├─ searchText.isNotEmpty                       → SearchResultsView
  ├─ selectedGenre != nil                        → GenreResultsView
  └─ Right Column Panel (isRightPanelVisible):
       ├─ selectedTrackDetail != nil → TrackDetailPanelView
       ├─ selectedAlbumDetail != nil → AlbumDetailPanelView
       └─ playlist.isNotEmpty && isPlayerExpanded:
            ├─ TurntableCDView (spinning vinyl cover art)
            └─ TrackCarouselView (drag-to-reorder list)
  └─ Mini Player Bar: playlist.isNotEmpty && !isPlayerExpanded && no active panels
```

---

## 6. Dependency Injection Map

| ViewModel | Initialized At | Injected Into |
|---|---|---|
| `AuthViewModel` | `ContentView` (@StateObject) | All views via `@EnvironmentObject` |
| `PlayerViewModel` | `MainAppView` (@StateObject) | Dashboard and all its subviews |
| `DatabaseViewModel` | `MainAppView` (@StateObject) | DatabaseManagementView and all subviews |
| `PipelineViewModel` | `MainAppView` (@StateObject) | IngestionView and all subviews |
| `PlaylistManagerViewModel` | `MusicDashboardView` (@StateObject) | LibraryView + AddToPlaylistSheet |
| `ProfileViewModel` | `ProfileView` (@StateObject) | Internal to ProfileView scope |

---

## 7. Architectural Rules & Best Practices

### MVVM Integrity (Strictly Enforced)
- **Views must not call Services directly.** All database and network transactions must go through a ViewModel.
- `AlbumDetailPanelView` uses `viewModel.fetchAlbumTracks(albumId:)` to query tracks.
- `PlaylistDetailView` uses `viewModel.fetchPlaylistTracks(trackIds:)` to resolve playlist members.
- `DatabaseManagementView` uses `DatabaseViewModel` (no direct `FirebaseDatabaseService.shared` calls).

### Error & Loading State Management
- Utilize `defer { isLoading = false }` at the start of async tasks to ensure loading animations are dismissed properly on failure paths.
- Avoid force-unwrapping optional values (`!`). Use `if let` or `guard let` safely.
- Use `async/await` patterns throughout. Avoid legacy completion handlers.

### EnvironmentObject Propagation
- Explicitly attach `.environmentObject(...)` modifier when presenting sheets, modals, or views outside the default navigation hierarchy.
- For example, `TurntableCDView` and `TrackCarouselView` require explicit `.environmentObject(viewModel)` attachment within the right-hand panel of `MusicDashboardView`.

### Audio File & Drive Conventions
- Standard Output Formats: **AAC** (for streaming optimization) and/or **ALAC** (lossless archive). Both are wrapped in a `.m4a` container.
- File Drive IDs are saved in `googleDriveAACID` and `googleDriveALACID` respectively.
- The legacy `audioUrl` field has been replaced by these file ID properties.

---

## 8. Known Gotchas

| Scenario | Resolution |
|---|---|
| Sorting and searching simultaneously causes Firestore composite index issues. | In `DatabaseViewModel`, disable the sort options picker when `searchText` is not empty. |
| `PlaylistRecord` with `type = .systemLiked` has no Firestore document. | `PlaylistDetailView.loadTracks()` checks the type. If `.systemLiked`, it pulls directly from `viewModel.likedTracks` in local memory. |
| Stream counts increment multiple times on manual scrub. | A boolean flag `streamCountIncrementedForCurrentTrack` is reset to `false` in `playTrack()`. |
| Preload logic fails after dragging to reorder the carousel queue. | A Combine publisher observing `$playlist` in `PlayerViewModel.init()` automatically triggers `preloadNextTrack()` on any mutations. |
| Cover art fails to load because the Drive file is private. | `GoogleDriveService.setPublicPermission(fileID:)` must be executed immediately after uploading the cover image file. |

# Premium Music Player

A beautifully crafted, Material 3-inspired music player built with Flutter. This application offers a seamless experience for managing and playing your local music library with a focus on premium aesthetics and intuitive navigation.

---

## Key Features

- **Grid-Based Navigation**: High-fidelity GridView for "Folders" and "Movies" for a modern browsing experience.
- **Global Search**: Instant, real-time filtering of songs and folders across the entire library.
- **Premium UI/UX**:
  - **Glassmorphism About Screen**: A stunning animated About page with depth effects and a floating logo.
  - **Animated Splash Screen**: Cinematic entry animation for branding identity.
  - **Material 3 Design**: Fully aligned with the latest design standards for a premium feel.
- **Playback Persistence**: Remembers your last played track and seek position across app restarts using shared_preferences.
- **Advanced Track Interactions**:
  - Swipe-to-dismiss mini player.
  - Expandable track cards with detailed metadata.
  - Interactive folders and categorized movie collections.
- **Dynamic Versioning**: Centralized version control via pubspec.yaml, automatically reflected in the UI.

---

## How It Works

### Local Library Scanning
The app uses the on_audio_query plugin to scan the device's storage for .mp3 and other audio formats. It extracts metadata including:
- Artist & Album names.
- High-quality album artwork.
- Duration and file path information.

### Playback & State Management
- **Audio Engine**: Powered by just_audio for high-performance and feature-rich audio control.
- **Persistence**: Upon every track change or pause, the current state (Track ID, position, and list index) is saved. On app launch, it automatically restores the last session's snapshot.
- **Categorization**: Dynamically groups songs into Folders and "Movies" (Folders containing the word 'Movie') for specialized library navigation.

---

## Technology Stack & Dependencies

The app leverages a robust set of Flutter plugins for high performance and reliability:

- **[just_audio](https://pub.dev/packages/just_audio)**: Advanced audio playing features.
- **[on_audio_query](https://pub.dev/packages/on_audio_query)**: Querying local audio metadata.
- **[shared_preferences](https://pub.dev/packages/shared_preferences)**: Persistent local storage for playback state.
- **[package_info_plus](https://pub.dev/packages/package_info_plus)**: Dynamic retrieval of app versioning.
- **[url_launcher](https://pub.dev/packages/url_launcher)**: External link support for developer profiles.
- **[permission_handler](https://pub.dev/packages/permission_handler)**: Managing Android storage and audio permissions.

---

## Developer Information

**Aravind Projects**

Dedicated to building premium open-source experiences that prioritize design and performance.

- **Email**: [projects.aravind@gmail.com](mailto:projects.aravind@gmail.com)
- **Play Store Profile**: [Check out more apps](https://play.google.com/store/apps/dev?id=6819753386707148968)
- **LinkedIn/GitHub**: Connect with us via email for more details!

---

## Installation & Setup

1. **Clone the repository**:
   ```bash
   git clone https://github.com/aravindvelpuri/musicplayer.git
   ```
2. **Install dependencies**:
   ```bash
   flutter pub get
   ```
3. **Run the app**:
   ```bash
   flutter run
   ```

> [!IMPORTANT]
> Ensure you grant the necessary storage permissions upon initial launch to allow the app to scan your music library.

---

© 2026 Aravind Projects. Constructed for excellence in audio.

# MacWhisperClone

A full Swift/SwiftUI macOS application that clones the core functionality of [MacWhisper](https://goodsnooze.gumroad.com/l/macwhisper) — an on-device speech-to-text transcription app powered by [whisper.cpp](https://github.com/ggerganov/whisper.cpp).

## Features

### Transcription Engines
- **whisper.cpp (Local)** — On-device inference with Metal GPU acceleration via the GGML backend
- **OpenAI Whisper API** — Cloud transcription via OpenAI's API
- **Groq Whisper API** — Cloud transcription via Groq's fast inference API
- **OpenAI-compatible endpoints** — Custom API endpoints

### Model Management
- Download GGML models from HuggingFace (tiny → large-v3-turbo)
- Model selection and switching
- Progress tracking for downloads
- Delete downloaded models

### Audio Processing
- Supports WAV, MP3, M4A, AIFF, CAF, OGG, MP4, MOV, M4V, FLAC, AAC
- Automatic conversion to 16kHz mono PCM (whisper.cpp requirement)
- Audio metadata extraction (duration, sample rate, channels)

### Export Formats
- **TXT** — Plain text transcript
- **SRT** — SubRip subtitles
- **VTT** — WebVTT subtitles
- **JSON** — Full metadata with word-level timestamps
- **CSV** — Segment-level spreadsheet data
- **Whisper Session** — Native session format for re-import

### UI Features
- Three-column NavigationSplitView layout (sidebar → list → detail)
- Real-time transcription progress with live segment preview
- Word-level timestamp display with probability coloring
- Searchable transcripts
- Dark/Light/System theme support
- Metadata pills (language, model, word count, duration, processing speed)

### Persistence
- SQLite database via GRDB.swift
- Automatic saving of completed transcriptions
- Session history with full segment data
- Full-text search across saved transcripts

## Architecture

```
MacWhisperClone/
├── Package.swift                          # SPM manifest
└── Sources/MacWhisperClone/
    ├── App/
    │   └── MacWhisperCloneApp.swift       # @main entry point, scenes
    ├── Models/
    │   ├── TranscriptionSegment.swift     # Segment & word data models
    │   ├── AudioFile.swift                # Audio file & engine type models
    │   ├── WhisperModel.swift             # GGML model definitions
    │   └── ExportFormat.swift             # Export formats & task state
    ├── Engines/
    │   ├── TranscriptionEngine.swift      # Engine protocol & errors
    │   ├── WhisperCPPEngine.swift         # Local whisper.cpp engine
    │   ├── CloudTranscriptionEngine.swift # Cloud API engines (OpenAI, Groq)
    │   └── ModelManager.swift             # Model download/manage
    ├── Audio/
    │   └── AudioProcessor.swift           # Audio loading & PCM conversion
    ├── Export/
    │   └── TranscriptExporter.swift       # Multi-format export
    ├── Persistence/
    │   └── DatabaseManager.swift          # GRDB SQLite persistence
    ├── ViewModels/
    │   ├── TranscriptionViewModel.swift   # Main transcription state
    │   └── SettingsViewModel.swift        # App settings & API keys
    ├── Views/
    │   ├── ContentView.swift              # Main layout & sidebar
    │   ├── TranscriptionListView.swift    # Task list
    │   ├── TranscriptionDetailView.swift  # Transcript display
    │   ├── ModelListView.swift            # Model management UI
    │   ├── SettingsView.swift             # Settings panel
    │   └── ExportSheetView.swift          # Export dialog
    └── Utilities/
        └── Utilities.swift                # Time formatting, paths, logging
```

## Requirements

- macOS 14.0+ (Sonoma)
- Xcode 15.0+
- Swift 5.9+

## Setup

### 1. Build the project

```bash
cd MacWhisperClone
swift build
```

### 2. Run the app

```bash
swift run MacWhisperClone
```

Or open in Xcode:
```bash
open Package.swift
```

### 3. Download a model

1. Launch the app
2. Go to **Models** in the sidebar
3. Download a model (recommended: **Base** for quick start, **Large v3 Turbo** for best quality)
4. Select the model by clicking "Select"

### 4. Transcribe audio

1. Go to **Transcriptions** in the sidebar
2. Click **Import** and select an audio file
3. Click **Transcribe** on the imported file
4. View the transcript with timestamps in the detail panel
5. Click **Export** to save in your preferred format

### 5. Configure cloud APIs (optional)

1. Go to **Settings**
2. Select a cloud engine (OpenAI or Groq)
3. Enter your API key
4. Transcribe using the cloud engine

## Dependencies

| Package | Purpose |
|---------|---------|
| [whisper.cpp](https://github.com/ggerganov/whisper.cpp) | Local speech-to-text inference |
| [AudioKit](https://github.com/AudioKit/AudioKit) | Audio processing framework |
| [GRDB.swift](https://github.com/groue/GRDB.swift) | SQLite database persistence |
| [Sparkle](https://github.com/sparkle-project/Sparkle) | Auto-update mechanism |
| [Defaults](https://github.com/sindresorhus/Defaults) | Preferences management |
| [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) | Global hotkeys |

## Comparison with Original MacWhisper

| Feature | MacWhisper | MacWhisperClone |
|---------|-----------|-----------------|
| whisper.cpp local engine | ✅ | ✅ |
| WhisperKit (CoreML) | ✅ | ❌ |
| Metal GPU acceleration | ✅ | ✅ |
| Cloud providers | 29 | 3 (OpenAI, Groq, compatible) |
| Model download from HuggingFace | ✅ | ✅ |
| Export formats | TXT, SRT, VTT, JSON, CSV, .whisper | ✅ Same |
| SQLite persistence | ✅ (GRDB) | ✅ (GRDB) |
| Dictation overlay | ✅ | ❌ |
| CLI tool | ✅ (mw) | ❌ |
| LLM post-processing | ✅ | ❌ |
| Speaker diarization | ✅ (ArgmaxSDK) | ❌ |
| Translation (DeepL) | ✅ | ❌ |
| YouTube extraction | ✅ | ❌ |
| Watched folders | ✅ | ❌ |
| Auto-update (Sparkle) | ✅ | ✅ (dependency included) |
| Global hotkeys | ✅ | ✅ (dependency included) |

## License

This is a clone for educational purposes. The original MacWhisper is a commercial product by Jordi Bruin (Goodsnooze).

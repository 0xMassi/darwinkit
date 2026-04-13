# Changelog

All notable changes to DarwinKit are documented here. Format loosely follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

DarwinKit is consumed as a git submodule by the [Stik](https://github.com/0xMassi/stik_app) app, so versions are cut when a meaningful batch of capabilities lands. The submodule SHA recorded in Stik's parent commit is the authoritative pin — tags are the human-readable handle on top of it.

## [0.3.0] — 2026-04-13

### Added
- **`dictation.*` methods** — streaming voice-to-text backed by [WhisperKit](https://github.com/argmaxinc/WhisperKit). All inference happens on-device via CoreML / Neural Engine; audio never leaves the machine.
  - `dictation.list_models`, `dictation.status`
  - `dictation.download_model`, `dictation.cancel_download`, `dictation.delete_model`
  - `dictation.set_active_model` (synchronous, blocks up to 180 s for CoreML compilation)
  - `dictation.start`, `dictation.stop`
  - Streaming notifications: `dictation.partial`, `dictation.final`, `dictation.error`, `dictation.download_progress`, `dictation.download_complete`, `dictation.download_error`
- **Curated Whisper model tiers** — `openai_whisper-small` (~250 MB, fast & accurate) and `openai_whisper-large-v3-v20240930_turbo_632MB` (~632 MB, higher accuracy for noisy speech).
- **Concurrent JSON-RPC dispatch** — `JsonRpcServer` now dispatches each request onto a concurrent `DispatchQueue` (`darwinkit.dispatch`, `.userInitiated`). A slow handler (e.g. a 60 s model load) no longer blocks the stdin reader, so fast calls remain responsive in parallel.
- **`Sources/DarwinKit/Info.plist`** — bundle metadata with `NSMicrophoneUsageDescription` so hosts bundling DarwinKit inherit the correct mic prompt string.
- **Writable working directory on startup** — the serve command now `chdir`s to `~/Library/Application Support/com.stik.app/` before boot, so swift-transformers' Hub client can write its tokenizer cache to a sandbox-writable location instead of failing silently inside a read-only app bundle.

### Changed
- **Minimum macOS raised to 14 (Sonoma)**, up from 13 — required by the WhisperKit dependency.
- **Swift tools version raised to 5.10**, up from 5.9.
- Added WhisperKit `0.9.0+` as a SwiftPM dependency on the `DarwinKitCore` target.

### Removed
- Previous SFSpeechRecognizer plan (`speech.*` methods) was dropped before shipping. It produced hallucinations and flickered partial results under real usage. Replaced entirely by the WhisperKit-backed `dictation.*` surface.

### Migration notes
- Hosts that built against DarwinKit 0.2.x with `macOS 13` as their deployment target must bump to `macOS 14`.
- No breaking changes to existing `nlp.*`, `vision.*`, `auth.*`, `icloud.*`, or `system.capabilities` methods.

## [0.2.0] — 2026-03-10

### Added
- `auth.*` methods — biometric / device-owner authentication via LocalAuthentication.
- `icloud.*` methods — coordinated file sync via NSFileCoordinator.

## [0.1.0] — 2026-02-06

### Added
- Initial release: JSON-RPC 2.0 server over NDJSON, NLP (`nlp.embed`, `nlp.distance`, `nlp.neighbors`, `nlp.tag`, `nlp.sentiment`, `nlp.language`), Vision (`vision.ocr`), `system.capabilities`.
- Provider protocols with mock-backed unit tests.
- Homebrew tap + universal (arm64 + x86_64) release binaries.

[0.3.0]: https://github.com/0xMassi/darwinkit/releases/tag/v0.3.0
[0.2.0]: https://github.com/0xMassi/darwinkit/releases/tag/v0.2.0
[0.1.0]: https://github.com/0xMassi/darwinkit/releases/tag/v0.1.0

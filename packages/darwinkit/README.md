# @genesiscz/darwinkit

TypeScript SDK for [DarwinKit](https://github.com/genesiscz/darwinkit-swift) — Apple's on-device ML via JSON-RPC.

Zero API keys. Zero cloud costs. Runs entirely on-device using Apple's NaturalLanguage and Vision frameworks.

## Install

```bash
npm install @genesiscz/darwinkit
# or
bun add @genesiscz/darwinkit
```

The `darwinkit` binary is bundled with the package. No extra setup needed.

## Quick Start

```typescript
import { DarwinKit } from "@genesiscz/darwinkit"

const dk = new DarwinKit()

// Auto-connects on first call
const { score, label } = await dk.nlp.sentiment({ text: "I love this product" })
console.log(label, score) // "positive" 1.0

const { vector } = await dk.nlp.embed({ text: "hello world", language: "en" })
console.log(vector.length) // 512

const { text } = await dk.vision.ocr({ path: "/tmp/screenshot.png" })
console.log(text)

dk.close()
```

## Features

### NLP

```typescript
await dk.nlp.embed({ text: "hello", language: "en" })           // 512-dim vector
await dk.nlp.distance({ text1: "cat", text2: "dog", language: "en" }) // cosine distance
await dk.nlp.neighbors({ text: "code", language: "en", count: 5 })    // similar words
await dk.nlp.tag({ text: "Steve Jobs founded Apple", schemes: ["nameType"] })
await dk.nlp.sentiment({ text: "Great product!" })               // score + label
await dk.nlp.language({ text: "Bonjour" })                       // { language: "fr" }
```

### Vision

```typescript
await dk.vision.ocr({ path: "/tmp/img.png" })
await dk.vision.ocr({ path: "/tmp/img.png", languages: ["en-US", "de-DE"], level: "fast" })
```

### Auth

```typescript
await dk.auth.available()                          // { available: true, biometry_type: "touchID" }
await dk.auth.authenticate({ reason: "Unlock" })   // { success: true }
```

### iCloud

```typescript
await dk.icloud.status()
await dk.icloud.read({ path: "/notes/todo.md" })
await dk.icloud.write({ path: "/notes/new.md", content: "# Hello" })
await dk.icloud.listDir({ path: "/notes" })
await dk.icloud.delete({ path: "/notes/old.md" })
await dk.icloud.startMonitoring()

dk.icloud.onFilesChanged(({ paths }) => {
  console.log("Changed:", paths)
})
```

### System

```typescript
const caps = await dk.system.capabilities()
console.log(caps.version, caps.arch, Object.keys(caps.methods))
```

## Batch Operations

Fire multiple requests concurrently with typed results:

```typescript
const [sentiment, lang, ocr] = await dk.batch(
  dk.nlp.sentiment.prepare({ text: "hello" }),
  dk.nlp.language.prepare({ text: "Bonjour" }),
  dk.vision.ocr.prepare({ path: "/tmp/img.png" }),
)
// TypeScript infers: [SentimentResult, LanguageResult, OCRResult]
```

## Configuration

```typescript
const dk = new DarwinKit({
  binary: "/path/to/darwinkit",  // default: bundled or auto-resolved
  timeout: 30_000,               // default request timeout
  reconnect: {
    enabled: true,                // auto-reconnect on crash
    maxRetries: 3,
    delay: 1000,
  },
  logger: console,
  logLevel: "info",              // "debug" | "info" | "warn" | "error" | "silent"
})
```

## Events

```typescript
// Typed per-event
dk.on("filesChanged", ({ paths }) => console.log(paths))
dk.on("reconnect", ({ attempt }) => console.log("Reconnecting...", attempt))
dk.on("disconnect", ({ code }) => console.log("Disconnected", code))

// Catch-all
dk.listen((event) => {
  if (event.type === "filesChanged") console.log(event.paths)
})
```

## Error Handling

```typescript
import { DarwinKitError } from "@genesiscz/darwinkit"

try {
  await dk.nlp.embed({ text: "hi", language: "xx" })
} catch (e) {
  if (e instanceof DarwinKitError) {
    console.log(e.code, e.message)
    e.isFrameworkUnavailable // true
    e.isPermissionDenied     // false
    e.isOSVersionTooOld      // false
    e.isCancelled            // false
  }
}
```

## Requirements

- macOS 13+ (Ventura)
- Node.js 18+

## License

MIT

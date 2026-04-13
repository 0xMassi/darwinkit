# DarwinKit

**Use Apple's on-device ML from any language.** DarwinKit is a Swift CLI that exposes Apple's NaturalLanguage and Vision frameworks via JSON-RPC over stdio. Spawn it as a subprocess, send JSON, get results. No Swift knowledge required.

Zero API keys. Zero cloud costs. Runs entirely on-device.

```
Your App (any language)          DarwinKit (Swift)          Apple Frameworks
       |                              |                           |
       |-- stdin: JSON-RPC request -->|                           |
       |                              |-- NLEmbedding.vector() -->|
       |                              |<-- [0.03, -0.08, ...]  --|
       |<-- stdout: JSON-RPC resp. ---|                           |
```

## Features

| Method | Description | Apple Framework |
|--------|-------------|-----------------|
| `nlp.embed` | Text embeddings (512-dim vectors) | NLEmbedding |
| `nlp.distance` | Semantic distance between texts | NLEmbedding |
| `nlp.neighbors` | Find similar words/sentences | NLEmbedding |
| `nlp.tag` | POS tagging, NER, lemmatization | NLTagger |
| `nlp.sentiment` | Sentiment analysis | NLTagger |
| `nlp.language` | Language detection | NLLanguageRecognizer |
| `vision.ocr` | Text extraction from images | VNRecognizeTextRequest |
| `dictation.*` | Streaming voice-to-text (Whisper) | WhisperKit (CoreML) |
| `auth.*` | Biometric / device-owner auth | LocalAuthentication |
| `icloud.*` | Coordinated iCloud file sync | NSFileCoordinator |
| `system.capabilities` | Query available methods + OS info | — |

See [Method Reference](#method-reference) for parameter schemas.

## Requirements

- **macOS 14+ (Sonoma)** — raised from 13 in v0.3.0 to support WhisperKit
- Sentence embeddings work on macOS 11+ (Big Sur) if you build without dictation

## Install

### Homebrew (recommended)

```bash
brew tap 0xMassi/darwinkit
brew install darwinkit
```

### GitHub Releases

```bash
curl -L https://github.com/0xMassi/darwinkit/releases/latest/download/darwinkit-macos-universal.tar.gz | tar xz
sudo mv darwinkit /usr/local/bin/
```

### Build from source

```bash
git clone https://github.com/0xMassi/darwinkit.git
cd darwinkit
swift build -c release
# Binary at .build/release/darwinkit
```

## Quick Start

### Server mode (long-running, for apps)

```bash
# Start the server — it reads from stdin and writes to stdout
echo '{"jsonrpc":"2.0","id":"1","method":"nlp.sentiment","params":{"text":"I love this product"}}' \
  | darwinkit serve 2>/dev/null
```

```json
{"id":"1","jsonrpc":"2.0","result":{"label":"positive","score":1.0}}
```

### Query mode (single request, for scripts)

```bash
darwinkit query '{"jsonrpc":"2.0","id":"1","method":"nlp.language","params":{"text":"Bonjour le monde"}}'
```

```json
{
  "id": "1",
  "jsonrpc": "2.0",
  "result": {
    "confidence": 0.9990198612213135,
    "language": "fr"
  }
}
```

## Protocol

DarwinKit uses **JSON-RPC 2.0** over **NDJSON** (one JSON object per line). Same pattern as [MCP](https://spec.modelcontextprotocol.io).

**Request** (you send):
```json
{"jsonrpc":"2.0","id":"1","method":"nlp.embed","params":{"text":"hello","language":"en"}}
```

**Response** (you receive):
```json
{"jsonrpc":"2.0","id":"1","result":{"vector":[0.031,-0.089,...],"dimension":512}}
```

**Error**:
```json
{"jsonrpc":"2.0","id":"1","error":{"code":-32602,"message":"Missing required param: text"}}
```

### Lifecycle

1. Spawn `darwinkit serve` as a subprocess
2. Read the `ready` notification from stdout (contains version + available methods)
3. Write requests to stdin, read responses from stdout
4. Close stdin when done — DarwinKit exits cleanly

### Error Codes

| Code | Meaning |
|------|---------|
| -32700 | Parse error (malformed JSON) |
| -32600 | Invalid request |
| -32601 | Method not found |
| -32602 | Invalid params |
| -32603 | Internal error |
| -32001 | Framework unavailable |
| -32002 | Permission denied |
| -32003 | OS version too old |
| -32004 | Operation cancelled |

---

## Method Reference

### nlp.embed

Compute semantic vectors using Apple's built-in embeddings.

```json
{"jsonrpc":"2.0","id":"1","method":"nlp.embed","params":{
  "text": "quarterly meeting notes",
  "language": "en",
  "type": "sentence"
}}
```

| Param | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `text` | string | yes | — | Text to embed |
| `language` | string | yes | — | Language code: `en`, `es`, `fr`, `de`, `it`, `pt`, `zh` |
| `type` | string | no | `"sentence"` | `"word"` or `"sentence"` |

Returns `{ "vector": [...], "dimension": 512 }`.

### nlp.distance

Cosine distance between two texts (0 = identical, 2 = opposite).

```json
{"jsonrpc":"2.0","id":"1","method":"nlp.distance","params":{
  "text1": "cat", "text2": "dog", "language": "en", "type": "word"
}}
```

Returns `{ "distance": 0.312, "type": "cosine" }`.

### nlp.neighbors

Find semantically similar words or sentences.

```json
{"jsonrpc":"2.0","id":"1","method":"nlp.neighbors","params":{
  "text": "programming", "language": "en", "type": "word", "count": 5
}}
```

Returns `{ "neighbors": [{"text": "coding", "distance": 0.21}, ...] }`.

### nlp.tag

Part-of-speech tagging and named entity recognition.

```json
{"jsonrpc":"2.0","id":"1","method":"nlp.tag","params":{
  "text": "Steve Jobs founded Apple in Cupertino",
  "schemes": ["nameType", "lexicalClass"]
}}
```

| Param | Type | Required | Default |
|-------|------|----------|---------|
| `text` | string | yes | — |
| `language` | string | no | auto-detect |
| `schemes` | string[] | no | `["lexicalClass"]` |

Available schemes: `lexicalClass`, `nameType`, `lemma`, `sentimentScore`, `language`.

### nlp.sentiment

Sentiment analysis with score and label.

```json
{"jsonrpc":"2.0","id":"1","method":"nlp.sentiment","params":{
  "text": "This is absolutely fantastic"
}}
```

Returns `{ "score": 0.9, "label": "positive" }`. Labels: `positive` (>0.1), `negative` (<-0.1), `neutral`.

### nlp.language

Detect the language of a text.

```json
{"jsonrpc":"2.0","id":"1","method":"nlp.language","params":{
  "text": "Bonjour, comment allez-vous?"
}}
```

Returns `{ "language": "fr", "confidence": 0.99 }`.

### vision.ocr

Extract text from images using Apple Vision.

```json
{"jsonrpc":"2.0","id":"1","method":"vision.ocr","params":{
  "path": "/tmp/screenshot.png",
  "languages": ["en-US"],
  "level": "accurate"
}}
```

| Param | Type | Required | Default |
|-------|------|----------|---------|
| `path` | string | yes | — |
| `languages` | string[] | no | `["en-US"]` |
| `level` | string | no | `"accurate"` |

Returns `{ "text": "...", "blocks": [{"text": "...", "confidence": 0.99, "bounds": {"x":0.1,"y":0.8,"width":0.3,"height":0.05}}] }`.

Bounds are normalized (0-1), origin at bottom-left. Supports JPEG, PNG, TIFF, HEIC, PDF.

### system.capabilities

Query version, OS info, and available methods.

```json
{"jsonrpc":"2.0","id":"1","method":"system.capabilities","params":{}}
```

### dictation.*

Streaming voice-to-text via [WhisperKit](https://github.com/argmaxinc/WhisperKit). Models run fully on-device through CoreML on the Neural Engine — no audio ever leaves the machine.

**Model management**

| Method | Description |
|--------|-------------|
| `dictation.list_models` | Curated list of available Whisper variants with size + downloaded flag |
| `dictation.status` | Currently installed + active model, any download in progress |
| `dictation.download_model` | Start downloading a model; streams `dictation.download_progress` notifications |
| `dictation.cancel_download` | Abort an in-flight download |
| `dictation.delete_model` | Remove a downloaded model from disk |
| `dictation.set_active_model` | Synchronously load a model into memory (blocks up to 180 s for CoreML compilation) |

**Recognition**

```json
{"jsonrpc":"2.0","id":"1","method":"dictation.start","params":{
  "language": "en",
  "model_id": "openai_whisper-small"
}}
```

| Param | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `language` | string | no | auto-detect | ISO code: `en`, `it`, `fr`, `de`, … |
| `model_id` | string | no | current or first installed | Whisper variant id from `list_models` |

While recording, the server emits `dictation.partial` notifications with the running transcription:

```json
{"jsonrpc":"2.0","method":"dictation.partial","params":{"text":"hello world so far"}}
```

`dictation.stop` returns the final transcription:

```json
{"jsonrpc":"2.0","id":"2","method":"dictation.stop"}
// → {"jsonrpc":"2.0","id":"2","result":{"text":"hello world so far"}}
```

**Where models live**

```
~/Library/Application Support/com.stik.app/WhisperModels/models/argmaxinc/whisperkit-coreml/<variant>/
```

The working directory is changed to `~/Library/Application Support/com.stik.app/` on startup so swift-transformers' Hub client can write its tokenizer cache to a sandbox-writable location.

---

## Integration Examples

DarwinKit works with any language that can spawn a subprocess and read/write its stdio. Below are working examples.

### Node.js / TypeScript

```typescript
import { spawn } from "child_process";
import * as readline from "readline";

class DarwinKit {
  private process;
  private rl;
  private pending = new Map<string, { resolve: Function; reject: Function }>();
  private nextId = 1;

  constructor() {
    this.process = spawn("darwinkit", ["serve"], {
      stdio: ["pipe", "pipe", "pipe"],
    });

    this.rl = readline.createInterface({ input: this.process.stdout });
    this.rl.on("line", (line) => {
      const msg = JSON.parse(line);
      // Skip notifications (no id)
      if (!msg.id) return;
      const pending = this.pending.get(msg.id);
      if (!pending) return;
      this.pending.delete(msg.id);
      if (msg.error) pending.reject(new Error(msg.error.message));
      else pending.resolve(msg.result);
    });
  }

  async call(method: string, params: Record<string, any> = {}): Promise<any> {
    const id = String(this.nextId++);
    const request = { jsonrpc: "2.0", id, method, params };
    this.process.stdin.write(JSON.stringify(request) + "\n");

    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
    });
  }

  close() {
    this.process.stdin.end();
  }
}

// Usage
const dk = new DarwinKit();

const sentiment = await dk.call("nlp.sentiment", { text: "I love this" });
console.log(sentiment); // { score: 1.0, label: "positive" }

const ocr = await dk.call("vision.ocr", { path: "/tmp/photo.png" });
console.log(ocr.text);

dk.close();
```

### Python

```python
import json
import subprocess
import threading

class DarwinKit:
    def __init__(self):
        self.process = subprocess.Popen(
            ["darwinkit", "serve"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )
        self._id = 0
        self._lock = threading.Lock()
        # Read and discard the 'ready' notification
        self.process.stdout.readline()

    def call(self, method: str, params: dict = None) -> dict:
        with self._lock:
            self._id += 1
            request = {"jsonrpc": "2.0", "id": str(self._id), "method": method, "params": params or {}}
            self.process.stdin.write(json.dumps(request) + "\n")
            self.process.stdin.flush()

            line = self.process.stdout.readline()
            response = json.loads(line)

            if "error" in response and response["error"]:
                raise Exception(f"DarwinKit error {response['error']['code']}: {response['error']['message']}")
            return response["result"]

    def close(self):
        self.process.stdin.close()
        self.process.wait()

# Usage
dk = DarwinKit()

embedding = dk.call("nlp.embed", {"text": "hello world", "language": "en", "type": "sentence"})
print(f"Vector dimension: {embedding['dimension']}")  # 512

lang = dk.call("nlp.language", {"text": "Ciao, come stai?"})
print(f"Detected: {lang['language']} ({lang['confidence']:.0%})")  # it (99%)

dk.close()
```

### Rust

```rust
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::io::{BufRead, BufReader, Write};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicU64, Ordering};

pub struct DarwinKit {
    child: std::process::Child,
    reader: BufReader<std::process::ChildStdout>,
    next_id: AtomicU64,
}

#[derive(Serialize)]
struct Request {
    jsonrpc: &'static str,
    id: String,
    method: String,
    params: Value,
}

#[derive(Deserialize)]
struct Response {
    id: Option<String>,
    result: Option<Value>,
    error: Option<RpcError>,
}

#[derive(Deserialize)]
struct RpcError {
    code: i32,
    message: String,
}

impl DarwinKit {
    pub fn new() -> std::io::Result<Self> {
        let mut child = Command::new("darwinkit")
            .args(["serve"])
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()?;

        let stdout = child.stdout.take().unwrap();
        let mut reader = BufReader::new(stdout);

        // Read and discard ready notification
        let mut ready = String::new();
        reader.read_line(&mut ready)?;

        Ok(Self { child, reader, next_id: AtomicU64::new(1) })
    }

    pub fn call(&mut self, method: &str, params: Value) -> Result<Value, String> {
        let id = self.next_id.fetch_add(1, Ordering::Relaxed).to_string();
        let request = Request { jsonrpc: "2.0", id: id.clone(), method: method.to_string(), params };

        let stdin = self.child.stdin.as_mut().unwrap();
        serde_json::to_writer(&mut *stdin, &request).map_err(|e| e.to_string())?;
        stdin.write_all(b"\n").map_err(|e| e.to_string())?;
        stdin.flush().map_err(|e| e.to_string())?;

        let mut line = String::new();
        self.reader.read_line(&mut line).map_err(|e| e.to_string())?;

        let response: Response = serde_json::from_str(&line).map_err(|e| e.to_string())?;
        if let Some(err) = response.error {
            return Err(format!("DarwinKit error {}: {}", err.code, err.message));
        }
        response.result.ok_or_else(|| "No result".to_string())
    }
}

impl Drop for DarwinKit {
    fn drop(&mut self) {
        drop(self.child.stdin.take()); // close stdin -> darwinkit exits
        let _ = self.child.wait();
    }
}

// Usage
fn main() -> Result<(), String> {
    let mut dk = DarwinKit::new().map_err(|e| e.to_string())?;

    let result = dk.call("nlp.sentiment", serde_json::json!({"text": "Rust is great"}))?;
    println!("Score: {}", result["score"]); // 1.0

    let ocr = dk.call("vision.ocr", serde_json::json!({"path": "/tmp/image.png"}))?;
    println!("Text: {}", ocr["text"]);

    Ok(())
}
```

### Go

```go
package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os/exec"
	"sync"
	"sync/atomic"
)

type DarwinKit struct {
	cmd    *exec.Cmd
	stdin  *json.Encoder
	reader *bufio.Reader
	nextID atomic.Int64
	mu     sync.Mutex
}

type rpcRequest struct {
	JSONRPC string      `json:"jsonrpc"`
	ID      string      `json:"id"`
	Method  string      `json:"method"`
	Params  interface{} `json:"params"`
}

type rpcResponse struct {
	ID     *string          `json:"id"`
	Result json.RawMessage  `json:"result"`
	Error  *struct {
		Code    int    `json:"code"`
		Message string `json:"message"`
	} `json:"error"`
}

func NewDarwinKit() (*DarwinKit, error) {
	cmd := exec.Command("darwinkit", "serve")
	stdin, _ := cmd.StdinPipe()
	stdout, _ := cmd.StdoutPipe()
	if err := cmd.Start(); err != nil {
		return nil, err
	}

	reader := bufio.NewReader(stdout)
	reader.ReadString('\n') // skip ready notification

	return &DarwinKit{
		cmd:    cmd,
		stdin:  json.NewEncoder(stdin),
		reader: reader,
	}, nil
}

func (dk *DarwinKit) Call(method string, params interface{}) (json.RawMessage, error) {
	dk.mu.Lock()
	defer dk.mu.Unlock()

	id := fmt.Sprintf("%d", dk.nextID.Add(1))
	req := rpcRequest{JSONRPC: "2.0", ID: id, Method: method, Params: params}
	if err := dk.stdin.Encode(req); err != nil {
		return nil, err
	}

	line, err := dk.reader.ReadString('\n')
	if err != nil {
		return nil, err
	}

	var resp rpcResponse
	if err := json.Unmarshal([]byte(line), &resp); err != nil {
		return nil, err
	}
	if resp.Error != nil {
		return nil, fmt.Errorf("darwinkit error %d: %s", resp.Error.Code, resp.Error.Message)
	}
	return resp.Result, nil
}

func (dk *DarwinKit) Close() {
	dk.cmd.Process.Kill()
	dk.cmd.Wait()
}

func main() {
	dk, err := NewDarwinKit()
	if err != nil {
		panic(err)
	}
	defer dk.Close()

	result, _ := dk.Call("nlp.language", map[string]string{"text": "Hola mundo"})
	fmt.Println(string(result)) // {"language":"es","confidence":0.99}
}
```

### Ruby

```ruby
require 'json'
require 'open3'

class DarwinKit
  def initialize
    @stdin, @stdout, @stderr, @wait = Open3.popen3("darwinkit", "serve")
    @id = 0
    @stdout.gets # skip ready notification
  end

  def call(method, params = {})
    @id += 1
    request = { jsonrpc: "2.0", id: @id.to_s, method: method, params: params }
    @stdin.puts(request.to_json)
    @stdin.flush

    line = @stdout.gets
    response = JSON.parse(line)

    if response["error"]
      raise "DarwinKit error #{response['error']['code']}: #{response['error']['message']}"
    end
    response["result"]
  end

  def close
    @stdin.close
    @wait.value
  end
end

# Usage
dk = DarwinKit.new

result = dk.call("nlp.sentiment", { text: "Ruby is elegant" })
puts "#{result['label']}: #{result['score']}"

ocr = dk.call("vision.ocr", { path: "/tmp/receipt.png" })
puts ocr["text"]

dk.close
```

### Shell (Bash)

```bash
# One-shot query (simplest usage)
darwinkit query '{"jsonrpc":"2.0","id":"1","method":"nlp.language","params":{"text":"Guten Tag"}}'

# Pipe multiple requests in server mode
{
  echo '{"jsonrpc":"2.0","id":"1","method":"nlp.sentiment","params":{"text":"Great product"}}'
  echo '{"jsonrpc":"2.0","id":"2","method":"nlp.language","params":{"text":"Bonjour"}}'
} | darwinkit serve 2>/dev/null

# Extract text from screenshot with jq
darwinkit query '{"jsonrpc":"2.0","id":"1","method":"vision.ocr","params":{"path":"/tmp/screenshot.png"}}' \
  | jq -r '.result.text'
```

### Tauri (Rust + Sidecar)

Bundle DarwinKit inside your Tauri app:

**1. Place binaries in `src-tauri/binaries/`:**
```
src-tauri/binaries/
  darwinkit-aarch64-apple-darwin      # Apple Silicon
  darwinkit-x86_64-apple-darwin       # Intel
```

**2. Configure `tauri.conf.json`:**
```json
{
  "bundle": {
    "externalBin": ["binaries/darwinkit"]
  }
}
```

**3. Spawn from Rust:**
```rust
use tauri_plugin_shell::ShellExt;

let sidecar = app.shell().sidecar("darwinkit").unwrap().args(["serve"]);
let (mut rx, child) = sidecar.spawn().unwrap();

// Send request
child.write(b"{\"jsonrpc\":\"2.0\",\"id\":\"1\",\"method\":\"nlp.sentiment\",\"params\":{\"text\":\"hello\"}}\n").unwrap();

// Read response
while let Some(event) = rx.recv().await {
    if let tauri_plugin_shell::process::CommandEvent::Stdout(line) = event {
        let response: serde_json::Value = serde_json::from_slice(&line).unwrap();
        println!("{}", response);
        break;
    }
}
```

---

## Architecture

```
darwinkit/
  Package.swift                          # Swift 5.10, macOS 14+
  Sources/
    DarwinKit/                           # Thin CLI entry point
      DarwinKit.swift                    # @main, serve + query subcommands
      Info.plist                         # Bundle metadata + mic usage string
    DarwinKitCore/                       # All logic (importable by tests)
      Server/
        Protocol.swift                   # JSON-RPC types, AnyCodable
        JsonRpcServer.swift              # stdin/stdout NDJSON loop + concurrent dispatch
        MethodRouter.swift               # Method dispatch + capabilities
      Handlers/
        SystemHandler.swift              # system.capabilities
        NLPHandler.swift                 # nlp.* methods
        VisionHandler.swift              # vision.ocr
        CloudHandler.swift               # icloud.* methods
        AuthHandler.swift                # auth.* methods
        DictationHandler.swift           # dictation.* methods (streaming)
      Providers/
        NLPProvider.swift                # NaturalLanguage impl
        VisionProvider.swift             # Apple Vision impl
        CloudProvider.swift              # NSFileCoordinator impl
        AuthProvider.swift               # LocalAuthentication impl
        WhisperDictationProvider.swift   # WhisperKit impl
  Tests/
    DarwinKitCoreTests/                  # Mock-backed unit tests
```

All Apple framework calls are behind **provider protocols**. Tests use mock providers for deterministic, fast unit tests without requiring specific OS versions.

### Concurrent dispatch

Since v0.3.0 the JSON-RPC server dispatches each request onto a concurrent `DispatchQueue` (`darwinkit.dispatch`, `.userInitiated`) rather than running handlers inline on the stdin reader loop. This keeps fast calls (`nlp.sentiment`, `system.capabilities`) responsive while a slow handler — e.g. `dictation.set_active_model` blocking for 30–60 s on CoreML compilation — is in flight.

## Development

```bash
swift build                    # Debug build
swift build -c release         # Release build
swift test                     # Run all 43 tests
swift test --filter NLP        # Run NLP tests only
```

### Build universal binary (arm64 + x86_64)

```bash
swift build -c release --arch arm64 --arch x86_64
# Binary at .build/apple/Products/Release/darwinkit
# (NOT .build/release/ — multi-arch builds land under .build/apple/Products/)
```

## Roadmap

- **v0.1.0** — NLP + Vision + JSON-RPC server
- **v0.2.0** — `auth.*` + `icloud.*` (biometric auth, coordinated file sync)
- **v0.3.0** (current) — `dictation.*` via WhisperKit, concurrent dispatch, macOS 14+
- **v0.4.0** — `llm.generate` via Apple Foundation Models (macOS 26+)

See [CHANGELOG.md](CHANGELOG.md) for release details.

## License

MIT

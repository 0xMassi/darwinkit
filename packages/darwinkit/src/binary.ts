import { execSync } from "node:child_process"
import { existsSync, mkdirSync, chmodSync } from "node:fs"
import { join, dirname } from "node:path"
import { fileURLToPath } from "node:url"
import { homedir } from "node:os"
import { Readable } from "node:stream"
import { pipeline } from "node:stream/promises"
import { createGunzip } from "node:zlib"
import { extract } from "tar"

const BINARY_NAME = "darwinkit"
const CACHE_DIR = join(homedir(), ".cache", "darwinkit")
const RELEASE_URL = "https://github.com/genesiscz/darwinkit-swift/releases/latest/download/darwinkit-macos-universal.tar.gz"
const REPO_URL = "https://github.com/genesiscz/darwinkit-swift.git"

/** Resolve the directory where this module lives (works in both ESM and CJS). */
function getPackageDir(): string {
  try {
    // ESM
    return dirname(fileURLToPath(import.meta.url))
  } catch {
    // CJS fallback
    return __dirname
  }
}

export async function ensureBinary(binaryPath?: string): Promise<string> {
  // 1. Explicit path
  if (binaryPath) {
    if (!existsSync(binaryPath)) {
      throw new Error(`Binary not found at specified path: ${binaryPath}`)
    }
    return binaryPath
  }

  // 2. Check bundled binary (shipped with npm package)
  const bundled = join(getPackageDir(), "..", "bin", BINARY_NAME)
  if (existsSync(bundled)) return bundled

  // 3. Check PATH
  const fromPath = findOnPath(BINARY_NAME)
  if (fromPath) return fromPath

  // 4. Check cache
  const cached = join(CACHE_DIR, BINARY_NAME)
  if (existsSync(cached)) return cached

  // 5. Download from GitHub releases
  mkdirSync(CACHE_DIR, { recursive: true })

  try {
    console.error("[darwinkit] Binary not found, downloading from GitHub releases...")
    await downloadAndExtract(RELEASE_URL, CACHE_DIR)
    chmodSync(cached, 0o755)
    console.error("[darwinkit] Binary downloaded to", cached)
    return cached
  } catch (downloadError) {
    console.error("[darwinkit] Download failed:", downloadError)
  }

  // 6. Build from source
  if (findOnPath("swift")) {
    try {
      console.error("[darwinkit] Attempting to build from source...")
      return await buildFromSource(cached)
    } catch (buildError) {
      console.error("[darwinkit] Build from source failed:", buildError)
    }
  }

  // 7. Fail with instructions
  throw new Error(
    "Could not find or install darwinkit binary.\n" +
    "Install it manually:\n" +
    "  curl -L https://github.com/genesiscz/darwinkit-swift/releases/latest/download/darwinkit-macos-universal.tar.gz | tar xz -C ~/.local/bin/\n" +
    "Or set the binary path:\n" +
    "  new DarwinKit({ binary: '/path/to/darwinkit' })"
  )
}

function findOnPath(name: string): string | null {
  try {
    return execSync(`which ${name}`, { encoding: "utf-8", stdio: ["pipe", "pipe", "pipe"] }).trim()
  } catch {
    return null
  }
}

async function downloadAndExtract(url: string, destDir: string): Promise<void> {
  const response = await fetch(url, { redirect: "follow" })
  if (!response.ok) {
    throw new Error(`HTTP ${response.status}: ${response.statusText}`)
  }
  if (!response.body) {
    throw new Error("No response body")
  }

  const nodeStream = Readable.fromWeb(response.body as any)
  await pipeline(
    nodeStream,
    createGunzip(),
    extract({ cwd: destDir }),
  )
}

async function buildFromSource(outputPath: string): Promise<string> {
  const { execSync } = await import("node:child_process")
  const tmpDir = execSync("mktemp -d", { encoding: "utf-8" }).trim()

  try {
    execSync(`git clone --depth 1 ${REPO_URL} "${tmpDir}/darwinkit-swift"`, {
      stdio: "pipe",
    })

    execSync(
      "swift build -c release --arch arm64 --arch x86_64",
      {
        cwd: join(tmpDir, "darwinkit-swift", "packages", "darwinkit-swift"),
        stdio: "pipe",
        timeout: 300_000, // 5 min build timeout
      },
    )

    const builtBinary = join(tmpDir, "darwinkit-swift", "packages", "darwinkit-swift", ".build", "apple", "Products", "Release", "darwinkit")
    const { copyFileSync } = await import("node:fs")
    copyFileSync(builtBinary, outputPath)
    chmodSync(outputPath, 0o755)
    console.error("[darwinkit] Built from source and cached at", outputPath)
    return outputPath
  } finally {
    try { execSync(`rm -rf "${tmpDir}"`, { stdio: "pipe" }) } catch {}
  }
}

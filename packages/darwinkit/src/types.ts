// ---------------------------------------------------------------------------
// NLP
// ---------------------------------------------------------------------------

export type EmbedType = "word" | "sentence"
export type NLPLanguage = "en" | "es" | "fr" | "de" | "it" | "pt" | "zh-Hans"

export interface EmbedParams {
  text: string
  language: string
  type?: EmbedType // default: "sentence"
}
export interface EmbedResult {
  vector: number[]
  dimension: number
}

export interface DistanceParams {
  text1: string
  text2: string
  language: string
  type?: EmbedType // default: "word"
}
export interface DistanceResult {
  distance: number
  type: "cosine"
}

export interface NeighborsParams {
  text: string
  language: string
  type?: EmbedType // default: "word"
  count?: number // default: 5
}
export interface Neighbor {
  text: string
  distance: number
}
export interface NeighborsResult {
  neighbors: Neighbor[]
}

export type TagScheme =
  | "lexicalClass"
  | "nameType"
  | "lemma"
  | "sentimentScore"
  | "language"

export interface TagParams {
  text: string
  language?: string
  schemes?: TagScheme[] // default: ["lexicalClass"]
}
export interface TagToken {
  text: string
  tags: Partial<Record<TagScheme, string>>
}
export interface TagResult {
  tokens: TagToken[]
}

export interface SentimentParams {
  text: string
}
export interface SentimentResult {
  score: number
  label: "positive" | "negative" | "neutral"
}

export interface LanguageParams {
  text: string
}
export interface LanguageResult {
  language: string
  confidence: number
}

// ---------------------------------------------------------------------------
// Vision
// ---------------------------------------------------------------------------

export type RecognitionLevel = "accurate" | "fast"

export interface OCRParams {
  path: string
  languages?: string[] // default: ["en-US"]
  level?: RecognitionLevel // default: "accurate"
}
export interface OCRBounds {
  x: number
  y: number
  width: number
  height: number
}
export interface OCRBlock {
  text: string
  confidence: number
  bounds: OCRBounds
}
export interface OCRResult {
  text: string
  blocks: OCRBlock[]
}

// ---------------------------------------------------------------------------
// Auth
// ---------------------------------------------------------------------------

export type BiometryType = "touchID" | "opticID" | "none"

export interface AuthAvailableResult {
  available: boolean
  biometry_type: BiometryType
}
export interface AuthenticateParams {
  reason?: string
}
export interface AuthenticateResult {
  success: boolean
}

// ---------------------------------------------------------------------------
// System
// ---------------------------------------------------------------------------

export interface MethodCapability {
  available: boolean
  note?: string
}
export interface CapabilitiesResult {
  version: string
  os: string
  arch: "arm64" | "x86_64" | "unknown"
  methods: Record<string, MethodCapability>
}

// ---------------------------------------------------------------------------
// iCloud
// ---------------------------------------------------------------------------

export interface ICloudStatusResult {
  available: boolean
  container_url: string
}

export interface ICloudReadParams {
  path: string
}
export interface ICloudReadResult {
  content: string
}

export interface ICloudWriteParams {
  path: string
  content: string
}
export interface ICloudWriteBytesParams {
  path: string
  data: string // base64
}

export interface ICloudDeleteParams {
  path: string
}
export interface ICloudMoveParams {
  source: string
  destination: string
}
export interface ICloudCopyFileParams {
  source: string
  destination: string
}

export interface ICloudListDirParams {
  path: string
}
export interface ICloudDirEntry {
  name: string
  is_directory: boolean
  size: number
  modified?: string // ISO8601
}
export interface ICloudListDirResult {
  entries: ICloudDirEntry[]
}

export interface ICloudEnsureDirParams {
  path: string
}
export interface ICloudOkResult {
  ok: true
}

// ---------------------------------------------------------------------------
// Notifications
// ---------------------------------------------------------------------------

export interface FilesChangedNotification {
  paths: string[]
}
export interface ReadyNotification {
  version: string
  capabilities: string[]
}

// ---------------------------------------------------------------------------
// MethodMap
// ---------------------------------------------------------------------------

export interface MethodMap {
  "nlp.embed": { params: EmbedParams; result: EmbedResult }
  "nlp.distance": { params: DistanceParams; result: DistanceResult }
  "nlp.neighbors": { params: NeighborsParams; result: NeighborsResult }
  "nlp.tag": { params: TagParams; result: TagResult }
  "nlp.sentiment": { params: SentimentParams; result: SentimentResult }
  "nlp.language": { params: LanguageParams; result: LanguageResult }
  "vision.ocr": { params: OCRParams; result: OCRResult }
  "auth.available": {
    params: Record<string, never>
    result: AuthAvailableResult
  }
  "auth.authenticate": {
    params: AuthenticateParams
    result: AuthenticateResult
  }
  "system.capabilities": {
    params: Record<string, never>
    result: CapabilitiesResult
  }
  "icloud.status": {
    params: Record<string, never>
    result: ICloudStatusResult
  }
  "icloud.read": { params: ICloudReadParams; result: ICloudReadResult }
  "icloud.write": { params: ICloudWriteParams; result: ICloudOkResult }
  "icloud.write_bytes": {
    params: ICloudWriteBytesParams
    result: ICloudOkResult
  }
  "icloud.delete": { params: ICloudDeleteParams; result: ICloudOkResult }
  "icloud.move": { params: ICloudMoveParams; result: ICloudOkResult }
  "icloud.copy_file": { params: ICloudCopyFileParams; result: ICloudOkResult }
  "icloud.list_dir": {
    params: ICloudListDirParams
    result: ICloudListDirResult
  }
  "icloud.ensure_dir": {
    params: ICloudEnsureDirParams
    result: ICloudOkResult
  }
  "icloud.start_monitoring": {
    params: Record<string, never>
    result: ICloudOkResult
  }
  "icloud.stop_monitoring": {
    params: Record<string, never>
    result: ICloudOkResult
  }
}

export type MethodName = keyof MethodMap

// ---------------------------------------------------------------------------
// PreparedCall (for batch API)
// ---------------------------------------------------------------------------

export interface PreparedCall<M extends MethodName> {
  readonly method: M
  readonly params: MethodMap[M]["params"]
  readonly __brand: MethodMap[M]["result"] // phantom type for inference
}

// Helper type to extract results from a tuple of PreparedCalls
export type BatchResult<T extends ReadonlyArray<PreparedCall<MethodName>>> = {
  [K in keyof T]: T[K] extends PreparedCall<infer M>
    ? MethodMap[M]["result"]
    : never
}

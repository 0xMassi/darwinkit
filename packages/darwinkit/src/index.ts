export { DarwinKit } from "./client.js"
export type { DarwinKitOptions, DarwinKitClient, Logger, LogLevel } from "./client.js"
export { DarwinKitError, ErrorCodes } from "./errors.js"
export type { ErrorCode } from "./errors.js"
export type { DarwinKitEvent, EventMap, EventType } from "./events.js"
export { ensureBinary } from "./binary.js"

// Namespace classes (for advanced usage / custom composition)
export { NLP } from "./namespaces/nlp.js"
export { Vision } from "./namespaces/vision.js"
export { Auth } from "./namespaces/auth.js"
export { System } from "./namespaces/system.js"
export { ICloud } from "./namespaces/icloud.js"

// All types
export type {
  MethodMap,
  MethodName,
  PreparedCall,
  BatchResult,
  // NLP
  EmbedType,
  NLPLanguage,
  EmbedParams,
  EmbedResult,
  DistanceParams,
  DistanceResult,
  Neighbor,
  NeighborsParams,
  NeighborsResult,
  TagScheme,
  TagParams,
  TagToken,
  TagResult,
  SentimentParams,
  SentimentResult,
  LanguageParams,
  LanguageResult,
  // Vision
  RecognitionLevel,
  OCRParams,
  OCRBounds,
  OCRBlock,
  OCRResult,
  // Auth
  BiometryType,
  AuthAvailableResult,
  AuthenticateParams,
  AuthenticateResult,
  // System
  MethodCapability,
  CapabilitiesResult,
  // iCloud
  ICloudStatusResult,
  ICloudReadParams,
  ICloudReadResult,
  ICloudWriteParams,
  ICloudWriteBytesParams,
  ICloudDeleteParams,
  ICloudMoveParams,
  ICloudCopyFileParams,
  ICloudListDirParams,
  ICloudDirEntry,
  ICloudListDirResult,
  ICloudEnsureDirParams,
  ICloudOkResult,
  // Notifications
  ReadyNotification,
  FilesChangedNotification,
} from "./types.js"

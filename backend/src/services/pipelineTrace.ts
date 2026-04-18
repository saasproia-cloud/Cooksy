// =====================================================================
// pipelineTrace — debug/observability record built during a URL import
// (plan §11). Captures per-stage inputs, outputs, timings, and the final
// snapshot selection so any quality regression can be inspected without
// replaying the run.
// =====================================================================

import type { SanitizedSourceEnvelope, SourceKind } from "./sourceSanitizer.js";
import type { GapReport } from "./gapAnalyzer.js";
import type { PipelineSnapshot, SnapshotStage } from "./pipelineSnapshots.js";

export interface PipelineTraceEnvelope {
  kind: SourceKind;
  rawCharCount: number;
  cleanedCharCount: number;
  foodSignalScore: number;
  recipeLineCount: number;
  noiseLineCount: number;
  sampleNoiseLines: string[];
}

export interface PipelineTraceSnapshot {
  stage: SnapshotStage;
  isBaseline: boolean;
  quality: number;
  ingredientCount: number;
  stepCount: number;
  sectionCount: number;
  specificityScore: number;
  foodSignalCoverage: number;
}

export interface PipelineTrace {
  requestId: string;
  url: string;

  // Stage 1
  envelopes: PipelineTraceEnvelope[];

  // Stage 2
  primarySource?: SourceKind | string;
  compilerIngredientCount?: number;
  compilerStepCount?: number;
  compilerSectionCount?: number;
  compilerQuality?: number;

  // Stage 3
  gaps?: string[];
  recommendedMode?: GapReport["recommendedMode"];

  // Stage 4
  llmMode?: "none" | "preservation" | "full";
  llmDurationMs?: number;

  // Stage 5
  snapshots: PipelineTraceSnapshot[];
  snapshotUsed?: SnapshotStage;
  nonDegradationTriggered?: boolean;

  // Timing
  stageDurations: Record<string, number>;
  totalDurationMs?: number;
}

export function createPipelineTrace(url: string, requestId?: string): PipelineTrace {
  return {
    requestId: requestId ?? Math.random().toString(36).slice(2, 10),
    url,
    envelopes: [],
    snapshots: [],
    stageDurations: {},
  };
}

export function summarizeEnvelopes(
  envelopes: SanitizedSourceEnvelope[]
): PipelineTraceEnvelope[] {
  return envelopes.map((env) => ({
    kind: env.kind,
    rawCharCount: env.rawText.length,
    cleanedCharCount: env.cleanedText.length,
    foodSignalScore: env.foodSignalScore,
    recipeLineCount: env.recipeLines.length,
    noiseLineCount: env.noiseLines.length,
    sampleNoiseLines: env.noiseLines.slice(0, 5),
  }));
}

export function summarizeSnapshot(snap: PipelineSnapshot): PipelineTraceSnapshot {
  return {
    stage: snap.stage,
    isBaseline: snap.isBaseline,
    quality: snap.quality,
    ingredientCount: snap.ingredientCount,
    stepCount: snap.stepCount,
    sectionCount: snap.sectionCount,
    specificityScore: snap.specificityScore,
    foodSignalCoverage: snap.foodSignalCoverage,
  };
}

export function recordStageDuration(
  trace: PipelineTrace,
  stage: string,
  durationMs: number
): void {
  trace.stageDurations[stage] = durationMs;
}

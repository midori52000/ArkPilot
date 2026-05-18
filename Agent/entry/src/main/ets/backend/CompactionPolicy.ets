export interface CompactionDecisionInput {
  contextRemainingPercent: number;
  hasTokenUsage: boolean;
  activeTurnId?: string;
  currentTurnId?: string;
  lastCompactionTurnId: string;
  cooldownMs: number;
  lastCompactionAtMs: number;
  nowMs: number;
  backendAutoCompactEnabled: boolean;
  backendCompactionStateAvailable: boolean;
}

export function shouldStartCompaction(input: CompactionDecisionInput): boolean {
  if (!input.hasTokenUsage) {
    return false;
  }
  if (input.contextRemainingPercent < 0 || input.contextRemainingPercent >= 20) {
    return false;
  }
  if ((input.activeTurnId ?? '').trim().length > 0) {
    return false;
  }
  if ((input.currentTurnId ?? '') === input.lastCompactionTurnId) {
    return false;
  }
  if (input.lastCompactionAtMs > 0 && (input.nowMs - input.lastCompactionAtMs) < input.cooldownMs) {
    return false;
  }
  return true;
}

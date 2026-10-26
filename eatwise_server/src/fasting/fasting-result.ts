/** D-08：延长达到原计划终点即达标；其余按当前终点的容差判断。 */
export function judgeFastingResult(
  plannedEndAt: Date,
  actualEndAt: Date,
  extendedMinutes: number,
  toleranceMs: number,
): { result: 'completed' | 'ended_early' | 'broken'; isQualified: boolean } {
  const earlyByMs = plannedEndAt.getTime() - actualEndAt.getTime();
  // 与 Dart closeCycle 同口径：actual >= planned - extended，起点相消。
  if (earlyByMs <= 0 || (extendedMinutes > 0 && earlyByMs <= extendedMinutes * 60000)) {
    return { result: 'completed', isQualified: true };
  }
  if (earlyByMs <= toleranceMs) return { result: 'ended_early', isQualified: true };
  return { result: 'broken', isQualified: false };
}

export function shiftSummary(
  code: string,
  startsAt: string | null,
  endsAt: string | null,
): string {
  return startsAt && endsAt ? code : `Working — ${code} (time not set)`;
}

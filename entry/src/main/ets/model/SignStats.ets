interface RawSignStats { cont_sign_num?: number | string; cout_total_sing_num?: number | string; }
interface RawSignEnvelope { user_info?: RawSignStats; }
export class SignStats { continuousCount: number = -1; totalCount: number = -1; }
function count(value: number | string | undefined): number {
  if (typeof value !== 'number' && (typeof value !== 'string' || !/^\d+$/.test(value))) { return -1; }
  const number: number = Number(value);
  return Number.isSafeInteger(number) && number >= 0 && number <= 4294967295 ? number : -1;
}

export function parseSignStats(source: string): SignStats {
  const stats: SignStats = new SignStats();
  try {
    const raw: RawSignEnvelope = JSON.parse(source) as RawSignEnvelope;
    stats.continuousCount = count(raw.user_info?.cont_sign_num);
    stats.totalCount = count(raw.user_info?.cout_total_sing_num);
  } catch (err) {  }
  return stats;
}
export function signStatsLabel(stats: SignStats): string {
  const labels: string[] = [];
  if (stats.continuousCount >= 0) { labels.push(`连续签到 ${stats.continuousCount} 次`); }
  if (stats.totalCount >= 0) { labels.push(`累计签到 ${stats.totalCount} 次`); }
  return labels.join(' · ');
}

export interface DebugLoopRecord {
  id: number;
  name: string;
  ownerId?: string;
  strokeColor: string;
  fillColor?: string;
  strokeWidth: number;
  distance: number;
  latitudes: Array<number>;
  longitudes: Array<number>;
  createdAt?: number;
  completedAt?: number;
  durationSeconds?: number;
  avgSpeedKmh?: number;
  /** 是否在闭环浅色填充区内展示广告 */
  adEnabled?: boolean;
  /** 预设品牌 Logo id，见 LoopAdCatalog */
  adPresetId?: string;
  /** 广告标题/口号，可覆盖预设 slogan */
  adTitle?: string;
  /** 自定义广告图（相册 URI 或文件路径） */
  adImageUri?: string;
}

export class DebugLoopStore {
  static ensureOwner(record: DebugLoopRecord): DebugLoopRecord {
    if (record.ownerId !== undefined && record.ownerId.length > 0) {
      return record;
    }
    return DebugLoopStore.copyMetadata(record, {
      id: record.id,
      name: record.name,
      ownerId: 'user_a',
      strokeColor: record.strokeColor,
      fillColor: record.fillColor,
      strokeWidth: record.strokeWidth,
      distance: record.distance,
      latitudes: record.latitudes.slice(),
      longitudes: record.longitudes.slice()
    });
  }

  static copyMetadata(source: DebugLoopRecord, target: DebugLoopRecord): DebugLoopRecord {
    if (source.createdAt !== undefined) {
      target.createdAt = source.createdAt;
    }
    if (source.completedAt !== undefined) {
      target.completedAt = source.completedAt;
    }
    if (source.durationSeconds !== undefined) {
      target.durationSeconds = source.durationSeconds;
    }
    if (source.avgSpeedKmh !== undefined) {
      target.avgSpeedKmh = source.avgSpeedKmh;
    }
    if (source.adEnabled !== undefined) {
      target.adEnabled = source.adEnabled;
    }
    if (source.adPresetId !== undefined) {
      target.adPresetId = source.adPresetId;
    }
    if (source.adTitle !== undefined) {
      target.adTitle = source.adTitle;
    }
    if (source.adImageUri !== undefined) {
      target.adImageUri = source.adImageUri;
    }
    return target;
  }

  static ownerLabel(ownerId: string | undefined): string {
    if (ownerId === 'user_b') {
      return '用户B';
    }
    if (ownerId === 'world') {
      return '世界';
    }
    if (ownerId === undefined || ownerId.length === 0) {
      return '未知';
    }
    if (ownerId === 'user_a') {
      return '用户A';
    }
    return ownerId;
  }
  static toFillColor(strokeColor: string): string {
    let normalized = strokeColor.startsWith('#') ? strokeColor.substring(1) : strokeColor;
    if (normalized.length === 8) {
      normalized = normalized.substring(0, 6);
    }
    if (normalized.length !== 6) {
      return '#2DB55B80';
    }
    return `#${normalized}80`;
  }

  static resolveFillColor(record: DebugLoopRecord): string {
    const fill = record.fillColor;
    if (fill !== undefined && fill !== null && fill.length >= 7) {
      return fill;
    }
    return DebugLoopStore.toFillColor(record.strokeColor);
  }

  static normalizeFillColor(color: string, fallbackStroke: string): string {
    let normalized = color.trim().toUpperCase();
    if (normalized.length === 7 && normalized.charAt(0) === '#') {
      return `${normalized}80`;
    }
    if (normalized.length === 9 && normalized.charAt(0) === '#') {
      return normalized;
    }
    return DebugLoopStore.toFillColor(fallbackStroke);
  }

  static serializeLoops(loops: Array<DebugLoopRecord>): string {
    return JSON.stringify(loops);
  }

  static formatDateTime(timestampMs: number | undefined): string {
    if (timestampMs === undefined || timestampMs <= 0) {
      return '—';
    }
    const date = new Date(timestampMs);
    const pad2 = (value: number): string => {
      return value < 10 ? `0${value}` : `${value}`;
    };
    return `${date.getFullYear()}-${pad2(date.getMonth() + 1)}-${pad2(date.getDate())} ${pad2(date.getHours())}:${pad2(date.getMinutes())}`;
  }

  static formatDuration(seconds: number | undefined): string {
    if (seconds === undefined || seconds <= 0) {
      return '—';
    }
    const total = Math.round(seconds);
    if (total < 60) {
      return `${total} 秒`;
    }
    const minutes = Math.floor(total / 60);
    const remainSeconds = total % 60;
    if (minutes < 60) {
      return remainSeconds > 0 ? `${minutes} 分 ${remainSeconds} 秒` : `${minutes} 分`;
    }
    const hours = Math.floor(minutes / 60);
    const remainMinutes = minutes % 60;
    return remainMinutes > 0 ? `${hours} 小时 ${remainMinutes} 分` : `${hours} 小时`;
  }

  static formatArea(areaM2: number): string {
    if (areaM2 >= 10000) {
      return `${(areaM2 / 10000).toFixed(2)} 公顷`;
    }
    return `${areaM2.toFixed(0)} m²`;
  }

  static formatDistance(meters: number): string {
    if (meters >= 1000) {
      return `${(meters / 1000).toFixed(2)} km`;
    }
    return `${meters.toFixed(0)} m`;
  }

  static formatPace(avgSpeedKmh: number | undefined, distanceMeters: number, durationSeconds: number | undefined): string {
    if (avgSpeedKmh !== undefined && avgSpeedKmh > 0.05) {
      const minutesPerKm = 60 / avgSpeedKmh;
      const paceMin = Math.floor(minutesPerKm);
      const paceSec = Math.round((minutesPerKm - paceMin) * 60);
      return `${paceMin}'${paceSec < 10 ? '0' : ''}${paceSec}" /km`;
    }
    if (durationSeconds !== undefined && durationSeconds > 0 && distanceMeters > 0) {
      const km = distanceMeters / 1000;
      const minutesPerKm = durationSeconds / 60 / km;
      const paceMin = Math.floor(minutesPerKm);
      const paceSec = Math.round((minutesPerKm - paceMin) * 60);
      return `${paceMin}'${paceSec < 10 ? '0' : ''}${paceSec}" /km`;
    }
    return '—';
  }

  static formatSpeed(avgSpeedKmh: number | undefined, distanceMeters: number, durationSeconds: number | undefined): string {
    if (avgSpeedKmh !== undefined && avgSpeedKmh > 0) {
      return `${avgSpeedKmh.toFixed(1)} km/h`;
    }
    if (durationSeconds !== undefined && durationSeconds > 0 && distanceMeters > 0) {
      const speed = (distanceMeters / 1000) / (durationSeconds / 3600);
      return `${speed.toFixed(1)} km/h`;
    }
    return '—';
  }

  static parseLoops(json: string): Array<DebugLoopRecord> {
    if (json.length === 0) {
      return [];
    }
    const parsed = JSON.parse(json) as Array<DebugLoopRecord>;
    if (!Array.isArray(parsed)) {
      return [];
    }
    return parsed;
  }
}

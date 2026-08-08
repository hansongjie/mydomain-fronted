/**
 * MyDomai Java 后端地址。
 * 真机请使用电脑局域网 IP（当前 Wi‑Fi: 192.168.0.105）。
 * 模拟器若走本机端口转发，可改回 http://127.0.0.1:8080。
 */
export class BackendConfig {
  /** 设为 false 可完全关闭后端同步 */
  static readonly ENABLED: boolean = true;
  /** 电脑局域网 IP，确保手机与电脑同一 Wi‑Fi */
  static readonly BASE_URL: string = 'http://192.168.0.105:8080';
  static readonly API_PREFIX: string = '/api/v1';
  static readonly CONNECT_TIMEOUT_MS: number = 8000;
  static readonly READ_TIMEOUT_MS: number = 15000;
  /** 领地拉取（GET）超时：失败应快速反馈，避免长时间卡在「刷新中」 */
  static readonly TERRITORY_FETCH_TIMEOUT_MS: number = 20000;
  /** 领地上传（PUT，坐标多）单独放宽读超时 */
  static readonly TERRITORY_SYNC_TIMEOUT_MS: number = 45000;
  /** 轨迹点批量上报频率（点数） */
  static readonly TRACK_FLUSH_EVERY: number = 12;

  static api(path: string): string {
    const base = BackendConfig.BASE_URL.endsWith('/')
      ? BackendConfig.BASE_URL.substring(0, BackendConfig.BASE_URL.length - 1)
      : BackendConfig.BASE_URL;
    const p = path.startsWith('/') ? path : `/${path}`;
    return `${base}${BackendConfig.API_PREFIX}${p}`;
  }
}

import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BackendConfig } from '../config/BackendConfig';
import { DebugLoopRecord } from '../model/DebugLoopModel';
import { PlacedItemRecord } from '../model/TerritoryItemModel';
import { TerritoryExportBundle, TerritoryExportStore } from '../model/TerritoryExportModel';

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'MyDomaiBackend';

export interface BackendTrackPoint {
  lat: number;
  lng: number;
  ts?: number;
}

interface BackendEnvelope {
  ok?: boolean;
  message?: string;
  data?: Object;
}

interface TrackSessionData {
  id?: number;
  userId?: string;
  status?: string;
  pointCount?: number;
}

interface UpsertUserBody {
  userId: string;
  displayName: string;
  diamonds: number;
}

interface StartTrackBody {
  userId: string;
}

interface AppendTrackBody {
  points: Array<BackendTrackPoint>;
  distanceMeters: number;
}

interface FinishTrackBody {
  points: Array<BackendTrackPoint>;
  distanceMeters: number;
  durationSeconds: number;
  avgSpeedKmh: number;
}

interface BackendLoopDto {
  id?: number;
  name?: string;
  ownerId?: string;
  strokeColor?: string;
  fillColor?: string;
  strokeWidth?: number;
  distance?: number;
  latitudes?: Array<number>;
  longitudes?: Array<number>;
  createdAt?: number;
  completedAt?: number;
  durationSeconds?: number;
  avgSpeedKmh?: number;
  adEnabled?: boolean;
  adPresetId?: string;
  adTitle?: string;
}

interface BackendPlacedItemDto {
  id?: number;
  loopId?: number;
  itemTypeId?: string;
  lat?: number;
  lng?: number;
  diamondCost?: number;
  ownerId?: string;
}

interface TerritorySyncData {
  formatVersion?: number;
  nextLoopId?: number;
  nextPlacedItemId?: number;
  savedLoops?: Array<BackendLoopDto>;
  pendingLoops?: Array<BackendLoopDto>;
  placedItems?: Array<BackendPlacedItemDto>;
  diamonds?: number;
  coordinateSystem?: string;
}

interface JsonHeaders {
  'Content-Type': string;
  Accept?: string;
  Authorization?: string;
}

interface AuthBody {
  username: string;
  password: string;
  displayName?: string;
}

export interface AuthSessionDto {
  userId: string;
  displayName: string;
  diamonds: number;
  token: string;
  expiresAt: string;
}

interface AuthSessionData {
  userId?: string;
  displayName?: string;
  diamonds?: number;
  token?: string;
  expiresAt?: string;
}

export class BackendApiService {
  static async health(): Promise<boolean> {
    if (!BackendConfig.ENABLED) {
      return false;
    }
    try {
      const raw = await BackendApiService.request('GET', '/health', null);
      return raw !== null;
    } catch (e) {
      return false;
    }
  }

  static async register(username: string, password: string, displayName: string): Promise<AuthSessionDto | null> {
    const body: AuthBody = {
      username: username,
      password: password,
      displayName: displayName
    };
    return BackendApiService.parseAuthResponse(
      await BackendApiService.request('POST', '/auth/register', body)
    );
  }

  static async login(username: string, password: string): Promise<AuthSessionDto | null> {
    const body: AuthBody = {
      username: username,
      password: password
    };
    return BackendApiService.parseAuthResponse(
      await BackendApiService.request('POST', '/auth/login', body)
    );
  }

  static async logout(token: string): Promise<boolean> {
    const raw = await BackendApiService.request('POST', '/auth/logout', null, BackendConfig.READ_TIMEOUT_MS, token);
    return raw !== null;
  }

  static async me(token: string): Promise<AuthSessionDto | null> {
    return BackendApiService.parseAuthResponse(
      await BackendApiService.request('GET', '/auth/me', null, BackendConfig.READ_TIMEOUT_MS, token)
    );
  }

  private static parseAuthResponse(raw: string | null): AuthSessionDto | null {
    if (raw === null) {
      return null;
    }
    try {
      const envelope = JSON.parse(raw) as BackendEnvelope;
      if (envelope.ok === false) {
        return null;
      }
      const data = envelope.data as AuthSessionData;
      if (data === undefined || data === null || data.userId === undefined || data.token === undefined) {
        return null;
      }
      const session: AuthSessionDto = {
        userId: `${data.userId}`,
        displayName: data.displayName !== undefined ? `${data.displayName}` : `${data.userId}`,
        diamonds: data.diamonds !== undefined ? Number(data.diamonds) : 100,
        token: `${data.token}`,
        expiresAt: data.expiresAt !== undefined ? `${data.expiresAt}` : ''
      };
      return session;
    } catch (e) {
      return null;
    }
  }

  static async upsertUser(userId: string, displayName: string, diamonds: number): Promise<boolean> {
    const body: UpsertUserBody = {
      userId: userId,
      displayName: displayName,
      diamonds: diamonds
    };
    const raw = await BackendApiService.request('POST', '/users', body);
    return raw !== null;
  }

  static async startTrackSession(userId: string): Promise<number> {
    const body: StartTrackBody = { userId: userId };
    const raw = await BackendApiService.request('POST', '/tracks/sessions', body);
    if (raw === null) {
      return -1;
    }
    try {
      const envelope = JSON.parse(raw) as BackendEnvelope;
      const data = envelope.data as TrackSessionData;
      const id = data !== undefined && data !== null && data.id !== undefined ? Number(data.id) : -1;
      return id;
    } catch (e) {
      return -1;
    }
  }

  static async appendTrackPoints(
    sessionId: number,
    points: Array<BackendTrackPoint>,
    distanceMeters: number
  ): Promise<boolean> {
    if (sessionId < 0 || points.length === 0) {
      return false;
    }
    const body: AppendTrackBody = {
      points: points,
      distanceMeters: distanceMeters
    };
    const raw = await BackendApiService.request('POST', `/tracks/sessions/${sessionId}/points`, body);
    return raw !== null;
  }

  static async finishTrackSession(
    sessionId: number,
    points: Array<BackendTrackPoint>,
    distanceMeters: number,
    durationSeconds: number,
    avgSpeedKmh: number
  ): Promise<boolean> {
    if (sessionId < 0) {
      return false;
    }
    const body: FinishTrackBody = {
      points: points,
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
      avgSpeedKmh: avgSpeedKmh
    };
    const raw = await BackendApiService.request('POST', `/tracks/sessions/${sessionId}/finish`, body);
    return raw !== null;
  }

  static async syncTerritory(
    userId: string,
    savedLoops: Array<DebugLoopRecord>,
    pendingLoops: Array<DebugLoopRecord>,
    placedItems: Array<PlacedItemRecord>,
    nextLoopId: number,
    nextPlacedItemId: number,
    userADiamonds: number,
    userBDiamonds: number,
    deletedLoopIds: Array<number> = []
  ): Promise<boolean> {
    const ownerSaved: Array<DebugLoopRecord> = [];
    const ownerPending: Array<DebugLoopRecord> = [];
    const ownerItems: Array<PlacedItemRecord> = [];
    for (let i = 0; i < savedLoops.length; i++) {
      if (BackendApiService.loopBelongsToUser(savedLoops[i], userId)) {
        ownerSaved.push(savedLoops[i]);
      }
    }
    for (let i = 0; i < pendingLoops.length; i++) {
      if (BackendApiService.loopBelongsToUser(pendingLoops[i], userId)) {
        ownerPending.push(pendingLoops[i]);
      }
    }
    for (let i = 0; i < placedItems.length; i++) {
      if (BackendApiService.itemBelongsToUser(placedItems[i], userId)) {
        ownerItems.push(placedItems[i]);
      }
    }
    const bundle: TerritoryExportBundle = TerritoryExportStore.buildBundle(
      ownerSaved,
      ownerPending,
      ownerItems,
      nextLoopId,
      nextPlacedItemId,
      userADiamonds,
      userBDiamonds
    );
    if (deletedLoopIds.length > 0) {
      bundle.deletedLoopIds = deletedLoopIds;
    }
    if (userId === 'user_b') {
      bundle.diamonds = userBDiamonds;
    } else if (userId === 'user_a') {
      bundle.diamonds = userADiamonds;
    } else {
      bundle.diamonds = userADiamonds;
    }
    hilog.info(LOG_DOMAIN, LOG_TAG,
      'syncTerritory user=%{public}s saved=%{public}d pending=%{public}d deleted=%{public}d',
      userId, ownerSaved.length, ownerPending.length, deletedLoopIds.length);
    const raw = await BackendApiService.request(
      'PUT',
      `/territory/${userId}`,
      bundle,
      BackendConfig.TERRITORY_SYNC_TIMEOUT_MS
    );
    return raw !== null;
  }

  private static loopBelongsToUser(loop: DebugLoopRecord, userId: string): boolean {
    const owner = loop.ownerId !== undefined && loop.ownerId.length > 0 ? loop.ownerId : 'user_a';
    return owner === userId;
  }

  private static itemBelongsToUser(item: PlacedItemRecord, userId: string): boolean {
    const owner = item.ownerId !== undefined && item.ownerId.length > 0 ? item.ownerId : userId;
    return owner === userId;
  }

  /** 从后端拉取指定用户的领地快照（GET），供 App 合并管理台等远端修改 */
  static async fetchTerritory(userId: string): Promise<TerritoryExportBundle | null> {
    let raw = await BackendApiService.request(
      'GET',
      `/territory/${userId}`,
      null,
      BackendConfig.TERRITORY_FETCH_TIMEOUT_MS
    );
    if (raw === null) {
      await new Promise<void>((resolve: () => void) => {
        setTimeout(() => resolve(), 500);
      });
      raw = await BackendApiService.request(
        'GET',
        `/territory/${userId}`,
        null,
        BackendConfig.TERRITORY_FETCH_TIMEOUT_MS
      );
    }
    if (raw === null) {
      return null;
    }
    try {
      const envelope = JSON.parse(raw) as BackendEnvelope;
      const data = envelope.data as TerritorySyncData;
      if (data === undefined || data === null) {
        return null;
      }
      return BackendApiService.toTerritoryBundle(data, userId);
    } catch (e) {
      return null;
    }
  }

  private static toTerritoryBundle(data: TerritorySyncData, userId: string): TerritoryExportBundle {
    const savedLoops: Array<DebugLoopRecord> = [];
    const pendingLoops: Array<DebugLoopRecord> = [];
    const placedItems: Array<PlacedItemRecord> = [];
    const savedRaw = data.savedLoops !== undefined ? data.savedLoops : [];
    const pendingRaw = data.pendingLoops !== undefined ? data.pendingLoops : [];
    const itemsRaw = data.placedItems !== undefined ? data.placedItems : [];
    for (let i = 0; i < savedRaw.length; i++) {
      const loop = BackendApiService.toDebugLoop(savedRaw[i], userId);
      if (loop !== null) {
        savedLoops.push(loop);
      }
    }
    for (let i = 0; i < pendingRaw.length; i++) {
      const loop = BackendApiService.toDebugLoop(pendingRaw[i], userId);
      if (loop !== null) {
        pendingLoops.push(loop);
      }
    }
    for (let i = 0; i < itemsRaw.length; i++) {
      const item = BackendApiService.toPlacedItem(itemsRaw[i], userId);
      if (item !== null) {
        placedItems.push(item);
      }
    }
    const bundle: TerritoryExportBundle = {
      formatVersion: TerritoryExportStore.FORMAT_VERSION,
      app: TerritoryExportStore.APP_NAME,
      exportedAt: new Date().toISOString(),
      coordinateSystem: data.coordinateSystem !== undefined && data.coordinateSystem.length > 0
        ? data.coordinateSystem : 'BD09',
      nextLoopId: data.nextLoopId !== undefined && data.nextLoopId > 0 ? Math.round(data.nextLoopId) : 1,
      nextPlacedItemId: data.nextPlacedItemId !== undefined && data.nextPlacedItemId > 0
        ? Math.round(data.nextPlacedItemId) : 1,
      savedLoops: savedLoops,
      pendingLoops: pendingLoops,
      placedItems: placedItems
    };
    if (data.diamonds !== undefined) {
      bundle.diamonds = data.diamonds;
      if (userId === 'user_b') {
        bundle.userBDiamonds = data.diamonds;
      } else {
        bundle.userADiamonds = data.diamonds;
      }
    }
    return bundle;
  }

  private static toDebugLoop(raw: BackendLoopDto, userId: string): DebugLoopRecord | null {
    if (raw.id === undefined || raw.latitudes === undefined || raw.longitudes === undefined) {
      return null;
    }
    if (raw.latitudes.length < 3 || raw.latitudes.length !== raw.longitudes.length) {
      return null;
    }
    const loop: DebugLoopRecord = {
      id: Math.round(raw.id),
      name: raw.name !== undefined && raw.name.length > 0 ? raw.name : `领地 ${raw.id}`,
      ownerId: raw.ownerId !== undefined && raw.ownerId.length > 0 ? raw.ownerId : userId,
      strokeColor: raw.strokeColor !== undefined && raw.strokeColor.length > 0 ? raw.strokeColor : '#2DB55B',
      strokeWidth: raw.strokeWidth !== undefined ? raw.strokeWidth : 3,
      distance: raw.distance !== undefined ? raw.distance : 0,
      latitudes: raw.latitudes.slice(),
      longitudes: raw.longitudes.slice()
    };
    if (raw.fillColor !== undefined && raw.fillColor !== null && raw.fillColor.length > 0) {
      loop.fillColor = raw.fillColor;
    }
    if (raw.createdAt !== undefined && raw.createdAt !== null) {
      loop.createdAt = raw.createdAt;
    }
    if (raw.completedAt !== undefined && raw.completedAt !== null) {
      loop.completedAt = raw.completedAt;
    }
    if (raw.durationSeconds !== undefined && raw.durationSeconds !== null) {
      loop.durationSeconds = raw.durationSeconds;
    }
    if (raw.avgSpeedKmh !== undefined && raw.avgSpeedKmh !== null) {
      loop.avgSpeedKmh = raw.avgSpeedKmh;
    }
    if (raw.adEnabled === true || raw.adEnabled === false) {
      loop.adEnabled = raw.adEnabled;
    }
    if (raw.adPresetId !== undefined && raw.adPresetId !== null && raw.adPresetId.length > 0) {
      loop.adPresetId = raw.adPresetId;
    }
    if (raw.adTitle !== undefined && raw.adTitle !== null && raw.adTitle.length > 0) {
      loop.adTitle = raw.adTitle;
    }
    return loop;
  }

  private static toPlacedItem(raw: BackendPlacedItemDto, userId: string): PlacedItemRecord | null {
    if (raw.id === undefined || raw.loopId === undefined || raw.itemTypeId === undefined) {
      return null;
    }
    if (raw.lat === undefined || raw.lng === undefined) {
      return null;
    }
    const item: PlacedItemRecord = {
      id: Math.round(raw.id),
      loopId: Math.round(raw.loopId),
      itemTypeId: raw.itemTypeId,
      lat: raw.lat,
      lng: raw.lng
    };
    if (raw.diamondCost !== undefined) {
      item.diamondCost = raw.diamondCost;
    }
    if (raw.ownerId !== undefined && raw.ownerId.length > 0) {
      item.ownerId = raw.ownerId;
    } else {
      item.ownerId = userId;
    }
    return item;
  }

  private static async request(
    method: string,
    path: string,
    body: Object | null,
    readTimeoutMs: number = BackendConfig.READ_TIMEOUT_MS,
    authToken: string = ''
  ): Promise<string | null> {
    if (!BackendConfig.ENABLED) {
      return null;
    }
    const request = http.createHttp();
    try {
      const headers: JsonHeaders = {
        'Content-Type': 'application/json',
        Accept: 'application/json'
      };
      if (authToken.length > 0) {
        headers.Authorization = `Bearer ${authToken}`;
      }
      let httpMethod: http.RequestMethod = http.RequestMethod.GET;
      if (method === 'POST') {
        httpMethod = http.RequestMethod.POST;
      } else if (method === 'PUT') {
        httpMethod = http.RequestMethod.PUT;
      } else if (method === 'DELETE') {
        httpMethod = http.RequestMethod.DELETE;
      }
      const options: http.HttpRequestOptions = {
        method: httpMethod,
        header: headers,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: BackendConfig.CONNECT_TIMEOUT_MS,
        readTimeout: readTimeoutMs
      };
      if (body !== null) {
        options.extraData = JSON.stringify(body);
      }
      const response = await request.request(BackendConfig.api(path), options);
      if (response.responseCode < 200 || response.responseCode >= 300) {
        hilog.warn(LOG_DOMAIN, LOG_TAG, 'HTTP %{public}d %{public}s', response.responseCode, path);
        return null;
      }
      return `${response.result}`;
    } catch (error) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'request failed %{public}s %{public}s', path, JSON.stringify(error));
      return null;
    } finally {
      try {
        request.destroy();
      } catch (e) {
        // ignore
      }
    }
  }
}

import { abilityAccessCtrl, common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { geoLocationManager } from '@kit.LocationKit';
import { MapComponent, MapController, MapOptions, MapStatus, Polygon, Polyline, Label, Circle, Stroke, SysEnum, ILocation, ILocationConfig, TouchType as MapTouchType, OnTouchListener, OverlayEvent, EOverLayTypeName, EventOverlayBundle, IMapClickListener, Marker, ImageEntity, MapEvent } from '@bdmap/map';
import { CoordTrans, LatLng, Point, NativeMethods } from '@bdmap/base';
import { NanjingTerritoryStore, TerritoryInfo, TerritoryPoint } from '../model/TerritoryModel';
import { DebugLoopRecord, DebugLoopStore } from '../model/DebugLoopModel';
import { PlaceableItemType, PlacedItemRecord, TerritoryItemCatalog, TerritoryItemStore, TerritoryItemDefaults } from '../model/TerritoryItemModel';
import { LoopAdCatalog, LoopAdPreset } from '../model/LoopAdModel';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { LoopDetector } from '../utils/LoopDetector';
import { PolygonClipper } from '../utils/PolygonClipper';
import { TerritoryExportBundle, TerritoryExportStore } from '../model/TerritoryExportModel';
import { TerritoryFileIO } from '../utils/TerritoryFileIO';
import { LoopAdComposer } from '../utils/LoopAdComposer';
import { MapAgentBridge } from '../agent/MapAgentBridge';
import {
  AgentLoopSummary,
  AgentMapContext,
  AgentPoiPoint,
  AgentResourcePoint,
  AgentRoutePoint,
  AgentTrapPoint
} from '../agent/MapAgentModels';
import { BackendConfig } from '../config/BackendConfig';
import { BackendApiService, BackendTrackPoint } from '../service/BackendApiService';
import { AuthSessionStore } from '../model/AuthSessionModel';

const BUNDLED_TERRITORY_RAWFILE: string = 'mydomai-territory-20260731-130832.mydomai.json';
const BUNDLED_TERRITORY_FLAG: string = 'appended_rawfile_20260731_130832';

interface TrackRestartLog {
  lat: number;
  lng: number;
  trackPoints: number;
}

interface LoopGeneratedLog {
  pendingCount: number;
  savedCount: number;
  newLoopId: number;
  trackPoints: number;
}

interface LoopsSavedLog {
  savedCount: number;
  totalSaved: number;
}

interface CompleteTerritoryLog {
  savedCount: number;
  totalLoops: number;
  verticesBefore: number;
  verticesAfter: number;
  mergeMs: number;
  saveMs: number;
  overlayMs: number;
  totalMs: number;
}

interface MapTapLog {
  x: number;
  y: number;
  lat: number;
  lng: number;
  loopCount: number;
  hit: number;
}

interface PendingDeletedLoop {
  ownerId: string;
  loopId: number;
}

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'MyDomaiLoop';

const DEFAULT_LATITUDE: number = 31.986741;
const DEFAULT_LONGITUDE: number = 118.772483;
const LOCATION_ZOOM: number = 16;
const JOYSTICK_SIZE: number = 48;
const JOYSTICK_RADIUS: number = 22;
const JOYSTICK_KNOB_SIZE: number = 14;
const JOYSTICK_RIGHT_INSET: number = 12;
const JOYSTICK_BOTTOM_INSET: number = 88;
const JOYSTICK_MOVE_INTERVAL_MS: number = 150;
const DEBUG_PANEL_WIDTH: number = 292;
const DEBUG_PANEL_MAX_HEIGHT: number = 420;
/** 调试面板半透明色（HarmonyOS 为 #AARRGGBB，勿写成 CSS 的 #RRGGBBAA） */
const DEBUG_GLASS: string = '#55FFFFFF';
const DEBUG_GLASS_SOFT: string = '#66F4F7F4';
const DEBUG_GLASS_NEUTRAL: string = '#66F3F5F3';
const DEBUG_GLASS_GREEN_SOFT: string = '#66EEF5F0';
const DEBUG_GLASS_GREEN: string = '#9937B75B';
const DEBUG_GLASS_BLUE: string = '#993B82F6';
const DEBUG_GLASS_BLUE_SOFT: string = '#66EEF5FF';
const DEBUG_GLASS_ORANGE: string = '#99F59E0B';
const DEBUG_GLASS_RED_SOFT: string = '#66FEE2E2';
const DEBUG_GLASS_TEAL_SOFT: string = '#66ECFDF5';
const DEBUG_GLASS_GRAY: string = '#9964748B';
const DEBUG_GLASS_TOOL: string = '#66FFFFFF';
const DEBUG_PANEL_BG: string = '#22FFFFFF';
const DEBUG_PANEL_BORDER: string = '#66FFFFFF';
const DEBUG_JOYSTICK_KNOB: string = '#CC8BC9A0';
const TOP_TOOLBAR_INSET: number = 96;
const MAP_TOOLBAR_TOP_INSET: number = 72;
const LOOP_DOUBLE_TAP_WINDOW_MS: number = 320;
const LOOP_DOUBLE_TAP_MAX_DISTANCE: number = 40;
const LOOP_TAP_DEDUPE_MS: number = 80;
const DEBUG_USER_A_COLOR: string = '#2DB55B';
const DEBUG_USER_B_COLOR: string = '#3B82F6';
const DEFAULT_DEBUG_DIAMONDS: number = 100;
const MAX_TRACK_OVERLAY_POINTS: number = 400;
const TRACK_OVERLAY_UPDATE_MS: number = 350;
const MAX_TRACK_POINTS: number = 3000;
const MAX_RANDOM_WORLD_RESOURCES: number = 80;
const ITEM_ICON_WIDTH_VP: number = 99;
const ITEM_ICON_HEIGHT_VP: number = 27;
const ITEM_ICON_CACHE_VERSION: string = 'v6-scale225';
const LOOP_AD_ICON_WIDTH_VP: number = 132;
const LOOP_AD_ICON_HEIGHT_VP: number = 108;
const LOOP_AD_ICON_CACHE_VERSION: string = 'v4-marker-photo';
/** 广告相对闭环包围盒的最大占比（宽/高取更紧的一侧） */
const LOOP_AD_MAX_LOOP_RATIO: number = 0.25;
const LOOP_AD_MIN_SCALE: number = 0.2;
const LOOP_AD_MAX_SCALE: number = 10;
const AGENT_ROUTE_STROKE: string = '#60A5FA';
const AGENT_ROUTE_FILL: string = '#93C5FD33';

@Component
export struct BaiduMapView {
  @Prop focusTerritoryId: number = -1;
  /** 与「我的」登录会话同步：谁登录就相当于调试选中谁 */
  @Prop @Watch('onSessionUserChanged') sessionUserId: string = '';
  @Prop sessionDisplayName: string = '';
  @Prop sessionDiamonds: number = DEFAULT_DEBUG_DIAMONDS;
  private mapController: MapController | null = null;
  private mapOptions: MapOptions = new MapOptions({
      mapStatus: new MapStatus({
        center: new LatLng(DEFAULT_LATITUDE, DEFAULT_LONGITUDE),
        zoom: 14
      })
  });

  @State private locationReady: boolean = false;
  @State private locationMessage: string = '正在获取当前位置';
  @State private debugMode: boolean = false;
  /** 调试面板相对默认位置的拖动偏移 */
  @State private debugPanelOffsetX: number = 0;
  @State private debugPanelOffsetY: number = 0;
  private debugPanelDragBaseX: number = 0;
  private debugPanelDragBaseY: number = 0;
  @State private showMapPlaceLabels: boolean = false;
  @State private debugSpeed: number = 8;
  @State private debugSpeedText: string = '8';
  @State private debugDirection: number = 0;
  @State private debugDistance: number = 0;
  @State private debugMessage: string = '推动摇杆即可移动，或点击“生成闭环”快速测试';
  @State private joystickKnobX: number = 0;
  @State private joystickKnobY: number = 0;
  @State private joystickActive: boolean = false;
  @State private savedLoops: Array<DebugLoopRecord> = [];
  @State private pendingLoops: Array<DebugLoopRecord> = [];
  @State private selectedLoopId: number = -1;
  @State private draftLoopName: string = '新领地';
  @State private draftStrokeColor: string = '#2DB55B';
  @State private draftFillColor: string = '#2DB55B80';
  @State private draftColorText: string = '#2DB55B';
  @State private draftFillColorText: string = '#2DB55B80';
  @State private draftStrokeWidth: number = 1;
  @State private draftStrokeWidthText: string = '1';
  @State private draftAdEnabled: boolean = false;
  @State private draftAdPresetId: string = '';
  @State private draftAdTitle: string = '';
  @State private draftAdImageUri: string = '';
  @State private adBadgeEmoji: string = '';
  @State private adBadgeBrand: string = '';
  @State private adBadgeSlogan: string = '';
  @State private adBadgeBg: string = '#111111';
  @State private adBadgeFg: string = '#FFFFFF';
  @State private adPreviewUri: string = '';
  @State private adPreviewSlogan: string = '';
  @State private showPlacementDialog: boolean = false;
  @State private showLoopEditDialog: boolean = false;
  @State private showTrapSetupDialog: boolean = false;
  @State private showTrapDialog: boolean = false;
  @State private showLoopInfoDialog: boolean = false;
  @State private loopInfoName: string = '';
  @State private loopInfoOwnerLabel: string = '';
  @State private loopInfoOwnerColor: string = '#2DB55B';
  @State private loopInfoStatusLabel: string = '';
  @State private loopInfoCreatedText: string = '—';
  @State private loopInfoCompletedText: string = '—';
  @State private loopInfoAreaText: string = '—';
  @State private loopInfoPerimeterText: string = '—';
  @State private loopInfoDurationText: string = '—';
  @State private loopInfoPaceText: string = '—';
  @State private loopInfoSpeedText: string = '—';
  @State private currentDebugUserId: string = '';
  @State private userADiamonds: number = DEFAULT_DEBUG_DIAMONDS;
  @State private userBDiamonds: number = DEFAULT_DEBUG_DIAMONDS;
  @State private trapSetupCostText: string = `${TerritoryItemDefaults.TRAP_DIAMOND_COST}`;
  @State private trappedTrapCost: number = 0;
  @State private trappedTrapOwnerLabel: string = '';
  @State private trappedTrapOwnerId: string = '';
  @State private placementLoopName: string = '';
  @State private placementLoopId: number = -1;
  @State private placementLat: number = 0;
  @State private placementLng: number = 0;
  @State private placedItems: Array<PlacedItemRecord> = [];
  @State private resourceRadiusKmText: string = '1.5';
  @State private resourceDensityText: string = '8';
  @State private itemBadgeText: string = '';
  @State private itemBadgeColor: string = '#2DB55B';
  private placeableItems: Array<PlaceableItemType> = TerritoryItemCatalog.getAll();
  private resourceRandSeed: number = Date.now() % 100000;
  private placedItemCircles: Array<Circle> = [];
  private placedItemLabels: Array<Label> = [];
  private placedItemMarkers: Array<Marker> = [];
  private itemIconCache: Map<string, image.PixelMap> = new Map();
  private loopAdIconCache: Map<string, image.PixelMap> = new Map();
  private loopAdMarkers: Map<number, Marker> = new Map();
  private loopAdPresets: Array<LoopAdPreset> = LoopAdCatalog.getPresets();
  private mapAdScaleListenerBound: boolean = false;
  private itemOverlayGeneration: number = 0;
  private nextPlacedItemId: number = 1;
  private trappedTrapItemId: number = -1;
  private triggeredTrapIds: Array<number> = [];
  private lastMapTapX: number = 0;
  private lastMapTapY: number = 0;
  private pendingSingleTapTimer: number = -1;
  private loopTapCandidateTimeMs: number = 0;
  private loopTapCandidateX: number = 0;
  private loopTapCandidateY: number = 0;
  private loopTapDeliveryTimeMs: number = 0;
  private loopTapDeliveryX: number = 0;
  private loopTapDeliveryY: number = 0;
  private pendingPlacementLoopId: number = -1;
  private pendingPlacementLoopName: string = '';
  private pendingPlacementLat: number = 0;
  private pendingPlacementLng: number = 0;
  private debugColorOptions: Array<string> = ['#2DB55B', '#3B82F6', '#F59E0B', '#EF5B5B', '#8B5CF6'];
  private currentLocation: LatLng | null = null;
  private debugLocation: LatLng | null = null;
  private lastDebugLocation: LatLng | null = null;
  private debugStart: LatLng | null = null;
  private activeTrackPoints: Array<LatLng> = [];
  private activeTrackOverlay: Polyline | null = null;
  private loopOverlayIds: Array<number> = [];
  private loopOverlayPolygons: Array<Polygon> = [];
  private loopOverlayPolylines: Array<Polyline> = [];
  private loopOverlayLabels: Array<Label> = [];
  private nextLoopId: number = 1;
  private territoryOverlays: Array<Polygon> = [];
  private debugTimer: number = -1;
  private joystickSpeedFactor: number = 0;
  @State private joystickCapturing: boolean = false;
  /** 手指按在调试面板上时禁用地图拖拽；面板外保持可拖 */
  private panelTouchCapturing: boolean = false;
  private debugApplyTick: number = 0;
  private debugFollowConfigured: boolean = false;
  private lastTrackOverlayUpdateMs: number = 0;
  private debugTrackStartedAtMs: number = 0;
  private remoteTrackSessionId: number = -1;
  private remoteTrackPendingPoints: Array<BackendTrackPoint> = [];
  private remoteSyncInFlight: boolean = false;
  private remoteSyncQueued: boolean = false;
  /** 排队等待上传的显式删除（ownerId + clientLoopId） */
  private pendingDeletedLoops: Array<PendingDeletedLoop> = [];
  private queuedSyncOwnerIds: Array<string> = [];
  private territoryPullInFlight: boolean = false;
  private lastTerritoryPullOk: boolean = false;
  private lastTerritoryPushOk: boolean = false;
  private backendConnectGeneration: number = 0;
  @State private backendStatusText: string = '后端: 未连接';

  private applyGestureLockState(): void {
    if (this.joystickCapturing || this.panelTouchCapturing) {
      this.mapOptions.moveGesturesEnabled = false;
      this.mapOptions.zoomGesturesEnabled = true;
      this.mapOptions.rotateGesturesEnabled = true;
      this.mapOptions.overlookingGesturesEnabled = true;
      this.mapOptions.updateGestureEnable();
      this.mapController?.disableGesturesDrag();
      this.mapController?.enableGesturesZoom();
      // #region agent log
      hilog.info(LOG_DOMAIN, LOG_TAG,
        '[DBG8add10] gesture lock on panel=%{public}d joystick=%{public}d',
        this.panelTouchCapturing ? 1 : 0, this.joystickCapturing ? 1 : 0);
      // #endregion
    } else {
      this.restoreMapGestures();
      // #region agent log
      hilog.info(LOG_DOMAIN, LOG_TAG, '[DBG8add10] gesture lock off');
      // #endregion
    }
  }

  private beginPanelTouchCapture(): void {
    if (this.panelTouchCapturing) {
      return;
    }
    this.panelTouchCapturing = true;
    this.applyGestureLockState();
  }

  private endPanelTouchCapture(): void {
    if (!this.panelTouchCapturing) {
      return;
    }
    this.panelTouchCapturing = false;
    this.applyGestureLockState();
  }

  private onDebugPanelTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      this.beginPanelTouchCapture();
      // #region agent log
      hilog.info(LOG_DOMAIN, LOG_TAG, '[DBG8add10] panel Down');
      // #endregion
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.endPanelTouchCapture();
      // #region agent log
      hilog.info(LOG_DOMAIN, LOG_TAG, '[DBG8add10] panel Up/Cancel type=%{public}d', event.type);
      // #endregion
    }
  }

  private onDebugPanelPanStart(): void {
    this.debugPanelDragBaseX = this.debugPanelOffsetX;
    this.debugPanelDragBaseY = this.debugPanelOffsetY;
    this.beginPanelTouchCapture();
    // #region agent log
    hilog.info(LOG_DOMAIN, LOG_TAG, '[DBG8add10] panel drag start x=%{public}d y=%{public}d',
      Math.round(this.debugPanelOffsetX), Math.round(this.debugPanelOffsetY));
    // #endregion
  }

  private onDebugPanelPanUpdate(offsetX: number, offsetY: number): void {
    this.debugPanelOffsetX = this.debugPanelDragBaseX + offsetX;
    this.debugPanelOffsetY = this.debugPanelDragBaseY + offsetY;
  }

  private onDebugPanelPanEnd(): void {
    this.endPanelTouchCapture();
    // #region agent log
    hilog.info(LOG_DOMAIN, LOG_TAG, '[DBG8add10] panel drag end x=%{public}d y=%{public}d',
      Math.round(this.debugPanelOffsetX), Math.round(this.debugPanelOffsetY));
    // #endregion
  }

  private restoreMapGestures(): void {
    this.mapOptions.moveGesturesEnabled = true;
    this.mapOptions.zoomGesturesEnabled = true;
    this.mapOptions.rotateGesturesEnabled = true;
    this.mapOptions.overlookingGesturesEnabled = true;
    this.mapOptions.updateGestureEnable();
    if (this.mapController) {
      this.mapController.enableGesturesDrag();
      this.mapController.enableGesturesZoom();
      this.mapController.enableGesturesRotate();
      this.mapController.enableGesturesPich();
    }
  }

  aboutToAppear(): void {
    this.applyMapPlaceLabelVisibility();
    this.requestCurrentLocation();
    MapAgentBridge.register(
      (): AgentMapContext | null => this.buildAgentMapContext(),
      (routeName: string, points: Array<AgentRoutePoint>, reply: string): boolean =>
        this.applyAgentSuggestedRoute(routeName, points, reply),
      (reply: string): Promise<boolean> => this.applyDefaultTerritoryAsAgentRoute(reply)
    );
    void this.bootstrapMapData();
  }

  onSessionUserChanged(): void {
    void this.applySessionIdentity(true);
  }

  private async bootstrapMapData(): Promise<void> {
    await this.restoreDebugTerritory();
    await this.restorePlacedItems();
    await this.restoreDebugDiamonds();
    await this.preloadDefaultTerritoryCache();
    await this.applySessionIdentity(true);
  }

  /** 用「我的」登录身份驱动当前调试用户 */
  private async applySessionIdentity(pullBackend: boolean): Promise<void> {
    const userId = this.sessionUserId;
    if (userId.length === 0) {
      this.currentDebugUserId = '';
      this.debugMessage = '请先在「我的」登录后再圈地 / 同步';
      this.backendStatusText = '未登录';
      return;
    }
    const changed = this.currentDebugUserId !== userId;
    this.currentDebugUserId = userId;
    this.setUserDiamonds(userId, this.sessionDiamonds);
    if (userId === 'user_b') {
      this.draftStrokeColor = DEBUG_USER_B_COLOR;
      this.draftColorText = DEBUG_USER_B_COLOR;
      this.draftFillColor = DebugLoopStore.toFillColor(DEBUG_USER_B_COLOR);
      this.draftFillColorText = this.draftFillColor;
    } else {
      this.draftStrokeColor = DEBUG_USER_A_COLOR;
      this.draftColorText = DEBUG_USER_A_COLOR;
      this.draftFillColor = DebugLoopStore.toFillColor(DEBUG_USER_A_COLOR);
      this.draftFillColorText = this.draftFillColor;
    }
    const label = this.sessionDisplayName.length > 0 ? this.sessionDisplayName : DebugLoopStore.ownerLabel(userId);
    this.debugMessage = `当前用户：${label} · 钻石 ${this.getCurrentUserDiamonds()}`;
    if (pullBackend && (changed || AuthSessionStore.isLoggedIn())) {
      if (changed) {
        this.triggeredTrapIds = [];
      }
      await this.connectBackendAndSync(false);
    }
  }

  private async refreshTerritoryFromBackend(): Promise<void> {
    if (!BackendConfig.ENABLED) {
      this.backendStatusText = '后端: 已关闭';
      return;
    }
    if (this.territoryPullInFlight) {
      return;
    }
    this.territoryPullInFlight = true;
    this.backendStatusText = '后端: 刷新中…';
    try {
      const online = await BackendApiService.health();
      if (!online) {
        this.backendStatusText = `后端: 离线 ${BackendConfig.BASE_URL}`;
        return;
      }
      // 刷新=以后端为准：等待进行中的上传结束后，只拉取并覆盖当前用户本地数据（禁止先 PUT）
      await this.waitForTerritorySyncIdle();
      const ok = await this.pullTerritoryFromBackend(true);
      if (ok) {
        try {
          this.fitMapToCurrentUserLoops();
        } catch (mapError) {
          hilog.warn(LOG_DOMAIN, LOG_TAG, 'fitMapToCurrentUserLoops failed %{public}s', JSON.stringify(mapError));
        }
        const count = this.countLoopsForUser(this.currentDebugUserId);
        this.backendStatusText = `后端: 已拉取 ${count} 块领地`;
      } else {
        this.backendStatusText = `后端: 拉取失败，请确认 ${BackendConfig.BASE_URL} 可访问`;
      }
    } catch (error) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'refreshTerritoryFromBackend failed %{public}s', JSON.stringify(error));
      this.backendStatusText = '后端: 拉取异常';
    } finally {
      this.territoryPullInFlight = false;
    }
  }

  /** @param pushAfterPull 切换用户时仅拉取后端数据，避免多余上传与并发竞态 */
  private async connectBackendAndSync(pushAfterPull: boolean): Promise<void> {
    const generation = ++this.backendConnectGeneration;
    if (!BackendConfig.ENABLED) {
      this.backendStatusText = '后端: 已关闭';
      return;
    }
    const userId = this.currentDebugUserId;
    if (userId.length === 0) {
      this.backendStatusText = '未登录';
      return;
    }
    this.backendStatusText = `后端: 连接中 ${BackendConfig.BASE_URL}`;
    const ok = await BackendApiService.health();
    if (generation !== this.backendConnectGeneration) {
      return;
    }
    if (!ok) {
      this.backendStatusText = `后端: 离线 ${BackendConfig.BASE_URL}`;
      return;
    }
    this.backendStatusText = '后端: 已连接';
    // 已登录用户由 auth 创建，无需再 upsert；仅兼容旧本地身份
    if (!AuthSessionStore.isLoggedIn()) {
      const displayName = this.sessionDisplayName.length > 0
        ? this.sessionDisplayName
        : DebugLoopStore.ownerLabel(userId);
      await BackendApiService.upsertUser(userId, displayName, this.getCurrentUserDiamonds());
      if (generation !== this.backendConnectGeneration) {
        return;
      }
    }
    const pulled = await this.pullTerritoryFromBackend();
    if (generation !== this.backendConnectGeneration) {
      return;
    }
    if (!pushAfterPull) {
      this.backendStatusText = pulled ? '后端: 已拉取最新领地' : '后端: 拉取失败';
      return;
    }
    const pushed = await this.syncTerritoryToBackend(false, generation, true);
    if (generation !== this.backendConnectGeneration) {
      return;
    }
    if (pulled && pushed) {
      this.backendStatusText = '后端: 已拉取并同步';
    } else if (pulled) {
      this.backendStatusText = '后端: 已拉取最新领地（上传失败）';
    } else if (pushed) {
      this.backendStatusText = '后端: 已同步';
    } else {
      this.backendStatusText = '后端: 同步失败';
    }
  }

  private async pullTerritoryFromBackend(replaceUserData: boolean = false): Promise<boolean> {
    try {
      const bundle = await BackendApiService.fetchTerritory(this.currentDebugUserId);
      if (bundle === null) {
        this.lastTerritoryPullOk = false;
        return false;
      }
      if (replaceUserData) {
        this.replaceUserTerritoryFromRemote(bundle, this.currentDebugUserId);
      } else {
        this.mergeRemoteTerritory(bundle, this.currentDebugUserId);
      }
      await this.persistTerritoryLocally();
      this.refreshAllLoopOverlays();
      this.refreshAllPlacedItemOverlays();
      this.lastTerritoryPullOk = true;
      return true;
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, 'pullTerritoryFromBackend failed %{public}s', JSON.stringify(error));
      this.lastTerritoryPullOk = false;
      return false;
    }
  }

  /** 手动刷新：用后端快照覆盖当前用户本地领地，避免 merge 残留旧数据 */
  private replaceUserTerritoryFromRemote(bundle: TerritoryExportBundle, userId: string): void {
    const keepSaved: Array<DebugLoopRecord> = [];
    for (let i = 0; i < this.savedLoops.length; i++) {
      if (this.resolveLoopOwnerId(this.savedLoops[i]) !== userId) {
        keepSaved.push(this.savedLoops[i]);
      }
    }
    const keepPending: Array<DebugLoopRecord> = [];
    for (let i = 0; i < this.pendingLoops.length; i++) {
      if (this.resolveLoopOwnerId(this.pendingLoops[i]) !== userId) {
        keepPending.push(this.pendingLoops[i]);
      }
    }
    const keepItems: Array<PlacedItemRecord> = [];
    for (let i = 0; i < this.placedItems.length; i++) {
      const owner = this.placedItems[i].ownerId !== undefined && this.placedItems[i].ownerId!.length > 0
        ? this.placedItems[i].ownerId! : userId;
      if (owner !== userId) {
        keepItems.push(this.placedItems[i]);
      }
    }
    const remoteSaved: Array<DebugLoopRecord> = [];
    for (let i = 0; i < bundle.savedLoops.length; i++) {
      remoteSaved.push(LoopDetector.compactLoopRecord(DebugLoopStore.ensureOwner(bundle.savedLoops[i])));
    }
    const remotePending: Array<DebugLoopRecord> = [];
    for (let i = 0; i < bundle.pendingLoops.length; i++) {
      remotePending.push(LoopDetector.compactLoopRecord(DebugLoopStore.ensureOwner(bundle.pendingLoops[i])));
    }
    this.savedLoops = keepSaved.concat(remoteSaved);
    this.pendingLoops = keepPending.concat(remotePending);
    this.placedItems = keepItems.concat(bundle.placedItems);
    if (bundle.nextLoopId > this.nextLoopId) {
      this.nextLoopId = bundle.nextLoopId;
    }
    if (bundle.nextPlacedItemId > this.nextPlacedItemId) {
      this.nextPlacedItemId = bundle.nextPlacedItemId;
    }
    this.applyRemoteDiamonds(bundle, userId);
    const userLoopCount = this.countLoopsForUser(userId);
    this.debugMessage = `已从后端覆盖 ${DebugLoopStore.ownerLabel(userId)} 的 ${userLoopCount} 块领地`;
  }

  private mergeRemoteTerritory(bundle: TerritoryExportBundle, userId: string): void {
    this.savedLoops = this.mergeLoopListsForUser(this.savedLoops, bundle.savedLoops, userId);
    this.pendingLoops = this.mergeLoopListsForUser(this.pendingLoops, bundle.pendingLoops, userId);
    this.placedItems = this.mergePlacedItemsForUser(this.placedItems, bundle.placedItems, userId);
    if (bundle.nextLoopId > this.nextLoopId) {
      this.nextLoopId = bundle.nextLoopId;
    }
    if (bundle.nextPlacedItemId > this.nextPlacedItemId) {
      this.nextPlacedItemId = bundle.nextPlacedItemId;
    }
    this.applyRemoteDiamonds(bundle, userId);
    const userLoopCount = this.countLoopsForUser(userId);
    this.debugMessage = `已从后端同步 ${DebugLoopStore.ownerLabel(userId)} 的 ${userLoopCount} 块领地`;
  }

  private applyRemoteDiamonds(bundle: TerritoryExportBundle, userId: string): void {
    let diamonds = -1;
    if (bundle.diamonds !== undefined) {
      diamonds = bundle.diamonds;
    } else if (userId === 'user_b' && bundle.userBDiamonds !== undefined) {
      diamonds = bundle.userBDiamonds;
    } else if (bundle.userADiamonds !== undefined) {
      diamonds = bundle.userADiamonds;
    }
    if (diamonds >= 0) {
      this.setUserDiamonds(userId, diamonds);
      AuthSessionStore.updateDiamonds(diamonds);
    }
  }

  private countLoopsForUser(userId: string): number {
    let count = 0;
    const loops = this.getAllDisplayLoops();
    for (let i = 0; i < loops.length; i++) {
      if (this.resolveLoopOwnerId(loops[i]) === userId) {
        count++;
      }
    }
    return count;
  }

  private mergeLoopListsForUser(
    localLoops: Array<DebugLoopRecord>,
    remoteLoops: Array<DebugLoopRecord>,
    userId: string
  ): Array<DebugLoopRecord> {
    const remoteById: Map<number, DebugLoopRecord> = new Map();
    for (let i = 0; i < remoteLoops.length; i++) {
      const remote = LoopDetector.compactLoopRecord(DebugLoopStore.ensureOwner(remoteLoops[i]));
      if (this.resolveLoopOwnerId(remote) === userId) {
        remoteById.set(remote.id, remote);
      }
    }
    const merged: Array<DebugLoopRecord> = [];
    const seenIds: Set<number> = new Set();
    for (let i = 0; i < localLoops.length; i++) {
      const local = localLoops[i];
      if (this.resolveLoopOwnerId(local) !== userId) {
        merged.push(local);
        continue;
      }
      const remote = remoteById.get(local.id);
      if (remote !== undefined) {
        merged.push(remote);
        seenIds.add(local.id);
      } else {
        merged.push(local);
        seenIds.add(local.id);
      }
    }
    remoteById.forEach((remote: DebugLoopRecord, id: number) => {
      if (!seenIds.has(id)) {
        merged.push(remote);
      }
    });
    return merged;
  }

  private mergePlacedItemsForUser(
    localItems: Array<PlacedItemRecord>,
    remoteItems: Array<PlacedItemRecord>,
    userId: string
  ): Array<PlacedItemRecord> {
    const remoteById: Map<number, PlacedItemRecord> = new Map();
    for (let i = 0; i < remoteItems.length; i++) {
      const item = remoteItems[i];
      const owner = item.ownerId !== undefined && item.ownerId.length > 0 ? item.ownerId : userId;
      if (owner === userId) {
        remoteById.set(item.id, item);
      }
    }
    const merged: Array<PlacedItemRecord> = [];
    const seenIds: Set<number> = new Set();
    for (let i = 0; i < localItems.length; i++) {
      const local = localItems[i];
      const owner = local.ownerId !== undefined && local.ownerId.length > 0 ? local.ownerId : userId;
      if (owner !== userId) {
        merged.push(local);
        continue;
      }
      const remote = remoteById.get(local.id);
      if (remote !== undefined) {
        merged.push(remote);
        seenIds.add(local.id);
      } else {
        merged.push(local);
        seenIds.add(local.id);
      }
    }
    remoteById.forEach((remote: PlacedItemRecord, id: number) => {
      if (!seenIds.has(id)) {
        merged.push(remote);
      }
    });
    return merged;
  }

  private async persistTerritoryLocally(): Promise<void> {
    try {
      const compactLoops: Array<DebugLoopRecord> = [];
      for (let i = 0; i < this.savedLoops.length; i++) {
        compactLoops.push(LoopDetector.compactLoopRecord(this.savedLoops[i]));
      }
      this.savedLoops = compactLoops;
      const serialized = DebugLoopStore.serializeLoops(compactLoops);
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const store = await preferences.getPreferences(context, { name: 'debug_territory' });
      await store.put('loops', serialized);
      await store.put('nextLoopId', this.nextLoopId);
      await store.put('userADiamonds', this.userADiamonds);
      await store.put('userBDiamonds', this.userBDiamonds);
      await store.put('placedItems', TerritoryItemStore.serializeItems(this.placedItems));
      await store.put('nextPlacedItemId', this.nextPlacedItemId);
      await store.flush();
    } catch (error) {
      console.error(`Persist territory locally failed: ${JSON.stringify(error)}`);
    }
  }

  private async waitForTerritorySyncIdle(): Promise<void> {
    let spins = 0;
    while (this.remoteSyncInFlight && spins < 120) {
      await new Promise<void>((resolve: () => void) => {
        setTimeout(() => {
          resolve();
        }, 100);
      });
      spins++;
    }
  }

  private queueLoopDeletion(ownerId: string, loopId: number): void {
    for (let i = 0; i < this.pendingDeletedLoops.length; i++) {
      if (this.pendingDeletedLoops[i].ownerId === ownerId && this.pendingDeletedLoops[i].loopId === loopId) {
        return;
      }
    }
    const ref: PendingDeletedLoop = { ownerId: ownerId, loopId: loopId };
    this.pendingDeletedLoops.push(ref);
  }

  private takeDeletedLoopIdsForUser(userId: string): Array<number> {
    const ids: Array<number> = [];
    const remain: Array<PendingDeletedLoop> = [];
    for (let i = 0; i < this.pendingDeletedLoops.length; i++) {
      const item = this.pendingDeletedLoops[i];
      if (item.ownerId === userId) {
        ids.push(item.loopId);
      } else {
        remain.push(item);
      }
    }
    this.pendingDeletedLoops = remain;
    return ids;
  }

  private restoreDeletedLoopIds(userId: string, ids: Array<number>): void {
    for (let i = 0; i < ids.length; i++) {
      this.queueLoopDeletion(userId, ids[i]);
    }
  }

  private enqueueOwnerSync(userId: string): void {
    for (let i = 0; i < this.queuedSyncOwnerIds.length; i++) {
      if (this.queuedSyncOwnerIds[i] === userId) {
        return;
      }
    }
    this.queuedSyncOwnerIds.push(userId);
  }

  private async syncTerritoryToBackend(
    updateStatus: boolean = true,
    generation?: number,
    skipPull: boolean = false,
    targetUserId?: string
  ): Promise<boolean> {
    if (!BackendConfig.ENABLED) {
      return false;
    }
    const userId = targetUserId !== undefined && targetUserId.length > 0
      ? targetUserId
      : this.currentDebugUserId;
    if (this.remoteSyncInFlight) {
      this.remoteSyncQueued = true;
      this.enqueueOwnerSync(userId);
      return false;
    }
    this.remoteSyncInFlight = true;
    let ok = false;
    const deletedIds = this.takeDeletedLoopIdsForUser(userId);
    try {
      if (!skipPull && userId === this.currentDebugUserId) {
        const pulled = await this.pullTerritoryFromBackend();
        if (!pulled) {
          this.restoreDeletedLoopIds(userId, deletedIds);
          if (updateStatus && (generation === undefined || generation === this.backendConnectGeneration)) {
            this.backendStatusText = '后端: 拉取失败，未上传';
          }
          return false;
        }
      }
      // #region agent log
      hilog.info(LOG_DOMAIN, LOG_TAG,
        '[DBG8add10] push territory user=%{public}s deleted=%{public}d skipPull=%{public}d',
        userId, deletedIds.length, skipPull ? 1 : 0);
      // #endregion
      ok = await BackendApiService.syncTerritory(
        userId,
        this.savedLoops,
        this.pendingLoops,
        this.placedItems,
        this.nextLoopId,
        this.nextPlacedItemId,
        this.userADiamonds,
        this.userBDiamonds,
        deletedIds
      );
      if (!ok) {
        this.restoreDeletedLoopIds(userId, deletedIds);
      }
      this.lastTerritoryPushOk = ok;
      if (updateStatus && (generation === undefined || generation === this.backendConnectGeneration)) {
        this.backendStatusText = ok ? '后端: 已同步' : '后端: 上传失败';
      }
      return ok;
    } finally {
      this.remoteSyncInFlight = false;
      if (this.remoteSyncQueued || this.queuedSyncOwnerIds.length > 0) {
        this.remoteSyncQueued = false;
        const nextOwners: Array<string> = [];
        for (let i = 0; i < this.queuedSyncOwnerIds.length; i++) {
          nextOwners.push(this.queuedSyncOwnerIds[i]);
        }
        this.queuedSyncOwnerIds = [];
        if (nextOwners.length === 0) {
          void this.syncTerritoryToBackend(updateStatus, generation, true);
        } else {
          void this.pushTerritoriesForOwners(nextOwners, updateStatus, generation);
        }
      }
    }
  }

  /** 依次上传多个用户的领地（占领后需同步受害方） */
  private async pushTerritoriesForOwners(
    ownerIds: Array<string>,
    updateStatus: boolean = true,
    generation?: number
  ): Promise<void> {
    for (let i = 0; i < ownerIds.length; i++) {
      await this.syncTerritoryToBackend(updateStatus, generation, true, ownerIds[i]);
    }
  }

  private async startRemoteTrackSession(): Promise<void> {
    if (!BackendConfig.ENABLED) {
      return;
    }
    await this.finishRemoteTrackSession();
    this.remoteTrackPendingPoints = [];
    const sessionId = await BackendApiService.startTrackSession(this.currentDebugUserId);
    this.remoteTrackSessionId = sessionId;
  }

  private enqueueRemoteTrackPoint(point: LatLng): void {
    if (!BackendConfig.ENABLED || this.remoteTrackSessionId < 0) {
      return;
    }
    const p: BackendTrackPoint = { lat: point.lat, lng: point.lng, ts: Date.now() };
    this.remoteTrackPendingPoints.push(p);
    if (this.remoteTrackPendingPoints.length >= BackendConfig.TRACK_FLUSH_EVERY) {
      void this.flushRemoteTrackPoints();
    }
  }

  private async flushRemoteTrackPoints(): Promise<void> {
    if (this.remoteTrackSessionId < 0 || this.remoteTrackPendingPoints.length === 0) {
      return;
    }
    const batch: Array<BackendTrackPoint> = this.remoteTrackPendingPoints.slice();
    this.remoteTrackPendingPoints = [];
    await BackendApiService.appendTrackPoints(this.remoteTrackSessionId, batch, this.debugDistance);
  }

  private async finishRemoteTrackSession(): Promise<void> {
    if (this.remoteTrackSessionId < 0) {
      this.remoteTrackPendingPoints = [];
      return;
    }
    const batch: Array<BackendTrackPoint> = this.remoteTrackPendingPoints.slice();
    this.remoteTrackPendingPoints = [];
    const durationSeconds = Math.max(0, Math.round((Date.now() - this.debugTrackStartedAtMs) / 1000));
    const hours = durationSeconds > 0 ? durationSeconds / 3600.0 : 0;
    const avgSpeed = hours > 0 ? (this.debugDistance / 1000.0) / hours : 0;
    await BackendApiService.finishTrackSession(
      this.remoteTrackSessionId,
      batch,
      this.debugDistance,
      durationSeconds,
      avgSpeed
    );
    this.remoteTrackSessionId = -1;
  }

  aboutToDisappear(): void {
    MapAgentBridge.unregister();
    this.clearPendingLoopSingleTap();
    this.releaseJoystick();
    this.stopDebugTimer();
    void this.finishRemoteTrackSession();
    this.itemOverlayGeneration++;
    if (this.debugMode) {
      this.debugMode = false;
      this.applyGestureLockState();
    }
  }

  private buildAgentMapContext(): AgentMapContext {
    const center = this.getResourceCenter() ?? new LatLng(DEFAULT_LATITUDE, DEFAULT_LONGITUDE);
    const resources: Array<AgentResourcePoint> = [];
    const traps: Array<AgentTrapPoint> = [];
    let worldResourceCount = 0;
    let territoryItemCount = 0;
    for (let i = 0; i < this.placedItems.length; i++) {
      const item = this.placedItems[i];
      const type = TerritoryItemCatalog.getById(item.itemTypeId);
      const isWorld = item.loopId === TerritoryItemDefaults.WORLD_RESOURCE_LOOP_ID;
      const distance = this.distanceMetersBetween(center.lat, center.lng, item.lat, item.lng);
      if (item.itemTypeId === 'trap') {
        const trap: AgentTrapPoint = {
          id: item.id,
          lat: item.lat,
          lng: item.lng,
          ownerId: this.resolveTrapOwnerId(item),
          diamondCost: this.resolveTrapDiamondCost(item),
          distanceMeters: Math.round(distance),
          loopId: item.loopId
        };
        traps.push(trap);
        continue;
      }
      if (isWorld) {
        worldResourceCount++;
      } else {
        territoryItemCount++;
      }
      const point: AgentResourcePoint = {
        id: item.id,
        typeId: item.itemTypeId,
        name: type !== null ? type.name : item.itemTypeId,
        icon: type !== null ? type.icon : '📍',
        lat: item.lat,
        lng: item.lng,
        scope: isWorld ? 'world' : 'territory',
        loopId: item.loopId,
        distanceMeters: Math.round(distance)
      };
      resources.push(point);
    }
    resources.sort((a: AgentResourcePoint, b: AgentResourcePoint) => {
      return a.distanceMeters - b.distanceMeters;
    });
    traps.sort((a: AgentTrapPoint, b: AgentTrapPoint) => {
      return a.distanceMeters - b.distanceMeters;
    });
    const loops: Array<AgentLoopSummary> = [];
    const pois: Array<AgentPoiPoint> = [];
    const allLoops = this.getAllDisplayLoops();
    for (let i = 0; i < allLoops.length; i++) {
      const loop = allLoops[i];
      const centroid = this.loopCentroid(loop);
      const ownerId = this.resolveLoopOwnerId(loop);
      const summary: AgentLoopSummary = {
        id: loop.id,
        name: loop.name,
        ownerId: ownerId,
        pointCount: loop.latitudes.length,
        centerLat: centroid.lat,
        centerLng: centroid.lng
      };
      loops.push(summary);
      const poi: AgentPoiPoint = {
        id: `loop_${loop.id}`,
        name: loop.name.length > 0 ? loop.name : `闭环${loop.id}`,
        kind: 'loop',
        lat: centroid.lat,
        lng: centroid.lng,
        distanceMeters: Math.round(this.distanceMetersBetween(center.lat, center.lng, centroid.lat, centroid.lng))
      };
      pois.push(poi);
    }
    // 安德门地标，供模型理解周边 POI
    const landmark: AgentPoiPoint = {
      id: 'landmark_andemen',
      name: '安德门地铁站',
      kind: 'landmark',
      lat: DEFAULT_LATITUDE,
      lng: DEFAULT_LONGITUDE,
      distanceMeters: Math.round(
        this.distanceMetersBetween(center.lat, center.lng, DEFAULT_LATITUDE, DEFAULT_LONGITUDE))
    };
    pois.push(landmark);
    pois.sort((a: AgentPoiPoint, b: AgentPoiPoint) => {
      return a.distanceMeters - b.distanceMeters;
    });
    // clusters filled by MapAgentService.enrichContext
    const context: AgentMapContext = {
      userLat: center.lat,
      userLng: center.lng,
      resources: resources,
      traps: traps,
      pois: pois,
      clusters: [],
      loops: loops,
      worldResourceCount: worldResourceCount,
      territoryItemCount: territoryItemCount,
      trapCount: traps.length,
      poiCount: pois.length,
      roadPromptText: '',
      roadCount: 0
    };
    hilog.info(LOG_DOMAIN, LOG_TAG,
      '[Agent] context built resources=%{public}d traps=%{public}d pois=%{public}d world=%{public}d territory=%{public}d @%{public}s,%{public}s',
      resources.length, traps.length, pois.length, worldResourceCount, territoryItemCount,
      `${center.lat}`, `${center.lng}`);
    return context;
  }

  private distanceMetersBetween(lat1: number, lng1: number, lat2: number, lng2: number): number {
    const toRad = Math.PI / 180;
    const dLat = (lat2 - lat1) * toRad;
    const dLng = (lng2 - lng1) * toRad;
    const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
      Math.cos(lat1 * toRad) * Math.cos(lat2 * toRad) * Math.sin(dLng / 2) * Math.sin(dLng / 2);
    return 6371000 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  }

  private defaultTerritoryName: string = '可探索区域';
  private defaultTerritoryPoints: Array<AgentRoutePoint> = [];
  private defaultTerritoryLoaded: boolean = false;

  private async preloadDefaultTerritoryCache(): Promise<void> {
    if (this.defaultTerritoryLoaded) {
      return;
    }
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const raw = await context.resourceManager.getRawFileContent(BUNDLED_TERRITORY_RAWFILE);
      const decoder = util.TextDecoder.create('utf-8');
      const json = decoder.decodeToString(new Uint8Array(raw.buffer));
      const parsed = TerritoryExportStore.parse(json);
      if (parsed === null) {
        return;
      }
      const normalized = TerritoryExportStore.normalize(parsed);
      if (normalized === null || normalized.savedLoops.length === 0) {
        return;
      }
      const loop = LoopDetector.compactLoopRecord(normalized.savedLoops[0]);
      const points: Array<AgentRoutePoint> = [];
      for (let i = 0; i < loop.latitudes.length; i++) {
        const point: AgentRoutePoint = { lat: loop.latitudes[i], lng: loop.longitudes[i] };
        points.push(point);
      }
      this.defaultTerritoryName = loop.name.length > 0 ? loop.name : '可探索区域';
      this.defaultTerritoryPoints = points;
      this.defaultTerritoryLoaded = points.length >= 4;
      hilog.info(LOG_DOMAIN, LOG_TAG, '[Agent] default territory cached name=%{public}s points=%{public}d',
        this.defaultTerritoryName, points.length);
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, '[Agent] preload default territory failed %{public}s',
        JSON.stringify(error));
    }
  }

  /** Agent 询问结束后默认展示内置领地 JSON（不清除已有其他路径） */
  private async applyDefaultTerritoryAsAgentRoute(reply: string): Promise<boolean> {
    if (!this.defaultTerritoryLoaded) {
      await this.preloadDefaultTerritoryCache();
    }
    if (!this.defaultTerritoryLoaded || this.defaultTerritoryPoints.length < 4) {
      this.debugMessage = '默认领地 JSON 未就绪';
      return false;
    }
    // 若已有同名 Agent 默认区域，先移除再画，避免重复叠层
    this.removeLoopsByName(this.defaultTerritoryName);
    const text = reply.trim().length > 0 ? reply : `已为你标出默认可探索区域「${this.defaultTerritoryName}」`;
    return this.applyAgentSuggestedRoute(this.defaultTerritoryName, this.defaultTerritoryPoints, text);
  }

  private removeLoopsByName(name: string): void {
    const nextSaved: Array<DebugLoopRecord> = [];
    for (let i = 0; i < this.savedLoops.length; i++) {
      if (this.savedLoops[i].name !== name) {
        nextSaved.push(this.savedLoops[i]);
      } else {
        this.removeLoopOverlay(this.savedLoops[i].id);
      }
    }
    const nextPending: Array<DebugLoopRecord> = [];
    for (let i = 0; i < this.pendingLoops.length; i++) {
      if (this.pendingLoops[i].name !== name) {
        nextPending.push(this.pendingLoops[i]);
      } else {
        this.removeLoopOverlay(this.pendingLoops[i].id);
      }
    }
    this.savedLoops = nextSaved;
    this.pendingLoops = nextPending;
  }

  private applyAgentSuggestedRoute(routeName: string, points: Array<AgentRoutePoint>, reply: string): boolean {
    if (points.length < 4) {
      return false;
    }
    const latitudes: Array<number> = [];
    const longitudes: Array<number> = [];
    const latLngPoints: Array<LatLng> = [];
    for (let i = 0; i < points.length; i++) {
      const lat = points[i].lat;
      const lng = points[i].lng;
      if (!this.isValidCoordinate(lat, lng)) {
        continue;
      }
      latitudes.push(lat);
      longitudes.push(lng);
      latLngPoints.push(new LatLng(lat, lng));
    }
    if (latitudes.length < 4) {
      return false;
    }
    const firstLat = latitudes[0];
    const firstLng = longitudes[0];
    const lastLat = latitudes[latitudes.length - 1];
    const lastLng = longitudes[longitudes.length - 1];
    if (Math.abs(firstLat - lastLat) > 1e-7 || Math.abs(firstLng - lastLng) > 1e-7) {
      latitudes.push(firstLat);
      longitudes.push(firstLng);
      latLngPoints.push(new LatLng(firstLat, firstLng));
    }
    const name = routeName.trim().length > 0 ? routeName.trim() : 'Agent推荐路线';
    const perimeter = LoopDetector.calculatePerimeter(latLngPoints);
    const newLoop: DebugLoopRecord = LoopDetector.compactLoopRecord({
      id: this.nextLoopId++,
      name: name,
      ownerId: this.currentDebugUserId,
      strokeColor: AGENT_ROUTE_STROKE,
      fillColor: AGENT_ROUTE_FILL,
      strokeWidth: 1,
      distance: perimeter,
      latitudes: latitudes,
      longitudes: longitudes,
      createdAt: Date.now()
    });
    const nextPending: Array<DebugLoopRecord> = [];
    for (let i = 0; i < this.pendingLoops.length; i++) {
      nextPending.push(this.pendingLoops[i]);
    }
    nextPending.push(newLoop);
    this.pendingLoops = nextPending;
    this.selectedLoopId = newLoop.id;
    this.refreshAllLoopOverlays();
    const centroid = this.loopCentroid(newLoop);
    if (this.mapController !== null) {
      this.mapController.setMapCenter(centroid, 16, false);
    }
    this.debugMessage = reply.length > 0 ? reply : `Agent 已规划：${name}`;
    hilog.info(LOG_DOMAIN, LOG_TAG, '[Agent] route applied id=%{public}d points=%{public}d',
      newLoop.id, latitudes.length);
    return true;
  }

  private applyMapPlaceLabelVisibility(): void {
    this.mapOptions.showMapPoi = this.showMapPlaceLabels;
    this.mapOptions.showMapIndoorPoi = this.showMapPlaceLabels;
    this.mapOptions.refresh();
  }

  private toggleMapPlaceLabels(): void {
    this.showMapPlaceLabels = !this.showMapPlaceLabels;
    this.applyMapPlaceLabelVisibility();
    this.debugMessage = this.showMapPlaceLabels ? '已显示地图地名标注' : '已隐藏地图地名标注';
  }

  private async requestCurrentLocation(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const permissionManager = abilityAccessCtrl.createAtManager();

    try {
      const permissionResult = await permissionManager.requestPermissionsFromUser(
        context,
        ['ohos.permission.LOCATION', 'ohos.permission.APPROXIMATELY_LOCATION']
      );
      const granted = permissionResult.authResults.some((status: number) => status === 0);
      if (!granted) {
        this.locationMessage = '未授权定位，显示默认区域';
        this.locationReady = false;
        return;
      }

      const location = await geoLocationManager.getCurrentLocation();
      const wgs84Location = new LatLng(location.latitude, location.longitude);
      this.currentLocation = CoordTrans.wgsToBaidu(wgs84Location);
      this.locationReady = this.currentLocation !== null;
      this.locationMessage = this.locationReady ? '已定位到当前位置' : '坐标转换失败，显示默认区域';
      this.applyCurrentLocation(true);
    } catch (error) {
      this.locationMessage = '定位不可用，显示默认区域';
      this.locationReady = false;
      console.error(`Get current location failed: ${JSON.stringify(error)}`);
    }
  }

  /** 将地图中心移到当前位置（需已有 currentLocation） */
  private centerMapOnCurrentLocation(): boolean {
    if (!this.mapController || this.currentLocation === null) {
      return false;
    }
    this.mapController.setMapCenter(this.currentLocation, LOCATION_ZOOM, false);
    return true;
  }

  /** 点击定位：重新获取 GPS 并居中 */
  private async locateToCurrentPosition(): Promise<void> {
    this.locationMessage = '正在定位…';
    this.locationReady = false;
    await this.requestCurrentLocation();
    if (this.centerMapOnCurrentLocation()) {
      this.debugMessage = '已定位到当前位置';
    } else if (!this.locationReady) {
      this.debugMessage = this.locationMessage;
    }
  }

  /**
   * @param moveCamera 是否将视野移到当前位置；打开应用/手动定位为 true，
   *                   地图 onReady 时若尚未拿到定位则仅更新蓝点
   */
  private applyCurrentLocation(moveCamera: boolean = false): void {
    if (!this.mapController || !this.currentLocation) {
      return;
    }

    this.mapController.setLocationInfo({
      latlng: this.currentLocation,
      direction: 0,
      radius: 60
    }, {
      enableDirection: false,
      locationMode: SysEnum.LocationMode.NORMAL,
      accuracyCircleFillColor: '#35B75B33'
    });
    if (this.focusTerritoryId >= 0) {
      this.focusSelectedTerritory();
      return;
    }
    if (moveCamera) {
      this.centerMapOnCurrentLocation();
    }
  }

  private refreshNanjingTerritories(): void {
    if (!this.mapController) {
      return;
    }
    this.territoryOverlays.forEach((overlay: Polygon) => {
      this.mapController?.removeOverlay(overlay);
    });
    this.territoryOverlays = [];
    NanjingTerritoryStore.getAll().forEach((territory: TerritoryInfo) => {
      const points: Array<LatLng> = territory.points.map((point: TerritoryPoint) => new LatLng(point.lat, point.lng));
      const overlay = new Polygon({
        points: points,
        fillcolor: territory.fillColor,
        stroke: new Stroke({ color: territory.borderColor, strokeWidth: 3 })
      });
      this.territoryOverlays.push(overlay);
      this.mapController?.addOverlay(overlay);
    });
  }

  private focusSelectedTerritory(): void {
    if (!this.mapController || this.focusTerritoryId < 0) {
      return;
    }
    const territory = NanjingTerritoryStore.getById(this.focusTerritoryId);
    if (!territory) {
      return;
    }
    this.mapController.setMapCenter(new LatLng(territory.center.lat, territory.center.lng), 15);
  }

  private toggleDebugMode(): void {
    this.debugMode = !this.debugMode;
    if (!this.debugMode) {
      this.endPanelTouchCapture();
    }
    if (this.debugMode && !this.debugStart) {
      this.resetDebugRun();
    }
    // 关闭调试面板时保留摇杆，不中断移动
  }

  /** 摇杆始终可用：未初始化时自动从当前位置开始调试轨迹 */
  private ensureJoystickReady(): void {
    if (this.debugStart !== null && this.debugLocation !== null) {
      return;
    }
    this.resetDebugRun();
  }

  private stopDebugTimer(): void {
    if (this.debugTimer >= 0) {
      clearInterval(this.debugTimer);
      this.debugTimer = -1;
    }
  }

  private resetDebugRun(): void {
    this.releaseJoystick();
    this.debugApplyTick = 0;
    this.debugFollowConfigured = false;
    this.debugDistance = 0;
    this.debugDirection = 0;
    const start: LatLng = this.currentLocation ?? new LatLng(DEFAULT_LATITUDE, DEFAULT_LONGITUDE);
    this.debugStart = start;
    this.debugLocation = start;
    this.lastDebugLocation = new LatLng(start.lat, start.lng);
    this.beginNewTrackFromCurrentLocation();
    this.applyDebugLocation();
    this.debugMessage = '推动摇杆即可移动，或点击“生成闭环”快速测试';
  }

  private resetActiveTrack(): void {
    this.releaseJoystick();
    this.debugDistance = 0;
    this.beginNewTrackFromCurrentLocation();
    this.debugMessage = '轨迹已重置，可从当前位置重新绘制';
  }

  private beginNewTrackFromCurrentLocation(): void {
    void this.startRemoteTrackSession();
    this.activeTrackPoints = [];
    this.triggeredTrapIds = [];
    this.lastTrackOverlayUpdateMs = 0;
    this.debugTrackStartedAtMs = Date.now();
    this.removeActiveTrackOverlay();
    if (this.debugLocation !== null) {
      this.debugStart = this.debugLocation;
      this.pushTrackPoint(this.debugLocation);
      this.scheduleTrackOverlayRefresh(true);
      const trackLog: TrackRestartLog = {
        lat: this.debugLocation.lat,
        lng: this.debugLocation.lng,
        trackPoints: this.activeTrackPoints.length
      };
      // #region agent log
      hilog.info(LOG_DOMAIN, LOG_TAG, '[C] track restarted %{public}s', JSON.stringify(trackLog));
      // #endregion
    }
  }

  private getAllDisplayLoops(): Array<DebugLoopRecord> {
    const loops: Array<DebugLoopRecord> = [];
    for (let i = 0; i < this.savedLoops.length; i++) {
      loops.push(this.savedLoops[i]);
    }
    for (let i = 0; i < this.pendingLoops.length; i++) {
      loops.push(this.pendingLoops[i]);
    }
    return loops;
  }

  private getLoopById(id: number): DebugLoopRecord | null {
    for (let i = 0; i < this.savedLoops.length; i++) {
      if (this.savedLoops[i].id === id) {
        return this.savedLoops[i];
      }
    }
    for (let i = 0; i < this.pendingLoops.length; i++) {
      if (this.pendingLoops[i].id === id) {
        return this.pendingLoops[i];
      }
    }
    return null;
  }

  private isPendingLoop(id: number): boolean {
    for (let i = 0; i < this.pendingLoops.length; i++) {
      if (this.pendingLoops[i].id === id) {
        return true;
      }
    }
    return false;
  }

  private selectLoop(id: number): void {
    const loop = this.getLoopById(id);
    if (loop === null) {
      return;
    }
    this.selectedLoopId = id;
    this.draftLoopName = loop.name;
    this.draftStrokeColor = loop.strokeColor;
    this.draftFillColor = DebugLoopStore.resolveFillColor(loop);
    this.draftColorText = loop.strokeColor;
    this.draftFillColorText = DebugLoopStore.resolveFillColor(loop);
    this.draftStrokeWidth = loop.strokeWidth;
    this.draftStrokeWidthText = `${loop.strokeWidth}`;
    this.syncDraftAdFromLoop(loop);
    this.debugMessage = `已选中「${loop.name}」，双击可编辑`;
  }

  private syncDraftAdFromLoop(loop: DebugLoopRecord): void {
    this.draftAdEnabled = loop.adEnabled === true;
    this.draftAdPresetId = loop.adPresetId !== undefined ? loop.adPresetId : '';
    this.draftAdTitle = loop.adTitle !== undefined ? loop.adTitle : '';
    this.draftAdImageUri = loop.adImageUri !== undefined ? loop.adImageUri : '';
  }

  private deselectLoop(): void {
    this.selectedLoopId = -1;
    this.showLoopEditDialog = false;
    this.debugMessage = '推动摇杆即可移动，或点击「生成闭环」';
  }

  private openLoopEditDialog(loop: DebugLoopRecord): void {
    this.selectLoop(loop.id);
    this.showLoopEditDialog = true;
    this.debugMessage = `编辑「${loop.name}」`;
  }

  private closeLoopEditDialog(revertDraft: boolean = true): void {
    const loopId = this.selectedLoopId;
    this.showLoopEditDialog = false;
    this.selectedLoopId = -1;
    if (revertDraft && loopId >= 0) {
      const loop = this.getLoopById(loopId);
      if (loop !== null) {
        this.draftLoopName = loop.name;
        this.draftStrokeColor = loop.strokeColor;
        this.draftFillColor = DebugLoopStore.resolveFillColor(loop);
        this.draftColorText = loop.strokeColor;
        this.draftFillColorText = DebugLoopStore.resolveFillColor(loop);
        this.draftStrokeWidth = loop.strokeWidth;
        this.draftStrokeWidthText = `${loop.strokeWidth}`;
        this.syncDraftAdFromLoop(loop);
      }
    }
  }

  private saveLoopEditDialog(): void {
    this.applySelectedLoopEdits();
    this.closeLoopEditDialog(false);
  }

  private deleteSelectedLoop(): void {
    if (this.selectedLoopId < 0) {
      return;
    }
    const loopId = this.selectedLoopId;
    const loop = this.getLoopById(loopId);
    if (loop === null) {
      return;
    }
    const loopName = loop.name;
    const ownerId = this.resolveLoopOwnerId(loop);
    this.queueLoopDeletion(ownerId, loopId);
    if (this.isPendingLoop(loopId)) {
      const nextPending: Array<DebugLoopRecord> = [];
      for (let i = 0; i < this.pendingLoops.length; i++) {
        if (this.pendingLoops[i].id !== loopId) {
          nextPending.push(this.pendingLoops[i]);
        }
      }
      this.pendingLoops = nextPending;
    } else {
      const nextSaved: Array<DebugLoopRecord> = [];
      for (let i = 0; i < this.savedLoops.length; i++) {
        if (this.savedLoops[i].id !== loopId) {
          nextSaved.push(this.savedLoops[i]);
        }
      }
      this.savedLoops = nextSaved;
    }
    this.removeLoopOverlay(loopId);
    this.removePlacedItemsForLoop(loopId, false);
    this.clearPendingLoopSingleTap();
    this.showLoopEditDialog = false;
    this.selectedLoopId = -1;
    this.debugMessage = `已删除并释放「${loopName}」`;
    // #region agent log
    hilog.info(LOG_DOMAIN, LOG_TAG, '[K] loop deleted loopId=%{public}d owner=%{public}s', loopId, ownerId);
    // #endregion
    void this.persistAndPushOwners([ownerId]);
  }

  private removePlacedItemsForLoop(loopId: number, syncAfter: boolean = true): void {
    const remaining: Array<PlacedItemRecord> = [];
    let removedCount = 0;
    for (let i = 0; i < this.placedItems.length; i++) {
      if (this.placedItems[i].loopId !== loopId) {
        remaining.push(this.placedItems[i]);
      } else {
        removedCount++;
      }
    }
    if (removedCount === 0) {
      return;
    }
    this.placedItems = remaining;
    this.refreshAllPlacedItemOverlays();
    // #region agent log
    hilog.info(LOG_DOMAIN, LOG_TAG, '[P] items cleared loopId=%{public}d removed=%{public}d remaining=%{public}d',
      loopId, removedCount, remaining.length);
    // #endregion
    if (syncAfter) {
      void this.savePlacedItems(true);
    }
  }

  private purgePlacedItemsForMissingLoops(): void {
    const validLoopIds: Set<number> = new Set();
    const loops = this.getAllDisplayLoops();
    for (let i = 0; i < loops.length; i++) {
      validLoopIds.add(loops[i].id);
    }
    const remaining: Array<PlacedItemRecord> = [];
    let removedCount = 0;
    for (let i = 0; i < this.placedItems.length; i++) {
      const loopId = this.placedItems[i].loopId;
      if (loopId === TerritoryItemDefaults.WORLD_RESOURCE_LOOP_ID || validLoopIds.has(loopId)) {
        remaining.push(this.placedItems[i]);
      } else {
        removedCount++;
      }
    }
    if (removedCount === 0) {
      return;
    }
    this.placedItems = remaining;
    this.refreshAllPlacedItemOverlays();
    this.savePlacedItems();
    // #region agent log
    hilog.info(LOG_DOMAIN, LOG_TAG, '[P] orphaned items cleared removed=%{public}d remaining=%{public}d',
      removedCount, remaining.length);
    // #endregion
  }

  private applySelectedLoopEdits(): void {
    if (this.selectedLoopId < 0) {
      return;
    }
    const source = this.getLoopById(this.selectedLoopId);
    if (source === null) {
      return;
    }
    const hasAdContent = this.draftAdImageUri.length > 0;
    const adEnabled = this.draftAdEnabled && hasAdContent;
    const updated: DebugLoopRecord = DebugLoopStore.copyMetadata(source, {
      id: source.id,
      name: this.draftLoopName.trim().length > 0 ? this.draftLoopName.trim() : '未命名领地',
      ownerId: source.ownerId,
      strokeColor: this.draftStrokeColor,
      fillColor: DebugLoopStore.normalizeFillColor(this.draftFillColor, this.draftStrokeColor),
      strokeWidth: this.draftStrokeWidth,
      distance: source.distance,
      latitudes: source.latitudes.slice(),
      longitudes: source.longitudes.slice(),
      adEnabled: adEnabled,
      adPresetId: '',
      adTitle: adEnabled ? this.draftAdTitle.trim() : '',
      adImageUri: adEnabled ? this.draftAdImageUri : ''
    });
    if (this.isPendingLoop(this.selectedLoopId)) {
      const nextPending: Array<DebugLoopRecord> = [];
      for (let i = 0; i < this.pendingLoops.length; i++) {
        nextPending.push(this.pendingLoops[i].id === this.selectedLoopId ? updated : this.pendingLoops[i]);
      }
      this.pendingLoops = nextPending;
    } else {
      const nextSaved: Array<DebugLoopRecord> = [];
      for (let i = 0; i < this.savedLoops.length; i++) {
        nextSaved.push(this.savedLoops[i].id === this.selectedLoopId ? updated : this.savedLoops[i]);
      }
      this.savedLoops = nextSaved;
      this.saveAllLoops();
    }
    this.refreshLoopOverlay(updated);
  }

  private updateSelectedLoopFillColor(color: string): void {
    this.draftFillColor = DebugLoopStore.normalizeFillColor(color, this.draftStrokeColor);
    this.draftFillColorText = this.draftFillColor;
    if (this.showLoopEditDialog) {
      return;
    }
    this.applySelectedLoopEdits();
  }

  private updateSelectedLoopFillColorFromInput(value: string): void {
    this.draftFillColorText = value.toUpperCase();
    if (this.draftFillColorText.length === 7 && this.draftFillColorText.charAt(0) === '#') {
      const hex = this.draftFillColorText.substring(1);
      if (/^[0-9A-Fa-f]{6}$/.test(hex)) {
        this.updateSelectedLoopFillColor(this.draftFillColorText);
      }
    } else if (this.draftFillColorText.length === 9 && this.draftFillColorText.charAt(0) === '#') {
      const hex = this.draftFillColorText.substring(1);
      if (/^[0-9A-Fa-f]{8}$/.test(hex)) {
        this.draftFillColor = this.draftFillColorText;
        if (!this.showLoopEditDialog) {
          this.applySelectedLoopEdits();
        }
      }
    }
  }

  private updateSelectedLoopName(value: string): void {
    this.draftLoopName = value;
    if (this.showLoopEditDialog) {
      return;
    }
    this.applySelectedLoopEdits();
  }

  private updateSelectedLoopColor(color: string): void {
    this.draftStrokeColor = color;
    this.draftColorText = color;
    if (this.showLoopEditDialog) {
      return;
    }
    this.applySelectedLoopEdits();
  }

  private updateSelectedLoopColorFromInput(value: string): void {
    this.draftColorText = value.toUpperCase();
    if (this.draftColorText.length === 7 && this.draftColorText.charAt(0) === '#') {
      const hex = this.draftColorText.substring(1);
      if (/^[0-9A-Fa-f]{6}$/.test(hex)) {
        this.updateSelectedLoopColor(this.draftColorText);
      }
    }
  }

  private updateSelectedLoopWidth(value: string): void {
    this.draftStrokeWidthText = value;
    const parsed = Number.parseInt(value, 10);
    if (Number.isNaN(parsed)) {
      return;
    }
    const width = Math.min(12, Math.max(1, parsed));
    this.draftStrokeWidth = width;
    this.draftStrokeWidthText = `${width}`;
    if (this.showLoopEditDialog) {
      return;
    }
    this.applySelectedLoopEdits();
  }

  private updateDebugSpeed(delta: number): void {
    this.debugSpeed = Math.max(0.1, this.debugSpeed + delta);
    this.debugSpeedText = `${this.debugSpeed}`;
  }

  private updateDebugSpeedFromInput(value: string): void {
    this.debugSpeedText = value;
    const parsed = Number(value);
    if (!isNaN(parsed) && value.length > 0 && parsed > 0) {
      this.debugSpeed = parsed;
      this.debugSpeedText = `${this.debugSpeed}`;
    }
  }

  private updateJoystickFromLocal(localX: number, localY: number): void {
    const center = JOYSTICK_SIZE / 2;
    let dx = localX - center;
    let dy = localY - center;
    const distance = Math.sqrt(dx * dx + dy * dy);
    if (distance > JOYSTICK_RADIUS) {
      dx = dx * JOYSTICK_RADIUS / distance;
      dy = dy * JOYSTICK_RADIUS / distance;
    }
    this.joystickKnobX = dx;
    this.joystickKnobY = dy;

    const magnitude = Math.sqrt(dx * dx + dy * dy) / JOYSTICK_RADIUS;
    if (magnitude < 0.08) {
      this.joystickKnobX = 0;
      this.joystickKnobY = 0;
      this.joystickActive = false;
      this.joystickSpeedFactor = 0;
      this.stopDebugTimer();
      return;
    }

    if (!this.debugStart) {
      this.resetDebugRun();
    }

    this.debugDirection = (Math.atan2(dx, -dy) * 180 / Math.PI + 360) % 360;
    this.joystickSpeedFactor = magnitude;
    this.joystickActive = true;
    this.beginJoystickCapture();
    this.debugMessage = `摇杆移动中 · ${this.debugDirection.toFixed(0)}°`;
    this.startJoystickMovement();
  }

  private releaseJoystick(): void {
    this.joystickActive = false;
    this.joystickSpeedFactor = 0;
    this.joystickKnobX = 0;
    this.joystickKnobY = 0;
    this.joystickCapturing = false;
    this.debugFollowConfigured = false;
    this.stopDebugTimer();
    this.applyGestureLockState();
    if (this.activeTrackPoints.length >= 2) {
      this.scheduleTrackOverlayRefresh(true);
    }
  }

  private beginJoystickCapture(): void {
    this.ensureJoystickReady();
    if (this.joystickCapturing) {
      return;
    }
    this.joystickCapturing = true;
    this.applyGestureLockState();
  }

  private startJoystickMovement(): void {
    if (this.debugTimer >= 0) {
      return;
    }
    this.debugTimer = setInterval(() => {
      if (this.joystickActive && this.joystickSpeedFactor > 0.08) {
        this.advanceDebugLocation();
      }
    }, JOYSTICK_MOVE_INTERVAL_MS);
  }

  private advanceDebugLocation(): void {
    if (this.showTrapDialog) {
      return;
    }
    const current: LatLng | null = this.debugLocation;
    if (!current) {
      return;
    }

    const speedKmh = this.debugSpeed * this.joystickSpeedFactor;
    const stepDistance = speedKmh * 1000 / 3600 * (JOYSTICK_MOVE_INTERVAL_MS / 1000);
    const angle = this.debugDirection * Math.PI / 180;
    const latitudeDelta = Math.cos(angle) * stepDistance / 111000;
    const longitudeScale = Math.max(0.2, Math.cos(current.lat * Math.PI / 180));
    const longitudeDelta = Math.sin(angle) * stepDistance / (111000 * longitudeScale);
    const previousLocation = this.lastDebugLocation !== null
      ? this.lastDebugLocation
      : new LatLng(current.lat, current.lng);
    this.debugLocation = new LatLng(current.lat + latitudeDelta, current.lng + longitudeDelta);
    this.pushTrackPoint(this.debugLocation);
    this.debugDistance += stepDistance;
    this.checkTrapCollisions(this.debugLocation, previousLocation);
    this.lastDebugLocation = new LatLng(this.debugLocation.lat, this.debugLocation.lng);
    this.debugApplyTick++;
    this.applyDebugLocation();
    this.scheduleTrackOverlayRefresh(false);
  }

  private isValidCoordinate(lat: number, lng: number): boolean {
    return Number.isFinite(lat) && Number.isFinite(lng) &&
      lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;
  }

  private pushTrackPoint(point: LatLng): void {
    if (!this.isValidCoordinate(point.lat, point.lng)) {
      // #region agent log
      hilog.warn(LOG_DOMAIN, LOG_TAG, '[N] invalid track point lat=%{public}f lng=%{public}f', point.lat, point.lng);
      // #endregion
      return;
    }
    this.activeTrackPoints.push(new LatLng(point.lat, point.lng));
    this.enqueueRemoteTrackPoint(point);
    if (this.activeTrackPoints.length > MAX_TRACK_POINTS) {
      const trimmed: Array<LatLng> = LoopDetector.simplify(this.activeTrackPoints, 2);
      this.activeTrackPoints = trimmed.length >= 2 ? trimmed : this.activeTrackPoints.slice(-MAX_TRACK_POINTS);
      // #region agent log
      hilog.info(LOG_DOMAIN, LOG_TAG, '[N] track trimmed to %{public}d points', this.activeTrackPoints.length);
      // #endregion
    }
  }

  private getTrackOverlayPoints(): Array<LatLng> {
    const source = this.activeTrackPoints;
    if (source.length <= MAX_TRACK_OVERLAY_POINTS) {
      const copied: Array<LatLng> = [];
      for (let i = 0; i < source.length; i++) {
        copied.push(new LatLng(source[i].lat, source[i].lng));
      }
      return copied;
    }
    const sampled: Array<LatLng> = [];
    const step = (source.length - 1) / (MAX_TRACK_OVERLAY_POINTS - 1);
    for (let i = 0; i < MAX_TRACK_OVERLAY_POINTS; i++) {
      const index = Math.min(source.length - 1, Math.round(i * step));
      sampled.push(new LatLng(source[index].lat, source[index].lng));
    }
    return sampled;
  }

  private scheduleTrackOverlayRefresh(force: boolean): void {
    const now = Date.now();
    if (!force && now - this.lastTrackOverlayUpdateMs < TRACK_OVERLAY_UPDATE_MS) {
      return;
    }
    this.lastTrackOverlayUpdateMs = now;
    this.refreshActiveTrackOverlay();
  }

  private getLoopDetectionPoints(): Array<LatLng> {
    if (this.activeTrackPoints.length <= 1500) {
      return this.activeTrackPoints;
    }
    return LoopDetector.simplify(this.activeTrackPoints, 3);
  }

  private applyDebugLocation(): void {
    if (!this.mapController || !this.debugLocation) {
      return;
    }
    if (!this.isValidCoordinate(this.debugLocation.lat, this.debugLocation.lng)) {
      return;
    }

    const locationData: ILocation = {
      latlng: new LatLng(this.debugLocation.lat, this.debugLocation.lng),
      direction: this.debugDirection,
      speed: (this.debugSpeed * this.joystickSpeedFactor) / 3.6,
      radius: 8
    };
    const followConfig: ILocationConfig = {
      enableDirection: true,
      locationMode: SysEnum.LocationMode.FOLLOWING,
      accuracyCircleFillColor: '#35B75B33'
    };
    const normalConfig: ILocationConfig = {
      enableDirection: true,
      locationMode: SysEnum.LocationMode.NORMAL,
      accuracyCircleFillColor: '#35B75B33'
    };

    if (this.joystickActive || this.joystickCapturing) {
      if (!this.debugFollowConfigured) {
        this.mapController.setLocationInfo(locationData, followConfig);
        this.mapController.setMapCenter(this.debugLocation, undefined, false);
        this.debugFollowConfigured = true;
      } else {
        this.mapController.setLocationInfo(locationData, followConfig);
      }
    } else {
      this.mapController.setLocationInfo(locationData, normalConfig);
      this.mapController.setMapCenter(this.debugLocation, undefined, false);
      this.debugFollowConfigured = false;
    }
  }

  private generateDebugLoop(): void {
    if (this.currentDebugUserId.length === 0) {
      this.debugMessage = '请先在「我的」登录';
      return;
    }
    if (this.showTrapDialog) {
      this.debugMessage = '掉进陷阱中，请先处理陷阱';
      return;
    }
    if (this.activeTrackPoints.length < 4) {
      this.debugMessage = '轨迹太短，请先推动摇杆移动';
      return;
    }

    const loop = LoopDetector.detectLargestLoop(this.getLoopDetectionPoints());
    if (!loop || loop.length < 4) {
      this.debugMessage = '未检测到闭环，请让轨迹首尾相交';
      return;
    }

    this.releaseJoystick();
    const latitudes: Array<number> = [];
    const longitudes: Array<number> = [];
    loop.forEach((point: LatLng) => {
      latitudes.push(point.lat);
      longitudes.push(point.lng);
    });
    const perimeter = LoopDetector.calculatePerimeter(loop);
    const nowMs = Date.now();
    const durationSeconds = this.debugTrackStartedAtMs > 0
      ? Math.max(1, (nowMs - this.debugTrackStartedAtMs) / 1000)
      : undefined;
    let avgSpeedKmh: number | undefined = undefined;
    if (durationSeconds !== undefined && durationSeconds > 0) {
      avgSpeedKmh = (perimeter / 1000) / (durationSeconds / 3600);
    } else if (this.debugSpeed > 0) {
      avgSpeedKmh = this.debugSpeed * 3.6;
    }
    const newLoop: DebugLoopRecord = LoopDetector.compactLoopRecord({
      id: this.nextLoopId++,
      name: this.draftLoopName.trim().length > 0 ? this.draftLoopName.trim() : `领地 ${this.nextLoopId - 1}`,
      ownerId: this.currentDebugUserId,
      strokeColor: this.draftStrokeColor,
      fillColor: DebugLoopStore.normalizeFillColor(this.draftFillColor, this.draftStrokeColor),
      strokeWidth: this.draftStrokeWidth,
      distance: perimeter,
      latitudes: latitudes,
      longitudes: longitudes,
      createdAt: nowMs,
      durationSeconds: durationSeconds,
      avgSpeedKmh: avgSpeedKmh
    });
    const nextPending: Array<DebugLoopRecord> = [];
    for (let i = 0; i < this.pendingLoops.length; i++) {
      nextPending.push(this.pendingLoops[i]);
    }
    nextPending.push(newLoop);
    this.pendingLoops = nextPending;
    const conqueredArea = this.resolveTerritoryConquest(newLoop);
    this.refreshAllLoopOverlays();
    this.beginNewTrackFromCurrentLocation();
    if (conqueredArea > 0) {
      this.debugMessage = `闭环已生成，从对手夺取 ${conqueredArea.toFixed(0)} m²`;
    } else {
      this.debugMessage = '闭环已生成，双击可编辑，长按查看详情';
    }
    const loopLog: LoopGeneratedLog = {
      pendingCount: this.pendingLoops.length,
      savedCount: this.savedLoops.length,
      newLoopId: newLoop.id,
      trackPoints: this.activeTrackPoints.length
    };
    // #region agent log
    hilog.info(LOG_DOMAIN, LOG_TAG, '[A] loop generated %{public}s', JSON.stringify(loopLog));
    // #endregion
  }

  private countLoopVertices(loops: Array<DebugLoopRecord>): number {
    let total = 0;
    for (let i = 0; i < loops.length; i++) {
      total += loops[i].latitudes.length;
    }
    return total;
  }

  private completeDebugTerritory(): void {
    if (this.currentDebugUserId.length === 0) {
      this.debugMessage = '请先在「我的」登录';
      return;
    }
    if (this.pendingLoops.length === 0) {
      this.debugMessage = '请先生成闭环';
      return;
    }
    const savedCount = this.pendingLoops.length;
    const pendingSnapshot: Array<DebugLoopRecord> = [];
    for (let i = 0; i < this.pendingLoops.length; i++) {
      pendingSnapshot.push(this.pendingLoops[i]);
    }
    const savedSnapshot: Array<DebugLoopRecord> = [];
    for (let i = 0; i < this.savedLoops.length; i++) {
      savedSnapshot.push(this.savedLoops[i]);
    }
    const verticesBefore = this.countLoopVertices(savedSnapshot) + this.countLoopVertices(pendingSnapshot);
    this.pendingLoops = [];
    this.selectedLoopId = -1;
    this.debugMessage = '正在保存圈地...';
    // #region agent log
    hilog.info(LOG_DOMAIN, LOG_TAG, '[M] complete start count=%{public}d saved=%{public}d pending=%{public}d verts=%{public}d',
      savedCount, savedSnapshot.length, pendingSnapshot.length, verticesBefore);
    // #endregion
    setTimeout(async () => {
      const started = Date.now();
      let mergeMs = 0;
      let saveMs = 0;
      let overlayMs = 0;
      const mergeStarted = Date.now();
      const merged: Array<DebugLoopRecord> = [];
      for (let i = 0; i < savedSnapshot.length; i++) {
        merged.push(LoopDetector.compactLoopRecord(savedSnapshot[i]));
      }
      for (let i = 0; i < pendingSnapshot.length; i++) {
        const pendingLoop = pendingSnapshot[i];
        const savedLoop = DebugLoopStore.copyMetadata(pendingLoop, LoopDetector.compactLoopRecord(pendingLoop));
        if (savedLoop.completedAt === undefined) {
          savedLoop.completedAt = Date.now();
        }
        merged.push(savedLoop);
      }
      mergeMs = Date.now() - mergeStarted;
      const verticesAfter = this.countLoopVertices(merged);
      this.savedLoops = merged;
      const saveStarted = Date.now();
      await this.saveAllLoops();
      saveMs = Date.now() - saveStarted;
      const overlayStarted = Date.now();
      this.refreshAllLoopOverlays();
      overlayMs = Date.now() - overlayStarted;
      this.debugMessage = `圈地成功 · 已保存 ${savedCount} 个闭环`;
      const completeLog: CompleteTerritoryLog = {
        savedCount: savedCount,
        totalLoops: merged.length,
        verticesBefore: verticesBefore,
        verticesAfter: verticesAfter,
        mergeMs: mergeMs,
        saveMs: saveMs,
        overlayMs: overlayMs,
        totalMs: Date.now() - started
      };
      // #region agent log
      hilog.info(LOG_DOMAIN, LOG_TAG, '[M] complete done %{public}s', JSON.stringify(completeLog));
      hilog.info(LOG_DOMAIN, LOG_TAG, '[B] loops saved %{public}s', JSON.stringify({
        savedCount: savedCount,
        totalSaved: this.savedLoops.length
      } as LoopsSavedLog));
      // #endregion
    }, 0);
  }

  /** 管理台与 App 均使用百度 BD09；不再做 WGS84 转换 */
  private loopUsesWgs84Vertices(_record: DebugLoopRecord): boolean {
    return false;
  }

  private loopPoints(record: DebugLoopRecord): Array<LatLng> {
    const points: Array<LatLng> = [];
    const convertWgs = this.loopUsesWgs84Vertices(record);
    for (let i = 0; i < record.latitudes.length; i++) {
      const lat = record.latitudes[i];
      const lng = record.longitudes[i];
      if (convertWgs) {
        const bd = CoordTrans.wgsToBaidu(new LatLng(lat, lng));
        points.push(bd !== null ? bd : new LatLng(lat, lng));
      } else {
        points.push(new LatLng(lat, lng));
      }
    }
    return points;
  }

  private fitMapToCurrentUserLoops(): void {
    if (!this.mapController) {
      return;
    }
    let minLat = 90;
    let maxLat = -90;
    let minLng = 180;
    let maxLng = -180;
    let vertexCount = 0;
    const loops = this.getAllDisplayLoops();
    for (let i = 0; i < loops.length; i++) {
      if (this.resolveLoopOwnerId(loops[i]) !== this.currentDebugUserId) {
        continue;
      }
      const points = this.loopPoints(loops[i]);
      for (let j = 0; j < points.length; j++) {
        minLat = Math.min(minLat, points[j].lat);
        maxLat = Math.max(maxLat, points[j].lat);
        minLng = Math.min(minLng, points[j].lng);
        maxLng = Math.max(maxLng, points[j].lng);
        vertexCount++;
      }
    }
    if (vertexCount === 0) {
      return;
    }
    const centerLat = (minLat + maxLat) / 2;
    const centerLng = (minLng + maxLng) / 2;
    const span = Math.max(maxLat - minLat, maxLng - minLng);
    let zoom = 14;
    if (span > 0.08) {
      zoom = 11;
    } else if (span > 0.04) {
      zoom = 12;
    } else if (span > 0.015) {
      zoom = 13;
    } else if (span > 0.006) {
      zoom = 14;
    } else {
      zoom = 15;
    }
    this.mapController.setMapCenter(new LatLng(centerLat, centerLng), zoom, false);
  }

  private findLoopOverlayIndex(id: number): number {
    for (let i = 0; i < this.loopOverlayIds.length; i++) {
      if (this.loopOverlayIds[i] === id) {
        return i;
      }
    }
    return -1;
  }

  private removeLoopOverlay(id: number): void {
    const index = this.findLoopOverlayIndex(id);
    if (index < 0 || !this.mapController) {
      this.removeLoopAdOverlay(id);
      return;
    }
    this.mapController.removeOverlay(this.loopOverlayPolygons[index]);
    this.mapController.removeOverlay(this.loopOverlayPolylines[index]);
    this.mapController.removeOverlay(this.loopOverlayLabels[index]);
    this.loopOverlayIds.splice(index, 1);
    this.loopOverlayPolygons.splice(index, 1);
    this.loopOverlayPolylines.splice(index, 1);
    this.loopOverlayLabels.splice(index, 1);
    this.removeLoopAdOverlay(id);
  }

  private removeLoopAdOverlay(loopId: number): void {
    const marker = this.loopAdMarkers.get(loopId);
    if (marker === undefined) {
      return;
    }
    if (this.mapController !== null) {
      this.mapController.removeOverlay(marker);
    }
    this.loopAdMarkers.delete(loopId);
  }

  private loopBoundingBox(record: DebugLoopRecord): Array<number> {
    const points = this.loopPoints(record);
    if (points.length === 0) {
      return [0, 0, 0, 0];
    }
    let minLat = points[0].lat;
    let maxLat = points[0].lat;
    let minLng = points[0].lng;
    let maxLng = points[0].lng;
    for (let i = 1; i < points.length; i++) {
      const lat = points[i].lat;
      const lng = points[i].lng;
      if (lat < minLat) {
        minLat = lat;
      }
      if (lat > maxLat) {
        maxLat = lat;
      }
      if (lng < minLng) {
        minLng = lng;
      }
      if (lng > maxLng) {
        maxLng = lng;
      }
    }
    const box: Array<number> = [minLat, maxLat, minLng, maxLng];
    return box;
  }

  /**
   * 按闭环在屏幕上的投影计算广告缩放：图片+口号整体约为闭环的 25%。
   * 地图放大/缩小时随闭环屏幕尺寸同步变化。
   */
  private computeAdMarkerScale(record: DebugLoopRecord): number {
    if (this.mapController === null || record.latitudes.length < 3) {
      return 1;
    }
    const box = this.loopBoundingBox(record);
    const sw = new LatLng(box[0], box[2]);
    const ne = new LatLng(box[1], box[3]);
    const p1 = this.mapController.ll2pixel(sw);
    const p2 = this.mapController.ll2pixel(ne);
    if (p1 === null || p1 === undefined || p2 === null || p2 === undefined) {
      return 1;
    }
    const x1: number = p1[0];
    const y1: number = p1[1];
    const x2: number = p2[0];
    const y2: number = p2[1];
    const loopWpx = Math.abs(x2 - x1);
    const loopHpx = Math.abs(y2 - y1);
    if (loopWpx < 8 || loopHpx < 8) {
      return LOOP_AD_MIN_SCALE;
    }
    const maxW = loopWpx * LOOP_AD_MAX_LOOP_RATIO;
    const maxH = loopHpx * LOOP_AD_MAX_LOOP_RATIO;
    const iconW = vp2px(LOOP_AD_ICON_WIDTH_VP);
    const iconH = vp2px(LOOP_AD_ICON_HEIGHT_VP);
    const scaleW = maxW / Math.max(1, iconW);
    const scaleH = maxH / Math.max(1, iconH);
    let scale = Math.min(scaleW, scaleH);
    if (scale < LOOP_AD_MIN_SCALE) {
      scale = LOOP_AD_MIN_SCALE;
    }
    if (scale > LOOP_AD_MAX_SCALE) {
      scale = LOOP_AD_MAX_SCALE;
    }
    return scale;
  }

  private syncAllLoopAdScales(): void {
    if (this.loopAdMarkers.size === 0) {
      return;
    }
    const loops = this.getAllDisplayLoops();
    for (let i = 0; i < loops.length; i++) {
      const loop = loops[i];
      const marker = this.loopAdMarkers.get(loop.id);
      if (marker === undefined) {
        continue;
      }
      const scale = this.computeAdMarkerScale(loop);
      marker.setScale(scale, scale);
    }
  }

  private bindLoopAdScaleListener(): void {
    if (this.mapController === null || this.mapAdScaleListenerBound) {
      return;
    }
    this.mapController.addEventListener(MapEvent.MAPSTATUSCHANGE, () => {
      this.syncAllLoopAdScales();
    });
    this.mapController.addEventListener(MapEvent.MAPSTATUSCHANGEFINISH, () => {
      this.syncAllLoopAdScales();
    });
    this.mapAdScaleListenerBound = true;
  }

  private removeActiveTrackOverlay(): void {
    if (this.activeTrackOverlay && this.mapController) {
      this.mapController.removeOverlay(this.activeTrackOverlay);
      this.activeTrackOverlay = null;
    }
  }

  private clearAllLoopOverlays(): void {
    while (this.loopOverlayIds.length > 0) {
      this.removeLoopOverlay(this.loopOverlayIds[0]);
    }
  }

  private refreshLoopOverlay(record: DebugLoopRecord): void {
    if (!this.mapController || record.latitudes.length < 3) {
      return;
    }
    this.removeLoopOverlay(record.id);
    const points = this.loopPoints(record);
    const polygon = new Polygon({
      points: points,
      fillcolor: DebugLoopStore.resolveFillColor(record),
      stroke: new Stroke({ color: record.strokeColor, strokeWidth: record.strokeWidth }),
      isClickable: true
    });
    polygon.setClickable(true);
    const polyline = new Polyline({
      points: points,
      width: record.strokeWidth + 1,
      strokeColor: record.strokeColor,
      strokeWidth: record.strokeWidth,
      fillcolor: record.strokeColor
    });
    const centroid = this.loopCentroid(record);
    // 名称标签略偏北，广告占浅色填充区中心
    const labelPos = new LatLng(centroid.lat + 0.00018, centroid.lng);
    const label = new Label({
      position: labelPos,
      text: `${record.name} (${DebugLoopStore.ownerLabel(record.ownerId)})`,
      fontsize: 14,
      fontcolorstr: '#FFFFFF',
      bordercolorstr: record.strokeColor,
      bordersize: 2
    });
    this.mapController.addOverlay(polygon);
    this.mapController.addOverlay(polyline);
    this.mapController.addOverlay(label);
    this.loopOverlayIds.push(record.id);
    this.loopOverlayPolygons.push(polygon);
    this.loopOverlayPolylines.push(polyline);
    this.loopOverlayLabels.push(label);
    void this.refreshLoopAdOverlay(record);
  }

  private async refreshLoopAdOverlay(record: DebugLoopRecord): Promise<void> {
    this.removeLoopAdOverlay(record.id);
    if (!this.mapController || record.adEnabled !== true) {
      return;
    }
    this.bindLoopAdScaleListener();
    const imageUri = record.adImageUri !== undefined ? record.adImageUri : '';
    if (imageUri.length === 0) {
      return;
    }
    const slogan = record.adTitle !== undefined ? record.adTitle.trim() : '';
    const pixelMap = await this.createAdPhotoSloganPixelMap(imageUri, slogan);
    const latest = this.getLoopById(record.id);
    if (pixelMap === null || !this.mapController || latest === null || latest.adEnabled !== true) {
      this.debugMessage = '广告图片加载失败，请重新插入图片后保存';
      hilog.error(LOG_DOMAIN, LOG_TAG, '[Ad] marker pixelmap failed loopId=%{public}d uri=%{public}s',
        record.id, imageUri);
      return;
    }
    this.removeLoopAdOverlay(record.id);
    const centroid = this.loopCentroid(latest);
    const scale = this.computeAdMarkerScale(latest);
    const icon = new ImageEntity(pixelMap, vp2px(LOOP_AD_ICON_WIDTH_VP), vp2px(LOOP_AD_ICON_HEIGHT_VP));
    const marker = new Marker({
      position: centroid,
      icon: icon,
      located: SysEnum.Located.CENTER,
      isPerspective: false,
      isClickable: false,
      scaleX: scale,
      scaleY: scale,
      yOffset: 0
    });
    this.mapController.addOverlay(marker);
    this.loopAdMarkers.set(record.id, marker);
    this.debugMessage = `广告已按闭环缩放显示 · ×${scale.toFixed(2)}`;
    hilog.info(LOG_DOMAIN, LOG_TAG, '[Ad] marker shown loopId=%{public}d scale=%{public}s sloganLen=%{public}d',
      record.id, `${scale}`, slogan.length);
  }

  @Builder
  loopAdPhotoSloganBuilder() {
    Column() {
      Image(this.adPreviewUri)
        .width(LOOP_AD_ICON_WIDTH_VP)
        .height(this.adPreviewSlogan.length > 0 ? 78 : LOOP_AD_ICON_HEIGHT_VP)
        .objectFit(ImageFit.Cover)
      if (this.adPreviewSlogan.length > 0) {
        Text(this.adPreviewSlogan)
          .width('100%')
          .fontSize(11)
          .fontColor('#FFFFFF')
          .fontWeight(FontWeight.Medium)
          .maxLines(2)
          .textAlign(TextAlign.Center)
          .padding({ left: 6, right: 6, top: 6, bottom: 6 })
          .backgroundColor('#000000')
      }
    }
    .width(LOOP_AD_ICON_WIDTH_VP)
    .clip(true)
    .borderRadius(8)
    .backgroundColor('#000000')
  }

  private async createAdPhotoSloganPixelMap(imageUri: string, slogan: string): Promise<image.PixelMap | null> {
    const displayUri = LoopAdComposer.toDisplayUri(imageUri);
    const cacheKey = `${LOOP_AD_ICON_CACHE_VERSION}|${displayUri}|${slogan}`;
    const cached = this.loopAdIconCache.get(cacheKey);
    if (cached !== undefined) {
      return cached;
    }

    // 方案1：快照合成（上图下口号）——与物品图标同一套 ComponentSnapshot
    this.adPreviewUri = displayUri;
    this.adPreviewSlogan = slogan;
    try {
      await new Promise<void>((resolve: () => void) => {
        setTimeout(() => {
          resolve();
        }, 280);
      });
      const snapshot = this.getUIContext().getComponentSnapshot();
      const fromBuilder = await snapshot.createFromBuilder(() => {
        this.loopAdPhotoSloganBuilder();
      }, 320, true);
      this.loopAdIconCache.set(cacheKey, fromBuilder);
      hilog.info(LOG_DOMAIN, LOG_TAG, '[Ad] snapshot card ok');
      return fromBuilder;
    } catch (error) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, '[Ad] snapshot failed %{public}s', JSON.stringify(error));
    }

    // 方案2：至少把原图贴上 Marker（口号可能丢失，但图片必须可见）
    const photoOnly = await LoopAdComposer.loadPhotoPixelMap(imageUri);
    if (photoOnly !== null) {
      this.loopAdIconCache.set(cacheKey, photoOnly);
      hilog.info(LOG_DOMAIN, LOG_TAG, '[Ad] fallback photo-only pixelmap ok');
      return photoOnly;
    }
    return null;
  }

  private async pickLoopAdImage(): Promise<void> {
    try {
      const picker = new photoAccessHelper.PhotoViewPicker();
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      const result = await picker.select(options);
      if (result.photoUris.length === 0) {
        return;
      }
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      this.debugMessage = '正在保存广告图片...';
      const localPath = await LoopAdComposer.persistPhoto(context, result.photoUris[0]);
      if (localPath === null) {
        this.draftAdImageUri = result.photoUris[0];
        this.debugMessage = '图片沙箱保存失败，将尝试用原图显示';
      } else {
        this.draftAdImageUri = localPath;
        this.debugMessage = '已插入广告图片，保存后显示在闭环内';
      }
      this.draftAdEnabled = true;
      this.loopAdIconCache.clear();
    } catch (error) {
      this.debugMessage = '未选择广告图片';
      hilog.error(LOG_DOMAIN, LOG_TAG, '[Ad] pick image failed %{public}s', JSON.stringify(error));
    }
  }

  private selectDraftAdPreset(presetId: string): void {
    this.draftAdPresetId = presetId;
    this.draftAdEnabled = true;
    const preset = LoopAdCatalog.getById(presetId);
    if (preset !== null && this.draftAdTitle.trim().length === 0) {
      this.draftAdTitle = preset.slogan;
    }
  }

  private clearDraftAd(): void {
    this.draftAdEnabled = false;
    this.draftAdPresetId = '';
    this.draftAdTitle = '';
    this.draftAdImageUri = '';
  }

  private resolveLoopOwnerId(record: DebugLoopRecord): string {
    const ownerId = record.ownerId;
    if (ownerId !== undefined && ownerId.length > 0) {
      return ownerId;
    }
    return 'user_a';
  }

  private refreshAllLoopOverlays(): void {
    this.clearAllLoopOverlays();
    const loops = this.getAllDisplayLoops();
    const others: Array<DebugLoopRecord> = [];
    const mine: Array<DebugLoopRecord> = [];
    for (let i = 0; i < loops.length; i++) {
      const ownerId = this.resolveLoopOwnerId(loops[i]);
      if (ownerId === this.currentDebugUserId) {
        mine.push(loops[i]);
      } else {
        others.push(loops[i]);
      }
    }
    for (let i = 0; i < others.length; i++) {
      this.refreshLoopOverlay(others[i]);
    }
    for (let i = 0; i < mine.length; i++) {
      this.refreshLoopOverlay(mine[i]);
    }
  }

  private refreshActiveTrackOverlay(): void {
    if (!this.mapController || this.activeTrackPoints.length < 2) {
      return;
    }
    const points = this.getTrackOverlayPoints();
    if (points.length < 2) {
      return;
    }
    for (let i = 0; i < points.length; i++) {
      if (!this.isValidCoordinate(points[i].lat, points[i].lng)) {
        // #region agent log
        hilog.warn(LOG_DOMAIN, LOG_TAG, '[N] skip overlay invalid point index=%{public}d', i);
        // #endregion
        return;
      }
    }
    if (this.activeTrackOverlay) {
      this.mapController.removeOverlay(this.activeTrackOverlay);
      this.activeTrackOverlay = null;
    }
    this.activeTrackOverlay = new Polyline({
      points: points,
      width: 3,
      strokeColor: '#888888',
      strokeWidth: 2,
      fillcolor: '#888888'
    });
    this.mapController.addOverlay(this.activeTrackOverlay);
    // #region agent log
    hilog.info(LOG_DOMAIN, LOG_TAG, '[N] track overlay rebuilt total=%{public}d overlay=%{public}d',
      this.activeTrackPoints.length, points.length);
    // #endregion
  }

  private setupMapInteraction(): void {
    if (!this.mapController) {
      return;
    }
    const mapClickListener: IMapClickListener = {
      onClickedBackground: (x: number, y: number) => {
        this.recordLoopTapInteraction(x, y, 'background');
      }
    };
    this.mapController.setMapClickListener(mapClickListener);
    const touchListener: OnTouchListener = {
      onTouchMessage: (msg: MapTouchType, x: number, y: number) => {
        this.lastMapTapX = x;
        this.lastMapTapY = y;
        if (this.joystickCapturing || this.showPlacementDialog || this.showLoopEditDialog || this.showTrapDialog || this.showTrapSetupDialog || this.showLoopInfoDialog) {
          return;
        }
        if (msg === MapTouchType.SINGLE_FINGER_LONG_PRESS_START) {
          this.clearPendingLoopSingleTap();
          this.loopTapCandidateTimeMs = 0;
          return;
        }
        if (msg === MapTouchType.SINGLE_FINGER_LONG_PRESS) {
          this.clearPendingLoopSingleTap();
          this.loopTapCandidateTimeMs = 0;
          // #region agent log
          hilog.info(LOG_DOMAIN, LOG_TAG, '[LP] sdk long press x=%{public}d y=%{public}d', x, y);
          // #endregion
          this.handleMapLongPress(x, y);
          return;
        }
        if (msg === MapTouchType.SINGLE_FINGER_DOUBLE_TAP) {
          this.clearPendingLoopSingleTap();
          this.loopTapCandidateTimeMs = 0;
          // #region agent log
          hilog.info(LOG_DOMAIN, LOG_TAG, '[J] sdk double tap x=%{public}d y=%{public}d', x, y);
          // #endregion
          this.handleMapDoubleTap(x, y);
          return;
        }
        if (msg === MapTouchType.SINGLE_FINGER_TAP) {
          this.recordLoopTapInteraction(x, y, 'touch');
        }
      }
    };
    this.mapController.setOnTouchMessageListener(touchListener);
    this.mapController.addOverlayEventListener(
      EOverLayTypeName.POLYGON,
      OverlayEvent.CLICK,
      (bundle: EventOverlayBundle) => {
        this.handlePolygonOverlayClick(bundle);
      }
    );
  }

  private screenToLatLng(x: number, y: number): LatLng | null {
    if (!this.mapController?.bmMapCtr) {
      return null;
    }
    const geo = this.mapController.bmMapCtr.screenPointToGeoPoint(x, y);
    if (geo === null) {
      return null;
    }
    const mcPoint = new Point(geo.x, geo.y);
    return NativeMethods.mc2ll(mcPoint);
  }

  private buildPlacedItemLabelText(record: PlacedItemRecord, itemType: PlaceableItemType): string {
    if (record.itemTypeId === 'trap') {
      return `${itemType.icon} ${itemType.name} ${this.resolveTrapDiamondCost(record)}💎`;
    }
    return `${itemType.icon} ${itemType.name}`;
  }

  @Builder
  itemEmojiBadgeBuilder() {
    Text(this.itemBadgeText)
      .fontSize(6)
      .fontWeight(FontWeight.Medium)
      .fontColor('#A5D8FF')
      .maxLines(1)
      .textShadow({ radius: 1, color: '#00000088', offsetX: 0, offsetY: 0 })
      .backgroundColor(Color.Transparent)
      .padding(0)
  }

  private async createItemIconPixelMap(text: string, color: string): Promise<image.PixelMap | null> {
    const cacheKey = `${ITEM_ICON_CACHE_VERSION}|${text}|${color}`;
    const cached = this.itemIconCache.get(cacheKey);
    if (cached !== undefined) {
      return cached;
    }
    this.itemBadgeText = text;
    this.itemBadgeColor = color;
    try {
      const snapshot = this.getUIContext().getComponentSnapshot();
      const pixelMap = await snapshot.createFromBuilder(() => {
        this.itemEmojiBadgeBuilder();
      }, 40, false);
      this.itemIconCache.set(cacheKey, pixelMap);
      // #region agent log
      hilog.info(LOG_DOMAIN, LOG_TAG, '[H] emoji pixelmap created text=%{public}s', text);
      // #endregion
      return pixelMap;
    } catch (error) {
      // #region agent log
      hilog.error(LOG_DOMAIN, LOG_TAG, '[H] emoji pixelmap failed %{public}s', JSON.stringify(error));
      // #endregion
      return null;
    }
  }

  private loopCentroid(record: DebugLoopRecord): LatLng {
    const points = this.loopPoints(record);
    let latSum = 0;
    let lngSum = 0;
    for (let i = 0; i < points.length; i++) {
      latSum += points[i].lat;
      lngSum += points[i].lng;
    }
    const count = Math.max(1, points.length);
    return new LatLng(latSum / count, lngSum / count);
  }

  private handlePolygonOverlayClick(bundle: EventOverlayBundle): void {
    if (this.joystickCapturing || this.showPlacementDialog || this.showLoopEditDialog || this.showTrapDialog || this.showTrapSetupDialog || this.showLoopInfoDialog) {
      return;
    }
    const target = bundle.target;
    if (target === undefined) {
      return;
    }
    for (let i = 0; i < this.loopOverlayPolygons.length; i++) {
      if (this.loopOverlayPolygons[i] === target) {
        // #region agent log
        hilog.info(LOG_DOMAIN, LOG_TAG, '[E] polygon click loopId=%{public}d x=%{public}d y=%{public}d', this.loopOverlayIds[i], this.lastMapTapX, this.lastMapTapY);
        // #endregion
        this.recordLoopTapInteraction(this.lastMapTapX, this.lastMapTapY, 'polygon');
        return;
      }
    }
  }

  private clearPendingLoopSingleTap(): void {
    if (this.pendingSingleTapTimer >= 0) {
      clearTimeout(this.pendingSingleTapTimer);
      this.pendingSingleTapTimer = -1;
    }
  }

  private isDuplicateLoopTapDelivery(x: number, y: number, nowMs: number): boolean {
    if (this.loopTapDeliveryTimeMs <= 0) {
      return false;
    }
    const elapsed = nowMs - this.loopTapDeliveryTimeMs;
    const dx = x - this.loopTapDeliveryX;
    const dy = y - this.loopTapDeliveryY;
    return elapsed < LOOP_TAP_DEDUPE_MS && Math.sqrt(dx * dx + dy * dy) < LOOP_DOUBLE_TAP_MAX_DISTANCE;
  }

  private recordLoopTapInteraction(x: number, y: number, source: string): void {
    if (this.joystickCapturing || this.showPlacementDialog || this.showLoopEditDialog || this.showTrapDialog || this.showTrapSetupDialog || this.showLoopInfoDialog) {
      return;
    }
    this.lastMapTapX = x;
    this.lastMapTapY = y;
    const nowMs = Date.now();
    if (this.isDuplicateLoopTapDelivery(x, y, nowMs)) {
      // #region agent log
      hilog.info(LOG_DOMAIN, LOG_TAG, '[J] tap deduped source=%{public}s x=%{public}d y=%{public}d', source, x, y);
      // #endregion
      return;
    }
    this.loopTapDeliveryTimeMs = nowMs;
    this.loopTapDeliveryX = x;
    this.loopTapDeliveryY = y;

    if (this.loopTapCandidateTimeMs > 0) {
      const elapsed = nowMs - this.loopTapCandidateTimeMs;
      const dx = x - this.loopTapCandidateX;
      const dy = y - this.loopTapCandidateY;
      const distance = Math.sqrt(dx * dx + dy * dy);
      if (elapsed <= LOOP_DOUBLE_TAP_WINDOW_MS && distance <= LOOP_DOUBLE_TAP_MAX_DISTANCE) {
        this.clearPendingLoopSingleTap();
        this.loopTapCandidateTimeMs = 0;
        // #region agent log
        hilog.info(LOG_DOMAIN, LOG_TAG, '[J] manual double tap source=%{public}s dt=%{public}d dist=%{public}d', source, elapsed, Math.round(distance));
        // #endregion
        this.handleMapDoubleTap(x, y);
        return;
      }
    }

    this.loopTapCandidateTimeMs = nowMs;
    this.loopTapCandidateX = x;
    this.loopTapCandidateY = y;
    this.clearPendingLoopSingleTap();
    // #region agent log
    hilog.info(LOG_DOMAIN, LOG_TAG, '[J] single tap scheduled source=%{public}s x=%{public}d y=%{public}d', source, x, y);
    // #endregion
    this.pendingSingleTapTimer = setTimeout(() => {
      this.pendingSingleTapTimer = -1;
      this.loopTapCandidateTimeMs = 0;
      this.handleMapTap(x, y);
    }, LOOP_DOUBLE_TAP_WINDOW_MS);
  }

  private getOwnedLoops(): Array<DebugLoopRecord> {
    const loops = this.getAllDisplayLoops();
    const owned: Array<DebugLoopRecord> = [];
    for (let i = 0; i < loops.length; i++) {
      const ownerId = this.resolveLoopOwnerId(loops[i]);
      if (ownerId === this.currentDebugUserId) {
        owned.push(loops[i]);
      }
    }
    return owned;
  }

  private collectOtherUserLoops(ownerId: string): Array<DebugLoopRecord> {
    const loops = this.getAllDisplayLoops();
    const others: Array<DebugLoopRecord> = [];
    for (let i = 0; i < loops.length; i++) {
      const loopOwner = this.resolveLoopOwnerId(loops[i]);
      if (loopOwner !== ownerId) {
        others.push(loops[i]);
      }
    }
    return others;
  }

  private containsLoopId(ids: Array<number>, loopId: number): boolean {
    for (let i = 0; i < ids.length; i++) {
      if (ids[i] === loopId) {
        return true;
      }
    }
    return false;
  }

  private isLoopPending(loopId: number): boolean {
    return this.isPendingLoop(loopId);
  }

  private resolveTerritoryConquest(attacker: DebugLoopRecord): number {
    const attackerOwner = this.resolveLoopOwnerId(attacker);
    const victims = this.collectOtherUserLoops(attackerOwner);
    const removeIds: Array<number> = [];
    const replacementMap: Map<number, DebugLoopRecord> = new Map();
    const pendingAdditions: Array<DebugLoopRecord> = [];
    const savedAdditions: Array<DebugLoopRecord> = [];
    const affectedOwners: Array<string> = [attackerOwner];
    let conqueredArea = 0;
    let savedMutated = false;

    for (let i = 0; i < victims.length; i++) {
      const victim = victims[i];
      if (victim.id === attacker.id || !PolygonClipper.overlaps(attacker, victim)) {
        continue;
      }
      const victimOwner = this.resolveLoopOwnerId(victim);
      let ownerKnown = false;
      for (let o = 0; o < affectedOwners.length; o++) {
        if (affectedOwners[o] === victimOwner) {
          ownerKnown = true;
          break;
        }
      }
      if (!ownerKnown) {
        affectedOwners.push(victimOwner);
      }
      conqueredArea += PolygonClipper.intersectionArea(attacker, victim);
      removeIds.push(victim.id);
      const remainRings = PolygonClipper.subtract(attacker, victim);
      const origin = new LatLng(
        (attacker.latitudes[0] + victim.latitudes[0]) / 2,
        (attacker.longitudes[0] + victim.longitudes[0]) / 2
      );
      if (remainRings.length === 0) {
        // 领地被完全吃掉：本地移除 + 后端显式删除
        this.queueLoopDeletion(victimOwner, victim.id);
        if (!this.isLoopPending(victim.id)) {
          savedMutated = true;
        }
        continue;
      }
      for (let r = 0; r < remainRings.length; r++) {
        const fragmentId = r === 0 ? victim.id : this.nextLoopId++;
        const fragmentName = r === 0 ? victim.name : `${victim.name}-${r + 1}`;
        const fragment = PolygonClipper.ringToRecord(remainRings[r], origin, victim, fragmentId, fragmentName);
        if (fragment === null) {
          continue;
        }
        // #region agent log
        hilog.info(LOG_DOMAIN, LOG_TAG, '[L] fragment victim=%{public}d before=%{public}d after=%{public}d ringPts=%{public}d',
          victim.id, victim.latitudes.length, fragment.latitudes.length, remainRings[r].length);
        // #endregion
        if (r === 0) {
          replacementMap.set(victim.id, fragment);
        } else if (this.isLoopPending(victim.id)) {
          pendingAdditions.push(fragment);
        } else {
          savedAdditions.push(fragment);
          savedMutated = true;
        }
      }
      if (!replacementMap.has(victim.id)) {
        // 切割后无有效残留 → 等同整块删除
        this.queueLoopDeletion(victimOwner, victim.id);
      }
      if (!this.isLoopPending(victim.id)) {
        savedMutated = true;
      }
    }

    if (removeIds.length === 0) {
      return 0;
    }

    this.pendingLoops = this.applyConquestToLoops(this.pendingLoops, removeIds, replacementMap, pendingAdditions);
    this.savedLoops = this.applyConquestToLoops(this.savedLoops, removeIds, replacementMap, savedAdditions);
    for (let i = 0; i < removeIds.length; i++) {
      // 无 replacement 的 id 表示整块删除，清理放置物；有 replacement 时 loopId 仍保留
      if (!replacementMap.has(removeIds[i])) {
        this.removePlacedItemsForLoop(removeIds[i], false);
      }
    }
    this.purgePlacedItemsForMissingLoops();
    // #region agent log
    hilog.info(LOG_DOMAIN, LOG_TAG,
      '[DBG8add10] conquest owner=%{public}s area=%{public}f victims=%{public}d owners=%{public}d',
      attackerOwner, conqueredArea, removeIds.length, affectedOwners.length);
    // #endregion
    if (savedMutated || affectedOwners.length > 1) {
      setTimeout(() => {
        void this.persistAndPushOwners(affectedOwners);
      }, 0);
    }
    return conqueredArea;
  }

  private applyConquestToLoops(
    source: Array<DebugLoopRecord>,
    removeIds: Array<number>,
    replacementMap: Map<number, DebugLoopRecord>,
    additions: Array<DebugLoopRecord>
  ): Array<DebugLoopRecord> {
    const next: Array<DebugLoopRecord> = [];
    for (let i = 0; i < source.length; i++) {
      const loop = source[i];
      if (this.containsLoopId(removeIds, loop.id)) {
        const replacement = replacementMap.get(loop.id);
        if (replacement !== undefined) {
          next.push(replacement);
        }
        continue;
      }
      next.push(loop);
    }
    for (let i = 0; i < additions.length; i++) {
      next.push(additions[i]);
    }
    return next;
  }

  private switchDebugUser(userId: string): void {
    this.currentDebugUserId = userId;
    // 切换用户后重置已触发陷阱，便于另一用户复测踩踏
    this.triggeredTrapIds = [];
    if (userId === 'user_b') {
      this.draftStrokeColor = DEBUG_USER_B_COLOR;
      this.draftColorText = DEBUG_USER_B_COLOR;
      this.draftFillColor = DebugLoopStore.toFillColor(DEBUG_USER_B_COLOR);
      this.draftFillColorText = this.draftFillColor;
    } else {
      this.draftStrokeColor = DEBUG_USER_A_COLOR;
      this.draftColorText = DEBUG_USER_A_COLOR;
      this.draftFillColor = DebugLoopStore.toFillColor(DEBUG_USER_A_COLOR);
      this.draftFillColorText = this.draftFillColor;
    }
    this.debugMessage = `当前调试用户：${DebugLoopStore.ownerLabel(userId)} · 钻石 ${this.getUserDiamonds(userId)}`;
    void this.connectBackendAndSync(false);
  }

  private getUserDiamonds(userId: string): number {
    return userId === 'user_b' ? this.userBDiamonds : this.userADiamonds;
  }

  private setUserDiamonds(userId: string, amount: number): void {
    const safeAmount = Math.max(0, Math.round(amount));
    if (userId === 'user_b') {
      this.userBDiamonds = safeAmount;
    } else {
      this.userADiamonds = safeAmount;
    }
  }

  private getCurrentUserDiamonds(): number {
    return this.getUserDiamonds(this.currentDebugUserId);
  }

  private async saveDebugDiamonds(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const store = await preferences.getPreferences(context, { name: 'debug_territory' });
      await store.put('userADiamonds', this.userADiamonds);
      await store.put('userBDiamonds', this.userBDiamonds);
      await store.flush();
      void this.syncTerritoryToBackend();
    } catch (error) {
      console.error(`Save debug diamonds failed: ${JSON.stringify(error)}`);
    }
  }

  private async restoreDebugDiamonds(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const store = await preferences.getPreferences(context, { name: 'debug_territory' });
      this.userADiamonds = Number(await store.get('userADiamonds', DEFAULT_DEBUG_DIAMONDS));
      this.userBDiamonds = Number(await store.get('userBDiamonds', DEFAULT_DEBUG_DIAMONDS));
      if (this.userADiamonds < 0) {
        this.userADiamonds = DEFAULT_DEBUG_DIAMONDS;
      }
      if (this.userBDiamonds < 0) {
        this.userBDiamonds = DEFAULT_DEBUG_DIAMONDS;
      }
    } catch (error) {
      console.error(`Restore debug diamonds failed: ${JSON.stringify(error)}`);
    }
  }

  private containsTrapId(trapId: number): boolean {
    for (let i = 0; i < this.triggeredTrapIds.length; i++) {
      if (this.triggeredTrapIds[i] === trapId) {
        return true;
      }
    }
    return false;
  }

  private markTrapTriggered(trapId: number): void {
    if (this.containsTrapId(trapId)) {
      return;
    }
    this.triggeredTrapIds.push(trapId);
  }

  private resolveTrapDiamondCost(item: PlacedItemRecord): number {
    if (item.diamondCost !== undefined && item.diamondCost > 0) {
      return Math.round(item.diamondCost);
    }
    return TerritoryItemDefaults.TRAP_DIAMOND_COST;
  }

  private getTrapApproachDistanceMeters(item: PlacedItemRecord, location: LatLng, previousLocation: LatLng | null): number {
    const trapPos = new LatLng(item.lat, item.lng);
    let minDist = LoopDetector.distanceMeters(location, trapPos);
    if (previousLocation !== null) {
      const segmentDist = LoopDetector.distancePointToSegmentMeters(trapPos, previousLocation, location);
      minDist = Math.min(minDist, segmentDist);
      const midLat = (location.lat + previousLocation.lat) / 2;
      const midLng = (location.lng + previousLocation.lng) / 2;
      const midDist = LoopDetector.distanceMeters(new LatLng(midLat, midLng), trapPos);
      minDist = Math.min(minDist, midDist);
    }
    return minDist;
  }

  private resolveTrapOwnerId(item: PlacedItemRecord): string {
    if (item.ownerId !== undefined && item.ownerId.length > 0) {
      return item.ownerId;
    }
    if (item.loopId === TerritoryItemDefaults.WORLD_RESOURCE_LOOP_ID) {
      return TerritoryItemDefaults.WORLD_TRAP_OWNER_ID;
    }
    const loop = this.getLoopById(item.loopId);
    if (loop !== null) {
      return this.resolveLoopOwnerId(loop);
    }
    return TerritoryItemDefaults.WORLD_TRAP_OWNER_ID;
  }

  private checkTrapCollisions(location: LatLng, previousLocation: LatLng | null): void {
    if (this.showTrapDialog || (!this.debugMode && !this.joystickCapturing && !this.joystickActive)) {
      return;
    }
    for (let i = 0; i < this.placedItems.length; i++) {
      const item = this.placedItems[i];
      if (item.itemTypeId !== 'trap' || this.containsTrapId(item.id)) {
        continue;
      }
      const trapOwner = this.resolveTrapOwnerId(item);
      if (trapOwner === this.currentDebugUserId) {
        continue;
      }
      const approachDist = this.getTrapApproachDistanceMeters(item, location, previousLocation);
      if (approachDist > TerritoryItemDefaults.TRAP_HIT_RADIUS_METERS) {
        continue;
      }
      this.handleTrapHit(item, trapOwner);
      return;
    }
  }

  private handleTrapHit(item: PlacedItemRecord, trapOwnerId: string): void {
    this.releaseJoystick();
    this.trappedTrapItemId = item.id;
    this.trappedTrapCost = this.resolveTrapDiamondCost(item);
    this.trappedTrapOwnerId = trapOwnerId;
    this.trappedTrapOwnerLabel = DebugLoopStore.ownerLabel(trapOwnerId);
    this.showTrapDialog = true;
    this.debugMessage = `掉进${this.trappedTrapOwnerLabel}的陷阱！`;
    // #region agent log
    hilog.info(LOG_DOMAIN, LOG_TAG, '[T] trap hit runner=%{public}s owner=%{public}s cost=%{public}d trapId=%{public}d loopId=%{public}d',
      this.currentDebugUserId, trapOwnerId, this.trappedTrapCost, item.id, item.loopId);
    // #endregion
  }

  private closeTrapDialog(): void {
    this.showTrapDialog = false;
    this.trappedTrapItemId = -1;
    this.trappedTrapCost = 0;
    this.trappedTrapOwnerId = '';
    this.trappedTrapOwnerLabel = '';
  }

  private payTrapDiamonds(): void {
    const cost = this.trappedTrapCost;
    const runnerBalance = this.getCurrentUserDiamonds();
    if (runnerBalance < cost) {
      this.debugMessage = `钻石不足，需要 ${cost}，当前 ${runnerBalance}`;
      return;
    }
    this.setUserDiamonds(this.currentDebugUserId, runnerBalance - cost);
    this.setUserDiamonds(this.trappedTrapOwnerId, this.getUserDiamonds(this.trappedTrapOwnerId) + cost);
    this.markTrapTriggered(this.trappedTrapItemId);
    this.saveDebugDiamonds();
    this.closeTrapDialog();
    this.debugMessage = `已支付 ${cost} 钻石，成功脱困，可继续圈地`;
    // #region agent log
    hilog.info(LOG_DOMAIN, LOG_TAG, '[T] trap paid runner=%{public}s owner=%{public}s cost=%{public}d',
      this.currentDebugUserId, this.trappedTrapOwnerId, cost);
    // #endregion
  }

  private failTrapEncounter(): void {
    const trapId = this.trappedTrapItemId;
    this.markTrapTriggered(trapId);
    this.closeTrapDialog();
    this.resetActiveTrack();
    this.debugMessage = '圈地失败：未支付钻石，轨迹已重置';
    // #region agent log
    hilog.info(LOG_DOMAIN, LOG_TAG, '[T] trap failed runner=%{public}s trapId=%{public}d',
      this.currentDebugUserId, trapId);
    // #endregion
  }

  private openTrapSetupDialog(): void {
    this.trapSetupCostText = `${TerritoryItemDefaults.TRAP_DIAMOND_COST}`;
    this.showPlacementDialog = false;
    this.showTrapSetupDialog = true;
  }

  private closeTrapSetupDialog(): void {
    this.showTrapSetupDialog = false;
    this.trapSetupCostText = `${TerritoryItemDefaults.TRAP_DIAMOND_COST}`;
  }

  private confirmPlaceTrap(): void {
    const parsed = Number(this.trapSetupCostText);
    const diamondCost = Number.isFinite(parsed) && parsed > 0 ? Math.round(parsed) : TerritoryItemDefaults.TRAP_DIAMOND_COST;
    this.placeItem('trap', diamondCost);
    this.closeTrapSetupDialog();
  }

  private handleMapTap(x: number, y: number): void {
    const tapPoint = this.screenToLatLng(x, y);
    if (tapPoint === null) {
      hilog.info(LOG_DOMAIN, LOG_TAG, '[D] map tap geo convert failed x=%{public}d y=%{public}d', x, y);
      return;
    }
    const loop = LoopDetector.findSmallestLoopAt(tapPoint.lat, tapPoint.lng, this.getOwnedLoops());
    const tapLog: MapTapLog = {
      x: x,
      y: y,
      lat: tapPoint.lat,
      lng: tapPoint.lng,
      loopCount: this.getOwnedLoops().length,
      hit: loop !== null ? loop.id : -1
    };
    // #region agent log
    hilog.info(LOG_DOMAIN, LOG_TAG, '[D] map tap %{public}s', JSON.stringify(tapLog));
    // #endregion
    if (loop === null) {
      return;
    }
    this.openPlacementDialog(loop, tapPoint.lat, tapPoint.lng);
  }

  private handleMapDoubleTap(x: number, y: number): void {
    this.clearPendingLoopSingleTap();
    this.loopTapCandidateTimeMs = 0;
    if (this.showPlacementDialog) {
      this.closePlacementDialog();
    }
    const tapPoint = this.screenToLatLng(x, y);
    if (tapPoint === null) {
      return;
    }
    const loop = LoopDetector.findSmallestLoopAt(tapPoint.lat, tapPoint.lng, this.getOwnedLoops());
    if (loop === null) {
      return;
    }
    const loopOwner = this.resolveLoopOwnerId(loop);
    if (loopOwner !== this.currentDebugUserId) {
      this.debugMessage = '这是对手的闭环，无法编辑';
      return;
    }
    // #region agent log
    hilog.info(LOG_DOMAIN, LOG_TAG, '[I] loop double tap loopId=%{public}d lat=%{public}f lng=%{public}f', loop.id, tapPoint.lat, tapPoint.lng);
    // #endregion
    this.openLoopEditDialog(loop);
  }

  private handleMapLongPress(x: number, y: number): void {
    if (this.joystickCapturing || this.showPlacementDialog || this.showLoopEditDialog || this.showTrapDialog || this.showTrapSetupDialog || this.showLoopInfoDialog) {
      return;
    }
    const tapPoint = this.screenToLatLng(x, y);
    if (tapPoint === null) {
      // #region agent log
      hilog.warn(LOG_DOMAIN, LOG_TAG, '[LP] long press geo failed x=%{public}d y=%{public}d', x, y);
      // #endregion
      return;
    }
    const loop = LoopDetector.findSmallestLoopAt(tapPoint.lat, tapPoint.lng, this.getAllDisplayLoops());
    // #region agent log
    hilog.info(LOG_DOMAIN, LOG_TAG, '[LP] long press loopId=%{public}d lat=%{public}f lng=%{public}f loops=%{public}d',
      loop !== null ? loop.id : -1, tapPoint.lat, tapPoint.lng, this.getAllDisplayLoops().length);
    // #endregion
    if (loop === null) {
      this.debugMessage = '此处没有闭环，请长按闭环区域';
      return;
    }
    this.openLoopInfoDialog(loop);
  }

  private openLoopInfoDialog(loop: DebugLoopRecord): void {
    const ownerId = this.resolveLoopOwnerId(loop);
    const areaM2 = LoopDetector.loopArea(loop);
    this.loopInfoName = loop.name;
    this.loopInfoOwnerLabel = DebugLoopStore.ownerLabel(ownerId);
    this.loopInfoOwnerColor = loop.strokeColor;
    this.loopInfoStatusLabel = this.isPendingLoop(loop.id) ? '待保存' : '已保存';
    this.loopInfoCreatedText = DebugLoopStore.formatDateTime(loop.createdAt);
    this.loopInfoCompletedText = DebugLoopStore.formatDateTime(loop.completedAt);
    this.loopInfoAreaText = DebugLoopStore.formatArea(areaM2);
    this.loopInfoPerimeterText = DebugLoopStore.formatDistance(loop.distance);
    this.loopInfoDurationText = DebugLoopStore.formatDuration(loop.durationSeconds);
    this.loopInfoPaceText = DebugLoopStore.formatPace(loop.avgSpeedKmh, loop.distance, loop.durationSeconds);
    this.loopInfoSpeedText = DebugLoopStore.formatSpeed(loop.avgSpeedKmh, loop.distance, loop.durationSeconds);
    this.showLoopInfoDialog = true;
    this.debugMessage = `查看「${loop.name}」详情`;
    // #region agent log
    hilog.info(LOG_DOMAIN, LOG_TAG, '[LP] info dialog opened loopId=%{public}d owner=%{public}s area=%{public}d dist=%{public}d',
      loop.id, ownerId, Math.round(areaM2), Math.round(loop.distance));
    // #endregion
  }

  private closeLoopInfoDialog(): void {
    this.showLoopInfoDialog = false;
  }

  private openPlacementDialog(loop: DebugLoopRecord, lat: number, lng: number): void {
    this.pendingPlacementLoopId = loop.id;
    this.pendingPlacementLoopName = loop.name;
    this.pendingPlacementLat = lat;
    this.pendingPlacementLng = lng;
    this.placementLoopId = loop.id;
    this.placementLoopName = loop.name;
    this.placementLat = lat;
    this.placementLng = lng;
    this.showPlacementDialog = true;
    this.selectLoop(loop.id);
    this.debugMessage = `在「${loop.name}」选点放置物品`;
    // #region agent log
    hilog.info(LOG_DOMAIN, LOG_TAG, '[F] placement dialog opened loopId=%{public}d lat=%{public}f lng=%{public}f', loop.id, lat, lng);
    // #endregion
  }

  private closePlacementDialog(): void {
    this.showPlacementDialog = false;
    this.placementLoopId = -1;
    this.placementLoopName = '';
    this.pendingPlacementLoopId = -1;
    this.pendingPlacementLoopName = '';
  }

  private nextResourceRandom(): number {
    this.resourceRandSeed = (this.resourceRandSeed * 1103515245 + 12345) % 2147483647;
    return this.resourceRandSeed / 2147483647;
  }

  private getResourceCenter(): LatLng | null {
    if (this.debugLocation !== null) {
      return this.debugLocation;
    }
    if (this.currentLocation !== null) {
      return this.currentLocation;
    }
    return new LatLng(DEFAULT_LATITUDE, DEFAULT_LONGITUDE);
  }

  private parseResourceRadiusKm(): number {
    const parsed = Number(this.resourceRadiusKmText);
    if (!Number.isFinite(parsed)) {
      return 1.5;
    }
    return Math.min(5, Math.max(0.3, parsed));
  }

  private parseResourceDensity(): number {
    const parsed = Number(this.resourceDensityText);
    if (!Number.isFinite(parsed)) {
      return 8;
    }
    return Math.min(30, Math.max(1, parsed));
  }

  private countWorldResources(): number {
    let count = 0;
    for (let i = 0; i < this.placedItems.length; i++) {
      if (this.placedItems[i].loopId === TerritoryItemDefaults.WORLD_RESOURCE_LOOP_ID) {
        count++;
      }
    }
    return count;
  }

  private randomPointInRadius(center: LatLng, radiusMeters: number): LatLng {
    const u = this.nextResourceRandom();
    const v = this.nextResourceRandom();
    const r = radiusMeters * Math.sqrt(u);
    const theta = 2 * Math.PI * v;
    const north = r * Math.cos(theta);
    const east = r * Math.sin(theta);
    const dLat = north / 111320;
    const dLng = east / (111320 * Math.cos(center.lat * Math.PI / 180));
    return new LatLng(center.lat + dLat, center.lng + dLng);
  }

  private spawnRandomWorldResources(): void {
    if (!this.mapController) {
      this.debugMessage = '地图未就绪，无法投放资源';
      return;
    }
    const center = this.getResourceCenter();
    if (center === null) {
      this.debugMessage = '无法确定投放中心点';
      return;
    }
    const radiusKm = this.parseResourceRadiusKm();
    const density = this.parseResourceDensity();
    this.resourceRadiusKmText = `${radiusKm}`;
    this.resourceDensityText = `${density}`;
    const areaKm2 = Math.PI * radiusKm * radiusKm;
    let count = Math.round(areaKm2 * density);
    count = Math.min(MAX_RANDOM_WORLD_RESOURCES, Math.max(1, count));
    const radiusMeters = radiusKm * 1000;
    const nextItems: Array<PlacedItemRecord> = [];
    for (let i = 0; i < this.placedItems.length; i++) {
      nextItems.push(this.placedItems[i]);
    }
    for (let i = 0; i < count; i++) {
      const itemType = TerritoryItemCatalog.pickRandomWorldResource(this.resourceRandSeed + i * 17);
      this.nextResourceRandom();
      const point = this.randomPointInRadius(center, radiusMeters);
      const placed: PlacedItemRecord = {
        id: this.nextPlacedItemId++,
        loopId: TerritoryItemDefaults.WORLD_RESOURCE_LOOP_ID,
        itemTypeId: itemType.id,
        lat: point.lat,
        lng: point.lng,
        diamondCost: itemType.id === 'trap' ? TerritoryItemDefaults.TRAP_DIAMOND_COST : undefined,
        ownerId: itemType.id === 'trap' ? TerritoryItemDefaults.WORLD_TRAP_OWNER_ID : undefined
      };
      nextItems.push(placed);
    }
    this.placedItems = nextItems;
    this.refreshAllPlacedItemOverlays();
    this.savePlacedItems();
    this.debugMessage = `已在 ${radiusKm}km 内随机投放 ${count} 个资源（密度 ${density}/km²）`;
    // #region agent log
    hilog.info(LOG_DOMAIN, LOG_TAG, '[R] spawn world resources count=%{public}d radiusKm=%{public}s density=%{public}s total=%{public}d',
      count, `${radiusKm}`, `${density}`, this.placedItems.length);
    // #endregion
  }

  private clearWorldResources(): void {
    const remaining: Array<PlacedItemRecord> = [];
    let removed = 0;
    for (let i = 0; i < this.placedItems.length; i++) {
      if (this.placedItems[i].loopId === TerritoryItemDefaults.WORLD_RESOURCE_LOOP_ID) {
        removed++;
      } else {
        remaining.push(this.placedItems[i]);
      }
    }
    if (removed === 0) {
      this.debugMessage = '没有可清除的世界资源';
      return;
    }
    this.placedItems = remaining;
    this.refreshAllPlacedItemOverlays();
    this.savePlacedItems();
    this.debugMessage = `已清除 ${removed} 个世界资源`;
  }

  private placeItem(itemTypeId: string, diamondCost: number = 0): void {
    const loopId = this.pendingPlacementLoopId;
    const lat = this.pendingPlacementLat;
    const lng = this.pendingPlacementLng;
    const loopName = this.pendingPlacementLoopName;
    if (loopId < 0) {
      // #region agent log
      hilog.info(LOG_DOMAIN, LOG_TAG, '[G] place rejected loopId=%{public}d lat=%{public}f lng=%{public}f', loopId, lat, lng);
      // #endregion
      return;
    }
    const itemType = TerritoryItemCatalog.getById(itemTypeId);
    if (itemType === null || !this.mapController) {
      return;
    }
    const placed: PlacedItemRecord = {
      id: this.nextPlacedItemId++,
      loopId: loopId,
      itemTypeId: itemTypeId,
      lat: lat,
      lng: lng,
      diamondCost: itemTypeId === 'trap' ? diamondCost : undefined,
      ownerId: itemTypeId === 'trap' ? this.currentDebugUserId : undefined
    };
    const nextItems: Array<PlacedItemRecord> = [];
    for (let i = 0; i < this.placedItems.length; i++) {
      nextItems.push(this.placedItems[i]);
    }
    nextItems.push(placed);
    this.placedItems = nextItems;
    this.refreshPlacedItemOverlayAsync(placed);
    this.savePlacedItems();
    this.closePlacementDialog();
    if (itemTypeId === 'trap') {
      this.debugMessage = `已在「${loopName}」放置陷阱（${diamondCost} 钻石）`;
    } else {
      this.debugMessage = `已在「${loopName}」放置${itemType.icon} ${itemType.name}`;
    }
    // #region agent log
    hilog.info(LOG_DOMAIN, LOG_TAG, '[G] placed %{public}s at lat=%{public}f lng=%{public}f overlays=%{public}d',
      itemTypeId, lat, lng, this.placedItemMarkers.length);
    // #endregion
  }

  private clearPlacedItemOverlays(): void {
    if (!this.mapController) {
      this.placedItemCircles = [];
      this.placedItemLabels = [];
      this.placedItemMarkers = [];
      return;
    }
    for (let i = 0; i < this.placedItemCircles.length; i++) {
      this.mapController.removeOverlay(this.placedItemCircles[i]);
    }
    for (let i = 0; i < this.placedItemLabels.length; i++) {
      this.mapController.removeOverlay(this.placedItemLabels[i]);
    }
    for (let i = 0; i < this.placedItemMarkers.length; i++) {
      this.mapController.removeOverlay(this.placedItemMarkers[i]);
    }
    this.placedItemCircles = [];
    this.placedItemLabels = [];
    this.placedItemMarkers = [];
  }

  private async refreshPlacedItemOverlayAsync(record: PlacedItemRecord): Promise<void> {
    if (!this.mapController) {
      // #region agent log
      hilog.info(LOG_DOMAIN, LOG_TAG, '[H] overlay skip no mapController id=%{public}d', record.id);
      // #endregion
      return;
    }
    const itemType = TerritoryItemCatalog.getById(record.itemTypeId);
    if (itemType === null) {
      return;
    }
    const labelText = this.buildPlacedItemLabelText(record, itemType);
    const pixelMap = await this.createItemIconPixelMap(labelText, itemType.color);
    if (pixelMap === null || !this.mapController) {
      return;
    }
    const icon = new ImageEntity(pixelMap, vp2px(ITEM_ICON_WIDTH_VP), vp2px(ITEM_ICON_HEIGHT_VP));
    const marker = new Marker({
      position: new LatLng(record.lat, record.lng),
      icon: icon,
      located: SysEnum.Located.CENTER,
      isPerspective: true,
      isClickable: false,
      scaleX: 1,
      scaleY: 1,
      yOffset: 0
    });
    this.mapController.addOverlay(marker);
    this.placedItemMarkers.push(marker);
    // #region agent log
    hilog.info(LOG_DOMAIN, LOG_TAG, '[H] emoji marker added %{public}s text=%{public}s total=%{public}d',
      record.itemTypeId, labelText, this.placedItemMarkers.length);
    // #endregion
  }

  private refreshAllPlacedItemOverlays(): void {
    this.clearPlacedItemOverlays();
    const generation = ++this.itemOverlayGeneration;
    this.refreshAllPlacedItemOverlaysAsync(generation);
  }

  private async refreshAllPlacedItemOverlaysAsync(generation: number): Promise<void> {
    let added = 0;
    for (let i = 0; i < this.placedItems.length; i++) {
      if (generation !== this.itemOverlayGeneration) {
        return;
      }
      await this.refreshPlacedItemOverlayAsync(this.placedItems[i]);
      added++;
    }
    // #region agent log
    hilog.info(LOG_DOMAIN, LOG_TAG, '[H] emoji markers refresh done added=%{public}d totalItems=%{public}d gen=%{public}d',
      added, this.placedItems.length, generation);
    // #endregion
  }

  private async savePlacedItems(skipPull: boolean = true): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const store = await preferences.getPreferences(context, { name: 'debug_territory' });
      await store.put('placedItems', TerritoryItemStore.serializeItems(this.placedItems));
      await store.put('nextPlacedItemId', this.nextPlacedItemId);
      await store.flush();
      // 默认 skipPull，避免拉取把刚删除/刚切割的本地领地冲掉
      void this.syncTerritoryToBackend(true, undefined, skipPull);
    } catch (error) {
      console.error(`Save placed items failed: ${JSON.stringify(error)}`);
    }
  }

  private async restorePlacedItems(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const store = await preferences.getPreferences(context, { name: 'debug_territory' });
      const itemsJson = String(await store.get('placedItems', ''));
      if (itemsJson.length === 0) {
        return;
      }
      this.placedItems = TerritoryItemStore.parseItems(itemsJson);
      this.nextPlacedItemId = Number(await store.get('nextPlacedItemId', 1));
      if (this.nextPlacedItemId < 1) {
        this.nextPlacedItemId = 1;
      }
      let backfilled = false;
      for (let i = 0; i < this.placedItems.length; i++) {
        if (this.placedItems[i].id >= this.nextPlacedItemId) {
          this.nextPlacedItemId = this.placedItems[i].id + 1;
        }
        const item = this.placedItems[i];
        if (item.itemTypeId === 'trap' && (item.ownerId === undefined || item.ownerId.length === 0)) {
          item.ownerId = this.resolveTrapOwnerId(item);
          backfilled = true;
        }
      }
      if (backfilled) {
        this.savePlacedItems();
      }
      this.refreshAllPlacedItemOverlays();
    } catch (error) {
      console.error(`Restore placed items failed: ${JSON.stringify(error)}`);
    }
  }

  private applyImportedTerritory(bundle: TerritoryExportBundle): void {
    this.releaseJoystick();
    this.closeTrapDialog();
    this.closePlacementDialog();
    this.closeTrapSetupDialog();
    this.closeLoopEditDialog(false);
    const savedLoops: Array<DebugLoopRecord> = [];
    for (let i = 0; i < bundle.savedLoops.length; i++) {
      savedLoops.push(LoopDetector.compactLoopRecord(bundle.savedLoops[i]));
    }
    const pendingLoops: Array<DebugLoopRecord> = [];
    for (let i = 0; i < bundle.pendingLoops.length; i++) {
      pendingLoops.push(LoopDetector.compactLoopRecord(bundle.pendingLoops[i]));
    }
    const placedItems: Array<PlacedItemRecord> = [];
    for (let i = 0; i < bundle.placedItems.length; i++) {
      placedItems.push({
        id: bundle.placedItems[i].id,
        loopId: bundle.placedItems[i].loopId,
        itemTypeId: bundle.placedItems[i].itemTypeId,
        lat: bundle.placedItems[i].lat,
        lng: bundle.placedItems[i].lng,
        diamondCost: bundle.placedItems[i].diamondCost,
        ownerId: bundle.placedItems[i].ownerId
      });
    }
    this.savedLoops = savedLoops;
    this.pendingLoops = pendingLoops;
    this.placedItems = placedItems;
    this.nextLoopId = bundle.nextLoopId;
    this.nextPlacedItemId = bundle.nextPlacedItemId;
    if (bundle.userADiamonds !== undefined) {
      this.userADiamonds = Math.max(0, Math.round(bundle.userADiamonds));
    }
    if (bundle.userBDiamonds !== undefined) {
      this.userBDiamonds = Math.max(0, Math.round(bundle.userBDiamonds));
    }
    this.selectedLoopId = -1;
    this.triggeredTrapIds = [];
    this.beginNewTrackFromCurrentLocation();
    this.refreshAllLoopOverlays();
    this.refreshAllPlacedItemOverlays();
    this.saveAllLoops();
    this.savePlacedItems();
    this.saveDebugDiamonds();
    this.debugMessage = `已导入 ${savedLoops.length + pendingLoops.length} 个闭环 · ${placedItems.length} 个物品`;
    // #region agent log
    hilog.info(LOG_DOMAIN, LOG_TAG, '[X] import applied loops=%{public}d items=%{public}d',
      savedLoops.length + pendingLoops.length, placedItems.length);
    // #endregion
  }

  /** 追加领地数据：保留现有闭环/物品，仅合并新路径 */
  private appendImportedTerritory(bundle: TerritoryExportBundle): void {
    const loopIdMap: Map<number, number> = new Map();
    let nextLoopId = this.nextLoopId;
    let nextItemId = this.nextPlacedItemId;

    const nextSaved: Array<DebugLoopRecord> = [];
    for (let i = 0; i < this.savedLoops.length; i++) {
      nextSaved.push(this.savedLoops[i]);
    }
    for (let i = 0; i < bundle.savedLoops.length; i++) {
      const source = LoopDetector.compactLoopRecord(bundle.savedLoops[i]);
      const newId = nextLoopId++;
      loopIdMap.set(source.id, newId);
      nextSaved.push(this.cloneLoopWithId(source, newId));
    }

    const nextPending: Array<DebugLoopRecord> = [];
    for (let i = 0; i < this.pendingLoops.length; i++) {
      nextPending.push(this.pendingLoops[i]);
    }
    for (let i = 0; i < bundle.pendingLoops.length; i++) {
      const source = LoopDetector.compactLoopRecord(bundle.pendingLoops[i]);
      const newId = nextLoopId++;
      loopIdMap.set(source.id, newId);
      nextPending.push(this.cloneLoopWithId(source, newId));
    }

    const nextItems: Array<PlacedItemRecord> = [];
    for (let i = 0; i < this.placedItems.length; i++) {
      nextItems.push(this.placedItems[i]);
    }
    for (let i = 0; i < bundle.placedItems.length; i++) {
      const source = bundle.placedItems[i];
      let mappedLoopId = source.loopId;
      if (source.loopId !== TerritoryItemDefaults.WORLD_RESOURCE_LOOP_ID) {
        const mapped = loopIdMap.get(source.loopId);
        if (mapped !== undefined) {
          mappedLoopId = mapped;
        }
      }
      const item: PlacedItemRecord = {
        id: nextItemId++,
        loopId: mappedLoopId,
        itemTypeId: source.itemTypeId,
        lat: source.lat,
        lng: source.lng,
        diamondCost: source.diamondCost
      };
      nextItems.push(item);
    }

    this.savedLoops = nextSaved;
    this.pendingLoops = nextPending;
    this.placedItems = nextItems;
    this.nextLoopId = nextLoopId;
    this.nextPlacedItemId = nextItemId;
    this.refreshAllLoopOverlays();
    this.refreshAllPlacedItemOverlays();
    this.saveAllLoops();
    this.savePlacedItems();
    const addedLoops = bundle.savedLoops.length + bundle.pendingLoops.length;
    this.debugMessage =
      `已追加 ${addedLoops} 个闭环 · ${bundle.placedItems.length} 个物品（保留原有 ${this.savedLoops.length + this.pendingLoops.length - addedLoops} 个路径）`;
    hilog.info(LOG_DOMAIN, LOG_TAG, '[X] append applied addedLoops=%{public}d totalLoops=%{public}d',
      addedLoops, this.savedLoops.length + this.pendingLoops.length);
  }

  private cloneLoopWithId(source: DebugLoopRecord, newId: number): DebugLoopRecord {
    return DebugLoopStore.copyMetadata(source, {
      id: newId,
      name: source.name,
      ownerId: source.ownerId,
      strokeColor: source.strokeColor,
      fillColor: source.fillColor,
      strokeWidth: source.strokeWidth,
      distance: source.distance,
      latitudes: source.latitudes.slice(),
      longitudes: source.longitudes.slice(),
      adEnabled: source.adEnabled,
      adPresetId: source.adPresetId,
      adTitle: source.adTitle,
      adImageUri: source.adImageUri
    });
  }

  private async appendBundledTerritoryIfNeeded(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const store = await preferences.getPreferences(context, { name: 'debug_territory' });
      const already = Boolean(await store.get(BUNDLED_TERRITORY_FLAG, false));
      if (already) {
        return;
      }
      const ok = await this.appendTerritoryFromRawFile(BUNDLED_TERRITORY_RAWFILE);
      if (ok) {
        await store.put(BUNDLED_TERRITORY_FLAG, true);
        await store.flush();
      }
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, '[X] append bundled failed %{public}s', JSON.stringify(error));
    }
  }

  private async appendTerritoryFromRawFile(fileName: string): Promise<boolean> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const raw = await context.resourceManager.getRawFileContent(fileName);
      const decoder = util.TextDecoder.create('utf-8');
      const json = decoder.decodeToString(new Uint8Array(raw.buffer));
      const parsed = TerritoryExportStore.parse(json);
      if (parsed === null) {
        this.debugMessage = `追加失败：${fileName} 格式无效`;
        return false;
      }
      const normalized = TerritoryExportStore.normalize(parsed);
      if (normalized === null) {
        this.debugMessage = `追加失败：${fileName} 数据校验失败`;
        return false;
      }
      this.appendImportedTerritory(normalized);
      return true;
    } catch (error) {
      this.debugMessage = `追加失败：无法读取 ${fileName}`;
      hilog.error(LOG_DOMAIN, LOG_TAG, '[X] rawfile append failed %{public}s', JSON.stringify(error));
      return false;
    }
  }

  private async exportDebugTerritory(): Promise<void> {
    try {
      const bundle = TerritoryExportStore.buildBundle(
        this.savedLoops,
        this.pendingLoops,
        this.placedItems,
        this.nextLoopId,
        this.nextPlacedItemId,
        this.userADiamonds,
        this.userBDiamonds
      );
      const json = TerritoryExportStore.serialize(bundle);
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const saved = await TerritoryFileIO.exportText(context, json, TerritoryExportStore.defaultExportFileName());
      if (saved) {
        this.debugMessage = `已导出 ${bundle.savedLoops.length + bundle.pendingLoops.length} 个闭环 · ${bundle.placedItems.length} 个物品 · ${json.length} 字节`;
        // #region agent log
        hilog.info(LOG_DOMAIN, LOG_TAG, '[X] export success loops=%{public}d items=%{public}d bytes=%{public}d',
          bundle.savedLoops.length + bundle.pendingLoops.length, bundle.placedItems.length, json.length);
        // #endregion
      } else {
        this.debugMessage = json.length > 0 ? '导出失败，文件未写入' : '导出已取消';
      }
    } catch (error) {
      this.debugMessage = '导出失败';
      console.error(`Export debug territory failed: ${JSON.stringify(error)}`);
    }
  }

  private async importDebugTerritory(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const json = await TerritoryFileIO.importText(context);
      if (json === null) {
        this.debugMessage = '导入已取消';
        return;
      }
      const parsed = TerritoryExportStore.parse(json);
      if (parsed === null) {
        this.debugMessage = '文件格式无效，请使用 .mydomai.json';
        return;
      }
      const normalized = TerritoryExportStore.normalize(parsed);
      if (normalized === null) {
        this.debugMessage = '导入数据校验失败';
        return;
      }
      this.applyImportedTerritory(normalized);
    } catch (error) {
      this.debugMessage = '导入失败';
      console.error(`Import debug territory failed: ${JSON.stringify(error)}`);
    }
  }

  private async saveAllLoops(): Promise<void> {
    try {
      await this.persistAndPushOwners([this.currentDebugUserId]);
    } catch (error) {
      this.debugMessage = '闭环已生成，但本地保存失败';
      console.error(`Save debug loops failed: ${JSON.stringify(error)}`);
    }
  }

  /** 本地持久化后，按用户依次上传（含显式删除与占领后的受害方） */
  private async persistAndPushOwners(ownerIds: Array<string>): Promise<void> {
    await this.persistTerritoryLocally();
    const uniqueOwners: Array<string> = [];
    for (let i = 0; i < ownerIds.length; i++) {
      const id = ownerIds[i];
      let exists = false;
      for (let j = 0; j < uniqueOwners.length; j++) {
        if (uniqueOwners[j] === id) {
          exists = true;
          break;
        }
      }
      if (!exists && id.length > 0) {
        uniqueOwners.push(id);
      }
    }
    if (uniqueOwners.length === 0) {
      uniqueOwners.push(this.currentDebugUserId);
    }
    // #region agent log
    hilog.info(LOG_DOMAIN, LOG_TAG, '[DBG8add10] persistAndPush owners=%{public}d', uniqueOwners.length);
    // #endregion
    await this.pushTerritoriesForOwners(uniqueOwners, true, undefined);
  }

  private async restoreDebugTerritory(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const store = await preferences.getPreferences(context, { name: 'debug_territory' });
      const loopsJson = String(await store.get('loops', ''));
      if (loopsJson.length > 0) {
        this.savedLoops = DebugLoopStore.parseLoops(loopsJson).map((loop: DebugLoopRecord) =>
          LoopDetector.compactLoopRecord(DebugLoopStore.ensureOwner(loop)));
        this.nextLoopId = Number(await store.get('nextLoopId', 1));
        if (this.nextLoopId < 1) {
          this.nextLoopId = 1;
        }
        for (let i = 0; i < this.savedLoops.length; i++) {
          const loop = this.savedLoops[i];
          if (loop.id >= this.nextLoopId) {
            this.nextLoopId = loop.id + 1;
          }
        }
        this.refreshAllLoopOverlays();
        this.debugMessage = `已恢复 ${this.savedLoops.length} 个测试领地`;
        return;
      }
      const latitudeJson = String(await store.get('latitudes', ''));
      const longitudeJson = String(await store.get('longitudes', ''));
      if (latitudeJson.length === 0 || longitudeJson.length === 0) {
        return;
      }
      const latitudes = JSON.parse(latitudeJson) as Array<number>;
      const longitudes = JSON.parse(longitudeJson) as Array<number>;
      if (latitudes.length < 4 || latitudes.length !== longitudes.length) {
        return;
      }
      const legacyLoop: DebugLoopRecord = LoopDetector.compactLoopRecord(DebugLoopStore.ensureOwner({
        id: 1,
        name: '领地 1',
        strokeColor: String(await store.get('color', '#2DB55B')),
        fillColor: DebugLoopStore.toFillColor(String(await store.get('color', '#2DB55B'))),
        strokeWidth: 3,
        distance: Number(await store.get('distance', 0)),
        latitudes: latitudes,
        longitudes: longitudes
      }));
      this.savedLoops = [legacyLoop];
      this.nextLoopId = 2;
      await store.put('loops', DebugLoopStore.serializeLoops(this.savedLoops));
      await store.put('nextLoopId', this.nextLoopId);
      await store.flush();
      this.refreshAllLoopOverlays();
      this.debugMessage = '已恢复本地测试领地';
    } catch (error) {
      console.error(`Restore debug territory failed: ${JSON.stringify(error)}`);
    }
  }

  @Builder
  debugUserSection() {
    Column() {
      Text('同步').fontSize(12).fontColor('#3D4A44').width('100%').margin({ bottom: 6 })
      if (this.currentDebugUserId.length === 0) {
        Text('未登录：请到「我的」注册 / 登录')
          .fontSize(11)
          .fontColor('#B45309')
          .width('100%')
      } else {
        Text(`当前：${this.sessionDisplayName.length > 0 ? this.sessionDisplayName : DebugLoopStore.ownerLabel(this.currentDebugUserId)}`)
          .fontSize(11)
          .fontColor('#1E2D25')
          .fontWeight(FontWeight.Medium)
          .width('100%')
        Text(`账号 ${this.currentDebugUserId} · 钻石 ${this.getCurrentUserDiamonds()}💎`)
          .fontSize(10)
          .fontColor('#4B5563')
          .width('100%')
          .margin({ top: 2 })
      }
      Text(this.backendStatusText)
        .fontSize(10).fontColor('#475569').width('100%').margin({ top: 4 })
      Button('从后端刷新领地')
        .width('100%')
        .height(28)
        .fontSize(11)
        .fontColor('#1D4ED8')
        .backgroundColor(DEBUG_GLASS)
        .borderRadius(10)
        .margin({ top: 6 })
        .enabled(this.currentDebugUserId.length > 0)
        .onClick(() => {
          void this.refreshTerritoryFromBackend();
        })
      Button('定位到我的领地')
        .width('100%')
        .height(28)
        .fontSize(11)
        .fontColor('#1D4ED8')
        .backgroundColor(DEBUG_GLASS)
        .borderRadius(10)
        .margin({ top: 6 })
        .enabled(this.currentDebugUserId.length > 0)
        .onClick(() => {
          this.fitMapToCurrentUserLoops();
        })
    }.width('100%').margin({ bottom: 10 })
  }

  @Builder
  debugMapLabelSection() {
    Column() {
      Text('地图地名').fontSize(12).fontColor('#3D4A44').width('100%').margin({ bottom: 6 })
      Button(this.showMapPlaceLabels ? '隐藏地名标注' : '显示地名标注')
        .width('100%')
        .height(30)
        .fontSize(11)
        .fontColor(this.showMapPlaceLabels ? '#FFFFFF' : '#374151')
        .backgroundColor(this.showMapPlaceLabels ? DEBUG_GLASS_GRAY : DEBUG_GLASS)
        .borderRadius(10)
        .onClick(() => {
          this.toggleMapPlaceLabels();
        })
      Text(this.showMapPlaceLabels ? '当前：显示底图 POI 名称' : '当前：隐藏底图 POI 名称')
        .fontSize(10)
        .fontColor('#4B5563')
        .width('100%')
        .margin({ top: 4 })
    }.width('100%').margin({ bottom: 10 })
  }

  @Builder
  debugResourceSpawnSection() {
    Column() {
      Text('随机资源投放').fontSize(12).fontColor('#3D4A44').width('100%').margin({ bottom: 6 })
      Row() {
        Text('半径').fontSize(11).fontColor('#3D4A44').width(32)
        TextInput({ text: this.resourceRadiusKmText })
          .layoutWeight(1)
          .height(28)
          .fontSize(12)
          .fontColor('#1E2D25')
          .backgroundColor(DEBUG_GLASS_SOFT)
          .borderRadius(8)
          .type(InputType.Number)
          .onChange((value: string) => {
            this.resourceRadiusKmText = value;
          })
        Text('km').fontSize(10).fontColor('#4B5563').margin({ left: 4 })
      }.width('100%')
      Row() {
        Text('密度').fontSize(11).fontColor('#3D4A44').width(32)
        TextInput({ text: this.resourceDensityText })
          .layoutWeight(1)
          .height(28)
          .fontSize(12)
          .fontColor('#1E2D25')
          .backgroundColor(DEBUG_GLASS_SOFT)
          .borderRadius(8)
          .type(InputType.Number)
          .onChange((value: string) => {
            this.resourceDensityText = value;
          })
        Text('/km²').fontSize(10).fontColor('#4B5563').margin({ left: 4 })
      }.width('100%').margin({ top: 6 })
      Row() {
        Button('稀疏').layoutWeight(1).height(28).fontSize(11).backgroundColor(DEBUG_GLASS_GREEN_SOFT).fontColor('#2B8B4A').onClick(() => {
          this.resourceDensityText = '3';
        })
        Button('适中').layoutWeight(1).height(28).fontSize(11).backgroundColor(DEBUG_GLASS_GREEN_SOFT).fontColor('#2B8B4A').margin({ left: 4 }).onClick(() => {
          this.resourceDensityText = '8';
        })
        Button('密集').layoutWeight(1).height(28).fontSize(11).backgroundColor(DEBUG_GLASS_GREEN_SOFT).fontColor('#2B8B4A').margin({ left: 4 }).onClick(() => {
          this.resourceDensityText = '18';
        })
      }.width('100%').margin({ top: 6 })
      Row() {
        Button('随机投放').layoutWeight(1).height(32).fontSize(12).backgroundColor(DEBUG_GLASS_ORANGE).fontColor('#FFFFFF').onClick(() => {
          this.spawnRandomWorldResources();
        })
        Button('清除资源').layoutWeight(1).height(32).fontSize(12).backgroundColor(DEBUG_GLASS_RED_SOFT).fontColor('#B91C1C').margin({ left: 6 }).onClick(() => {
          this.clearWorldResources();
        })
      }.width('100%').margin({ top: 8 })
      Text(`以当前位置为中心 · 已有世界资源 ${this.countWorldResources()} 个 · 单次最多 ${MAX_RANDOM_WORLD_RESOURCES}`)
        .fontSize(10)
        .fontColor('#4B5563')
        .width('100%')
        .margin({ top: 4 })
      Text('含🏥银行🏦工厂🏭监狱🔒宝箱🎁等，地图以 emoji 标注')
        .fontSize(10)
        .fontColor('#4B5563')
        .width('100%')
        .margin({ top: 2 })
    }.width('100%').margin({ bottom: 10 })
  }

  @Builder
  debugSpeedSection() {
    Column() {
      Text('基础速度').fontSize(12).fontColor('#3D4A44').margin({ bottom: 6 })
      Row() {
        Button('−').width(28).height(28).fontSize(14).backgroundColor(DEBUG_GLASS_GREEN_SOFT).fontColor('#2B8B4A').onClick(() => { this.updateDebugSpeed(-1); })
        TextInput({ text: this.debugSpeedText }).width(68).height(28).fontSize(13).fontWeight(FontWeight.Bold).fontColor('#1E2D25').backgroundColor(DEBUG_GLASS_SOFT).borderRadius(8).onChange((value: string) => {
          this.updateDebugSpeedFromInput(value);
        })
        Button('+').width(28).height(28).fontSize(14).backgroundColor(DEBUG_GLASS_GREEN_SOFT).fontColor('#2B8B4A').onClick(() => { this.updateDebugSpeed(1); })
        Text('km/h').fontSize(10).fontColor('#4B5563').margin({ left: 6 })
      }
    }.width('100%')
  }

  @Builder
  loopStyleEditor() {
    Column() {
      Text('新闭环默认样式').fontSize(12).fontColor('#3D4A44').width('100%').margin({ bottom: 6 })
      Row() {
        Text('名称').fontSize(11).fontColor('#3D4A44').width(32)
        TextInput({ text: this.draftLoopName }).layoutWeight(1).height(28).fontSize(11).fontColor('#1E2D25').backgroundColor(DEBUG_GLASS_SOFT).borderRadius(8).onChange((value: string) => {
          this.draftLoopName = value;
        })
      }.width('100%')
      Row() {
        Text('线色').fontSize(11).fontColor('#3D4A44').width(32)
        TextInput({ text: this.draftColorText }).layoutWeight(1).height(28).fontSize(11).fontColor('#1E2D25').backgroundColor(DEBUG_GLASS_SOFT).borderRadius(8).onChange((value: string) => {
          this.draftColorText = value.toUpperCase();
          if (this.draftColorText.length === 7 && this.draftColorText.charAt(0) === '#') {
            const hex = this.draftColorText.substring(1);
            if (/^[0-9A-Fa-f]{6}$/.test(hex)) {
              this.draftStrokeColor = this.draftColorText;
              this.draftFillColor = DebugLoopStore.toFillColor(this.draftStrokeColor);
              this.draftFillColorText = this.draftFillColor;
            }
          }
        })
      }.width('100%').margin({ top: 6 })
      Row() {
        Text('填充').fontSize(11).fontColor('#3D4A44').width(32)
        TextInput({ text: this.draftFillColorText }).layoutWeight(1).height(28).fontSize(11).fontColor('#1E2D25').backgroundColor(DEBUG_GLASS_SOFT).borderRadius(8).onChange((value: string) => {
          this.draftFillColorText = value.toUpperCase();
          if (this.draftFillColorText.length === 7 && this.draftFillColorText.charAt(0) === '#') {
            const hex = this.draftFillColorText.substring(1);
            if (/^[0-9A-Fa-f]{6}$/.test(hex)) {
              this.draftFillColor = DebugLoopStore.normalizeFillColor(this.draftFillColorText, this.draftStrokeColor);
              this.draftFillColorText = this.draftFillColor;
            }
          } else if (this.draftFillColorText.length === 9 && this.draftFillColorText.charAt(0) === '#') {
            const hex = this.draftFillColorText.substring(1);
            if (/^[0-9A-Fa-f]{8}$/.test(hex)) {
              this.draftFillColor = this.draftFillColorText;
            }
          }
        })
      }.width('100%').margin({ top: 6 })
      Row() {
        ForEach(this.debugColorOptions, (color: string) => {
          Row() {
            if (this.draftStrokeColor === color) {
              Text('✓').fontSize(11).fontColor('#FFFFFF')
            }
          }
          .width(22)
          .height(22)
          .borderRadius(11)
          .backgroundColor(color)
          .opacity(0.85)
          .border({ width: this.draftStrokeColor === color ? 2 : 1, color: '#CCFFFFFF' })
          .onClick(() => {
            this.draftStrokeColor = color;
            this.draftColorText = color;
            this.draftFillColor = DebugLoopStore.toFillColor(color);
            this.draftFillColorText = this.draftFillColor;
          })
        }, (color: string) => `style-${color}`)
      }.width('100%').justifyContent(FlexAlign.SpaceBetween).margin({ top: 6 })
      Row() {
        Text('线宽').fontSize(11).fontColor('#3D4A44').width(32)
        TextInput({ text: this.draftStrokeWidthText }).width(44).height(28).fontSize(11).fontColor('#1E2D25').backgroundColor(DEBUG_GLASS_SOFT).borderRadius(8).onChange((value: string) => {
          this.draftStrokeWidthText = value;
          const parsed = Number.parseInt(value, 10);
          if (!Number.isNaN(parsed)) {
            this.draftStrokeWidth = Math.min(12, Math.max(1, parsed));
            this.draftStrokeWidthText = `${this.draftStrokeWidth}`;
          }
        })
        Text('px').fontSize(10).fontColor('#4B5563').margin({ left: 6 })
      }.width('100%').margin({ top: 6 })
      Text('双击闭环可编辑样式，并在填充区设置广告 Logo').fontSize(10).fontColor('#4B5563').width('100%').margin({ top: 6 })
    }.width('100%')
  }

  @Builder
  loopEditDialog() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#00000055')
        .zIndex(1)
        .onClick(() => {
          this.closeLoopEditDialog();
        })
      Column() {
        Row() {
          Text('编辑闭环').fontSize(16).fontWeight(FontWeight.Bold).fontColor('#1E2D25')
          Blank().layoutWeight(1)
          Text('✕').fontSize(16).fontColor('#8A9790').onClick(() => {
            this.closeLoopEditDialog();
          })
        }.width('100%')
        Scroll() {
          Column() {
            Row() {
              Text('名称').fontSize(11).fontColor('#66756D').width(36)
              TextInput({ text: this.draftLoopName }).layoutWeight(1).height(32).fontSize(12).backgroundColor('#F4F7F4').borderRadius(8).onChange((value: string) => {
                this.draftLoopName = value;
              })
            }.width('100%').margin({ top: 12 })
            Row() {
              Text('线色').fontSize(11).fontColor('#66756D').width(36)
              TextInput({ text: this.draftColorText }).layoutWeight(1).height(32).fontSize(12).backgroundColor('#F4F7F4').borderRadius(8).onChange((value: string) => {
                this.updateSelectedLoopColorFromInput(value);
              })
            }.width('100%').margin({ top: 8 })
            Row() {
              Text('填充').fontSize(11).fontColor('#66756D').width(36)
              TextInput({ text: this.draftFillColorText }).layoutWeight(1).height(32).fontSize(12).backgroundColor('#F4F7F4').borderRadius(8).onChange((value: string) => {
                this.updateSelectedLoopFillColorFromInput(value);
              })
            }.width('100%').margin({ top: 8 })
            Row() {
              ForEach(this.debugColorOptions, (color: string) => {
                Row() {
                  if (this.draftStrokeColor === color) {
                    Text('✓').fontSize(11).fontColor('#FFFFFF')
                  }
                }
                .width(24)
                .height(24)
                .borderRadius(12)
                .backgroundColor(color)
                .border({ width: this.draftStrokeColor === color ? 2 : 1, color: '#FFFFFF' })
                .onClick(() => {
                  this.draftStrokeColor = color;
                  this.draftColorText = color;
                })
              }, (color: string) => `edit-stroke-${color}`)
            }.width('100%').justifyContent(FlexAlign.SpaceBetween).margin({ top: 8 })
            Row() {
              ForEach(this.debugColorOptions, (color: string) => {
                Row() {
                  if (this.draftFillColor === DebugLoopStore.toFillColor(color)) {
                    Text('✓').fontSize(11).fontColor('#1E2D25')
                  }
                }
                .width(24)
                .height(24)
                .borderRadius(12)
                .backgroundColor(DebugLoopStore.toFillColor(color))
                .border({ width: this.draftFillColor === DebugLoopStore.toFillColor(color) ? 2 : 1, color: color })
                .onClick(() => {
                  this.draftFillColor = DebugLoopStore.toFillColor(color);
                  this.draftFillColorText = this.draftFillColor;
                })
              }, (color: string) => `edit-fill-${color}`)
            }.width('100%').justifyContent(FlexAlign.SpaceBetween).margin({ top: 8 })
            Row() {
              Text('线宽').fontSize(11).fontColor('#66756D').width(36)
              TextInput({ text: this.draftStrokeWidthText }).width(52).height(32).fontSize(12).backgroundColor('#F4F7F4').borderRadius(8).onChange((value: string) => {
                this.draftStrokeWidthText = value;
                const parsed = Number.parseInt(value, 10);
                if (!Number.isNaN(parsed)) {
                  this.draftStrokeWidth = Math.min(12, Math.max(1, parsed));
                  this.draftStrokeWidthText = `${this.draftStrokeWidth}`;
                }
              })
              Text('px').fontSize(10).fontColor('#8A9790').margin({ left: 6 })
            }.width('100%').margin({ top: 8 })

            Text('闭环广告')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor('#1E2D25')
              .width('100%')
              .margin({ top: 14 })
            Text('地图上只显示：上方图片 + 下方口号（需插入图片）')
              .fontSize(10)
              .fontColor('#8A9790')
              .width('100%')
              .margin({ top: 2 })
            Row() {
              Text(this.draftAdEnabled && this.draftAdImageUri.length > 0 ? '已开启' : '未开启（请插入图片）')
                .fontSize(12)
                .fontColor(this.draftAdEnabled && this.draftAdImageUri.length > 0 ? '#37B75B' : '#8A9790')
                .layoutWeight(1)
              Button(this.draftAdEnabled ? '关闭广告' : '开启广告')
                .height(30)
                .fontSize(11)
                .backgroundColor(this.draftAdEnabled ? '#F3F5F3' : '#37B75B')
                .fontColor(this.draftAdEnabled ? '#62716A' : '#FFFFFF')
                .onClick(() => {
                  if (this.draftAdEnabled) {
                    this.clearDraftAd();
                  } else {
                    this.draftAdEnabled = true;
                  }
                })
            }.width('100%').margin({ top: 8 })
            Row() {
              Text('口号').fontSize(11).fontColor('#66756D').width(36)
              TextInput({ text: this.draftAdTitle, placeholder: '显示在图片下方' })
                .layoutWeight(1)
                .height(32)
                .fontSize(12)
                .backgroundColor('#F4F7F4')
                .borderRadius(8)
                .onChange((value: string) => {
                  this.draftAdTitle = value;
                })
            }.width('100%').margin({ top: 8 })
            Text('插入广告图片').fontSize(11).fontColor('#66756D').width('100%').margin({ top: 10 })
            if (this.draftAdImageUri.length > 0) {
              Image(LoopAdComposer.toDisplayUri(this.draftAdImageUri))
                .width('100%')
                .height(110)
                .objectFit(ImageFit.Cover)
                .borderRadius(10)
                .margin({ top: 6 })
            } else {
              Column() {
                Text('📷').fontSize(22)
                Text('尚未插入图片').fontSize(11).fontColor('#8A9790').margin({ top: 4 })
              }
              .width('100%')
              .height(88)
              .justifyContent(FlexAlign.Center)
              .backgroundColor('#F4F7F4')
              .borderRadius(10)
              .margin({ top: 6 })
            }
            Row() {
              Button(this.draftAdImageUri.length > 0 ? '更换图片' : '从相册插入图片')
                .layoutWeight(1)
                .height(34)
                .fontSize(12)
                .backgroundColor('#2563EB')
                .fontColor('#FFFFFF')
                .onClick(() => {
                  void this.pickLoopAdImage();
                })
              if (this.draftAdImageUri.length > 0) {
                Button('清除图片')
                  .width(84)
                  .height(34)
                  .fontSize(12)
                  .backgroundColor('#F3F5F3')
                  .fontColor('#62716A')
                  .margin({ left: 8 })
                  .onClick(() => {
                    this.draftAdImageUri = '';
                  })
              }
            }.width('100%').margin({ top: 8 })

            Button('删除并释放')
              .width('100%')
              .height(38)
              .fontSize(13)
              .backgroundColor('#FEECEC')
              .fontColor('#D64545')
              .margin({ top: 12 })
              .onClick(() => {
                this.deleteSelectedLoop();
              })
            Row() {
              Button('取消').layoutWeight(1).height(38).fontSize(13).backgroundColor('#F3F5F3').fontColor('#62716A').onClick(() => {
                this.closeLoopEditDialog();
              })
              Button('保存').layoutWeight(1).height(38).fontSize(13).backgroundColor('#37B75B').fontColor('#FFFFFF').margin({ left: 8 }).onClick(() => {
                this.saveLoopEditDialog();
              })
            }.width('100%').margin({ top: 14, bottom: 4 })
          }.width('100%')
        }
        .width('100%')
        .constraintSize({ maxHeight: '72%' })
        .scrollBar(BarState.Off)
      }
      .width('88%')
      .padding(16)
      .backgroundColor('#FFFFFFFA')
      .borderRadius(16)
      .shadow({ radius: 12, color: '#00000022', offsetX: 0, offsetY: 2 })
      .zIndex(2)
      .hitTestBehavior(HitTestMode.Default)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  debugActionButtons() {
    Column() {
      Row() {
        Button('重置轨迹').layoutWeight(1).height(32).fontSize(12).backgroundColor(DEBUG_GLASS_NEUTRAL).fontColor('#374151').onClick(() => {
          this.resetActiveTrack();
        })
        Button('生成闭环').layoutWeight(1).height(32).fontSize(12).backgroundColor(DEBUG_GLASS_GREEN).fontColor('#FFFFFF').margin({ left: 6 }).onClick(() => {
          this.generateDebugLoop();
        })
      }.width('100%')
      if (this.pendingLoops.length > 0) {
        Button('完成圈地').width('100%').height(34).fontSize(13).backgroundColor(DEBUG_GLASS_GREEN).fontColor('#FFFFFF').margin({ top: 6 }).onClick(() => {
          this.completeDebugTerritory();
        })
      }
      Row() {
        Button('导出轨迹').layoutWeight(1).height(32).fontSize(12).backgroundColor(DEBUG_GLASS_BLUE_SOFT).fontColor('#1D4ED8').onClick(() => {
          this.exportDebugTerritory();
        })
        Button('导入轨迹').layoutWeight(1).height(32).fontSize(12).backgroundColor(DEBUG_GLASS_BLUE_SOFT).fontColor('#1D4ED8').margin({ left: 6 }).onClick(() => {
          this.importDebugTerritory();
        })
      }.width('100%').margin({ top: 6 })
      Button('追加可探索区域').width('100%').height(32).fontSize(12).backgroundColor(DEBUG_GLASS_TEAL_SOFT).fontColor('#047857')
        .margin({ top: 6 })
        .onClick(() => {
          void this.appendTerritoryFromRawFile(BUNDLED_TERRITORY_RAWFILE);
        })
    }.width('100%')
  }

  @Builder
  joystickControl() {
    Stack({ alignContent: Alignment.Center }) {
      Row()
        .width(JOYSTICK_SIZE)
        .height(JOYSTICK_SIZE)
        .borderRadius(JOYSTICK_SIZE / 2)
        .backgroundColor(DEBUG_GLASS_GREEN_SOFT)
        .border({ width: 1, color: DEBUG_PANEL_BORDER })
      Row()
        .width(JOYSTICK_KNOB_SIZE)
        .height(JOYSTICK_KNOB_SIZE)
        .borderRadius(JOYSTICK_KNOB_SIZE / 2)
        .backgroundColor(this.joystickActive ? DEBUG_GLASS_GREEN : DEBUG_JOYSTICK_KNOB)
        .shadow({ radius: 4, color: '#332D7F46', offsetX: 0, offsetY: 2 })
        .translate({ x: this.joystickKnobX, y: this.joystickKnobY })
    }
    .width(JOYSTICK_SIZE)
    .height(JOYSTICK_SIZE)
    .hitTestBehavior(HitTestMode.Block)
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.beginJoystickCapture();
      }
      if (event.type === TouchType.Down || event.type === TouchType.Move) {
        if (event.touches.length > 0) {
          this.updateJoystickFromLocal(event.touches[0].x, event.touches[0].y);
        }
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.releaseJoystick();
        this.debugMessage = '推动摇杆即可移动，或点击“生成闭环”快速测试';
      }
    })
  }

  @Builder
  debugPanelDragHeader() {
    Column() {
      Row()
        .width(40)
        .height(4)
        .borderRadius(2)
        .backgroundColor('#94A3B8AA')
        .margin({ top: 2, bottom: 8 })
      Row() {
        Text('调试跑步器').fontSize(14).fontWeight(FontWeight.Bold).fontColor('#1E2D25')
        Blank().layoutWeight(1)
        Text('拖动标题栏移动').fontSize(10).fontColor('#64748B')
      }.width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .hitTestBehavior(HitTestMode.Default)
    .gesture(
      PanGesture({ direction: PanDirection.All, distance: 1 })
        .onActionStart(() => {
          this.onDebugPanelPanStart();
        })
        .onActionUpdate((event: GestureEvent) => {
          this.onDebugPanelPanUpdate(event.offsetX, event.offsetY);
        })
        .onActionEnd(() => {
          this.onDebugPanelPanEnd();
        })
        .onActionCancel(() => {
          this.onDebugPanelPanEnd();
        })
    )
  }

  @Builder
  debugControls() {
    Column() {
      this.debugPanelDragHeader()
      Scroll() {
        Column() {
          this.debugUserSection()
          this.debugMapLabelSection()
          this.debugResourceSpawnSection()
          this.debugSpeedSection()
          Column() {
            this.loopStyleEditor()
          }.width('100%').margin({ top: 10 })
          Text(this.debugMessage).fontSize(10).fontColor('#15803D').maxLines(2).width('100%').margin({ top: 8 })
          Text(`轨迹 ${Math.round(this.debugDistance)} m`).fontSize(10).fontColor('#4B5563').width('100%').margin({ top: 4 })
        }.width('100%')
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring)
      // 挂在 Scroll 自身：Down 时禁用地图拖拽，不抢 Scroll 内部滑动手势
      .onTouch((event: TouchEvent) => {
        this.onDebugPanelTouch(event);
      })
      Column() {
        this.debugActionButtons()
      }
      .width('100%')
      .margin({ top: 8 })
      .onTouch((event: TouchEvent) => {
        this.onDebugPanelTouch(event);
      })
    }
    .width(272)
    .height(DEBUG_PANEL_MAX_HEIGHT)
    .padding(10)
    .backgroundColor(DEBUG_PANEL_BG)
    .borderRadius(14)
    .border({ width: 1, color: DEBUG_PANEL_BORDER })
    .translate({ x: this.debugPanelOffsetX, y: this.debugPanelOffsetY })
    // Default：不阻塞子节点（Scroll 可滑）。Block 会挡住子组件触摸，切勿使用。
    .hitTestBehavior(HitTestMode.Default)
    .clip(true)
  }

  @Builder
  placementItemButton(item: PlaceableItemType) {
    Button({ type: ButtonType.Normal }) {
      Row() {
        Text(item.icon).fontSize(18)
        Text(item.name).fontSize(13).fontColor('#1E2D25').margin({ left: 6 })
      }
    }
      .width('100%')
      .height(44)
      .backgroundColor('#FFFFFFEE')
      .borderRadius(12)
      .border({ width: 1, color: item.color })
      .onClick(() => {
        if (item.id === 'trap') {
          this.openTrapSetupDialog();
        } else {
          this.placeItem(item.id);
        }
      })
  }

  @Builder
  placementItemGrid() {
    GridRow({ columns: 2, gutter: 8 }) {
      ForEach(this.placeableItems, (item: PlaceableItemType) => {
        GridCol() {
          this.placementItemButton(item)
        }
      }, (item: PlaceableItemType) => `place-${item.id}`)
    }.width('100%').margin({ top: 10 })
  }

  @Builder
  trapSetupDialog() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#00000055')
        .zIndex(1)
        .onClick(() => {
          this.closeTrapSetupDialog();
        })
      Column() {
        Row() {
          Text('设置陷阱').fontSize(16).fontWeight(FontWeight.Bold).fontColor('#1E2D25')
          Blank().layoutWeight(1)
          Text('✕').fontSize(16).fontColor('#8A9790').onClick(() => {
            this.closeTrapSetupDialog();
          })
        }.width('100%')
        Text(`领地：${this.placementLoopName}`).fontSize(12).fontColor('#66756D').width('100%').margin({ top: 8 })
        Text('掉入陷阱的用户需支付以下钻石才能脱困').fontSize(11).fontColor('#8A9790').width('100%').margin({ top: 4 })
        Row() {
          Text('钻石').fontSize(11).fontColor('#66756D').width(40)
          TextInput({ text: this.trapSetupCostText })
            .layoutWeight(1)
            .height(32)
            .fontSize(13)
            .backgroundColor('#F4F7F4')
            .borderRadius(8)
            .type(InputType.Number)
            .onChange((value: string) => {
              this.trapSetupCostText = value;
            })
        }.width('100%').margin({ top: 12 })
        Button('确认放置陷阱')
          .width('100%')
          .height(40)
          .fontSize(14)
          .fontColor('#FFFFFF')
          .backgroundColor('#EF5B5B')
          .borderRadius(12)
          .margin({ top: 14 })
          .onClick(() => {
            this.confirmPlaceTrap();
          })
        Button('取消').width('100%').height(36).fontSize(13).backgroundColor('#F3F5F3').fontColor('#62716A').margin({ top: 8 }).onClick(() => {
          this.closeTrapSetupDialog();
        })
      }
      .width('88%')
      .padding(16)
      .backgroundColor('#FFFFFFFA')
      .borderRadius(16)
      .shadow({ radius: 12, color: '#00000022', offsetX: 0, offsetY: 2 })
      .zIndex(2)
      .hitTestBehavior(HitTestMode.Default)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  loopInfoStatCard(label: string, value: string, accent: string) {
    Column() {
      Text(label).fontSize(11).fontColor('#8A9790')
      Text(value).fontSize(16).fontWeight(FontWeight.Bold).fontColor('#1E2D25').margin({ top: 4 })
    }
    .layoutWeight(1)
    .padding({ left: 12, right: 12, top: 12, bottom: 12 })
    .backgroundColor('#F7FAF8')
    .borderRadius(12)
    .border({ width: 1, color: accent + '33' })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  loopInfoDialog() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#00000066')
        .zIndex(1)
        .onClick(() => {
          this.closeLoopInfoDialog();
        })
      Column() {
        Row() {
          Column()
            .width(4)
            .height(44)
            .borderRadius(2)
            .backgroundColor(this.loopInfoOwnerColor)
          Column() {
            Text(this.loopInfoName)
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor('#1E2D25')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Row() {
              Text(this.loopInfoOwnerLabel)
                .fontSize(11)
                .fontColor('#FFFFFF')
                .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                .backgroundColor(this.loopInfoOwnerColor)
                .borderRadius(10)
              Text(this.loopInfoStatusLabel)
                .fontSize(11)
                .fontColor('#66756D')
                .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                .backgroundColor('#EEF2EE')
                .borderRadius(10)
                .margin({ left: 6 })
            }.margin({ top: 6 })
          }
          .layoutWeight(1)
          .margin({ left: 10 })
          Text('✕')
            .fontSize(18)
            .fontColor('#8A9790')
            .onClick(() => {
              this.closeLoopInfoDialog();
            })
        }.width('100%').alignItems(VerticalAlign.Top)

        Row() {
          this.loopInfoStatCard('面积', this.loopInfoAreaText, this.loopInfoOwnerColor)
          Blank().width(8)
          this.loopInfoStatCard('周长', this.loopInfoPerimeterText, this.loopInfoOwnerColor)
        }.width('100%').margin({ top: 16 })

        Row() {
          this.loopInfoStatCard('用时', this.loopInfoDurationText, this.loopInfoOwnerColor)
          Blank().width(8)
          this.loopInfoStatCard('配速', this.loopInfoPaceText, this.loopInfoOwnerColor)
        }.width('100%').margin({ top: 8 })

        Row() {
          this.loopInfoStatCard('平均速度', this.loopInfoSpeedText, this.loopInfoOwnerColor)
          Blank().width(8)
          Column() {
            Text('生成时间').fontSize(11).fontColor('#8A9790')
            Text(this.loopInfoCreatedText).fontSize(12).fontWeight(FontWeight.Medium).fontColor('#1E2D25').margin({ top: 4 })
            Text('完成时间').fontSize(11).fontColor('#8A9790').margin({ top: 8 })
            Text(this.loopInfoCompletedText).fontSize(12).fontWeight(FontWeight.Medium).fontColor('#1E2D25').margin({ top: 4 })
          }
          .layoutWeight(1)
          .padding({ left: 12, right: 12, top: 12, bottom: 12 })
          .backgroundColor('#F7FAF8')
          .borderRadius(12)
          .border({ width: 1, color: this.loopInfoOwnerColor + '33' })
          .alignItems(HorizontalAlign.Start)
        }.width('100%').margin({ top: 8 })

        Button('关闭')
          .width('100%')
          .height(40)
          .fontSize(14)
          .fontColor('#FFFFFF')
          .backgroundColor(this.loopInfoOwnerColor)
          .borderRadius(12)
          .margin({ top: 16 })
          .onClick(() => {
            this.closeLoopInfoDialog();
          })
      }
      .width('90%')
      .padding(18)
      .backgroundColor('#FFFFFFFA')
      .borderRadius(20)
      .shadow({ radius: 18, color: '#00000033', offsetX: 0, offsetY: 4 })
      .zIndex(2)
      .hitTestBehavior(HitTestMode.Default)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  trapHitDialog() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#00000066')
        .zIndex(1)
      Column() {
        Text('⚠ 掉进陷阱').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#EF5B5B').width('100%')
        Text(`你跑进了${this.trappedTrapOwnerLabel}的领地并触发了陷阱！`)
          .fontSize(13).fontColor('#4B5563').width('100%').margin({ top: 10 })
        Text(`支付 ${this.trappedTrapCost} 钻石即可脱困继续圈地`)
          .fontSize(12).fontColor('#66756D').width('100%').margin({ top: 6 })
        Text(`你的钻石：${this.getCurrentUserDiamonds()} 💎`)
          .fontSize(12).fontColor('#2563EB').width('100%').margin({ top: 4 })
        Button(`支付 ${this.trappedTrapCost} 钻石脱困`)
          .width('100%')
          .height(42)
          .fontSize(14)
          .fontColor('#FFFFFF')
          .backgroundColor('#3B82F6')
          .borderRadius(12)
          .margin({ top: 16 })
          .onClick(() => {
            this.payTrapDiamonds();
          })
        Button('放弃支付（圈地失败）')
          .width('100%')
          .height(40)
          .fontSize(13)
          .fontColor('#EF5B5B')
          .backgroundColor('#FEE2E2')
          .borderRadius(12)
          .margin({ top: 8 })
          .onClick(() => {
            this.failTrapEncounter();
          })
      }
      .width('88%')
      .padding(18)
      .backgroundColor('#FFFFFFFA')
      .borderRadius(16)
      .shadow({ radius: 14, color: '#00000033', offsetX: 0, offsetY: 3 })
      .zIndex(2)
      .hitTestBehavior(HitTestMode.Default)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  placementDialog() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#00000055')
        .zIndex(1)
        .onClick(() => {
          this.closePlacementDialog();
        })
      Column() {
        Row() {
          Text('放置物品').fontSize(16).fontWeight(FontWeight.Bold).fontColor('#1E2D25')
          Blank().layoutWeight(1)
          Text('✕').fontSize(16).fontColor('#8A9790').onClick(() => {
            this.closePlacementDialog();
          })
        }.width('100%')
        Text(`领地：${this.placementLoopName}`).fontSize(12).fontColor('#66756D').width('100%').margin({ top: 8 })
        Text('选择要放置的物品').fontSize(11).fontColor('#8A9790').width('100%').margin({ top: 4 })
        Scroll() {
          this.placementItemGrid()
        }
        .width('100%')
        .height(220)
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring)
        Button('取消').width('100%').height(36).fontSize(13).backgroundColor('#F3F5F3').fontColor('#62716A').margin({ top: 12 }).onClick(() => {
          this.closePlacementDialog();
        })
      }
      .width('88%')
      .padding(16)
      .backgroundColor('#FFFFFFFA')
      .borderRadius(16)
      .shadow({ radius: 12, color: '#00000022', offsetX: 0, offsetY: 2 })
      .zIndex(2)
      .hitTestBehavior(HitTestMode.Default)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  joystickOverlay() {
    Column() {
      Text('方向摇杆').fontSize(10).fontColor('#66756D')
      this.joystickControl()
    }
    .alignItems(HorizontalAlign.End)
    .padding({ right: JOYSTICK_RIGHT_INSET, bottom: JOYSTICK_BOTTOM_INSET })
    .hitTestBehavior(HitTestMode.Default)
  }

  @Builder
  mapToolColumn() {
    Column() {
      Button(this.debugMode ? '关闭调试' : '调试')
        .fontSize(12)
        .fontColor(this.debugMode ? '#FFFFFF' : '#166534')
        .width(62)
        .height(34)
        .backgroundColor(this.debugMode ? DEBUG_GLASS_GREEN : DEBUG_GLASS_TOOL)
        .borderRadius(17)
        .hitTestBehavior(HitTestMode.Default)
        .onClick(() => {
          this.toggleDebugMode();
        })
      Button('定位')
        .fontSize(12)
        .fontColor('#1D4ED8')
        .width(62)
        .height(34)
        .backgroundColor(DEBUG_GLASS_TOOL)
        .borderRadius(17)
        .margin({ top: 8 })
        .hitTestBehavior(HitTestMode.Default)
        .onClick(() => {
          void this.locateToCurrentPosition();
        })
    }
    .width(DEBUG_PANEL_WIDTH)
    .alignItems(HorizontalAlign.End)
    .hitTestBehavior(HitTestMode.Transparent)
  }

  build() {
    Stack() {
      MapComponent({
        onReady: (error, controller) => {
          if (!error) {
            this.mapController = controller;
            this.refreshNanjingTerritories();
            // 若定位已返回则立刻居中；否则等 requestCurrentLocation 完成后再移动视野
            this.applyCurrentLocation(this.currentLocation !== null);
            this.refreshAllLoopOverlays();
            this.refreshActiveTrackOverlay();
            this.refreshAllPlacedItemOverlays();
            this.setupMapInteraction();
            if (this.focusTerritoryId >= 0) {
              this.focusSelectedTerritory();
            }
            this.applyGestureLockState();
          }
        },
        mapOptions: this.mapOptions
      })
      .width('100%')
      .height('100%')

      if (!this.locationReady) {
        Text(this.locationMessage)
          .fontSize(12)
          .fontColor('#62726A')
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .backgroundColor('#FFFFFFDD')
          .borderRadius(16)
          .margin({ top: TOP_TOOLBAR_INSET + 22, left: 12 })
          .align(Alignment.TopStart)
          .zIndex(150)
      }

      Stack({ alignContent: Alignment.TopEnd }) {
        Column() {
          this.mapToolColumn()
        }
        .width(DEBUG_PANEL_WIDTH)
        .margin({ right: 12, top: MAP_TOOLBAR_TOP_INSET })
        .hitTestBehavior(HitTestMode.Transparent)

        // 独立浮层，避免拖出窄 Column 后无法命中
        if (this.debugMode) {
          Column() {
            this.debugControls()
          }
          .margin({
            right: 12,
            // 按钮区：34 + 8 + 34，再加与面板间距 8
            top: MAP_TOOLBAR_TOP_INSET + 34 + 8 + 34 + 8
          })
          .hitTestBehavior(HitTestMode.Transparent)
        }
      }
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.Transparent)
      .zIndex(210)

      if (this.joystickCapturing) {
        Row() {
          Blank()
            .layoutWeight(1)
            .height('100%')
            .hitTestBehavior(HitTestMode.Block)
          Blank()
            .width(DEBUG_PANEL_WIDTH + 24)
            .height('100%')
            .hitTestBehavior(HitTestMode.None)
        }
        .width('100%')
        .height('100%')
        .align(Alignment.TopStart)
        .zIndex(205)
      }

      // 摇杆常驻显示，与调试面板开关无关
      Stack({ alignContent: Alignment.BottomEnd }) {
        this.joystickOverlay()
      }
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.Transparent)
      .zIndex(201)

      if (this.showLoopEditDialog) {
        Stack({ alignContent: Alignment.Center }) {
          this.loopEditDialog()
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.Default)
        .zIndex(310)
      }

      if (this.showPlacementDialog) {
        Stack({ alignContent: Alignment.Center }) {
          this.placementDialog()
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.Default)
        .zIndex(300)
      }

      if (this.showTrapSetupDialog) {
        Stack({ alignContent: Alignment.Center }) {
          this.trapSetupDialog()
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.Default)
        .zIndex(320)
      }

      if (this.showTrapDialog) {
        Stack({ alignContent: Alignment.Center }) {
          this.trapHitDialog()
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.Default)
        .zIndex(330)
      }

      if (this.showLoopInfoDialog) {
        Stack({ alignContent: Alignment.Center }) {
          this.loopInfoDialog()
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.Default)
        .zIndex(335)
      }
    }
    .width('100%')
    .height('100%')
  }
}

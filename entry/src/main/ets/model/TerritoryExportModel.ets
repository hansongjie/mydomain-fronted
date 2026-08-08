import { DebugLoopRecord, DebugLoopStore } from './DebugLoopModel';
import { PlacedItemRecord } from './TerritoryItemModel';

export interface TerritoryExportBundle {
  formatVersion: number;
  app: string;
  exportedAt: string;
  coordinateSystem: string;
  nextLoopId: number;
  nextPlacedItemId: number;
  savedLoops: Array<DebugLoopRecord>;
  pendingLoops: Array<DebugLoopRecord>;
  placedItems: Array<PlacedItemRecord>;
  userADiamonds?: number;
  userBDiamonds?: number;
}

export class TerritoryExportStore {
  static readonly FORMAT_VERSION: number = 1;
  static readonly APP_NAME: string = 'MyDomai';
  static readonly FILE_SUFFIX: string = '.mydomai.json';

  static buildBundle(
    savedLoops: Array<DebugLoopRecord>,
    pendingLoops: Array<DebugLoopRecord>,
    placedItems: Array<PlacedItemRecord>,
    nextLoopId: number,
    nextPlacedItemId: number,
    userADiamonds: number,
    userBDiamonds: number
  ): TerritoryExportBundle {
    return {
      formatVersion: TerritoryExportStore.FORMAT_VERSION,
      app: TerritoryExportStore.APP_NAME,
      exportedAt: new Date().toISOString(),
      coordinateSystem: 'WGS84',
      nextLoopId: nextLoopId,
      nextPlacedItemId: nextPlacedItemId,
      savedLoops: TerritoryExportStore.cloneLoops(savedLoops),
      pendingLoops: TerritoryExportStore.cloneLoops(pendingLoops),
      placedItems: TerritoryExportStore.cloneItems(placedItems),
      userADiamonds: userADiamonds,
      userBDiamonds: userBDiamonds
    };
  }

  static serialize(bundle: TerritoryExportBundle): string {
    return JSON.stringify(bundle, null, 2);
  }

  static parse(json: string): TerritoryExportBundle | null {
    if (json.trim().length === 0) {
      return null;
    }
    try {
      const parsed = JSON.parse(json) as TerritoryExportBundle;
      if (parsed === null || parsed.formatVersion !== TerritoryExportStore.FORMAT_VERSION) {
        return null;
      }
      if (!Array.isArray(parsed.savedLoops) || !Array.isArray(parsed.pendingLoops) || !Array.isArray(parsed.placedItems)) {
        return null;
      }
      return parsed;
    } catch (error) {
      return null;
    }
  }

  static normalize(bundle: TerritoryExportBundle): TerritoryExportBundle | null {
    const savedLoops: Array<DebugLoopRecord> = [];
    const pendingLoops: Array<DebugLoopRecord> = [];
    for (let i = 0; i < bundle.savedLoops.length; i++) {
      const loop = TerritoryExportStore.normalizeLoop(bundle.savedLoops[i]);
      if (loop !== null) {
        savedLoops.push(loop);
      }
    }
    for (let i = 0; i < bundle.pendingLoops.length; i++) {
      const loop = TerritoryExportStore.normalizeLoop(bundle.pendingLoops[i]);
      if (loop !== null) {
        pendingLoops.push(loop);
      }
    }
    const validLoopIds: Set<number> = new Set();
    for (let i = 0; i < savedLoops.length; i++) {
      validLoopIds.add(savedLoops[i].id);
    }
    for (let i = 0; i < pendingLoops.length; i++) {
      validLoopIds.add(pendingLoops[i].id);
    }
    const placedItems: Array<PlacedItemRecord> = [];
    for (let i = 0; i < bundle.placedItems.length; i++) {
      const item = TerritoryExportStore.normalizeItem(bundle.placedItems[i]);
      if (item !== null && (item.loopId === 0 || validLoopIds.has(item.loopId))) {
        placedItems.push(item);
      }
    }
    let nextLoopId = bundle.nextLoopId > 0 ? Math.round(bundle.nextLoopId) : 1;
    let nextPlacedItemId = bundle.nextPlacedItemId > 0 ? Math.round(bundle.nextPlacedItemId) : 1;
    for (let i = 0; i < savedLoops.length; i++) {
      if (savedLoops[i].id >= nextLoopId) {
        nextLoopId = savedLoops[i].id + 1;
      }
    }
    for (let i = 0; i < pendingLoops.length; i++) {
      if (pendingLoops[i].id >= nextLoopId) {
        nextLoopId = pendingLoops[i].id + 1;
      }
    }
    for (let i = 0; i < placedItems.length; i++) {
      if (placedItems[i].id >= nextPlacedItemId) {
        nextPlacedItemId = placedItems[i].id + 1;
      }
    }
    return {
      formatVersion: TerritoryExportStore.FORMAT_VERSION,
      app: TerritoryExportStore.APP_NAME,
      exportedAt: bundle.exportedAt,
      coordinateSystem: bundle.coordinateSystem,
      nextLoopId: nextLoopId,
      nextPlacedItemId: nextPlacedItemId,
      savedLoops: savedLoops,
      pendingLoops: pendingLoops,
      placedItems: placedItems,
      userADiamonds: bundle.userADiamonds,
      userBDiamonds: bundle.userBDiamonds
    };
  }

  static defaultExportFileName(): string {
    const now = new Date();
    const pad2 = (value: number): string => {
      return value < 10 ? `0${value}` : `${value}`;
    };
    return `mydomai-territory-${now.getFullYear()}${pad2(now.getMonth() + 1)}${pad2(now.getDate())}-${pad2(now.getHours())}${pad2(now.getMinutes())}${pad2(now.getSeconds())}${TerritoryExportStore.FILE_SUFFIX}`;
  }

  private static cloneLoops(source: Array<DebugLoopRecord>): Array<DebugLoopRecord> {
    const cloned: Array<DebugLoopRecord> = [];
    for (let i = 0; i < source.length; i++) {
      const loop = source[i];
      cloned.push(DebugLoopStore.copyMetadata(loop, {
        id: loop.id,
        name: loop.name,
        ownerId: loop.ownerId,
        strokeColor: loop.strokeColor,
        fillColor: loop.fillColor,
        strokeWidth: loop.strokeWidth,
        distance: loop.distance,
        latitudes: loop.latitudes.slice(),
        longitudes: loop.longitudes.slice(),
        adEnabled: loop.adEnabled,
        adPresetId: loop.adPresetId,
        adTitle: loop.adTitle,
        adImageUri: loop.adImageUri
      }));
    }
    return cloned;
  }

  private static cloneItems(source: Array<PlacedItemRecord>): Array<PlacedItemRecord> {
    const cloned: Array<PlacedItemRecord> = [];
    for (let i = 0; i < source.length; i++) {
      const item = source[i];
      cloned.push({
        id: item.id,
        loopId: item.loopId,
        itemTypeId: item.itemTypeId,
        lat: item.lat,
        lng: item.lng,
        diamondCost: item.diamondCost,
        ownerId: item.ownerId
      });
    }
    return cloned;
  }

  private static normalizeLoop(raw: DebugLoopRecord): DebugLoopRecord | null {
    if (raw === null || raw.id === undefined || raw.latitudes === undefined || raw.longitudes === undefined) {
      return null;
    }
    if (raw.latitudes.length < 4 || raw.latitudes.length !== raw.longitudes.length) {
      return null;
    }
    return DebugLoopStore.ensureOwner(DebugLoopStore.copyMetadata(raw, {
      id: Math.round(raw.id),
      name: raw.name !== undefined && raw.name.length > 0 ? raw.name : `领地 ${raw.id}`,
      ownerId: raw.ownerId,
      strokeColor: raw.strokeColor !== undefined ? raw.strokeColor : '#2DB55B',
      fillColor: raw.fillColor,
      strokeWidth: raw.strokeWidth !== undefined ? raw.strokeWidth : 1,
      distance: raw.distance !== undefined ? raw.distance : 0,
      latitudes: raw.latitudes.slice(),
      longitudes: raw.longitudes.slice(),
      adEnabled: raw.adEnabled,
      adPresetId: raw.adPresetId,
      adTitle: raw.adTitle,
      adImageUri: raw.adImageUri
    }));
  }

  private static normalizeItem(raw: PlacedItemRecord): PlacedItemRecord | null {
    if (raw === null || raw.id === undefined || raw.loopId === undefined || raw.itemTypeId === undefined) {
      return null;
    }
    if (!Number.isFinite(raw.lat) || !Number.isFinite(raw.lng)) {
      return null;
    }
    return {
      id: Math.round(raw.id),
      loopId: Math.round(raw.loopId),
      itemTypeId: raw.itemTypeId,
      lat: raw.lat,
      lng: raw.lng,
      diamondCost: raw.diamondCost,
      ownerId: raw.ownerId
    };
  }
}

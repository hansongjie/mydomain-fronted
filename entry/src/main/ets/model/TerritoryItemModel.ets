export interface PlaceableItemType {
  id: string;
  name: string;
  icon: string;
  mapLabel: string;
  color: string;
}

export interface PlacedItemRecord {
  id: number;
  loopId: number;
  itemTypeId: string;
  lat: number;
  lng: number;
  diamondCost?: number;
  /** 放置者；陷阱触发时优先用该字段，而不是闭环当前主人 */
  ownerId?: string;
}

export class TerritoryItemDefaults {
  static readonly TRAP_DIAMOND_COST: number = 10;
  /** 调试摇杆步长较大，命中半径略放大以保证可触发 */
  static readonly TRAP_HIT_RADIUS_METERS: number = 32;
  /** 世界随机资源不属于任何闭环 */
  static readonly WORLD_RESOURCE_LOOP_ID: number = 0;
  /** 世界随机陷阱的虚拟主人（对所有玩家敌对） */
  static readonly WORLD_TRAP_OWNER_ID: string = 'world';
}

export class TerritoryItemCatalog {
  /** 领地内可手动放置的建筑/防御 */
  static getAll(): Array<PlaceableItemType> {
    const factory: PlaceableItemType = { id: 'factory', name: '工厂', icon: '🏭', mapLabel: '🏭', color: '#64748B' };
    const mine: PlaceableItemType = { id: 'mine', name: '矿场', icon: '⛏️', mapLabel: '⛏️', color: '#78716C' };
    const granary: PlaceableItemType = { id: 'granary', name: '粮仓', icon: '🏚️', mapLabel: '🏚️', color: '#D97706' };
    const cannon: PlaceableItemType = { id: 'cannon', name: '火炮', icon: '💣', mapLabel: '💣', color: '#DC2626' };
    const trap: PlaceableItemType = { id: 'trap', name: '陷阱', icon: '🪤', mapLabel: '🪤', color: '#EF5B5B' };
    const shield: PlaceableItemType = { id: 'shield', name: '护盾', icon: '🛡️', mapLabel: '🛡️', color: '#3B82F6' };
    const tower: PlaceableItemType = { id: 'tower', name: '防御塔', icon: '🗼', mapLabel: '🗼', color: '#7C3AED' };
    return [factory, mine, granary, cannon, trap, shield, tower];
  }

  /** 地图随机投放的大富翁风格世界资源 */
  static getWorldResources(): Array<PlaceableItemType> {
    return [
      { id: 'trap', name: '陷阱', icon: '🪤', mapLabel: '🪤', color: '#EF5B5B' },
      { id: 'factory', name: '工厂', icon: '🏭', mapLabel: '🏭', color: '#64748B' },
      { id: 'hospital', name: '医院', icon: '🏥', mapLabel: '🏥', color: '#F43F5E' },
      { id: 'bank', name: '银行', icon: '🏦', mapLabel: '🏦', color: '#0EA5E9' },
      { id: 'police', name: '警察局', icon: '🚓', mapLabel: '🚓', color: '#1D4ED8' },
      { id: 'jail', name: '监狱', icon: '🔒', mapLabel: '🔒', color: '#334155' },
      { id: 'school', name: '学校', icon: '🏫', mapLabel: '🏫', color: '#F59E0B' },
      { id: 'park', name: '公园', icon: '🏞️', mapLabel: '🏞️', color: '#22C55E' },
      { id: 'shop', name: '商店', icon: '🏪', mapLabel: '🏪', color: '#FB923C' },
      { id: 'mall', name: '商场', icon: '🏬', mapLabel: '🏬', color: '#A855F7' },
      { id: 'hotel', name: '酒店', icon: '🏨', mapLabel: '🏨', color: '#EC4899' },
      { id: 'gas', name: '加油站', icon: '⛽', mapLabel: '⛽', color: '#F97316' },
      { id: 'station', name: '车站', icon: '🚉', mapLabel: '🚉', color: '#6366F1' },
      { id: 'airport', name: '机场', icon: '✈️', mapLabel: '✈️', color: '#0284C7' },
      { id: 'harbor', name: '港口', icon: '⚓', mapLabel: '⚓', color: '#0F766E' },
      { id: 'power', name: '电厂', icon: '⚡', mapLabel: '⚡', color: '#EAB308' },
      { id: 'water', name: '水厂', icon: '💧', mapLabel: '💧', color: '#38BDF8' },
      { id: 'mine', name: '矿场', icon: '⛏️', mapLabel: '⛏️', color: '#78716C' },
      { id: 'farm', name: '农场', icon: '🚜', mapLabel: '🚜', color: '#84CC16' },
      { id: 'granary', name: '粮仓', icon: '🏚️', mapLabel: '🏚️', color: '#D97706' },
      { id: 'market', name: '菜市场', icon: '🛒', mapLabel: '🛒', color: '#16A34A' },
      { id: 'restaurant', name: '餐厅', icon: '🍜', mapLabel: '🍜', color: '#EA580C' },
      { id: 'cafe', name: '咖啡厅', icon: '☕', mapLabel: '☕', color: '#92400E' },
      { id: 'cinema', name: '电影院', icon: '🎬', mapLabel: '🎬', color: '#7C3AED' },
      { id: 'gym', name: '健身房', icon: '🏋️', mapLabel: '🏋️', color: '#DC2626' },
      { id: 'stadium', name: '体育场', icon: '🏟️', mapLabel: '🏟️', color: '#059669' },
      { id: 'library', name: '图书馆', icon: '📚', mapLabel: '📚', color: '#4F46E5' },
      { id: 'museum', name: '博物馆', icon: '🏛️', mapLabel: '🏛️', color: '#B45309' },
      { id: 'church', name: '教堂', icon: '⛪', mapLabel: '⛪', color: '#6B7280' },
      { id: 'temple', name: '寺庙', icon: '🏯', mapLabel: '🏯', color: '#B91C1C' },
      { id: 'casino', name: '赌场', icon: '🎰', mapLabel: '🎰', color: '#DB2777' },
      { id: 'lottery', name: '彩票站', icon: '🎟️', mapLabel: '🎟️', color: '#C026D3' },
      { id: 'treasure', name: '宝箱', icon: '🎁', mapLabel: '🎁', color: '#F59E0B' },
      { id: 'gold', name: '金库', icon: '💰', mapLabel: '💰', color: '#CA8A04' },
      { id: 'diamond', name: '钻石矿', icon: '💎', mapLabel: '💎', color: '#06B6D4' },
      { id: 'cannon', name: '火炮', icon: '💣', mapLabel: '💣', color: '#DC2626' },
      { id: 'shield', name: '护盾', icon: '🛡️', mapLabel: '🛡️', color: '#3B82F6' },
      { id: 'tower', name: '防御塔', icon: '🗼', mapLabel: '🗼', color: '#7C3AED' },
      { id: 'checkpoint', name: '关卡', icon: '🚧', mapLabel: '🚧', color: '#FACC15' },
      { id: 'portal', name: '传送门', icon: '🌀', mapLabel: '🌀', color: '#8B5CF6' }
    ];
  }

  static getLegacyItems(): Array<PlaceableItemType> {
    const grass: PlaceableItemType = { id: 'grass', name: '草地', icon: '🌿', mapLabel: '🌿', color: '#2DB55B' };
    const wheat: PlaceableItemType = { id: 'wheat', name: '麦田', icon: '🌾', mapLabel: '🌾', color: '#F59E0B' };
    return [grass, wheat];
  }

  static findInList(id: string, items: Array<PlaceableItemType>): PlaceableItemType | null {
    for (let i = 0; i < items.length; i++) {
      if (items[i].id === id) {
        return items[i];
      }
    }
    return null;
  }

  static getById(id: string): PlaceableItemType | null {
    const fromWorld = TerritoryItemCatalog.findInList(id, TerritoryItemCatalog.getWorldResources());
    if (fromWorld !== null) {
      return fromWorld;
    }
    const fromAll = TerritoryItemCatalog.findInList(id, TerritoryItemCatalog.getAll());
    if (fromAll !== null) {
      return fromAll;
    }
    return TerritoryItemCatalog.findInList(id, TerritoryItemCatalog.getLegacyItems());
  }

  static pickRandomWorldResource(seed: number): PlaceableItemType {
    const items = TerritoryItemCatalog.getWorldResources();
    const index = Math.abs(Math.floor(seed)) % items.length;
    return items[index];
  }
}

export class TerritoryItemStore {
  static serializeItems(items: Array<PlacedItemRecord>): string {
    return JSON.stringify(items);
  }

  static parseItems(json: string): Array<PlacedItemRecord> {
    if (json.length === 0) {
      return [];
    }
    const parsed = JSON.parse(json) as Array<PlacedItemRecord>;
    if (!Array.isArray(parsed)) {
      return [];
    }
    return parsed;
  }
}

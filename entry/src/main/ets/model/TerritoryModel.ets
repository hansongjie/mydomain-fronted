export interface TerritoryPoint {
  lat: number;
  lng: number;
}

export interface TerritoryInfo {
  id: number;
  name: string;
  level: string;
  areaKm2: number;
  income: string;
  center: TerritoryPoint;
  points: Array<TerritoryPoint>;
  fillColor: string;
  borderColor: string;
}

export class NanjingTerritoryStore {
  private static territories: Array<TerritoryInfo> = [];

  static getAll(): Array<TerritoryInfo> {
    if (NanjingTerritoryStore.territories.length === 0) {
      NanjingTerritoryStore.territories = NanjingTerritoryStore.createTerritories();
    }
    return NanjingTerritoryStore.territories;
  }

  static getById(id: number): TerritoryInfo | null {
    const territories = NanjingTerritoryStore.getAll();
    for (let index = 0; index < territories.length; index++) {
      if (territories[index].id === id) {
        return territories[index];
      }
    }
    return null;
  }

  static getTotalArea(): number {
    let total = 0;
    NanjingTerritoryStore.getAll().forEach((territory: TerritoryInfo) => {
      total += territory.areaKm2;
    });
    return Number(total.toFixed(2));
  }

  private static createTerritories(): Array<TerritoryInfo> {
    return [];
  }
}

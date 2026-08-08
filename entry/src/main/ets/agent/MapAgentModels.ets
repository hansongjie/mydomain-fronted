export interface AgentResourcePoint {
  id: number;
  typeId: string;
  name: string;
  icon: string;
  lat: number;
  lng: number;
  /** world | territory */
  scope: string;
  loopId: number;
  /** meters from current user/map center */
  distanceMeters: number;
}

export interface AgentTrapPoint {
  id: number;
  lat: number;
  lng: number;
  ownerId: string;
  diamondCost: number;
  distanceMeters: number;
  loopId: number;
}

export interface AgentPoiPoint {
  id: string;
  name: string;
  /** loop | building | landmark */
  kind: string;
  lat: number;
  lng: number;
  distanceMeters: number;
}

export interface AgentLoopSummary {
  id: number;
  name: string;
  ownerId: string;
  pointCount: number;
  centerLat: number;
  centerLng: number;
}

export interface AgentResourceCluster {
  centerLat: number;
  centerLng: number;
  count: number;
  resourceIds: Array<number>;
  label: string;
  distanceMeters: number;
}

export interface AgentMapContext {
  userLat: number;
  userLng: number;
  resources: Array<AgentResourcePoint>;
  traps: Array<AgentTrapPoint>;
  pois: Array<AgentPoiPoint>;
  clusters: Array<AgentResourceCluster>;
  loops: Array<AgentLoopSummary>;
  worldResourceCount: number;
  territoryItemCount: number;
  trapCount: number;
  poiCount: number;
  /** OSM walkable roads in Baidu coords; filled before LLM call */
  roadPromptText: string;
  roadCount: number;
}

export interface AgentRoutePoint {
  lat: number;
  lng: number;
}

export interface AgentPlanResult {
  reply: string;
  action: string;
  routeName: string;
  points: Array<AgentRoutePoint>;
  source: string;
}

/** pending | running | done | warn | error */
export interface AgentProcessStep {
  id: number;
  title: string;
  detail: string;
  status: string;
}

export type AgentProgressReporter =
  (title: string, detail: string, status: string) => void | Promise<void>;

import { AgentMapContext, AgentRoutePoint } from './MapAgentModels';

export type AgentContextProvider = () => AgentMapContext | null;
export type AgentRouteApplier = (routeName: string, points: Array<AgentRoutePoint>, reply: string) => boolean;
export type AgentDefaultTerritoryApplier = (reply: string) => Promise<boolean>;

/**
 * Bridge between map page voice UI and BaiduMapView instance.
 */
export class MapAgentBridge {
  private static contextProvider: AgentContextProvider | null = null;
  private static routeApplier: AgentRouteApplier | null = null;
  private static defaultTerritoryApplier: AgentDefaultTerritoryApplier | null = null;

  static register(
    contextProvider: AgentContextProvider,
    routeApplier: AgentRouteApplier,
    defaultTerritoryApplier: AgentDefaultTerritoryApplier
  ): void {
    MapAgentBridge.contextProvider = contextProvider;
    MapAgentBridge.routeApplier = routeApplier;
    MapAgentBridge.defaultTerritoryApplier = defaultTerritoryApplier;
  }

  static unregister(): void {
    MapAgentBridge.contextProvider = null;
    MapAgentBridge.routeApplier = null;
    MapAgentBridge.defaultTerritoryApplier = null;
  }

  static getContext(): AgentMapContext | null {
    if (MapAgentBridge.contextProvider === null) {
      return null;
    }
    return MapAgentBridge.contextProvider();
  }

  static applyRoute(routeName: string, points: Array<AgentRoutePoint>, reply: string): boolean {
    if (MapAgentBridge.routeApplier === null) {
      return false;
    }
    return MapAgentBridge.routeApplier(routeName, points, reply);
  }

  /** 询问 Agent 后默认展示的内置领地 JSON 区域 */
  static async applyDefaultTerritory(reply: string): Promise<boolean> {
    if (MapAgentBridge.defaultTerritoryApplier === null) {
      return false;
    }
    return await MapAgentBridge.defaultTerritoryApplier(reply);
  }
}

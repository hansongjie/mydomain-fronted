import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CoordTrans, LatLng } from '@bdmap/base';
import { AndemenRoadFallback } from './AndemenRoadFallback';
import { CoordApprox } from './CoordApprox';
import { AgentRoutePoint } from './MapAgentModels';
import { RoadPoint, RoadSegment } from './RoadNetworkModels';

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'MyDomaiRoad';
const MAX_WAYS: number = 40;
const MAX_POINTS_PER_WAY: number = 8;

export class RoadNetworkService {
  private static readonly OVERPASS_URLS: Array<string> = [
    'https://overpass.kumi.systems/api/interpreter',
    'https://overpass-api.de/api/interpreter',
    'https://lz4.overpass-api.de/api/interpreter'
  ];

  static async fetchWalkableRoads(baiduLat: number, baiduLng: number, radiusM: number = 700): Promise<Array<RoadSegment>> {
    const gcj = CoordTrans.baiduToGcj(new LatLng(baiduLat, baiduLng));
    let wgsLat = baiduLat;
    let wgsLng = baiduLng;
    if (gcj !== null) {
      const wgs = CoordApprox.gcjToWgs(gcj.lat, gcj.lng);
      wgsLat = wgs[0];
      wgsLng = wgs[1];
    }
    const query =
      `[out:json][timeout:25];` +
      `way["highway"~"^(primary|secondary|tertiary|residential|living_street|unclassified|footway|path|cycleway|pedestrian|service)$"]` +
      `(around:${Math.round(radiusM)},${wgsLat.toFixed(6)},${wgsLng.toFixed(6)});` +
      `out geom;`;

    for (let i = 0; i < RoadNetworkService.OVERPASS_URLS.length; i++) {
      const url = RoadNetworkService.OVERPASS_URLS[i];
      const roads = await RoadNetworkService.requestOverpass(url, query);
      if (roads.length > 0) {
        hilog.info(LOG_DOMAIN, LOG_TAG, '[Road] live osm ways=%{public}d from %{public}s', roads.length, url);
        return roads;
      }
    }

    hilog.warn(LOG_DOMAIN, LOG_TAG, '[Road] live osm empty, using Andemen static fallback');
    return RoadNetworkService.toBaiduRoads(AndemenRoadFallback.getWgsRoads());
  }

  private static async requestOverpass(url: string, query: string): Promise<Array<RoadSegment>> {
    const request = http.createHttp();
    try {
      const response = await request.request(url, {
        method: http.RequestMethod.POST,
        header: RoadNetworkService.buildHeaders(),
        extraData: `data=${encodeURIComponent(query)}`,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 20000,
        readTimeout: 20000
      });
      if (response.responseCode < 200 || response.responseCode >= 300) {
        hilog.error(LOG_DOMAIN, LOG_TAG, '[Road] overpass http %{public}d %{public}s',
          response.responseCode, url);
        return [];
      }
      return RoadNetworkService.parseOverpass(`${response.result}`);
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, '[Road] overpass failed %{public}s %{public}s',
        url, JSON.stringify(error));
      return [];
    } finally {
      request.destroy();
    }
  }

  private static buildHeaders(): Record<string, string> {
    const headers: Record<string, string> = {};
    headers['Content-Type'] = 'application/x-www-form-urlencoded';
    return headers;
  }

  private static toBaiduRoads(wgsRoads: Array<RoadSegment>): Array<RoadSegment> {
    const out: Array<RoadSegment> = [];
    for (let i = 0; i < wgsRoads.length; i++) {
      const src = wgsRoads[i];
      const points: Array<RoadPoint> = [];
      for (let j = 0; j < src.points.length; j++) {
        const bd = CoordTrans.wgsToBaidu(new LatLng(src.points[j].lat, src.points[j].lng));
        if (bd !== null) {
          const rp: RoadPoint = { lat: bd.lat, lng: bd.lng };
          points.push(rp);
        }
      }
      if (points.length >= 2) {
        const seg: RoadSegment = {
          id: src.id,
          name: src.name,
          highway: src.highway,
          points: points
        };
        out.push(seg);
      }
    }
    return out;
  }

  private static parseOverpass(raw: string): Array<RoadSegment> {
    const segments: Array<RoadSegment> = [];
    if (raw.length < 20 || raw.indexOf('elements') < 0) {
      return segments;
    }
    try {
      const root = JSON.parse(raw) as Record<string, Object>;
      const elements = root['elements'] as Array<Record<string, Object>> | undefined;
      if (elements === undefined) {
        return segments;
      }
      for (let i = 0; i < elements.length && segments.length < MAX_WAYS; i++) {
        const el = elements[i];
        if (`${el['type']}` !== 'way') {
          continue;
        }
        const tags = el['tags'] as Record<string, string> | undefined;
        const geometry = el['geometry'] as Array<Record<string, number>> | undefined;
        if (geometry === undefined || geometry.length < 2) {
          continue;
        }
        const highway = tags !== undefined ? `${tags['highway'] ?? 'road'}` : 'road';
        const name = tags !== undefined ? `${tags['name'] ?? highway}` : highway;
        const simplified = RoadNetworkService.simplifyGeometry(geometry);
        const points: Array<RoadPoint> = [];
        for (let j = 0; j < simplified.length; j++) {
          const wgsLat = Number(simplified[j]['lat']);
          const wgsLng = Number(simplified[j]['lon']);
          if (!Number.isFinite(wgsLat) || !Number.isFinite(wgsLng)) {
            continue;
          }
          const bd = CoordTrans.wgsToBaidu(new LatLng(wgsLat, wgsLng));
          if (bd === null) {
            continue;
          }
          const rp: RoadPoint = { lat: bd.lat, lng: bd.lng };
          points.push(rp);
        }
        if (points.length < 2) {
          continue;
        }
        const seg: RoadSegment = {
          id: Number(el['id'] ?? segments.length + 1),
          name: name,
          highway: highway,
          points: points
        };
        segments.push(seg);
      }
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, '[Road] parse failed %{public}s', JSON.stringify(error));
    }
    return segments;
  }

  private static simplifyGeometry(geometry: Array<Record<string, number>>): Array<Record<string, number>> {
    if (geometry.length <= MAX_POINTS_PER_WAY) {
      return geometry;
    }
    const step = Math.max(1, Math.floor((geometry.length - 1) / (MAX_POINTS_PER_WAY - 1)));
    const out: Array<Record<string, number>> = [];
    for (let i = 0; i < geometry.length; i += step) {
      out.push(geometry[i]);
    }
    const last = geometry[geometry.length - 1];
    const outLast = out[out.length - 1];
    if (Number(outLast['lat']) !== Number(last['lat']) || Number(outLast['lon']) !== Number(last['lon'])) {
      out.push(last);
    }
    return out;
  }

  static formatRoadsForPrompt(roads: Array<RoadSegment>): string {
    if (roads.length === 0) {
      return '(空) 未获取到可跑步道路';
    }
    const lines: Array<string> = [];
    lines.push(`可跑步道路共 ${roads.length} 条（百度坐标系，只能沿这些折线规划，禁止穿湖/穿楼）：`);
    for (let i = 0; i < roads.length; i++) {
      const r = roads[i];
      const pts: Array<string> = [];
      for (let j = 0; j < r.points.length; j++) {
        pts.push(`${r.points[j].lat.toFixed(5)},${r.points[j].lng.toFixed(5)}`);
      }
      lines.push(`R${i + 1} ${r.name}(${r.highway}): ${pts.join(' -> ')}`);
    }
    return lines.join('\n');
  }

  static snapRouteToRoads(route: Array<AgentRoutePoint>, roads: Array<RoadSegment>): Array<AgentRoutePoint> {
    if (route.length === 0 || roads.length === 0) {
      return route;
    }
    const samples = RoadNetworkService.collectSamples(roads);
    if (samples.length === 0) {
      return route;
    }
    const snapped: Array<AgentRoutePoint> = [];
    for (let i = 0; i < route.length; i++) {
      const p = route[i];
      let best = samples[0];
      let bestD = Number.MAX_VALUE;
      for (let j = 0; j < samples.length; j++) {
        const d = RoadNetworkService.distanceMeters(p.lat, p.lng, samples[j].lat, samples[j].lng);
        if (d < bestD) {
          bestD = d;
          best = samples[j];
        }
      }
      const sp: AgentRoutePoint = { lat: best.lat, lng: best.lng };
      if (snapped.length === 0 ||
        Math.abs(snapped[snapped.length - 1].lat - sp.lat) > 1e-6 ||
        Math.abs(snapped[snapped.length - 1].lng - sp.lng) > 1e-6) {
        snapped.push(sp);
      }
    }
    if (snapped.length >= 2) {
      const first = snapped[0];
      const last = snapped[snapped.length - 1];
      if (Math.abs(first.lat - last.lat) > 1e-6 || Math.abs(first.lng - last.lng) > 1e-6) {
        const close: AgentRoutePoint = { lat: first.lat, lng: first.lng };
        snapped.push(close);
      }
    }
    return snapped;
  }

  private static collectSamples(roads: Array<RoadSegment>): Array<RoadPoint> {
    const samples: Array<RoadPoint> = [];
    for (let i = 0; i < roads.length; i++) {
      const pts = roads[i].points;
      for (let j = 0; j < pts.length; j++) {
        samples.push(pts[j]);
        if (j + 1 < pts.length) {
          const mid: RoadPoint = {
            lat: (pts[j].lat + pts[j + 1].lat) / 2,
            lng: (pts[j].lng + pts[j + 1].lng) / 2
          };
          samples.push(mid);
        }
      }
    }
    return samples;
  }

  private static distanceMeters(lat1: number, lng1: number, lat2: number, lng2: number): number {
    const toRad = Math.PI / 180;
    const dLat = (lat2 - lat1) * toRad;
    const dLng = (lng2 - lng1) * toRad;
    const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
      Math.cos(lat1 * toRad) * Math.cos(lat2 * toRad) * Math.sin(dLng / 2) * Math.sin(dLng / 2);
    return 6371000 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  }
}

import { RoadPoint, RoadSegment } from './RoadNetworkModels';

/**
 * Static WGS84 walkable roads near Andemen Metro Station, Nanjing.
 * Used when live Overpass fetch fails. Approximate OSM-derived corridors:
 * 雨花大道 / 花神大道 / 安德门大街周边支路与人行道。
 */
export class AndemenRoadFallback {
  static getWgsRoads(): Array<RoadSegment> {
    const roads: Array<RoadSegment> = [];
    roads.push(AndemenRoadFallback.seg(1, '雨花大道', 'secondary', [
      [31.98480, 118.76890], [31.98540, 118.77020], [31.98600, 118.77150],
      [31.98660, 118.77280], [31.98720, 118.77410], [31.98780, 118.77540]
    ]));
    roads.push(AndemenRoadFallback.seg(2, '花神大道', 'primary', [
      [31.99020, 118.77100], [31.98920, 118.77140], [31.98820, 118.77180],
      [31.98720, 118.77220], [31.98620, 118.77260], [31.98520, 118.77300],
      [31.98420, 118.77340], [31.98320, 118.77380]
    ]));
    roads.push(AndemenRoadFallback.seg(3, '安德门大街', 'secondary', [
      [31.98780, 118.76950], [31.98750, 118.77080], [31.98720, 118.77210],
      [31.98690, 118.77340], [31.98660, 118.77470], [31.98630, 118.77600]
    ]));
    roads.push(AndemenRoadFallback.seg(4, '软件大道', 'tertiary', [
      [31.98500, 118.77000], [31.98560, 118.77080], [31.98620, 118.77160],
      [31.98680, 118.77240], [31.98740, 118.77320]
    ]));
    roads.push(AndemenRoadFallback.seg(5, '车站南路人行道', 'footway', [
      [31.98620, 118.77180], [31.98650, 118.77220], [31.98680, 118.77260],
      [31.98710, 118.77300], [31.98740, 118.77340]
    ]));
    roads.push(AndemenRoadFallback.seg(6, '安德门东路', 'residential', [
      [31.98560, 118.77320], [31.98610, 118.77360], [31.98660, 118.77400],
      [31.98710, 118.77440], [31.98760, 118.77480]
    ]));
    roads.push(AndemenRoadFallback.seg(7, '雨花西路支路', 'residential', [
      [31.98840, 118.77060], [31.98800, 118.77140], [31.98760, 118.77220],
      [31.98720, 118.77300], [31.98680, 118.77380]
    ]));
    roads.push(AndemenRoadFallback.seg(8, '地铁站环行人行道', 'pedestrian', [
      [31.98640, 118.77190], [31.98670, 118.77230], [31.98700, 118.77270],
      [31.98670, 118.77310], [31.98640, 118.77270], [31.98640, 118.77190]
    ]));
    roads.push(AndemenRoadFallback.seg(9, '花神湖北路', 'tertiary', [
      [31.98880, 118.77420], [31.98820, 118.77360], [31.98760, 118.77300],
      [31.98700, 118.77240], [31.98640, 118.77180]
    ]));
    roads.push(AndemenRoadFallback.seg(10, '康居路', 'residential', [
      [31.98460, 118.77120], [31.98510, 118.77180], [31.98560, 118.77240],
      [31.98610, 118.77300], [31.98660, 118.77360]
    ]));
    return roads;
  }

  private static seg(id: number, name: string, highway: string, coords: Array<Array<number>>): RoadSegment {
    const points: Array<RoadPoint> = [];
    for (let i = 0; i < coords.length; i++) {
      const p: RoadPoint = { lat: coords[i][0], lng: coords[i][1] };
      points.push(p);
    }
    return {
      id: id,
      name: name,
      highway: highway,
      points: points
    };
  }
}

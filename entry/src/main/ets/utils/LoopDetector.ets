import { LatLng } from '@bdmap/base';
import { DebugLoopRecord, DebugLoopStore } from '../model/DebugLoopModel';

interface Point2D {
  x: number;
  y: number;
}

export class LoopDetector {
  private static readonly CLOSURE_THRESHOLD_METERS: number = 25;
  private static readonly SIMPLIFY_MIN_METERS: number = 2;

  static detectLargestLoop(points: Array<LatLng>): Array<LatLng> | null {
    if (points.length < 4) {
      return null;
    }

    const simplified = LoopDetector.simplify(points);
    if (simplified.length < 4) {
      return null;
    }

    const origin = simplified[0];
    const localPoints = simplified.map((point: LatLng) => LoopDetector.toLocal(point, origin));

    let bestLoop: Array<LatLng> | null = null;
    let bestArea = 0;

    const endGap = LoopDetector.distance(localPoints[0], localPoints[localPoints.length - 1]);
    if (endGap <= LoopDetector.CLOSURE_THRESHOLD_METERS) {
      const closed = LoopDetector.closeLoop(simplified);
      const area = Math.abs(LoopDetector.shoelaceArea(
        closed.map((point: LatLng) => LoopDetector.toLocal(point, origin))
      ));
      if (area > bestArea) {
        bestArea = area;
        bestLoop = closed;
      }
    }

    for (let i = 0; i < localPoints.length - 1; i++) {
      for (let j = i + 2; j < localPoints.length - 1; j++) {
        const intersection = LoopDetector.segmentIntersect(
          localPoints[i], localPoints[i + 1], localPoints[j], localPoints[j + 1]
        );
        if (!intersection) {
          continue;
        }

        const loopLocal: Array<Point2D> = [intersection];
        for (let index = i + 1; index <= j; index++) {
          loopLocal.push(localPoints[index]);
        }
        loopLocal.push(intersection);

        const area = Math.abs(LoopDetector.shoelaceArea(loopLocal));
        if (area > bestArea) {
          bestArea = area;
          bestLoop = loopLocal.map((point: Point2D) => LoopDetector.fromLocal(point, origin));
        }
      }
    }

    if (!bestLoop || bestLoop.length < 4) {
      return null;
    }
    return LoopDetector.closeLoop(bestLoop);
  }

  static pointInPolygon(lat: number, lng: number, latitudes: Array<number>, longitudes: Array<number>): boolean {
    if (latitudes.length < 3 || latitudes.length !== longitudes.length) {
      return false;
    }
    let inside = false;
    for (let i = 0, j = latitudes.length - 1; i < latitudes.length; j = i++) {
      const yi = latitudes[i];
      const xi = longitudes[i];
      const yj = latitudes[j];
      const xj = longitudes[j];
      const intersect = ((yi > lat) !== (yj > lat)) &&
        (lng < (xj - xi) * (lat - yi) / (yj - yi + 1e-12) + xi);
      if (intersect) {
        inside = !inside;
      }
    }
    return inside;
  }

  static loopArea(record: DebugLoopRecord): number {
    const localPoints: Array<Point2D> = [];
    const origin = new LatLng(record.latitudes[0], record.longitudes[0]);
    for (let i = 0; i < record.latitudes.length; i++) {
      localPoints.push(LoopDetector.toLocal(new LatLng(record.latitudes[i], record.longitudes[i]), origin));
    }
    return Math.abs(LoopDetector.shoelaceArea(localPoints));
  }

  static findSmallestLoopAt(lat: number, lng: number, loops: Array<DebugLoopRecord>): DebugLoopRecord | null {
    let bestLoop: DebugLoopRecord | null = null;
    let bestArea = Number.MAX_VALUE;
    for (let i = 0; i < loops.length; i++) {
      const loop = loops[i];
      if (!LoopDetector.pointInPolygon(lat, lng, loop.latitudes, loop.longitudes)) {
        continue;
      }
      const area = LoopDetector.loopArea(loop);
      if (area < bestArea) {
        bestArea = area;
        bestLoop = loop;
      }
    }
    return bestLoop;
  }

  static calculatePerimeter(points: Array<LatLng>): number {
    let total = 0;
    for (let index = 0; index < points.length - 1; index++) {
      total += LoopDetector.distanceMeters(points[index], points[index + 1]);
    }
    return total;
  }

  static simplifyLoopRecord(record: DebugLoopRecord, minMeters: number = 4): DebugLoopRecord {
    if (record.latitudes.length < 5) {
      return record;
    }
    const points: Array<LatLng> = [];
    for (let i = 0; i < record.latitudes.length; i++) {
      points.push(new LatLng(record.latitudes[i], record.longitudes[i]));
    }
    const simplified = LoopDetector.simplify(points, minMeters);
    if (simplified.length < 4) {
      return record;
    }
    const latitudes: Array<number> = [];
    const longitudes: Array<number> = [];
    for (let i = 0; i < simplified.length; i++) {
      latitudes.push(simplified[i].lat);
      longitudes.push(simplified[i].lng);
    }
    const first = simplified[0];
    const last = simplified[simplified.length - 1];
    if (first.lat !== last.lat || first.lng !== last.lng) {
      latitudes.push(first.lat);
      longitudes.push(first.lng);
    }
    return DebugLoopStore.copyMetadata(record, {
      id: record.id,
      name: record.name,
      ownerId: record.ownerId,
      strokeColor: record.strokeColor,
      fillColor: record.fillColor,
      strokeWidth: record.strokeWidth,
      distance: LoopDetector.calculatePerimeter(simplified),
      latitudes: latitudes,
      longitudes: longitudes
    });
  }

  static compactLoopRecord(record: DebugLoopRecord, maxVertices: number = 300): DebugLoopRecord {
    let minMeters = 4;
    let compact = LoopDetector.simplifyLoopRecord(record, minMeters);
    while (compact.latitudes.length > maxVertices && minMeters < 28) {
      minMeters += 4;
      compact = LoopDetector.simplifyLoopRecord(record, minMeters);
    }
    return compact;
  }

  static smoothLoopRecord(
    record: DebugLoopRecord,
    iterations: number = 2,
    minMeters: number = 3,
    maxVertices: number = 400
  ): DebugLoopRecord {
    if (record.latitudes.length < 5) {
      return record;
    }
    const openPoints: Array<LatLng> = [];
    const lastIndex = record.latitudes.length - 1;
    const closesAtEnd = record.latitudes[0] === record.latitudes[lastIndex] &&
      record.longitudes[0] === record.longitudes[lastIndex];
    const vertexCount = closesAtEnd ? lastIndex : record.latitudes.length;
    for (let i = 0; i < vertexCount; i++) {
      openPoints.push(new LatLng(record.latitudes[i], record.longitudes[i]));
    }
    if (openPoints.length < 4) {
      return record;
    }
    const origin = openPoints[0];
    let localRing: Array<Point2D> = [];
    for (let i = 0; i < openPoints.length; i++) {
      localRing.push(LoopDetector.toLocal(openPoints[i], origin));
    }
    localRing = LoopDetector.smoothClosedRing(localRing, iterations);
    const smoothed: Array<LatLng> = [];
    for (let i = 0; i < localRing.length; i++) {
      smoothed.push(LoopDetector.fromLocal(localRing[i], origin));
    }
    const simplified = LoopDetector.simplify(smoothed, minMeters);
    if (simplified.length < 4) {
      return record;
    }
    const latitudes: Array<number> = [];
    const longitudes: Array<number> = [];
    for (let i = 0; i < simplified.length; i++) {
      latitudes.push(simplified[i].lat);
      longitudes.push(simplified[i].lng);
    }
    const first = simplified[0];
    const last = simplified[simplified.length - 1];
    if (first.lat !== last.lat || first.lng !== last.lng) {
      latitudes.push(first.lat);
      longitudes.push(first.lng);
    }
    let result: DebugLoopRecord = DebugLoopStore.copyMetadata(record, {
      id: record.id,
      name: record.name,
      ownerId: record.ownerId,
      strokeColor: record.strokeColor,
      fillColor: record.fillColor,
      strokeWidth: record.strokeWidth,
      distance: LoopDetector.calculatePerimeter(simplified),
      latitudes: latitudes,
      longitudes: longitudes
    });
    let currentMin = minMeters;
    while (result.latitudes.length > maxVertices && currentMin < 12) {
      currentMin += 2;
      result = LoopDetector.simplifyLoopRecord(result, currentMin);
    }
    return result;
  }

  private static smoothClosedRing(ring: Array<Point2D>, iterations: number): Array<Point2D> {
    let current = ring;
    for (let iter = 0; iter < iterations; iter++) {
      if (current.length < 3) {
        return current;
      }
      const next: Array<Point2D> = [];
      for (let i = 0; i < current.length; i++) {
        const p0 = current[i];
        const p1 = current[(i + 1) % current.length];
        next.push({
          x: 0.75 * p0.x + 0.25 * p1.x,
          y: 0.75 * p0.y + 0.25 * p1.y
        });
        next.push({
          x: 0.25 * p0.x + 0.75 * p1.x,
          y: 0.25 * p0.y + 0.75 * p1.y
        });
      }
      current = next;
    }
    return current;
  }

  static simplify(points: Array<LatLng>, minMeters: number = LoopDetector.SIMPLIFY_MIN_METERS): Array<LatLng> {
    if (points.length === 0) {
      return [];
    }
    const simplified: Array<LatLng> = [points[0]];
    for (let index = 1; index < points.length; index++) {
      const last = simplified[simplified.length - 1];
      if (LoopDetector.distanceMeters(last, points[index]) >= minMeters) {
        simplified.push(points[index]);
      }
    }
    const tail = points[points.length - 1];
    const lastKept = simplified[simplified.length - 1];
    if (lastKept.lat !== tail.lat || lastKept.lng !== tail.lng) {
      simplified.push(tail);
    }
    return simplified;
  }

  private static closeLoop(points: Array<LatLng>): Array<LatLng> {
    const closed = points.slice();
    const first = closed[0];
    const last = closed[closed.length - 1];
    if (LoopDetector.distanceMeters(first, last) > 1) {
      closed.push(new LatLng(first.lat, first.lng));
    }
    return closed;
  }

  private static toLocal(point: LatLng, origin: LatLng): Point2D {
    const scale = Math.max(0.2, Math.cos(origin.lat * Math.PI / 180));
    return {
      x: (point.lng - origin.lng) * 111000 * scale,
      y: (point.lat - origin.lat) * 111000
    };
  }

  private static fromLocal(point: Point2D, origin: LatLng): LatLng {
    const scale = Math.max(0.2, Math.cos(origin.lat * Math.PI / 180));
    return new LatLng(
      origin.lat + point.y / 111000,
      origin.lng + point.x / (111000 * scale)
    );
  }

  private static distance(a: Point2D, b: Point2D): number {
    const dx = a.x - b.x;
    const dy = a.y - b.y;
    return Math.sqrt(dx * dx + dy * dy);
  }

  static distanceMeters(a: LatLng, b: LatLng): number {
    return LoopDetector.distance(
      LoopDetector.toLocal(a, a),
      LoopDetector.toLocal(b, a)
    );
  }

  static distancePointToSegmentMeters(point: LatLng, segStart: LatLng, segEnd: LatLng): number {
    const p = LoopDetector.toLocal(point, segStart);
    const b = LoopDetector.toLocal(segEnd, segStart);
    const lenSq = b.x * b.x + b.y * b.y;
    if (lenSq < 1e-12) {
      return LoopDetector.distanceMeters(point, segStart);
    }
    let t = (p.x * b.x + p.y * b.y) / lenSq;
    t = Math.max(0, Math.min(1, t));
    const dx = p.x - b.x * t;
    const dy = p.y - b.y * t;
    return Math.sqrt(dx * dx + dy * dy);
  }

  private static shoelaceArea(points: Array<Point2D>): number {
    let sum = 0;
    for (let index = 0; index < points.length - 1; index++) {
      sum += points[index].x * points[index + 1].y - points[index + 1].x * points[index].y;
    }
    return sum / 2;
  }

  private static segmentIntersect(a1: Point2D, a2: Point2D, b1: Point2D, b2: Point2D): Point2D | null {
    const d1x = a2.x - a1.x;
    const d1y = a2.y - a1.y;
    const d2x = b2.x - b1.x;
    const d2y = b2.y - b1.y;
    const denom = d1x * d2y - d1y * d2x;
    if (Math.abs(denom) < 1e-9) {
      return null;
    }

    const t = ((b1.x - a1.x) * d2y - (b1.y - a1.y) * d2x) / denom;
    const u = ((b1.x - a1.x) * d1y - (b1.y - a1.y) * d1x) / denom;
    if (t <= 0.01 || t >= 0.99 || u <= 0.01 || u >= 0.99) {
      return null;
    }

    return {
      x: a1.x + t * d1x,
      y: a1.y + t * d1y
    };
  }
}

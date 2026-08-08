import { LatLng } from '@bdmap/base';
import { DebugLoopRecord, DebugLoopStore } from '../model/DebugLoopModel';
import { LoopDetector } from './LoopDetector';

interface Point2D {
  x: number;
  y: number;
}

interface GridBounds {
  minX: number;
  minY: number;
  maxX: number;
  maxY: number;
}

interface GridSpec {
  bounds: GridBounds;
  cols: number;
  rows: number;
  step: number;
}

export class PolygonClipper {
  private static readonly BASE_GRID_STEP_METERS: number = 5;
  private static readonly MAX_GRID_CELLS: number = 6000;
  private static readonly MAX_GRID_SIDE: number = 90;
  private static readonly MIN_FRAGMENT_AREA_SQM: number = 60;

  static overlaps(attacker: DebugLoopRecord, victim: DebugLoopRecord): boolean {
    return PolygonClipper.intersectionArea(attacker, victim) > 1;
  }

  static intersectionArea(attacker: DebugLoopRecord, victim: DebugLoopRecord): number {
    const grid = PolygonClipper.buildGridSpec(attacker, victim);
    if (grid === null) {
      return 0;
    }
    const cellArea = grid.step * grid.step;
    let overlapCells = 0;
    const origin = PolygonClipper.originOf(attacker, victim);
    for (let row = 0; row < grid.rows; row++) {
      for (let col = 0; col < grid.cols; col++) {
        const center = PolygonClipper.cellCenter(grid, col, row);
        const latLng = PolygonClipper.fromLocal(center, origin);
        if (LoopDetector.pointInPolygon(latLng.lat, latLng.lng, attacker.latitudes, attacker.longitudes) &&
          LoopDetector.pointInPolygon(latLng.lat, latLng.lng, victim.latitudes, victim.longitudes)) {
          overlapCells++;
        }
      }
    }
    return overlapCells * cellArea;
  }

  static subtract(attacker: DebugLoopRecord, victim: DebugLoopRecord): Array<Array<Point2D>> {
    const grid = PolygonClipper.buildGridSpec(attacker, victim);
    if (grid === null) {
      return [];
    }
    const origin = PolygonClipper.originOf(attacker, victim);
    const remainMask: Array<Array<boolean>> = [];
    for (let row = 0; row < grid.rows; row++) {
      const rowMask: Array<boolean> = [];
      for (let col = 0; col < grid.cols; col++) {
        const center = PolygonClipper.cellCenter(grid, col, row);
        const latLng = PolygonClipper.fromLocal(center, origin);
        const inVictim = LoopDetector.pointInPolygon(latLng.lat, latLng.lng, victim.latitudes, victim.longitudes);
        const inAttacker = LoopDetector.pointInPolygon(latLng.lat, latLng.lng, attacker.latitudes, attacker.longitudes);
        rowMask.push(inVictim && !inAttacker);
      }
      remainMask.push(rowMask);
    }
    return PolygonClipper.extractPolygonsFromMask(remainMask, grid);
  }

  static ringArea(ring: Array<Point2D>): number {
    if (ring.length < 3) {
      return 0;
    }
    let sum = 0;
    for (let i = 0; i < ring.length; i++) {
      const next = ring[(i + 1) % ring.length];
      sum += ring[i].x * next.y - next.x * ring[i].y;
    }
    return Math.abs(sum / 2);
  }

  static ringToRecord(ring: Array<Point2D>, origin: LatLng, template: DebugLoopRecord, id: number, name: string): DebugLoopRecord | null {
    if (ring.length < 3) {
      return null;
    }
    const latitudes: Array<number> = [];
    const longitudes: Array<number> = [];
    const points: Array<LatLng> = [];
    for (let i = 0; i < ring.length; i++) {
      const latLng = PolygonClipper.fromLocal(ring[i], origin);
      latitudes.push(latLng.lat);
      longitudes.push(latLng.lng);
      points.push(latLng);
    }
    if (latitudes.length > 0) {
      latitudes.push(latitudes[0]);
      longitudes.push(longitudes[0]);
      points.push(points[0]);
    }
    const record: DebugLoopRecord = DebugLoopStore.copyMetadata(template, {
      id: id,
      name: name,
      ownerId: template.ownerId,
      strokeColor: template.strokeColor,
      fillColor: template.fillColor,
      strokeWidth: template.strokeWidth,
      distance: LoopDetector.calculatePerimeter(points),
      latitudes: latitudes,
      longitudes: longitudes
    });
    return LoopDetector.smoothLoopRecord(record);
  }

  private static refineRing(ring: Array<Point2D>, grid: GridSpec): Array<Point2D> {
    if (ring.length < 4) {
      return ring;
    }
    let refined = PolygonClipper.simplifyRing(ring);
    const epsilon = Math.max(1.2, grid.step * 0.55);
    refined = PolygonClipper.douglasPeuckerClosed(refined, epsilon);
    refined = PolygonClipper.smoothRing(refined, 2);
    refined = PolygonClipper.douglasPeuckerClosed(refined, epsilon * 0.45);
    return refined.length >= 3 ? refined : ring;
  }

  private static douglasPeuckerClosed(ring: Array<Point2D>, epsilon: number): Array<Point2D> {
    if (ring.length <= 4) {
      return ring;
    }
    const open: Array<Point2D> = [];
    for (let i = 0; i < ring.length; i++) {
      open.push(ring[i]);
    }
    open.push(ring[0]);
    const simplified = PolygonClipper.douglasPeuckerOpen(open, epsilon);
    if (simplified.length > 1 && PolygonClipper.pointsClose(simplified[simplified.length - 1], simplified[0])) {
      simplified.pop();
    }
    return simplified.length >= 3 ? simplified : ring;
  }

  private static douglasPeuckerOpen(points: Array<Point2D>, epsilon: number): Array<Point2D> {
    if (points.length <= 2) {
      return points;
    }
    let maxDist = 0;
    let maxIndex = 0;
    const start = points[0];
    const end = points[points.length - 1];
    for (let i = 1; i < points.length - 1; i++) {
      const dist = PolygonClipper.perpendicularDistance(points[i], start, end);
      if (dist > maxDist) {
        maxDist = dist;
        maxIndex = i;
      }
    }
    if (maxDist <= epsilon) {
      return [start, end];
    }
    const left = PolygonClipper.douglasPeuckerOpen(points.slice(0, maxIndex + 1), epsilon);
    const right = PolygonClipper.douglasPeuckerOpen(points.slice(maxIndex), epsilon);
    const merged: Array<Point2D> = [];
    for (let i = 0; i < left.length - 1; i++) {
      merged.push(left[i]);
    }
    for (let i = 0; i < right.length; i++) {
      merged.push(right[i]);
    }
    return merged;
  }

  private static perpendicularDistance(point: Point2D, lineStart: Point2D, lineEnd: Point2D): number {
    const dx = lineEnd.x - lineStart.x;
    const dy = lineEnd.y - lineStart.y;
    const lenSq = dx * dx + dy * dy;
    if (lenSq < 1e-12) {
      return PolygonClipper.pointDistance(point, lineStart);
    }
    const t = ((point.x - lineStart.x) * dx + (point.y - lineStart.y) * dy) / lenSq;
    const clamped = Math.max(0, Math.min(1, t));
    const projX = lineStart.x + clamped * dx;
    const projY = lineStart.y + clamped * dy;
    return PolygonClipper.pointDistance(point, { x: projX, y: projY });
  }

  private static pointDistance(a: Point2D, b: Point2D): number {
    const dx = a.x - b.x;
    const dy = a.y - b.y;
    return Math.sqrt(dx * dx + dy * dy);
  }

  private static smoothRing(ring: Array<Point2D>, iterations: number): Array<Point2D> {
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

  private static buildGridSpec(attacker: DebugLoopRecord, victim: DebugLoopRecord): GridSpec | null {
    const origin = PolygonClipper.originOf(attacker, victim);
    let step = PolygonClipper.BASE_GRID_STEP_METERS;
    let bounds = PolygonClipper.unionBounds(attacker, victim, origin, step);
    let width = bounds.maxX - bounds.minX;
    let height = bounds.maxY - bounds.minY;
    if (width <= 0 || height <= 0) {
      return null;
    }
    let cols = Math.ceil(width / step);
    let rows = Math.ceil(height / step);
    while ((cols * rows > PolygonClipper.MAX_GRID_CELLS ||
      cols > PolygonClipper.MAX_GRID_SIDE ||
      rows > PolygonClipper.MAX_GRID_SIDE) && step < 80) {
      step += 3;
      bounds = PolygonClipper.unionBounds(attacker, victim, origin, step);
      width = bounds.maxX - bounds.minX;
      height = bounds.maxY - bounds.minY;
      cols = Math.ceil(width / step);
      rows = Math.ceil(height / step);
    }
    if (cols <= 0 || rows <= 0 || cols * rows > PolygonClipper.MAX_GRID_CELLS) {
      return null;
    }
    return { bounds: bounds, cols: cols, rows: rows, step: step };
  }

  private static originOf(a: DebugLoopRecord, b: DebugLoopRecord): LatLng {
    return new LatLng(
      (a.latitudes[0] + b.latitudes[0]) / 2,
      (a.longitudes[0] + b.longitudes[0]) / 2
    );
  }

  private static unionBounds(a: DebugLoopRecord, b: DebugLoopRecord, origin: LatLng, step: number): GridBounds {
    let minX = Number.MAX_VALUE;
    let minY = Number.MAX_VALUE;
    let maxX = Number.MIN_VALUE;
    let maxY = Number.MIN_VALUE;
    for (let i = 0; i < a.latitudes.length; i++) {
      const local = PolygonClipper.toLocal(new LatLng(a.latitudes[i], a.longitudes[i]), origin);
      minX = Math.min(minX, local.x);
      minY = Math.min(minY, local.y);
      maxX = Math.max(maxX, local.x);
      maxY = Math.max(maxY, local.y);
    }
    for (let i = 0; i < b.latitudes.length; i++) {
      const local = PolygonClipper.toLocal(new LatLng(b.latitudes[i], b.longitudes[i]), origin);
      minX = Math.min(minX, local.x);
      minY = Math.min(minY, local.y);
      maxX = Math.max(maxX, local.x);
      maxY = Math.max(maxY, local.y);
    }
    return {
      minX: minX - step,
      minY: minY - step,
      maxX: maxX + step,
      maxY: maxY + step
    };
  }

  private static cellCenter(grid: GridSpec, col: number, row: number): Point2D {
    return {
      x: grid.bounds.minX + (col + 0.5) * grid.step,
      y: grid.bounds.minY + (row + 0.5) * grid.step
    };
  }

  private static extractPolygonsFromMask(mask: Array<Array<boolean>>, grid: GridSpec): Array<Array<Point2D>> {
    const rows = mask.length;
    const cols = mask[0].length;
    const visited: Array<Array<boolean>> = [];
    for (let row = 0; row < rows; row++) {
      const rowVisited: Array<boolean> = [];
      for (let col = 0; col < cols; col++) {
        rowVisited.push(false);
      }
      visited.push(rowVisited);
    }
    const polygons: Array<Array<Point2D>> = [];
    for (let row = 0; row < rows; row++) {
      for (let col = 0; col < cols; col++) {
        if (!mask[row][col] || visited[row][col]) {
          continue;
        }
        const component = PolygonClipper.collectComponent(mask, visited, col, row);
        if (component.length > 2500) {
          continue;
        }
        const ring = PolygonClipper.componentToRing(component, grid);
        if (PolygonClipper.ringArea(ring) >= PolygonClipper.MIN_FRAGMENT_AREA_SQM) {
          polygons.push(PolygonClipper.refineRing(ring, grid));
        }
      }
    }
    return polygons;
  }

  private static collectComponent(
    mask: Array<Array<boolean>>,
    visited: Array<Array<boolean>>,
    startCol: number,
    startRow: number
  ): Array<Point2D> {
    const rows = mask.length;
    const cols = mask[0].length;
    const stack: Array<Point2D> = [{ x: startCol, y: startRow }];
    const cells: Array<Point2D> = [];
    visited[startRow][startCol] = true;
    while (stack.length > 0) {
      const current = stack.pop() as Point2D;
      cells.push(current);
      const neighbors: Array<Point2D> = [
        { x: current.x + 1, y: current.y },
        { x: current.x - 1, y: current.y },
        { x: current.x, y: current.y + 1 },
        { x: current.x, y: current.y - 1 }
      ];
      for (let i = 0; i < neighbors.length; i++) {
        const col = neighbors[i].x;
        const row = neighbors[i].y;
        if (col < 0 || row < 0 || col >= cols || row >= rows) {
          continue;
        }
        if (!mask[row][col] || visited[row][col]) {
          continue;
        }
        visited[row][col] = true;
        stack.push(neighbors[i]);
      }
    }
    return cells;
  }

  private static componentToRing(cells: Array<Point2D>, grid: GridSpec): Array<Point2D> {
    const cellSet: Set<string> = new Set();
    for (let i = 0; i < cells.length; i++) {
      cellSet.add(`${cells[i].x},${cells[i].y}`);
    }
    const edgeMap: Map<string, Array<Point2D>> = new Map();
    for (let i = 0; i < cells.length; i++) {
      const col = cells[i].x;
      const row = cells[i].y;
      if (!cellSet.has(`${col},${row - 1}`)) {
        PolygonClipper.toggleEdge(edgeMap, PolygonClipper.gridCorner(col, row, grid), PolygonClipper.gridCorner(col + 1, row, grid));
      }
      if (!cellSet.has(`${col + 1},${row}`)) {
        PolygonClipper.toggleEdge(edgeMap, PolygonClipper.gridCorner(col + 1, row, grid), PolygonClipper.gridCorner(col + 1, row + 1, grid));
      }
      if (!cellSet.has(`${col},${row + 1}`)) {
        PolygonClipper.toggleEdge(edgeMap, PolygonClipper.gridCorner(col + 1, row + 1, grid), PolygonClipper.gridCorner(col, row + 1, grid));
      }
      if (!cellSet.has(`${col - 1},${row}`)) {
        PolygonClipper.toggleEdge(edgeMap, PolygonClipper.gridCorner(col, row + 1, grid), PolygonClipper.gridCorner(col, row, grid));
      }
    }
    const edges: Array<Array<Point2D>> = [];
    edgeMap.forEach((value: Array<Point2D>) => {
      edges.push(value);
    });
    if (edges.length === 0) {
      return [];
    }
    const ring: Array<Point2D> = [edges[0][0], edges[0][1]];
    edges.splice(0, 1);
    while (edges.length > 0) {
      const tail = ring[ring.length - 1];
      let matched = -1;
      for (let i = 0; i < edges.length; i++) {
        if (PolygonClipper.pointsClose(edges[i][0], tail)) {
          ring.push(edges[i][1]);
          matched = i;
          break;
        }
        if (PolygonClipper.pointsClose(edges[i][1], tail)) {
          ring.push(edges[i][0]);
          matched = i;
          break;
        }
      }
      if (matched < 0) {
        break;
      }
      edges.splice(matched, 1);
    }
    return PolygonClipper.simplifyRing(ring);
  }

  private static toggleEdge(edgeMap: Map<string, Array<Point2D>>, start: Point2D, end: Point2D): void {
    const key = PolygonClipper.edgeKey(start, end);
    if (edgeMap.has(key)) {
      edgeMap.delete(key);
    } else {
      edgeMap.set(key, [start, end]);
    }
  }

  private static edgeKey(start: Point2D, end: Point2D): string {
    if (start.x < end.x || (start.x === end.x && start.y <= end.y)) {
      return `${start.x},${start.y}|${end.x},${end.y}`;
    }
    return `${end.x},${end.y}|${start.x},${start.y}`;
  }

  private static gridCorner(col: number, row: number, grid: GridSpec): Point2D {
    return {
      x: grid.bounds.minX + col * grid.step,
      y: grid.bounds.minY + row * grid.step
    };
  }

  private static pointsClose(a: Point2D, b: Point2D): boolean {
    const dx = a.x - b.x;
    const dy = a.y - b.y;
    return Math.sqrt(dx * dx + dy * dy) < 0.5;
  }

  private static simplifyRing(ring: Array<Point2D>): Array<Point2D> {
    if (ring.length <= 4) {
      return ring;
    }
    const simplified: Array<Point2D> = [];
    for (let i = 0; i < ring.length; i++) {
      const prev = ring[(i + ring.length - 1) % ring.length];
      const current = ring[i];
      const next = ring[(i + 1) % ring.length];
      const area = Math.abs((current.x - prev.x) * (next.y - prev.y) - (current.y - prev.y) * (next.x - prev.x));
      if (area > 0.2) {
        simplified.push(current);
      }
    }
    return simplified.length >= 3 ? simplified : ring;
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
}

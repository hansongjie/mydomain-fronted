export interface RoadPoint {
  lat: number;
  lng: number;
}

export interface RoadSegment {
  id: number;
  name: string;
  highway: string;
  points: Array<RoadPoint>;
}

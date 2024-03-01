from dataclasses import dataclass, field
from typing import List, Optional

@dataclass
class Coord:
    lat: float
    lon: float

    def to_tuple(self) -> tuple[float, float]:
        return (self.lat, self.lon)

    def to_geojson(self) -> list[float]:
        return [self.lon, self.lat]

@dataclass
class TurnInstruction:
    step_number: int
    instruction_text: str
    distance_m: float
    duration_s: float

@dataclass
class RouteResult:
    distance_m: float
    duration_s: float
    node_path: List[int] = field(default_factory=list)
    edge_path: List[int] = field(default_factory=list)
    geometry: List[Coord] = field(default_factory=list)
    instructions: List[TurnInstruction] = field(default_factory=list)

@dataclass
class MatchedPoint:
    original_lat: float
    original_lon: float
    matched_lat: float
    matched_lon: float
    edge_id: int
    confidence: float

@dataclass
class MatchResult:
    matched_points: List[MatchedPoint]
    total_distance_m: float
    average_confidence: float
    matched_geometry: List[Coord]

@dataclass
class Isochrone:
    center: Coord
    max_seconds: int
    boundary: List[Coord]

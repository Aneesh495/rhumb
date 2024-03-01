import json
import urllib.request
import urllib.parse
import urllib.error
from typing import List, Tuple, Optional, Dict, Any

from .types import Coord, RouteResult, TurnInstruction, MatchResult, MatchedPoint, Isochrone

class RhumbError(Exception):
    """Raised when the Rhumb routing engine returns an error or fails to connect."""
    pass

class RhumbClient:
    """High-performance client for interacting with the Rhumb geospatial engine daemon."""

    def __init__(self, base_url: str = "http://127.0.0.1:8080", timeout_s: float = 10.0):
        self.base_url = base_url.rstrip("/")
        self.timeout_s = timeout_s

    def health(self) -> Dict[str, Any]:
        """Query engine health, uptime, and metadata."""
        url = f"{self.base_url}/api/v1/health"
        req = urllib.request.Request(url, headers={"User-Agent": "Rhumb-Python-Client/0.1.0"})
        try:
            with urllib.request.urlopen(req, timeout=self.timeout_s) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                return data
        except urllib.error.URLError as e:
            raise RhumbError(f"Failed to connect to Rhumb engine at {self.base_url}: {e}")

    def route(
        self,
        from_coord: Tuple[float, float],
        to_coord: Tuple[float, float],
        algo: str = "dijkstra",
        profile: str = "car"
    ) -> RouteResult:
        """Compute shortest path route between two geographic coordinates."""
        params = urllib.parse.urlencode({
            "from": f"{from_coord[0]},{from_coord[1]}",
            "to": f"{to_coord[0]},{to_coord[1]}",
            "algo": algo,
            "profile": profile
        })
        url = f"{self.base_url}/api/v1/route?{params}"
        req = urllib.request.Request(url, headers={"User-Agent": "Rhumb-Python-Client/0.1.0"})
        try:
            with urllib.request.urlopen(req, timeout=self.timeout_s) as resp:
                data = json.loads(resp.read().decode("utf-8"))
        except urllib.error.URLError as e:
            raise RhumbError(f"Route calculation request failed: {e}")

        if "error" in data:
            raise RhumbError(f"Rhumb routing error: {data['error']}")

        instructions = []
        if "instructions" in data:
            for idx, inst in enumerate(data["instructions"]):
                instructions.append(TurnInstruction(
                    step_number=idx + 1,
                    instruction_text=inst.get("text", ""),
                    distance_m=float(inst.get("distance_m", 0.0)),
                    duration_s=float(inst.get("duration_ms", 0.0)) / 1000.0
                ))

        geom = []
        if "geometry" in data:
            for pt in data["geometry"]:
                geom.append(Coord(lat=float(pt["lat"]), lon=float(pt["lon"])))

        return RouteResult(
            distance_m=float(data.get("distance_m", 0.0)),
            duration_s=float(data.get("duration_ms", 0.0)) / 1000.0,
            node_path=data.get("node_path", []),
            edge_path=data.get("edge_path", []),
            geometry=geom,
            instructions=instructions
        )

    def match(
        self,
        points: List[Tuple[float, float]],
        search_radius_m: float = 50.0
    ) -> MatchResult:
        """Map-match raw GPS trajectory coordinates onto the road network using HMM Viterbi decoding."""
        payload = {
            "search_radius": search_radius_m,
            "points": [{"lat": p[0], "lon": p[1]} for p in points]
        }
        body = json.dumps(payload).encode("utf-8")
        url = f"{self.base_url}/api/v1/match"
        req = urllib.request.Request(
            url,
            data=body,
            headers={
                "Content-Type": "application/json",
                "User-Agent": "Rhumb-Python-Client/0.1.0"
            }
        )
        try:
            with urllib.request.urlopen(req, timeout=self.timeout_s) as resp:
                data = json.loads(resp.read().decode("utf-8"))
        except urllib.error.URLError as e:
            raise RhumbError(f"Map matching request failed: {e}")

        if "error" in data:
            raise RhumbError(f"Rhumb map matching error: {data['error']}")

        matched_pts = []
        for mp in data.get("matched_points", []):
            matched_pts.append(MatchedPoint(
                original_lat=float(mp["original_lat"]),
                original_lon=float(mp["original_lon"]),
                matched_lat=float(mp["matched_lat"]),
                matched_lon=float(mp["matched_lon"]),
                edge_id=int(mp["edge_id"]),
                confidence=float(mp.get("confidence", 1.0))
            ))

        geom = []
        for g in data.get("matched_geometry", []):
            geom.append(Coord(lat=float(g["lat"]), lon=float(g["lon"])))

        return MatchResult(
            matched_points=matched_pts,
            total_distance_m=float(data.get("total_distance_m", 0.0)),
            average_confidence=float(data.get("average_confidence", 1.0)),
            matched_geometry=geom
        )

    def isochrone(
        self,
        center: Tuple[float, float],
        max_duration_seconds: int = 300,
        profile: str = "car"
    ) -> Isochrone:
        """Compute reachable isochrone boundary from a center point within time threshold."""
        params = urllib.parse.urlencode({
            "center": f"{center[0]},{center[1]}",
            "time": str(max_duration_seconds),
            "profile": profile
        })
        url = f"{self.base_url}/api/v1/isochrone?{params}"
        req = urllib.request.Request(url, headers={"User-Agent": "Rhumb-Python-Client/0.1.0"})
        try:
            with urllib.request.urlopen(req, timeout=self.timeout_s) as resp:
                data = json.loads(resp.read().decode("utf-8"))
        except urllib.error.URLError as e:
            raise RhumbError(f"Isochrone request failed: {e}")

        if "error" in data:
            raise RhumbError(f"Rhumb isochrone error: {data['error']}")

        boundary = []
        for pt in data.get("boundary", []):
            boundary.append(Coord(lat=float(pt["lat"]), lon=float(pt["lon"])))

        return Isochrone(
            center=Coord(lat=center[0], lon=center[1]),
            max_seconds=max_duration_seconds,
            boundary=boundary
        )

    def get_tile(self, z: int, x: int, y: int) -> bytes:
        """Retrieve binary Mapbox Vector Tile (.mvt) protobuf for tile coordinates (z, x, y)."""
        url = f"{self.base_url}/tiles/{z}/{x}/{y}.mvt"
        req = urllib.request.Request(url, headers={"User-Agent": "Rhumb-Python-Client/0.1.0"})
        try:
            with urllib.request.urlopen(req, timeout=self.timeout_s) as resp:
                return resp.read()
        except urllib.error.URLError as e:
            raise RhumbError(f"Vector tile request failed: {e}")

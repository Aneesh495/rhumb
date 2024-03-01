import unittest
from unittest.mock import patch, MagicMock
import io
import json

from rhumb.types import Coord, RouteResult, TurnInstruction, MatchResult, MatchedPoint, Isochrone
from rhumb.client import RhumbClient, RhumbError

class TestRhumbTypes(unittest.TestCase):
    def test_coord_methods(self):
        c = Coord(lat=37.7749, lon=-122.4194)
        self.assertEqual(c.to_tuple(), (37.7749, -122.4194))
        self.assertEqual(c.to_geojson(), [-122.4194, 37.7749])

    def test_route_result_instantiation(self):
        step = TurnInstruction(step_number=1, instruction_text="Depart north", distance_m=250.0, duration_s=18.0)
        res = RouteResult(
            distance_m=1250.0,
            duration_s=90.0,
            node_path=[1, 2, 3],
            edge_path=[10, 11],
            geometry=[Coord(lat=37.77, lon=-122.42), Coord(lat=37.78, lon=-122.41)],
            instructions=[step]
        )
        self.assertEqual(res.distance_m, 1250.0)
        self.assertEqual(len(res.instructions), 1)
        self.assertEqual(res.instructions[0].step_number, 1)

class TestRhumbClient(unittest.TestCase):
    def setUp(self):
        self.client = RhumbClient(base_url="http://127.0.0.1:8080")

    @patch("urllib.request.urlopen")
    def test_health(self, mock_urlopen):
        mock_resp = MagicMock()
        mock_resp.read.return_value = json.dumps({"status": "healthy", "version": "0.1.0"}).encode("utf-8")
        mock_urlopen.return_value.__enter__.return_value = mock_resp

        data = self.client.health()
        self.assertEqual(data["status"], "healthy")
        self.assertEqual(data["version"], "0.1.0")

    @patch("urllib.request.urlopen")
    def test_route(self, mock_urlopen):
        payload = {
            "distance_m": 2720.0,
            "duration_ms": 230800,
            "node_path": [0, 1, 2, 3],
            "edge_path": [10, 11, 12],
            "geometry": [{"lat": 37.7850, "lon": -122.4150}, {"lat": 37.7730, "lon": -122.3990}],
            "instructions": [
                {"text": "Depart on Market St", "distance_m": 350.0, "duration_ms": 25000}
            ]
        }
        mock_resp = MagicMock()
        mock_resp.read.return_value = json.dumps(payload).encode("utf-8")
        mock_urlopen.return_value.__enter__.return_value = mock_resp

        res = self.client.route((37.7850, -122.4150), (37.7730, -122.3990), algo="dijkstra")
        self.assertAlmostEqual(res.distance_m, 2720.0)
        self.assertAlmostEqual(res.duration_s, 230.8)
        self.assertEqual(len(res.node_path), 4)
        self.assertEqual(len(res.instructions), 1)
        self.assertEqual(res.instructions[0].instruction_text, "Depart on Market St")

    @patch("urllib.request.urlopen")
    def test_match(self, mock_urlopen):
        payload = {
            "total_distance_m": 1104.8,
            "average_confidence": 0.85,
            "matched_points": [
                {
                    "original_lat": 37.7850,
                    "original_lon": -122.4150,
                    "matched_lat": 37.7850,
                    "matched_lon": -122.4150,
                    "edge_id": 4,
                    "confidence": 0.95
                }
            ],
            "matched_geometry": [
                {"lat": 37.7850, "lon": -122.4150}
            ]
        }
        mock_resp = MagicMock()
        mock_resp.read.return_value = json.dumps(payload).encode("utf-8")
        mock_urlopen.return_value.__enter__.return_value = mock_resp

        res = self.client.match([(37.7850, -122.4150), (37.7845, -122.4140)])
        self.assertAlmostEqual(res.total_distance_m, 1104.8)
        self.assertAlmostEqual(res.average_confidence, 0.85)
        self.assertEqual(len(res.matched_points), 1)
        self.assertEqual(res.matched_points[0].edge_id, 4)

    @patch("urllib.request.urlopen")
    def test_isochrone(self, mock_urlopen):
        payload = {
            "center": {"lat": 37.7850, "lon": -122.4150},
            "boundary": [
                {"lat": 37.7800, "lon": -122.4200},
                {"lat": 37.7900, "lon": -122.4100}
            ]
        }
        mock_resp = MagicMock()
        mock_resp.read.return_value = json.dumps(payload).encode("utf-8")
        mock_urlopen.return_value.__enter__.return_value = mock_resp

        iso = self.client.isochrone((37.7850, -122.4150), max_duration_seconds=300)
        self.assertEqual(len(iso.boundary), 2)
        self.assertEqual(iso.max_seconds, 300)

if __name__ == "__main__":
    unittest.main()

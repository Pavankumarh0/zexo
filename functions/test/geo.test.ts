import { test } from "node:test";
import assert from "node:assert/strict";

import { offsetPoint, haversineM, fuzzCoordinates } from "../src/lib/geo";

test("offsetPoint: measured distance matches request (~150m)", () => {
  for (const bearing of [0, Math.PI / 2, Math.PI, (3 * Math.PI) / 2]) {
    const p = offsetPoint(37.7749, -122.4194, 150, bearing);
    const back = haversineM({ lat: 37.7749, lng: -122.4194 }, p);
    assert.ok(Math.abs(back - 150) < 1.5, `bearing ${bearing}: ${back}`);
  }
});

test("fuzzCoordinates: offset within jitter band and != origin", () => {
  // Deterministic rand returning 0.5 -> mid bearing, mid distance (=150m).
  const fp = fuzzCoordinates(37.7749, -122.4194, 150, 0.25, () => 0.5);
  assert.ok(Math.abs(fp.offsetM - 150) < 1e-6);
  assert.notDeepEqual([fp.lat, fp.lng], [37.7749, -122.4194]);

  // Sweep the random source across [0,1) and check the band [112.5, 187.5].
  for (let i = 0; i < 100; i++) {
    const r = i / 100;
    const f = fuzzCoordinates(10, 10, 150, 0.25, () => r);
    assert.ok(f.offsetM >= 112.5 - 1e-6 && f.offsetM <= 187.5 + 1e-6, `${f.offsetM}`);
    const actual = haversineM({ lat: 10, lng: 10 }, { lat: f.lat, lng: f.lng });
    assert.ok(Math.abs(actual - f.offsetM) < 1.5);
  }
});

test("fuzzCoordinates: invalid params throw", () => {
  assert.throws(() => fuzzCoordinates(0, 0, 0));
  assert.throws(() => fuzzCoordinates(0, 0, 150, 1));
});

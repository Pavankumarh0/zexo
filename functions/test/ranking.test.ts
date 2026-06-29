import { test } from "node:test";
import assert from "node:assert/strict";

import {
  distanceScore,
  tagOverlap,
  sharedTags,
  computeScore,
  rank,
} from "../src/lib/ranking";

test("distanceScore: origin=1, edge=0, beyond clamped", () => {
  assert.equal(distanceScore(0, 5000), 1);
  assert.equal(distanceScore(5000, 5000), 0);
  assert.equal(distanceScore(9000, 5000), 0);
  assert.ok(Math.abs(distanceScore(2500, 5000) - 0.5) < 1e-9);
});

test("tagOverlap: Jaccard", () => {
  assert.equal(tagOverlap(["a", "b"], ["a", "b"]), 1);
  assert.equal(tagOverlap(["a"], ["b"]), 0);
  assert.ok(Math.abs(tagOverlap(["a", "b"], ["a", "c"]) - 1 / 3) < 1e-9);
  assert.equal(tagOverlap([], []), 0);
});

test("sharedTags sorted intersection", () => {
  assert.deepEqual(sharedTags(["jazz", "film"], ["film", "jazz", "x"]), ["film", "jazz"]);
});

test("computeScore: dual factor, zero weight rejected", () => {
  const noTags = computeScore(100, 5000, ["a"], ["z"]);
  const withTags = computeScore(100, 5000, ["a", "b"], ["a", "b"]);
  assert.ok(withTags > noTags);
  assert.throws(() => computeScore(100, 5000, ["a"], ["a"], 0, 1));
  assert.throws(() => computeScore(100, 5000, ["a"], ["a"], 1, 0));
  assert.ok(Math.abs(computeScore(0, 5000, ["a"], ["a"]) - 1) < 1e-9);
});

test("rank: score desc, distance asc, id asc", () => {
  const ranked = rank(
    ["jazz", "film"],
    [
      { userId: "far_match", distanceM: 4000, tags: ["jazz", "film"] },
      { userId: "near_nomatch", distanceM: 200, tags: ["sports"] },
      { userId: "near_match", distanceM: 300, tags: ["jazz"] },
    ],
    5000,
  );
  assert.equal(ranked[0].userId, "near_match");

  const tie = rank(
    ["a"],
    [
      { userId: "b", distanceM: 100, tags: ["a"] },
      { userId: "a", distanceM: 100, tags: ["a"] },
    ],
    1000,
  );
  assert.deepEqual(tie.map((t) => t.userId), ["a", "b"]);
});

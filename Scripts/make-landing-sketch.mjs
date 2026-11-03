// Draws the pencil sketch used as the landing page's icon (sasu.html in the sibling
// littlebobert.github.io repository) as a flipbook, in the way of Karui's and Umete's,
// laid out like the photo in Sasu's icon: a man in a kimono walks up the statue's
// sloping rock, stops where the statue stands, turns to face us and steps out into its
// stance to point at a written あ, which is ringed in red, then turns and walks on off
// the edge. Each drawing is redrawn with fresh wobble, so it boils like pencil on paper. Writes
// assets/sasu-icon-sketch.mp4, and him pointing as assets/sasu-icon-sketch.jpg. Nothing
// is committed or pushed.
//
//     node Scripts/make-landing-sketch.mjs
//
// Needs ffmpeg, and Playwright from Karui's AppStoreScreenshots/node_modules, or the
// package.json of another install in PLAYWRIGHT_FROM.
import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync } from "node:fs";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const site = process.env.LANDING_SITE ?? join(root, "../littlebobert.github.io");
const { chromium } = createRequire(process.env.PLAYWRIGHT_FROM ?? join(root, "../karui/AppStoreScreenshots/package.json"))("playwright");

const fps = 12;
// Drawn large for its detail, then brought down to 3.5 times the page's 64-point icon.
const drawnSize = 560;
const outputSize = 224;
// Fine lines go pale when brought down that far: deepens the pencil and leaves the paper.
const deepen = "curves=all='0/0 0.45/0.2 0.72/0.6 0.86/0.86 1/1'";
const graphite = "#34342f";
const paper = "#f5f1e9";
// Mostly pencil, as Karui's and Umete's are, with one red for the ring.
const robeTone = "#9c9990";
const legTone = "#6a6862";
const skinTone = "#c9c6bd";
const rockTone = "#bdbab2";
const red = "#d63a2c";

let seed = 11;
const rand = () => ((seed = (seed * 16807) % 2147483647) - 1) / 2147483646;
const j = (a) => (rand() - 0.5) * 2 * a;
const lerp = (a, b, t) => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t];
const add = (a, b) => [a[0] + b[0], a[1] + b[1]];
const along = (p, v, by) => [p[0] + v[0] * by, p[1] + v[1] * by];
const polar = (p, degrees, by) => along(p, [Math.cos((degrees * Math.PI) / 180), Math.sin((degrees * Math.PI) / 180)], by);
const line = (a, b, n = 8) => Array.from({ length: n + 1 }, (_, i) => lerp(a, b, i / n));
const smooth = (t) => t * t * (3 - 2 * t);
const pathOf = (points) => `M${points.map((p) => `${p[0].toFixed(1)} ${p[1].toFixed(1)}`).join("L")}Z`;

// A smooth curve through the points, closed or open.
function spline(points, closed, steps = 6) {
  const n = points.length, out = [];
  const get = (i) => (closed ? points[(i + n) % n] : points[Math.max(0, Math.min(n - 1, i))]);
  for (let i = 0; i < (closed ? n : n - 1); i++) {
    const p0 = get(i - 1), p1 = get(i), p2 = get(i + 1), p3 = get(i + 2);
    for (let s = 0; s < steps; s++) {
      const t = s / steps, t2 = t * t, t3 = t2 * t;
      out.push([0, 1].map((k) => 0.5 * (2 * p1[k] + (p2[k] - p0[k]) * t + (2 * p0[k] - 5 * p1[k] + 4 * p2[k] - p3[k]) * t2 + (3 * p1[k] - p0[k] - 3 * p2[k] + p3[k]) * t3)));
    }
  }
  out.push(closed ? out[0] : points[n - 1]);
  return out;
}

// The curve moved sideways by `by`, for the two edges of an arm or leg.
const offset = (points, by) => points.map((p, i) => {
  const q = points[Math.min(i + 1, points.length - 1)], o = points[Math.max(i - 1, 0)];
  const d = Math.hypot(q[0] - o[0], q[1] - o[1]) || 1;
  return [p[0] - ((q[1] - o[1]) / d) * by, p[1] + ((q[0] - o[0]) / d) * by];
});

// One pressed line as a filled shape: thin where the pencil lands and lifts, fuller in the
// middle, with the pressure drifting along the way. As in Karui's and Umete's.
function brush(points, width, opacity, { color = graphite, wobble = 2.5, shift = 2, overshoot = 6, heavy = 0.6 } = {}) {
  const ox = j(shift), oy = j(shift), phase = rand() * 6.28, freq = 0.012 + rand() * 0.01, drift = rand() * 6.28;
  const dense = [];
  points.forEach((p, i) => {
    dense.push(p);
    if (i < points.length - 1) dense.push(lerp(p, points[i + 1], 1 / 3), lerp(p, points[i + 1], 2 / 3));
  });
  let travelled = 0;
  const pts = dense.map((p, i) => {
    if (i) travelled += Math.hypot(p[0] - dense[i - 1][0], p[1] - dense[i - 1][1]);
    return [p[0] + ox + Math.sin(travelled * freq + phase) * wobble, p[1] + oy + Math.cos(travelled * freq * 1.3 + phase) * wobble];
  });
  const first = pts[0], next = pts[1], last = pts[pts.length - 1], before = pts[pts.length - 2];
  const reach = (p, q, by) => { const d = Math.hypot(p[0] - q[0], p[1] - q[1]) || 1; return [p[0] + ((p[0] - q[0]) / d) * by, p[1] + ((p[1] - q[1]) / d) * by]; };
  pts.unshift(reach(first, next, rand() * overshoot));
  pts.push(reach(last, before, rand() * overshoot));
  const left = [], right = [];
  pts.forEach((p, i) => {
    const q = pts[Math.min(i + 1, pts.length - 1)], o = pts[Math.max(i - 1, 0)];
    const d = Math.hypot(q[0] - o[0], q[1] - o[1]) || 1, nx = -(q[1] - o[1]) / d, ny = (q[0] - o[0]) / d;
    const t = i / (pts.length - 1);
    const pressure = (1 - heavy + heavy * Math.sin(Math.PI * t) ** 0.55) * (0.82 + 0.18 * Math.sin(t * 9 + drift));
    const half = (width * pressure) / 2;
    left.push([p[0] + nx * half, p[1] + ny * half]);
    right.unshift([p[0] - nx * half, p[1] - ny * half]);
  });
  const outline = [...left, ...right];
  let d = `M${outline[0][0].toFixed(1)} ${outline[0][1].toFixed(1)}`;
  for (let i = 1; i < outline.length; i++) {
    const m = lerp(outline[i], outline[(i + 1) % outline.length], 0.5);
    d += `Q${outline[i][0].toFixed(1)} ${outline[i][1].toFixed(1)} ${m[0].toFixed(1)} ${m[1].toFixed(1)}`;
  }
  return `<path d="${d}Z" fill="${color}" opacity="${(opacity * (0.82 + rand() * 0.3)).toFixed(2)}"/>`;
}

// Diagonal strokes across a box, rising to the right, to tone what they're clipped to.
function hatch(x0, x1, bottom, top, gap, width, tone, opacity, slope = 0.58) {
  let s = "";
  for (let x = x0; x < x1; x += gap + rand() * gap * 0.35) {
    s += brush(line([x, bottom], [x + (bottom - top) * slope, top], 4), width, opacity, { color: tone, wobble: 1.5, shift: 1, overshoot: 0, heavy: 0.3 });
  }
  return s;
}

// The scene is laid out as the icon's photo is: the statue's rock sloping down from the
// left to the right, under a deep sky, filling the square to its edges.

// Where a curve, left to right, is at x; straight on beyond its ends.
function heightOn(curve, x) {
  let i = curve.findIndex((p) => p[0] >= x);
  if (i <= 0) i = i === 0 ? 1 : curve.length - 1;
  const [a, b] = [curve[i - 1], curve[i]];
  return a[1] + ((b[1] - a[1]) * (x - a[0])) / (b[0] - a[0]);
}

// The rock's top, which he walks up, and a ledge below it on the left, as in the photo.
const rockTop = spline([[-60, 700], [0, 716], [120, 744], [215, 770], [411, 814], [571, 850], [743, 898], [866, 918], [1024, 936], [1100, 948]], false, 6);
const groundAt = (x) => heightOn(rockTop, x);
const ledge = spline([[-60, 846], [120, 870], [300, 922], [520, 986], [700, 1040], [800, 1080]], false, 5);
const rockShape = [...rockTop, [1100, 1100], [-60, 1100]];
const skyShape = [[-60, -60], [1100, -60], ...[...rockTop].reverse()];

function rock() {
  let s = `<g clip-path="url(#rock)">${hatch(-420, 1100, 1080, 680, 14, 9, rockTone, 0.7)}`;
  // The rock's face under the ledge in shade, crossed the other way.
  for (let x = -60; x < 1100; x += 9 + rand() * 5) {
    const top = heightOn(ledge, x) + 6 + rand() * 24;
    if (top > 1060) continue;
    s += brush(line([x, 1080], [x - (1080 - top) * 0.7, top], 3), 6, 0.6, { wobble: 1.5, shift: 1, overshoot: 2 });
  }
  s += "</g>";
  s += brush(rockTop, 16, 1, { wobble: 1.5, heavy: 0.5, overshoot: 6 }) + brush(rockTop, 8, 0.8, { wobble: 3, shift: 3, overshoot: 14 });
  s += brush(ledge, 10, 0.85, { wobble: 2, overshoot: 8 });
  for (const [a, b] of [[[250, 790], [292, 880]], [[640, 880], [600, 960]], [[880, 930], [930, 1010]]]) {
    s += brush(line(a, b, 4), 7, 0.75, { wobble: 3, overshoot: 4 });
  }
  return s;
}

// The sky, toned with the side of the pencil, deepest at the top as the photo's blue is:
// short, broad, faint strokes, more of them overlapping higher up.
function sky() {
  let s = `<g clip-path="url(#sky)">`;
  for (let y = -20; y < 700; y += 15 + rand() * 6) {
    const depth = Math.max(0, 1 - y / 700);
    for (let x = -60 + j(40); x < 1080; x += 70 + rand() * 60) {
      if (rand() > 0.25 + 0.75 * depth) continue;
      const length = 50 + rand() * 70;
      s += brush(line([x, y + length * 0.3], [x + length, y - length * 0.3], 2), 18, 0.12 + 0.16 * depth, { color: rockTone, wobble: 1, shift: 2, overshoot: 0, heavy: 0.8 });
    }
  }
  return `${s}</g>`;
}

// The walk, in drawings: each step is half a cycle, the planted foot staying put on the
// rock while the other swings forward, and he faces left, so forward is -x. He's drawn
// about his hip, standing on the rock at x = 0, and set into the scene at a scale.
const scale = 1.15;
const stride = 300;
const cycle = 10;
const thigh = 134, shin = 134, ankleHeight = 16;

function feet(pose, groundNear) {
  return [0, 1].map((k) => {
    const p = (pose.phase + k * 0.5) % 1;
    let reach, lift = 0;
    if (p < 0.5) {
      reach = pose.amp * (stride / 4 - stride * p);
    } else {
      const q = (p - 0.5) / 0.5;
      reach = pose.amp * (-stride / 4 + (stride / 2) * smooth(q));
      lift = pose.amp * 44 * Math.sin(Math.PI * q);
    }
    return { ankle: [-reach, groundNear(-reach) - ankleHeight - lift], lift };
  });
}

// The knee between the hip and the ankle, bent to the left, or with side -1 to the right.
function knee(hip, ankle, side = 1) {
  const dx = ankle[0] - hip[0], dy = ankle[1] - hip[1];
  const d = Math.min(Math.hypot(dx, dy), thigh + shin - 0.5);
  const base = Math.atan2(dy, dx), bend = Math.acos((thigh * thigh + d * d - shin * shin) / (2 * thigh * d));
  return [hip[0] + Math.cos(base + bend * side) * thigh, hip[1] + Math.sin(base + bend * side) * thigh];
}

// An arm or leg: paper under it so it hides what's behind, a tone, and its two edges.
function limb(points, width, tone) {
  const path = spline(points, false, 4);
  return `<polyline points="${path.map((p) => p.map((v) => v.toFixed(1)).join(",")).join(" ")}" fill="none" stroke="${paper}" stroke-width="${width}" stroke-linecap="round" stroke-linejoin="round"/>`
    + brush(path, width * 0.8, 0.75, { color: tone, wobble: 1.5, shift: 1, overshoot: 0, heavy: 0.2 })
    + brush(offset(path, width / 2), 10, 0.95, { wobble: 1.5, shift: 1, overshoot: 3 })
    + brush(offset(path, -width / 2), 10, 0.95, { wobble: 1.5, shift: 1, overshoot: 3 });
}

// A foot from the ankle, its toe `toward` along the rock.
function foot(ankle, toward, lift = 0) {
  const toe = [ankle[0] + toward, ankle[1] + 12 - lift * 0.2], heel = [ankle[0] - Math.sign(toward) * 10, ankle[1] + 12];
  return brush(line(heel, toe, 3), 20, 1, { wobble: 1, shift: 1, overshoot: 2, heavy: 0.3 });
}

// A kimono sleeve hanging from the upper arm, wide and deep, swinging down with the arm
// and sagging under it when it's raised. id names its clip for the hatching.
function sleeve(shoulder, elbowAngle, id) {
  const u = [Math.cos((elbowAngle * Math.PI) / 180), Math.sin((elbowAngle * Math.PI) / 180)];
  // Of the two sides of the arm, the one below and behind.
  const n = -u[1] * 0.5 + u[0] > 0 ? [-u[1], u[0]] : [u[1], -u[0]];
  const g = [0, 1];
  // Hanging, it falls either side of the arm; raised, it sags below it.
  const below = Math.max(0, -u[1]) * 0.6 + Math.abs(u[0]) * 0.6;
  const near = -32 * (1 - below), far = 52 + 30 * below;
  const shape = spline([
    along(along(shoulder, n, near * 0.4), u, -6),
    along(along(shoulder, u, 150), n, near),
    along(along(along(shoulder, u, 146), n, far), g, 18 * below),
    along(along(along(shoulder, u, 70), n, far + 12), g, 28 * below),
    along(along(along(shoulder, u, 4), n, far * 0.6), g, 8 * below),
  ], true, 6);
  const cuff = [along(along(shoulder, u, 150), n, near), along(along(along(shoulder, u, 146), n, far), g, 18 * below)];
  return {
    clip: `<clipPath id="${id}"><path d="${pathOf(shape)}"/></clipPath>`,
    svg: `<path d="${pathOf(shape)}" fill="${paper}"/><g clip-path="url(#${id})">${hatch(shoulder[0] - 260, shoulder[0] + 200, shoulder[1] + 260, shoulder[1] - 200, 13, 9, robeTone, 0.6)}</g>`
      + brush(shape, 13, 1, { wobble: 1.5, heavy: 0.5, overshoot: 4 }) + brush(line(cuff[0], cuff[1], 3), 7, 0.7, { overshoot: 2 }),
  };
}

function hand(wrist, angle, pointing) {
  const fist = Array.from({ length: 13 }, (_, k) => [wrist[0] + Math.cos(k / 2) * 15, wrist[1] + Math.sin(k / 2) * 15]);
  let s = `<circle cx="${wrist[0].toFixed(1)}" cy="${wrist[1].toFixed(1)}" r="15" fill="${paper}"/>` + brush(fist, 9, 1, { wobble: 1, shift: 1, overshoot: 0 });
  if (pointing) s += brush(line(polar(wrist, angle, 8), polar(wrist, angle, 46), 3), 11, 1, { wobble: 1, shift: 1, overshoot: 2, heavy: 0.3 });
  return s;
}

// The head, close-cropped, on its neck, its nose to the left: ear is where the ear is
// across it, near the middle side-on and at the back as he looks left facing us.
function head(center, neck, ear) {
  const skull = Array.from({ length: 25 }, (_, k) => { const a = (k / 24) * Math.PI * 2; return [center[0] + Math.cos(a) * 46, center[1] + Math.sin(a) * 54]; });
  let s = brush(line(add(center, [-14, 42]), add(neck, [-18, 4]), 3), 8, 0.9, { overshoot: 0 }) + brush(line(add(center, [22, 40]), add(neck, [16, -2]), 3), 8, 0.9, { overshoot: 0 });
  s += `<path d="${pathOf(skull)}" fill="${paper}"/><g clip-path="url(#head)">${hatch(center[0] - 120, center[0] + 60, center[1] + 60, center[1] - 60, 10, 7, skinTone, 0.6)}`;
  for (let x = center[0] - 30; x < center[0] + 60; x += 7 + rand() * 3) s += brush(line([x, center[1] - 12 + (x - center[0]) * 0.2], [x + 18, center[1] - 60], 3), 6, 0.75, { wobble: 1, shift: 1, overshoot: 0 });
  s += "</g>" + brush(skull, 12, 1, { wobble: 1.5, heavy: 0.5, overshoot: 4 });
  s += brush([add(center, [-40, -2]), add(center, [-53, 12]), add(center, [-40, 18])], 9, 1, { wobble: 1, overshoot: 0 });
  s += brush(line(add(center, [-26, -6]), add(center, [-20, -6]), 1), 9, 1, { wobble: 0.5, overshoot: 0 });
  s += brush(Array.from({ length: 6 }, (_, k) => [center[0] + ear + Math.cos(-1.4 + k * 0.6) * 11, center[1] + 6 + Math.sin(-1.4 + k * 0.6) * 13]), 6, 0.85, { wobble: 0.5, overshoot: 0 });
  return { clip: `<clipPath id="head"><path d="${pathOf(skull)}"/></clipPath>`, svg: s };
}

// The rock under him, in his own units, level with his hip's foot at 0.
const groundUnder = (pose) => (dx) => (groundAt(pose.x + dx * scale) - groundAt(pose.x)) / scale;

// His shadow on the rock, along its slope, from `from` to `to` across.
function shadow(groundNear, from, to) {
  let s = "";
  for (let i = 0; i < 5; i++) {
    const a = from + i * 6 + j(10), b = to - i * 10 + j(10), down = 10 + i * 4 + j(1.5);
    s += brush(line([a, groundNear(a) + down], [b, groundNear(b) + down + j(2)], 4), 7, 0.6 - i * 0.07, { wobble: 1.5, shift: 0.5, overshoot: 6 });
  }
  return s;
}

// Walking, side-on, facing left.
function walker(pose) {
  const groundNear = groundUnder(pose);
  const [nearFoot, farFoot] = feet(pose, groundNear);
  const hip = [0, -ankleHeight - (thigh + shin) * 0.985 + 12 * pose.amp + pose.amp * 5 * Math.cos(4 * Math.PI * pose.phase)];
  const shoulder = [hip[0] - 16, hip[1] - 214];
  const swing = pose.amp * 26 * Math.sin(2 * Math.PI * pose.phase);

  // The far arm, behind him, swinging against the near one.
  const farShoulder = add(shoulder, [12, 4]);
  const farElbow = polar(farShoulder, 90 - swing, 118), farWrist = polar(farElbow, 104 - swing, 104);
  const farSleeve = sleeve(farShoulder, 90 - swing, "farSleeve");
  let s = limb([farElbow, farWrist], 26, legTone) + farSleeve.svg + hand(farWrist, 104 - swing, false);

  // The legs, both under the robe from the knee up.
  for (const leg of [farFoot, nearFoot]) {
    const legHip = add(hip, leg === farFoot ? [10, 0] : [-4, 0]);
    s += limb([legHip, knee(legHip, leg.ankle), leg.ankle], 42, legTone) + foot(leg.ankle, -46, leg.lift);
  }

  // The robe, to just under the knee, its hem swaying as he walks.
  const sway = pose.amp * 12 * Math.sin(2 * Math.PI * pose.phase);
  const robe = spline([
    add(shoulder, [-30, 4]), add(hip, [-50, -80]), add(hip, [-58, -10]), add(hip, [-72 + sway, 150]), add(hip, [-6 + sway, 160]),
    add(hip, [66 + sway, 146]), add(hip, [58, -20]), add(hip, [52, -120]), add(shoulder, [42, 14]), add(shoulder, [12, -8]),
  ], true, 6);
  s += `<path d="${pathOf(robe)}" fill="${paper}"/><g clip-path="url(#robe)">`
    + hatch(hip[0] - 380, hip[0] + 120, hip[1] + 170, shoulder[1] - 20, 12, 10, robeTone, 0.7);
  // Pencil shade down the front and low on the back, crossed the other way.
  for (let x = hip[0] - 80; x < hip[0] + 90; x += 11 + rand() * 4) {
    const top = hip[1] + 30 + rand() * 40;
    s += brush(line([x + 70, hip[1] + 170], [x + 70 - (hip[1] + 170 - top) * 0.72, top], 3), 6, 0.6, { wobble: 1.5, shift: 1, overshoot: 2 });
  }
  s += "</g>" + brush(robe, 14, 1, { wobble: 1.5, heavy: 0.5, overshoot: 4 });
  s += brush(spline([add(hip, [-14, -4]), add(hip, [-26 + sway * 0.5, 70]), add(hip, [-34 + sway, 150])], false, 4), 7, 0.7, { overshoot: 2 });
  s += brush(spline([add(hip, [34, 0]), add(hip, [40 + sway * 0.5, 80]), add(hip, [44 + sway, 142])], false, 4), 7, 0.6, { overshoot: 2 });
  // The sash and the crossed collar.
  s += brush(line(add(hip, [-56, -30]), add(hip, [56, -27]), 4), 26, 0.75, { color: legTone, wobble: 1, overshoot: 0, heavy: 0.2 });
  s += brush(line(add(hip, [-58, -44]), add(hip, [56, -41]), 4), 8, 0.9, { overshoot: 3 }) + brush(line(add(hip, [-58, -14]), add(hip, [58, -12]), 4), 8, 0.9, { overshoot: 3 });
  s += brush(spline([add(shoulder, [-4, -4]), add(shoulder, [-18, 50]), add(hip, [-44, -50])], false, 4), 8, 0.9, { overshoot: 2 });

  const face = head(add(shoulder, [-18, -68]), shoulder, 10);
  s += face.svg;

  // The near arm, over the robe, swinging as he walks.
  const elbow = polar(shoulder, 90 + swing, 118), wrist = polar(elbow, 104 + swing, 104);
  const nearSleeve = sleeve(add(shoulder, [-4, 2]), 90 + swing, "nearSleeve");
  s += limb([elbow, wrist], 26, skinTone) + nearSleeve.svg + hand(wrist, 104 + swing, false);

  return {
    clips: `<clipPath id="robe"><path d="${pathOf(robe)}"/></clipPath>${face.clip}${farSleeve.clip}${nearSleeve.clip}`,
    svg: shadow(groundNear, -96, 90) + s,
  };
}

// Standing as the statue does, facing us, his head turned to look left: his right foot
// stepped out wide up the slope and his left under him, his right arm out straight to
// point, a deep sleeve hanging from it, and his left hand holding a scroll to his chest.
// turn is how far he's come round to face us from side-on, stance how far he's stepped
// out, step how high that foot is off the rock, and point how far the arm is raised.
const pointAngle = 204;

function stander(pose) {
  const groundNear = groundUnder(pose);
  const c = 0.4 + 0.6 * pose.turn;
  const X = (x) => x * c;
  const legs = [
    { top: X(-24), reach: X(-24) - 150 * pose.stance, lift: 40 * pose.step, side: 1, toe: -40 },
    { top: X(24), reach: X(24) + 30 * pose.stance, lift: 0, side: -1, toe: 26 },
  ];
  // The hip as high as both legs reach, the planted feet on the rock.
  const reachable = thigh + shin - 2;
  const hipY = Math.max(...legs.map((l) => groundNear(l.reach) - ankleHeight - Math.sqrt(reachable ** 2 - (l.reach - l.top) ** 2)));
  const top = hipY - 214;

  let s = "";
  for (const l of legs) {
    const ankle = [l.reach, groundNear(l.reach) - ankleHeight - l.lift], from = [l.top, hipY];
    s += limb([from, knee(from, ankle, l.side), ankle], 44, legTone) + foot(ankle, l.toe, l.lift);
  }

  // The robe, its outer coat open down the front and flared over his legs.
  const wide = pose.stance;
  const robe = spline([
    [X(-80), top + 8], [X(-70), top + 70], [X(-56), hipY - 40], [X(-70) - 70 * wide, hipY + 140], [X(-28) - 30 * wide, hipY + 160],
    [X(36) + 14 * wide, hipY + 172], [X(70) + 34 * wide, hipY + 158], [X(56), hipY - 40], [X(70), top + 70], [X(80), top + 8], [X(24), top - 4], [X(-24), top - 4],
  ], true, 6);
  s += `<path d="${pathOf(robe)}" fill="${paper}"/><g clip-path="url(#robe)">` + hatch(-420, 200, hipY + 190, top - 20, 12, 10, robeTone, 0.7);
  // Pencil shade on his left, away from the sun, crossed the other way.
  for (let x = X(10); x < X(90) + 40 * wide; x += 10 + rand() * 4) {
    const from = hipY + 190, upTo = top + 60 + rand() * 60;
    s += brush(line([x + 60, from], [x + 60 - (from - upTo) * 0.3, upTo], 3), 6, 0.6, { wobble: 1.5, shift: 1, overshoot: 2 });
  }
  s += "</g>" + brush(robe, 14, 1, { wobble: 1.5, heavy: 0.5, overshoot: 4 });
  s += brush(spline([[X(-22), top - 2], [X(-30), hipY - 30], [X(-40) - 30 * wide, hipY + 152]], false, 4), 8, 0.9, { overshoot: 2 });
  s += brush(spline([[X(22), top - 2], [X(32), hipY - 30], [X(44) + 16 * wide, hipY + 166]], false, 4), 8, 0.9, { overshoot: 2 });
  s += brush(line([X(-18), top], [X(8), top + 76], 3), 7, 0.85, { overshoot: 0 }) + brush(line([X(18), top], [X(-2), top + 62], 3), 7, 0.85, { overshoot: 0 });
  s += brush(line([X(-54), hipY - 30], [X(54), hipY - 28], 4), 24, 0.75, { color: legTone, wobble: 1, overshoot: 0, heavy: 0.2 });
  s += brush(line([X(-56), hipY - 43], [X(56), hipY - 41], 4), 7, 0.9, { overshoot: 3 }) + brush(line([X(-56), hipY - 16], [X(56), hipY - 14], 4), 7, 0.9, { overshoot: 3 });
  s += brush(spline([[X(-10), hipY - 10], [X(-16) - 10 * wide, hipY + 80], [X(-14) - 16 * wide, hipY + 162]], false, 4), 7, 0.6, { overshoot: 2 });

  const neck = [X(-2), top];
  const face = head([X(-8), top - 66], neck, 10 + 22 * pose.turn);
  s += face.svg;

  // His left arm, on our right, kept down by his side, the forearm angled in to hold a
  // scroll at his hip.
  const raise = Math.min(pose.point, 1);
  const leftShoulder = [X(70), top + 12];
  const leftUpper = 86 + (82 - 86) * raise, leftFore = 94 + (122 - 94) * raise;
  const leftElbow = polar(leftShoulder, leftUpper, 116), leftWrist = polar(leftElbow, leftFore, 96);
  const leftSleeve = sleeve(leftShoulder, leftUpper, "nearSleeve");
  s += leftSleeve.svg + limb([leftElbow, leftWrist], 26, skinTone);
  if (raise > 0.6) s += brush(line(add(leftWrist, [4, -44]), add(leftWrist, [-2, 50]), 3), 20, 0.9, { color: legTone, wobble: 1, shift: 1, overshoot: 2, heavy: 0.2 });
  s += hand(leftWrist, leftFore, false);

  // His right arm, on our left, raised out straight to point.
  const rightShoulder = [X(-70), top + 12];
  const rightUpper = 96 + (pointAngle - 4 - 96) * pose.point, rightFore = 100 + (pointAngle - 100) * pose.point;
  const rightElbow = polar(rightShoulder, rightUpper, 118), rightWrist = polar(rightElbow, rightFore, 104);
  const rightSleeve = sleeve(rightShoulder, rightUpper, "farSleeve");
  s += limb([rightElbow, rightWrist], 26, skinTone) + rightSleeve.svg + hand(rightWrist, rightFore, pose.point > 0.6);

  return {
    clips: `<clipPath id="robe"><path d="${pathOf(robe)}"/></clipPath>${face.clip}${rightSleeve.clip}${leftSleeve.clip}`,
    svg: shadow(groundNear, X(-110) - 150 * wide, X(100) + 30 * wide) + s,
    fingertip: polar(rightWrist, rightFore, 46),
  };
}

const figure = (pose) => (pose.turn > 0 ? stander(pose) : walker(pose));

// Where a point of his drawing is in the scene.
const placed = (pose, p) => [pose.x + p[0] * scale, groundAt(pose.x) + p[1] * scale];

// What he points at: あ, written in pencil, then ringed in red, out along his finger.
let target;
const kanaSize = 0.95;

function kana(amount) {
  if (amount <= 0) return "";
  const at = (x, y) => [target[0] + x * kanaSize, target[1] + y * kanaSize];
  const strokes = [
    line(at(-32, -28), at(30, -33), 4),
    spline([at(-6, -50), at(-7, -10), at(-3, 22), at(5, 46)], false, 4),
    spline([at(18, -14), at(4, 20), at(-18, 38), at(-34, 34), at(-34, 14), at(-12, -4), at(22, -6), at(40, 14), at(32, 38), at(10, 50)], false, 5),
  ];
  const shown = Math.ceil(strokes.length * amount);
  return strokes.slice(0, shown).map((stroke) => brush(stroke, 12, 1, { wobble: 1.5, shift: 2, overshoot: 4, heavy: 0.5 })).join("");
}

function ring(amount) {
  if (amount <= 0) return "";
  const loop = Array.from({ length: 41 }, (_, k) => {
    const a = -2.3 + (k / 40) * Math.PI * 2 * 1.12, r = 1 + 0.05 * Math.sin(k * 0.7);
    return [target[0] + Math.cos(a) * 76 * r, target[1] + 3 + Math.sin(a) * 66 * r];
  });
  const drawn = loop.slice(0, Math.max(2, Math.round(loop.length * amount)));
  return brush(drawn, 14, 1, { color: red, wobble: 2.5, shift: 2, overshoot: 0 }) + brush(drawn, 7, 0.8, { color: red, wobble: 4, shift: 5, overshoot: 0 });
}

// The timing, in drawings at 12 a second: he walks in from off the right edge and up the
// rock, slows to a stop where the statue stands, turns to face us, steps out and points,
// then turns back and walks on off the left edge; the あ and its ring go as he leaves.
const stopAt = 620;
const timeline = [];
const pace = (stride * scale) / cycle;
let x = stopAt + pace * (16 + 3.5);
let phase = 0;
function step(amp, extra = {}) {
  x -= amp * pace;
  phase = (phase + amp / cycle) % 1;
  timeline.push({ x, phase, amp, turn: 0, stance: 0, step: 0, point: 0, kana: 0, ring: 0, fade: 1, ...extra });
}
// The foot lifts most halfway through a step; parts of a move start and end at fractions
// of it, eased, so the arm can lead or follow the foot.
const stepping = (stance) => Math.sin(Math.PI * stance);
const part = (t, from, to) => smooth(Math.min(1, Math.max(0, (t - from) / (to - from))));
for (let i = 0; i < 16; i++) step(1);
for (let i = 1; i <= 8; i++) step(1 - smooth(i / 8));
step(0);
for (const turn of [0.25, 0.5, 0.75, 1]) step(0, { turn });
// He steps out, the arm rising with the foot and settling just after it lands.
for (let i = 1; i <= 8; i++) {
  const t = i / 8, stance = part(t, 0, 0.8);
  step(0, { turn: 1, stance, step: stepping(stance), point: part(t, 0.15, 1) + 0.05 * Math.sin(Math.PI * part(t, 0.7, 1)), kana: part(t, 0.55, 1) });
}
for (let i = 1; i <= 6; i++) step(0, { turn: 1, point: 1, stance: 1, kana: 1, ring: i / 6 });
for (let i = 0; i < 16; i++) step(0, { turn: 1, point: 1, stance: 1, kana: 1, ring: 1 });
// Then the arm comes down, the foot steps back in after it, and he turns to go.
for (let i = 1; i <= 7; i++) {
  const t = i / 7, stance = 1 - part(t, 0.3, 1);
  step(0, { turn: 1, point: 1 - part(t, 0, 0.7), stance, step: stepping(stance), kana: 1, ring: 1 });
}
for (const turn of [0.75, 0.5, 0.25]) step(0, { turn, kana: 1, ring: 1 });
for (let i = 1; i <= 8; i++) step(smooth(i / 8), { kana: 1, ring: 1 });
while (x > -260) step(1, { kana: 1, ring: 1 });
for (const fade of [0.6, 0.3, 0]) timeline.push({ x: -2000, phase, amp: 0, turn: 0, stance: 0, step: 0, point: 0, kana: 1, ring: 1, fade });
const pointing = { x: stopAt, phase: 0, amp: 0, turn: 1, stance: 1, step: 0, point: 1, kana: 1, ring: 1, fade: 1 };
target = polar(placed(pointing, figure(pointing).fingertip), pointAngle, 96);

const defs = `<filter id="pencil" x="-5%" y="-5%" width="110%" height="110%" color-interpolation-filters="sRGB">
<feTurbulence type="fractalNoise" baseFrequency="0.9 0.55" numOctaves="3" seed="4" result="grain"/>
<feColorMatrix in="grain" type="matrix" values="0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0 0 0 -2.6 2.05" result="tooth"/>
<feTurbulence type="fractalNoise" baseFrequency="0.035" numOctaves="2" seed="9" result="warp"/>
<feDisplacementMap in="SourceGraphic" in2="warp" scale="5" result="moved"/>
<feComposite in="moved" in2="tooth" operator="in"/>
</filter>
<filter id="paper" x="0" y="0" width="100%" height="100%" color-interpolation-filters="sRGB">
<feTurbulence type="fractalNoise" baseFrequency="0.7" numOctaves="4" seed="21"/>
<feColorMatrix type="matrix" values="0 0 0 0 0.45  0 0 0 0 0.42  0 0 0 0 0.34  0 0 0 0.09 -0.03"/>
</filter>
<clipPath id="rock"><path d="${pathOf(rockShape)}"/></clipPath>
<clipPath id="sky"><path d="${pathOf(skyShape)}"/></clipPath>
`;

// Takes of what holds still that alternate, so its lines boil without every frame being new.
const takes = [0, 1, 2].map(() => ({ sky: sky(), rock: rock() }));

function page(frame, index, size) {
  seed = 1000 + index * 97;
  const take = takes[Math.floor(index / 2) % takes.length];
  const onScene = frame.x < 1380 && frame.x > -300;
  const him = onScene ? figure(frame) : { clips: "", svg: "" };
  const marks = `<g opacity="${frame.fade}">${kana(frame.kana)}${ring(frame.ring)}</g>`;
  return `<!doctype html><body style="margin:0;background:${paper}"><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="${size}" height="${size}" style="display:block"><defs>${defs}${him.clips}</defs>
<rect width="1024" height="1024" fill="${paper}"/><rect width="1024" height="1024" filter="url(#paper)"/>
<g stroke="none" filter="url(#pencil)">
${take.sky}${take.rock}${marks}
${onScene ? `<g transform="translate(${frame.x.toFixed(1)} ${groundAt(frame.x).toFixed(1)}) scale(${scale})">${him.svg}</g>` : ""}
</g></svg></body>`;
}

const work = mkdtempSync(join(tmpdir(), "sasu-sketch-"));
const browser = await chromium.launch();
const tab = await browser.newPage({ viewport: { width: drawnSize, height: drawnSize } });
for (const [index, frame] of timeline.entries()) {
  await tab.setContent(page(frame, index, drawnSize));
  await tab.screenshot({ path: join(work, `${String(index).padStart(4, "0")}.png`) });
}
await tab.setContent(page(pointing, 0, drawnSize));
await tab.screenshot({ path: join(work, "still.png") });
await browser.close();

execFileSync("ffmpeg", ["-v", "error", "-y", "-framerate", String(fps), "-i", join(work, "%04d.png"),
  "-vf", `scale=${outputSize}:${outputSize}:flags=lanczos,${deepen},format=yuv420p`, "-r", "24", "-c:v", "libx264", "-profile:v", "high", "-crf", "22", "-preset", "slow",
  "-an", "-movflags", "+faststart", join(site, "assets/sasu-icon-sketch.mp4")]);
execFileSync("ffmpeg", ["-v", "error", "-y", "-i", join(work, "still.png"), "-vf", `scale=${outputSize}:${outputSize}:flags=lanczos,${deepen}`, "-q:v", "2", "-update", "1",
  join(site, "assets/sasu-icon-sketch.jpg")]);
rmSync(work, { recursive: true, force: true });
console.log(`${timeline.length} drawings, ${(timeline.length / fps).toFixed(1)} s. Installed in ${site}.`);

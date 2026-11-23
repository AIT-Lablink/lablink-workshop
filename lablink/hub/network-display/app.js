const SUBSTATIONS = 10;
const NODES = 4;

const INTERVAL_MS = 1000;
const FALLBACK_LOAD_W = 80000;
const MISSING_COLOR = "#b7c0c0";
const MISSING_WIDTH = 3;

const PITCH = 48;
const X0 = 140;
const RIGHT = 50;
const PROBE_R = 4.6;
const RING_R = 6.3;
const SUPPLY_Y = 52;
const RETURN_Y = 176;
const HOUSE_TOP = 78;
const HOUSE_BOT = 148;
const HOUSE_W = 56;
const PLANT_W = 64;

const SVGNS = "http://www.w3.org/2000/svg";

function range(from, to) {
  const values = [];
  for (let i = from; i <= to; i += 1) values.push(i);
  return values;
}

function xOf(index) {
  return X0 + index * PITCH;
}

function supplyProbes() {
  const probes = [];
  for (let pipe = 1; pipe < SUBSTATIONS; pipe += 1) {
    for (let node = 1; node < NODES; node += 1) probes.push({ pipe, node });
  }
  for (let node = 1; node <= NODES; node += 1) probes.push({ pipe: SUBSTATIONS, node });
  return probes.map((probe) => ({
    id: "TSupPip" + probe.pipe + "_" + probe.node,
    label: "S" + probe.pipe + "." + probe.node
  }));
}

function returnProbes() {
  const probes = [];
  for (let node = 1; node <= NODES; node += 1) probes.push({ pipe: 1, node });
  for (let pipe = 2; pipe <= SUBSTATIONS; pipe += 1) {
    for (let node = 2; node <= NODES; node += 1) probes.push({ pipe, node });
  }
  return probes.map((probe) => ({
    id: "TRetPip" + probe.pipe + "_" + probe.node,
    label: "R" + probe.pipe + "." + probe.node
  }));
}

function supplyGradientChannels(pipe) {
  const channels = [];
  for (let node = 1; node <= NODES; node += 1) {
    if (pipe < SUBSTATIONS && node === NODES) channels.push("TSupPip" + (pipe + 1) + "_1");
    else channels.push("TSupPip" + pipe + "_" + node);
  }
  return channels;
}

function returnGradientChannels(pipe) {
  if (pipe === 1) return range(1, NODES).map((node) => "TRetPip1_" + node);
  const channels = ["TRetPip" + (pipe - 1) + "_" + NODES];
  for (let node = 2; node <= NODES; node += 1) channels.push("TRetPip" + pipe + "_" + node);
  return channels;
}

const SUPPLY_PROBES = supplyProbes();
const RETURN_PROBES = returnProbes();
const PIPES = range(1, SUBSTATIONS).map((pipe) => ({
  pipe,
  x0: (NODES - 1) * (pipe - 1),
  x1: (NODES - 1) * pipe,
  mSup: "mSupPip" + pipe,
  mRet: "mRetPip" + pipe,
  supChannels: supplyGradientChannels(pipe),
  retChannels: returnGradientChannels(pipe)
}));
const STATIONS = range(1, SUBSTATIONS).map((k) => ({
  k,
  xIndex: (NODES - 1) * k,
  tSup: "TSupSub" + k,
  tRet: "TRetSub" + k,
  m: "mSub" + k,
  q: "QLoa" + k
}));

const CHANNELS = SUPPLY_PROBES.map((probe) => probe.id).concat(
  RETURN_PROBES.map((probe) => probe.id),
  STATIONS.map((station) => station.tSup),
  STATIONS.map((station) => station.tRet),
  PIPES.map((pipe) => pipe.mSup),
  PIPES.map((pipe) => pipe.mRet),
  STATIONS.map((station) => station.m),
  STATIONS.map((station) => station.q)
);

const UNITS = {};
CHANNELS.forEach((id) => {
  UNITS[id] = id.charAt(0) === "T" ? "K" : (id.charAt(0) === "Q" ? "W" : "kg/s");
});

const PROBE_COUNT = (NODES - 1) * SUBSTATIONS + 1;
const WIDTH = xOf(PROBE_COUNT - 1) + RIGHT;
const HEIGHT = 210;

let busy = false;

function el(name, attrs, parent) {
  const node = document.createElementNS(SVGNS, name);
  Object.keys(attrs).forEach((key) => node.setAttribute(key, attrs[key]));
  if (parent) parent.appendChild(node);
  return node;
}

function titled(name, attrs, parent) {
  const node = el(name, attrs, parent);
  el("title", {}, node);
  return node;
}

function usable(sample) {
  if (!sample || sample.missing || sample.validity === "invalid") return null;
  if (typeof sample.value !== "number" || !Number.isFinite(sample.value)) return null;
  return sample.value;
}

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}

function mix(start, end, t) {
  const from = [1, 3, 5].map((i) => parseInt(start.slice(i, i + 2), 16));
  const to = [1, 3, 5].map((i) => parseInt(end.slice(i, i + 2), 16));
  const mixed = from.map((channel, i) => Math.round(channel + (to[i] - channel) * t));
  return "#" + mixed.map((channel) => channel.toString(16).padStart(2, "0")).join("");
}

function scaleColor(kelvin, celsiusMin, celsiusMax, low, high) {
  const t = clamp((kelvin - 273.15 - celsiusMin) / (celsiusMax - celsiusMin), 0, 1);
  return mix(low, high, t);
}

function supplyColor(kelvin) {
  return scaleColor(kelvin, 50, 80, "#5a0000", "#ff3333");
}

function returnColor(kelvin) {
  return scaleColor(kelvin, 20, 33, "#001466", "#33aaff");
}

function flowWidth(kgPerS) {
  return clamp(5.2 * Math.abs(kgPerS), 2, 12);
}

function formatLoad(watts) {
  const kw = watts / 1000;
  const digits = Math.abs(kw) >= 10 ? 0 : 1;
  return kw.toFixed(digits) + " kW";
}

function sampleLine(id, samples) {
  const value = usable(samples[id]);
  if (value === null) return id + ": no sample";
  return id + ": " + value + " " + UNITS[id];
}

function setTitle(elementId, text) {
  document.getElementById(elementId).querySelector("title").textContent = text;
}

function paintNode(elementId, channelId, colorOf, samples) {
  const value = usable(samples[channelId]);
  const node = document.getElementById(elementId);
  node.setAttribute("fill", value === null ? MISSING_COLOR : colorOf(value));
  setTitle(elementId, sampleLine(channelId, samples));
}

function paintSolid(elementId, colorId, flowId, colorOf, samples) {
  const color = usable(samples[colorId]);
  const flow = usable(samples[flowId]);
  const line = document.getElementById(elementId);
  setTitle(elementId, sampleLine(colorId, samples) + "\n" + sampleLine(flowId, samples));
  if (color === null || flow === null) {
    line.setAttribute("stroke", MISSING_COLOR);
    line.setAttribute("stroke-width", String(MISSING_WIDTH));
    return;
  }
  line.setAttribute("stroke", colorOf(color));
  line.setAttribute("stroke-width", String(flowWidth(flow)));
}

function paintGradient(elementId, gradientId, channelIds, flowId, colorOf, samples) {
  const temps = channelIds.map((id) => usable(samples[id]));
  const flow = usable(samples[flowId]);
  const line = document.getElementById(elementId);
  setTitle(elementId, channelIds.concat(flowId).map((id) => sampleLine(id, samples)).join("\n"));
  if (temps.some((value) => value === null) || flow === null) {
    line.setAttribute("stroke", MISSING_COLOR);
    line.setAttribute("stroke-width", String(MISSING_WIDTH));
    return;
  }
  temps.forEach((kelvin, index) => {
    document.getElementById(gradientId + "-" + index).setAttribute("stop-color", colorOf(kelvin));
  });
  line.setAttribute("stroke", "url(#" + gradientId + ")");
  line.setAttribute("stroke-width", String(flowWidth(flow)));
}

function paintHouse(pathId, valueId, tempId, loadId, colorOf, samples) {
  const temp = usable(samples[tempId]);
  document.getElementById(pathId).setAttribute("fill", temp === null ? MISSING_COLOR : colorOf(temp));
  const load = usable(samples[loadId]);
  document.getElementById(valueId).textContent = formatLoad(load === null ? FALLBACK_LOAD_W : load);
  const loadTip = load === null ? loadId + " has no sample yet" : loadId + ": " + load + " W";
  setTitle(pathId, sampleLine(tempId, samples) + "\n" + loadTip);
  setTitle(valueId.replace("-value", ""), loadTip);
}

function paint(samples) {
  SUPPLY_PROBES.forEach((probe, index) => paintNode("node-sup-" + index, probe.id, supplyColor, samples));
  RETURN_PROBES.forEach((probe, index) => paintNode("node-ret-" + index, probe.id, returnColor, samples));

  paintSolid("sup-riser", "TSupPip1_1", "mSupPip1", supplyColor, samples);
  paintSolid("ret-riser", "TRetPip1_1", "mRetPip1", returnColor, samples);
  PIPES.forEach((pipe) => {
    paintGradient("sup-seg-" + pipe.pipe, "sup-grad-" + pipe.pipe, pipe.supChannels, pipe.mSup, supplyColor, samples);
    paintGradient("ret-seg-" + pipe.pipe, "ret-grad-" + pipe.pipe, pipe.retChannels, pipe.mRet, returnColor, samples);
  });
  STATIONS.forEach((station) => {
    paintSolid("sup-stub-" + station.k, station.tSup, station.m, supplyColor, samples);
    paintSolid("ret-stub-" + station.k, station.tRet, station.m, returnColor, samples);
    paintHouse("house-" + station.k, "loa-" + station.k + "-value", station.tSup, station.q, supplyColor, samples);
  });
}

function housing(parent, cx, width) {
  const x = cx - width / 2;
  el("rect", {
    class: "housing",
    x: x,
    y: HOUSE_TOP,
    width: width,
    height: HOUSE_BOT - HOUSE_TOP,
    rx: 1.6,
    ry: 1.6
  }, parent);
  el("path", { class: "housing-rim", d: "M " + (x + 1.6) + "," + (HOUSE_TOP + 2.2) + " H " + (x + width - 1.6) }, parent);
  const screws = el("g", { class: "screws" }, parent);
  [[3.2, 3.2], [width - 3.2, 3.2], [3.2, HOUSE_BOT - HOUSE_TOP - 3.2], [width - 3.2, HOUSE_BOT - HOUSE_TOP - 3.2]]
    .forEach(([dx, dy]) => el("circle", { cx: x + dx, cy: HOUSE_TOP + dy, r: 1.6 }, screws));
}

function build() {
  const probesEach = 2 * PROBE_COUNT;
  document.getElementById("topology").textContent =
    "1 plant \u00b7 " + SUBSTATIONS + " substations \u00b7 " + probesEach + " sensors";

  const svg = document.getElementById("diagram");
  const diagramHeight = HEIGHT - 16;
  svg.setAttribute("viewBox", "0 16 " + WIDTH + " " + diagramHeight);
  // Fixed CSS size, one user unit per pixel, so browser zoom enlarges the drawing
  // instead of refitting it to the panel. The panel scrolls when it no longer fits.
  svg.setAttribute("width", String(WIDTH));
  svg.setAttribute("height", String(diagramHeight));

  const defs = el("defs", {}, svg);
  PIPES.forEach((pipe) => {
    [["sup-grad-" + pipe.pipe, SUPPLY_Y], ["ret-grad-" + pipe.pipe, RETURN_Y]].forEach(([id, y]) => {
      const gradient = el("linearGradient", {
        id: id,
        gradientUnits: "userSpaceOnUse",
        x1: xOf(pipe.x0),
        y1: y,
        x2: xOf(pipe.x1),
        y2: y
      }, defs);
      for (let stop = 0; stop < NODES; stop += 1) {
        el("stop", {
          id: id + "-" + stop,
          offset: String(stop / (NODES - 1)),
          "stop-color": MISSING_COLOR
        }, gradient);
      }
    });
  });

  el("linearGradient", { id: "steel", x1: 0, y1: 0, x2: 0, y2: 1 }, defs);
  defs.lastChild.appendChild(el("stop", { offset: 0, "stop-color": "#fbfcfd" }));
  defs.lastChild.appendChild(el("stop", { offset: 0.08, "stop-color": "#eef2f6" }));
  defs.lastChild.appendChild(el("stop", { offset: 1, "stop-color": "#d9e1e8" }));
  const flange = el("linearGradient", { id: "flange", x1: 0, y1: 0, x2: 0, y2: 1 }, defs);
  el("stop", { offset: 0, "stop-color": "#eef2f6" }, flange);
  el("stop", { offset: 0.5, "stop-color": "#a9b7c4" }, flange);
  el("stop", { offset: 1, "stop-color": "#76889a" }, flange);
  const probeGrad = el("radialGradient", { id: "probe", cx: 0.4, cy: 0.35, r: 0.7 }, defs);
  el("stop", { offset: 0, "stop-color": "#ffffff" }, probeGrad);
  el("stop", { offset: 0.6, "stop-color": "#c3ced9" }, probeGrad);
  el("stop", { offset: 1, "stop-color": "#7f90a2" }, probeGrad);
  const glow = el("filter", {
    id: "glow",
    filterUnits: "userSpaceOnUse",
    x: 0,
    y: 16,
    width: WIDTH,
    height: HEIGHT
  }, defs);
  el("feGaussianBlur", { in: "SourceGraphic", stdDeviation: 1.6, result: "blur" }, glow);
  const transfer = el("feComponentTransfer", { in: "blur", result: "soft" }, glow);
  el("feFuncA", { type: "linear", slope: 0.45 }, transfer);
  const merge = el("feMerge", {}, glow);
  el("feMergeNode", { in: "soft" }, merge);
  el("feMergeNode", { in: "SourceGraphic" }, merge);
  const bench = el("pattern", { id: "bench", width: 4, height: 4, patternUnits: "userSpaceOnUse" }, defs);
  el("path", { d: "M 4 0 L 0 0 0 4", fill: "none", stroke: "#1f5d99", "stroke-opacity": 0.07, "stroke-width": 0.25 }, bench);

  el("rect", { x: 0, y: 16, width: WIDTH, height: HEIGHT - 16, fill: "url(#bench)" }, svg);

  const x0 = xOf(0);
  const xLast = xOf(PROBE_COUNT - 1);
  const supplyOutline = "M " + x0 + "," + HOUSE_TOP + " V " + SUPPLY_Y + " H " + xLast + " V " + HOUSE_TOP;
  const returnOutline = "M " + xLast + "," + HOUSE_BOT + " V " + RETURN_Y + " H " + x0 + " V " + HOUSE_BOT;
  const supplyStubs = STATIONS.slice(0, -1).map((station) => "M " + xOf(station.xIndex) + "," + SUPPLY_Y + " V " + HOUSE_TOP).join(" ");
  const returnStubs = STATIONS.slice(0, -1).map((station) => "M " + xOf(station.xIndex) + "," + HOUSE_BOT + " V " + RETURN_Y).join(" ");

  const jacket = el("g", { class: "jacket", fill: "none", "stroke-linecap": "round", "stroke-linejoin": "round", "aria-hidden": "true" }, svg);
  [supplyOutline + " " + supplyStubs, returnOutline + " " + returnStubs].forEach((d) => {
    el("path", { class: "jacket-outer", d: d }, jacket);
    el("path", { class: "jacket-bore", d: d }, jacket);
  });
  el("path", {
    class: "jacket-shine",
    d: "M " + (x0 + 8) + "," + (SUPPLY_Y - 6.4) + " H " + (xLast - 8) + " M " + (x0 + 8) + "," + (RETURN_Y - 6.4) + " H " + (xLast - 8)
  }, jacket);

  const medium = el("g", {
    fill: "none",
    stroke: MISSING_COLOR,
    "stroke-width": MISSING_WIDTH,
    "stroke-linecap": "round",
    "stroke-linejoin": "round",
    filter: "url(#glow)"
  }, svg);
  titled("line", { id: "sup-riser", x1: x0, y1: HOUSE_TOP, x2: x0, y2: SUPPLY_Y }, medium);
  PIPES.forEach((pipe) => {
    titled("line", { id: "sup-seg-" + pipe.pipe, x1: xOf(pipe.x0), y1: SUPPLY_Y, x2: xOf(pipe.x1), y2: SUPPLY_Y }, medium);
  });
  STATIONS.forEach((station) => {
    const x = xOf(station.xIndex);
    titled("line", { id: "sup-stub-" + station.k, x1: x, y1: SUPPLY_Y, x2: x, y2: HOUSE_TOP }, medium);
  });
  titled("line", { id: "ret-riser", x1: x0, y1: HOUSE_BOT, x2: x0, y2: RETURN_Y }, medium);
  PIPES.forEach((pipe) => {
    titled("line", { id: "ret-seg-" + pipe.pipe, x1: xOf(pipe.x0), y1: RETURN_Y, x2: xOf(pipe.x1), y2: RETURN_Y }, medium);
  });
  STATIONS.forEach((station) => {
    const x = xOf(station.xIndex);
    titled("line", { id: "ret-stub-" + station.k, x1: x, y1: HOUSE_BOT, x2: x, y2: RETURN_Y }, medium);
  });

  const tracer = el("g", { class: "tracer", fill: "none", "aria-hidden": "true" }, svg);
  el("path", { d: supplyOutline }, tracer);
  el("path", { d: supplyStubs }, tracer);
  el("path", { d: returnOutline }, tracer);
  el("path", { d: returnStubs }, tracer);

  const pipeLabel = el("g", { class: "pipe-label", "aria-hidden": "true" }, svg);
  const supplyWord = el("text", { x: 62, y: SUPPLY_Y + 4 }, pipeLabel);
  supplyWord.textContent = "SUPPLY \u25b8";
  const returnWord = el("text", { x: 62, y: RETURN_Y + 4 }, pipeLabel);
  returnWord.textContent = "\u25c2 RETURN";

  const plant = el("g", { id: "plant" }, svg);
  housing(plant, x0, PLANT_W);
  const iconTop = HOUSE_TOP + 28;
  const iconBot = HOUSE_BOT - 6;
  const iconLeft = x0 - PLANT_W / 2 + 8;
  el("path", {
    class: "plant-icon",
    d: "M " + iconLeft + "," + iconBot + " V " + iconTop + " h 8 v 16 l 10,-10 v 10 l 9,-9 v 9 l 8,-8 V " + iconBot + " Z"
  }, plant);

  STATIONS.forEach((station) => {
    const x = xOf(station.xIndex);
    const group = el("g", { id: "substation-" + station.k }, svg);
    housing(group, x, HOUSE_W);
    const roof = HOUSE_TOP + 28;
    const base = HOUSE_BOT - 5;
    const half = HOUSE_W * 0.34;
    titled("path", {
      id: "house-" + station.k,
      class: "house",
      fill: MISSING_COLOR,
      d: "M " + (x - half) + "," + base + " V " + (roof + 14) + " L " + x + "," + roof + " L " + (x + half) + "," + (roof + 14) + " V " + base + " Z"
    }, group);
    const load = el("text", {
      id: "loa-" + station.k,
      class: "load",
      x: x,
      y: base - 10,
      "text-anchor": "middle",
      fill: "#ffffff",
      "font-size": 11
    }, group);
    el("title", {}, load);
    const value = el("tspan", { id: "loa-" + station.k + "-value" }, load);
    value.textContent = formatLoad(FALLBACK_LOAD_W);
  });

  const tags = el("g", { class: "tag", "aria-hidden": "true" }, svg);
  const plantTag = el("text", { x: x0, y: HOUSE_TOP + 16, "text-anchor": "middle" }, tags);
  plantTag.textContent = "PLANT";
  STATIONS.forEach((station) => {
    const tag = el("text", { x: xOf(station.xIndex), y: HOUSE_TOP + 16, "text-anchor": "middle" }, tags);
    tag.textContent = "SUB " + station.k;
  });

  const flanges = el("g", { class: "flanges", fill: "url(#flange)", "aria-hidden": "true" }, svg);
  [x0].concat(STATIONS.map((station) => xOf(station.xIndex))).forEach((x) => {
    el("rect", { x: x - 8, y: HOUSE_TOP - 1.6, width: 16, height: 3.2, rx: 0.6 }, flanges);
    el("rect", { x: x - 8, y: HOUSE_BOT - 1.6, width: 16, height: 3.2, rx: 0.6 }, flanges);
  });

  const rings = el("g", { class: "probe-ring", fill: "url(#probe)", "aria-hidden": "true" }, svg);
  SUPPLY_PROBES.forEach((probe, index) => el("circle", { cx: xOf(index), cy: SUPPLY_Y, r: RING_R }, rings));
  RETURN_PROBES.forEach((probe, index) => el("circle", { cx: xOf(index), cy: RETURN_Y, r: RING_R }, rings));

  const dots = el("g", { class: "probe" }, svg);
  SUPPLY_PROBES.forEach((probe, index) => {
    titled("circle", { id: "node-sup-" + index, cx: xOf(index), cy: SUPPLY_Y, r: PROBE_R, fill: MISSING_COLOR }, dots);
  });
  RETURN_PROBES.forEach((probe, index) => {
    titled("circle", { id: "node-ret-" + index, cx: xOf(index), cy: RETURN_Y, r: PROBE_R, fill: MISSING_COLOR }, dots);
  });

  const labels = el("g", { class: "probe-label", "text-anchor": "middle", "aria-hidden": "true" }, svg);
  SUPPLY_PROBES.forEach((probe, index) => {
    const label = el("text", { x: xOf(index), y: SUPPLY_Y - 16 }, labels);
    label.textContent = probe.label;
  });
  RETURN_PROBES.forEach((probe, index) => {
    const label = el("text", { x: xOf(index), y: RETURN_Y + 20 }, labels);
    label.textContent = probe.label;
  });
}

function mark(text, ok) {
  const status = document.getElementById("status");
  status.textContent = text;
  status.className = ok ? "ok" : "down";
}

async function readSample(id) {
  const response = await fetch("/simpledh/channel/" + encodeURIComponent(id) + "/sample");
  if (!response.ok) return { missing: true };
  return response.json();
}

async function poll() {
  if (busy) return;
  busy = true;
  try {
    const statusResponse = await fetch("/simpledh/status");
    if (!statusResponse.ok) throw new Error("status");
    const status = await statusResponse.json();
    const pairs = await Promise.all(CHANNELS.map(async (id) => {
      try {
        return [id, await readSample(id)];
      } catch (err) {
        return [id, { missing: true }];
      }
    }));
    paint(Object.fromEntries(pairs));
    if (status.connected === "yes") mark("connected", true);
    else if (status.connected === "no") mark("not connected", false);
    else mark("unknown", false);
  } catch (err) {
    mark("disconnected", false);
  } finally {
    busy = false;
  }
}

build();
poll();
setInterval(poll, INTERVAL_MS);

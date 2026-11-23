const INTERVAL_MS = 1000;
const FALLBACK_LOAD_W = 80000;
const MISSING_COLOR = "#b7c0c0";
const MISSING_WIDTH = 3;

const SUPPLY_NODES = ["TSupPip1_1", "TSupPip1_2", "TSupPip1_3", "TSupPip2_1", "TSupPip2_2", "TSupPip2_3", "TSupPip2_4"];
const RETURN_NODES = ["TRetPip1_1", "TRetPip1_2", "TRetPip1_3", "TRetPip1_4", "TRetPip2_2", "TRetPip2_3", "TRetPip2_4"];

const CHANNELS = SUPPLY_NODES.concat(RETURN_NODES, [
  "TSupSub1", "TSupSub2", "TRetSub1", "TRetSub2",
  "mSupPip1", "mSupPip2", "mRetPip1", "mRetPip2", "mSub1", "mSub2",
  "QLoa1", "QLoa2"
]);

const UNITS = {
  TSupPip1_1: "K", TSupPip1_2: "K", TSupPip1_3: "K",
  TSupPip2_1: "K", TSupPip2_2: "K", TSupPip2_3: "K", TSupPip2_4: "K",
  TRetPip1_1: "K", TRetPip1_2: "K", TRetPip1_3: "K", TRetPip1_4: "K",
  TRetPip2_2: "K", TRetPip2_3: "K", TRetPip2_4: "K",
  TSupSub1: "K", TSupSub2: "K", TRetSub1: "K", TRetSub2: "K",
  mSupPip1: "kg/s", mSupPip2: "kg/s", mRetPip1: "kg/s", mRetPip2: "kg/s",
  mSub1: "kg/s", mSub2: "kg/s",
  QLoa1: "W", QLoa2: "W"
};

let busy = false;

function usable(sample) {
  if (!sample || sample.missing || sample.validity === "invalid") {
    return null;
  }
  if (typeof sample.value !== "number" || !Number.isFinite(sample.value)) {
    return null;
  }
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
  if (value === null) {
    return id + ": no sample";
  }
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
  SUPPLY_NODES.forEach((id, index) => paintNode("node-sup-" + index, id, supplyColor, samples));
  RETURN_NODES.forEach((id, index) => paintNode("node-ret-" + index, id, returnColor, samples));

  paintSolid("sup-riser", "TSupPip1_1", "mSupPip1", supplyColor, samples);
  paintGradient("sup-left", "sup-left-grad", SUPPLY_NODES.slice(0, 4), "mSupPip1", supplyColor, samples);
  paintGradient("sup-right", "sup-right-grad", SUPPLY_NODES.slice(3), "mSupPip2", supplyColor, samples);
  paintSolid("sup-stub1", "TSupSub1", "mSub1", supplyColor, samples);
  paintSolid("sup-stub2", "TSupSub2", "mSub2", supplyColor, samples);

  paintSolid("ret-riser", "TRetPip1_1", "mRetPip1", returnColor, samples);
  paintGradient("ret-left", "ret-left-grad", RETURN_NODES.slice(0, 4), "mRetPip1", returnColor, samples);
  paintGradient("ret-right", "ret-right-grad", RETURN_NODES.slice(3), "mRetPip2", returnColor, samples);
  paintSolid("ret-stub1", "TRetSub1", "mSub1", returnColor, samples);
  paintSolid("ret-stub2", "TRetSub2", "mSub2", returnColor, samples);

  paintHouse("house-1", "loa-1-value", "TSupSub1", "QLoa1", supplyColor, samples);
  paintHouse("house-2", "loa-2-value", "TSupSub2", "QLoa2", supplyColor, samples);
}

function mark(text, ok) {
  const status = document.getElementById("status");
  status.textContent = text;
  status.className = ok ? "ok" : "down";
}

async function readSample(id) {
  const response = await fetch("/simpledh/channel/" + encodeURIComponent(id) + "/sample");
  if (!response.ok) {
    return { missing: true };
  }
  return response.json();
}

async function poll() {
  if (busy) {
    return;
  }
  busy = true;
  try {
    const statusResponse = await fetch("/simpledh/status");
    if (!statusResponse.ok) {
      throw new Error("status");
    }
    const status = await statusResponse.json();
    const pairs = await Promise.all(CHANNELS.map(async (id) => {
      try {
        return [id, await readSample(id)];
      } catch (err) {
        return [id, { missing: true }];
      }
    }));
    paint(Object.fromEntries(pairs));
    if (status.connected === "yes") {
      mark("connected", true);
    } else if (status.connected === "no") {
      mark("not connected", false);
    } else {
      mark("unknown", false);
    }
  } catch (err) {
    mark("disconnected", false);
  } finally {
    busy = false;
  }
}

poll();
setInterval(poll, INTERVAL_MS);

const INTERVAL_MS = 1000;
const QLOA_MIN = 20000;
const QLOA_MAX = 80000;
const GREEN = "#1b7f3a";
const RED = "#d1242f";
const MISSING = "#b7c0c0";
const ARC_START = -120;
const ARC_END = 120;
const CX = 100;
const CY = 96;
const RADIUS = 72;

const GAUGES = {
  mSub: { scale: 1.0, digits: 2, fromKelvin: false },
  TSupSub: { scale: 100, digits: 1, fromKelvin: true },
  TRetSub: { scale: 50, digits: 1, fromKelvin: true }
};

let adjusting = false;
let pointerDown = false;
let gestureStart = null;
let committed = null;
let lastValues = null;
let pollSerial = 0;

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}

function mix(start, end, t) {
  const from = [1, 3, 5].map((i) => parseInt(start.slice(i, i + 2), 16));
  const to = [1, 3, 5].map((i) => parseInt(end.slice(i, i + 2), 16));
  const mixed = from.map((channel, i) => Math.round(channel + (to[i] - channel) * t));
  return "#" + mixed.map((channel) => channel.toString(16).padStart(2, "0")).join("");
}

function point(deg) {
  const rad = (deg - 90) * Math.PI / 180;
  return [CX + RADIUS * Math.cos(rad), CY + RADIUS * Math.sin(rad)];
}

function arc(start, end) {
  const from = point(start);
  const to = point(end);
  const large = end - start > 180 ? 1 : 0;
  return "M " + from[0].toFixed(2) + " " + from[1].toFixed(2)
    + " A " + RADIUS + " " + RADIUS + " 0 " + large + " 1 "
    + to[0].toFixed(2) + " " + to[1].toFixed(2);
}

function paintGauge(id, raw) {
  const spec = GAUGES[id];
  const stroke = document.getElementById(id + "-arc");
  const value = document.getElementById(id + "-value");
  if (typeof raw !== "number" || !Number.isFinite(raw)) {
    stroke.setAttribute("d", arc(ARC_START, ARC_START + 0.2));
    stroke.setAttribute("stroke", MISSING);
    value.textContent = "";
    return;
  }
  const shown = spec.fromKelvin ? raw - 273.15 : raw;
  const fraction = clamp(shown / spec.scale, 0, 1);
  const end = ARC_START + (ARC_END - ARC_START) * Math.max(fraction, 0.001);
  stroke.setAttribute("d", arc(ARC_START, end));
  const color = id === "TSupSub" ? supplyColor(raw)
    : id === "TRetSub" ? returnColor(raw)
    : mix(GREEN, RED, fraction);
  stroke.setAttribute("stroke", color);
  value.textContent = shown.toFixed(spec.digits);
}

function formatLoad(watts) {
  return (watts / 1000).toFixed(0) + " kW";
}

function mark(text, ok) {
  const status = document.getElementById("status");
  status.textContent = text;
  status.className = ok ? "ok" : "down";
}

function showLoad(watts) {
  document.getElementById("qloa").value = String(watts);
  document.getElementById("qloa-label").textContent = formatLoad(watts);
}

async function poll() {
  const serial = ++pollSerial;
  try {
    const response = await fetch("/values");
    if (serial !== pollSerial) {
      return;
    }
    if (!response.ok) {
      throw new Error("values");
    }
    const data = await response.json();
    lastValues = data;
    paintGauge("mSub", data.mSub);
    paintGauge("TSupSub", data.TSupSub);
    paintGauge("TRetSub", data.TRetSub);
    if (committed !== null && typeof data.QLoa === "number" && Number.isFinite(data.QLoa)) {
      const echoed = clamp(Math.round(data.QLoa / 1000) * 1000, QLOA_MIN, QLOA_MAX);
      if (echoed === committed) {
        committed = null;
      }
    }
    paintSchematic(loadView(data));
    if (!adjusting && committed === null && typeof data.QLoa === "number" && Number.isFinite(data.QLoa)) {
      const watts = clamp(Math.round(data.QLoa / 1000) * 1000, QLOA_MIN, QLOA_MAX);
      if (Number(document.getElementById("qloa").value) !== watts) {
        showLoad(watts);
      }
    }
    mark(data.connected ? "connected" : "not connected", data.connected === true);
  } catch (err) {
    if (serial !== pollSerial) {
      return;
    }
    mark("disconnected", false);
  }
}

function loadView(data) {
  if (committed === null) {
    return data;
  }
  return Object.assign({}, data, { QLoa: committed });
}

function previewLoad() {
  adjusting = true;
  document.getElementById("qloa-label").textContent = formatLoad(Number(document.getElementById("qloa").value));
}

function commitLoad() {
  const watts = Number(document.getElementById("qloa").value);
  document.getElementById("qloa-label").textContent = formatLoad(watts);
  adjusting = false;
  if (committed === watts || (gestureStart !== null && watts === gestureStart && committed === null)) {
    return;
  }
  gestureStart = watts;
  committed = watts;
  if (lastValues) {
    paintSchematic(loadView(lastValues));
  }
  writeLoad(watts);
}

function revertLoad() {
  committed = null;
  if (!lastValues) {
    return;
  }
  paintSchematic(lastValues);
  if (typeof lastValues.QLoa === "number" && Number.isFinite(lastValues.QLoa)) {
    const watts = clamp(Math.round(lastValues.QLoa / 1000) * 1000, QLOA_MIN, QLOA_MAX);
    showLoad(watts);
    gestureStart = watts;
  }
}

async function writeLoad(watts) {
  try {
    const response = await fetch("/qloa", {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ value: watts })
    });
    if (!response.ok && committed === watts) {
      revertLoad();
      mark("write failed", false);
    }
  } catch (err) {
    if (committed === watts) {
      revertLoad();
    }
    mark("disconnected", false);
  }
}

// ---------- process schematic ----------

const CP_WATER = 4180;
const DT_GOOD_K = 30;
const DT_FAIR_K = 20;

function finite(value) {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function scaleColor(kelvin, celsiusMin, celsiusMax, low, high) {
  const t = clamp((kelvin - 273.15 - celsiusMin) / (celsiusMax - celsiusMin), 0, 1);
  return mix(low, high, t);
}

function supplyColor(kelvin) {
  return scaleColor(kelvin, 50, 100, "#5a0000", "#ff3333");
}

function returnColor(kelvin) {
  return scaleColor(kelvin, 20, 50, "#001466", "#33aaff");
}

function pipeWidth(kgPerS) {
  return clamp(2 + 7 * Math.abs(kgPerS), 2, 9.4);
}

function setText(id, text) {
  document.getElementById(id).textContent = text;
}

function setTip(id, text) {
  document.getElementById(id).querySelector("title").textContent = text;
}

function paintPipe(id, kelvin, flow, colorOf) {
  const pipe = document.getElementById(id);
  if (kelvin === null || flow === null) {
    pipe.setAttribute("stroke", MISSING);
    pipe.setAttribute("stroke-width", "3");
    return;
  }
  pipe.setAttribute("stroke", colorOf(kelvin));
  pipe.setAttribute("stroke-width", String(pipeWidth(flow)));
}

function setMotion(flow) {
  const moving = flow !== null && Math.abs(flow) > 0.005;
  const tracerSeconds = moving ? clamp(1.0 / Math.abs(flow), 0.4, 8) : 0;
  const spinSeconds = moving ? clamp(0.8 / Math.abs(flow), 0.25, 8) : 0;
  document.querySelectorAll(".sch-tracer").forEach((path) => {
    path.style.animationPlayState = moving ? "running" : "paused";
    if (moving) {
      path.style.animationDuration = tracerSeconds.toFixed(2) + "s";
    }
  });
  const impeller = document.getElementById("sch-impeller");
  impeller.style.animationPlayState = moving ? "running" : "paused";
  if (moving) {
    impeller.style.animationDuration = spinSeconds.toFixed(2) + "s";
  }
}

function paintSchematic(data) {
  const tSup = finite(data.TSupSub);
  const tRet = finite(data.TRetSub);
  const flow = finite(data.mSub);
  const load = finite(data.QLoa);

  paintPipe("sch-sup", tSup, flow, supplyColor);
  paintPipe("sch-ret", tRet, flow, returnColor);
  setTip("sch-sup", "TSupSub / mSub");
  setTip("sch-ret", "TRetSub / mSub");

  document.getElementById("sch-tsup-dot").setAttribute("fill", tSup === null ? MISSING : supplyColor(tSup));
  document.getElementById("sch-tret-dot").setAttribute("fill", tRet === null ? MISSING : returnColor(tRet));
  document.getElementById("hx-grad-0").setAttribute("stop-color", tSup === null ? MISSING : supplyColor(tSup));
  document.getElementById("hx-grad-1").setAttribute("stop-color", tRet === null ? MISSING : returnColor(tRet));
  setTip("sch-hx", "primary side: TSupSub (top) to TRetSub (bottom)");

  setText("sch-tsup-value", tSup === null ? "--" : (tSup - 273.15).toFixed(1) + " °C");
  setText("sch-tret-value", tRet === null ? "--" : (tRet - 273.15).toFixed(1) + " °C");
  setText("sch-msub-value", flow === null ? "--" : flow.toFixed(2) + " kg/s");

  const house = document.getElementById("sch-house");
  house.setAttribute("fill", tSup === null ? MISSING : supplyColor(tSup));
  setTip("sch-house", load === null ? "QLoa: no value" : "QLoa: " + load + " W");
  setText("sch-house-value", load === null ? "--" : formatLoad(load));

  const dt = tSup !== null && tRet !== null ? tSup - tRet : null;
  const dtDot = document.getElementById("sch-dt-dot");
  if (dt === null) {
    setText("sch-dt-value", "--");
    dtDot.setAttribute("fill", MISSING);
  } else {
    setText("sch-dt-value", dt.toFixed(1) + " K");
    dtDot.setAttribute("fill", dt >= DT_GOOD_K ? "#138a4a" : dt >= DT_FAIR_K ? "#a87500" : "#c25a00");
  }

  const q = dt !== null && flow !== null ? flow * CP_WATER * dt : null;
  setText("sch-q-value", q === null ? "--" : (q / 1000).toFixed(1) + " kW");
  if (q === null || load === null || load === 0) {
    setText("sch-q-dev", "");
  } else {
    const dev = (q - load) / load * 100;
    setText("sch-q-dev", "vs QLoa " + (dev >= 0 ? "+" : "") + dev.toFixed(0) + " %");
  }

  setMotion(flow);
}

Object.keys(GAUGES).forEach((id) => {
  document.getElementById(id + "-track").setAttribute("d", arc(ARC_START, ARC_END));
  paintGauge(id, null);
});
paintSchematic({});

const slider = document.getElementById("qloa");
gestureStart = Number(slider.value);
slider.addEventListener("pointerdown", () => {
  pointerDown = true;
  adjusting = true;
  gestureStart = Number(slider.value);
});
function endPointer() {
  if (!pointerDown) {
    return;
  }
  pointerDown = false;
  commitLoad();
}
window.addEventListener("pointerup", endPointer);
window.addEventListener("pointercancel", endPointer);
slider.addEventListener("keyup", () => {
  if (!pointerDown) {
    commitLoad();
  }
});
slider.addEventListener("input", previewLoad);
slider.addEventListener("change", commitLoad);

poll();
setInterval(poll, INTERVAL_MS);

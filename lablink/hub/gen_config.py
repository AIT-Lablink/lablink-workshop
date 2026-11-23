#!/usr/bin/env python3
"""Generate the Lablink config server database for the SimpleDH hub/station split.

All signal routing is defined once in ROUTES. The datapoint bridge config, the
plotter inputs, the Universal API channels and the OPC UA client nodes are all
derived from it, so they cannot drift apart.

The hub address and one IP per substation come from network.yaml. Station
number k is FMU substation k and config id stationk. Each station host sets
OPCUA_CONFIG to that id.

The database is rebuilt from scratch (old rows are removed), and it is
rewritten in place, so a running config server keeps its file handle and
serves the new rows. Restart the Lablink clients afterwards so they reload.

Usage:
    python3 gen_config.py
    python3 gen_config.py --input network.yaml --dump-dir out/
"""

from __future__ import annotations

import argparse
import ipaddress
import json
import sqlite3
import sys
from collections import Counter
from dataclasses import dataclass
from pathlib import Path

GROUP = "SimpleDH"
SCENARIO = "NetworkFMU"
CONFIG_PORT = 10101       # config server, hub-internal only
HUB_HTTP_PORT = 8080      # hub reverse proxy; station clients use /config/get there
MQTT_PORT = 1883

# Config IDs. The client images append their default ID to LLCONFIG, so the
# lablink-* names must stay as they are. The plotters get theirs via PLOT_CONFIG.
# Each station OPC UA client sets OPCUA_CONFIG=station<k> instead of the image default.
ID_LOG4J = "ait.all.log4j2"
ID_PROPS_HUB = "ait.annex.simpledh.llproperties"
ID_PROPS_STATION = "ait.annex.simpledh.llproperties.station"
ID_SYNC = "ait.annex.simpledh.sync-host.properties"
ID_FMU = "lablink-fmusim.config"
ID_DPB = "lablink-dpbridge.config"
ID_UAPI = "lablink-universalapiclient.config"
ID_PLOT = "ait.annex.simpledh.plotter.{}.config"

# --------------------------------------------------------------------------
# Clients: Lablink client name, datapoint-ID prefix in the bridge, and host.
# --------------------------------------------------------------------------
FMU = "NetworkFMU"
UAPI = "UniversalAPIClient"
PLOT_TSUPPLY = "PlotterTSupply"
PLOT_MFLOW = "PlotterMSupply"
PLOT_TSUB = "PlotterTSub"

PREFIX = {
    FMU: "fmu",
    UAPI: "uapi",
    PLOT_TSUPPLY: "plot",
    PLOT_MFLOW: "plot",
    PLOT_TSUB: "plot",
}

# --------------------------------------------------------------------------
# FMU interface. SUBSTATIONS is the only topology knob: one pipe section per
# substation. NODES is the temperature points of a 3-segment pipe. The export
# always exposes QLoa1..QLoa10; at SUBSTATIONS == 10 every one of them is routed.
# --------------------------------------------------------------------------
SUBSTATIONS = 10
PIPES = SUBSTATIONS
NODES = 4
LOAD_INPUTS = 10


def station_client(k: int) -> str:
    return f"OpcUaClient{k}"


STATION_CLIENTS = {station_client(k) for k in range(1, SUBSTATIONS + 1)}

def _fmu_outputs() -> dict[str, str]:
    out: dict[str, str] = {}
    pn = [(p, n) for p in range(1, PIPES + 1) for n in range(1, NODES + 1)]
    out |= {f"TSupPip{p}_{n}": "K" for p, n in pn}
    out |= {f"mSupPip{p}": "kg/s" for p in range(1, PIPES + 1)}
    out |= {f"TSupSub{s}": "K" for s in range(1, SUBSTATIONS + 1)}
    out |= {f"TRetPip{p}_{n}": "K" for p, n in pn}
    out |= {f"TRetSub{s}": "K" for s in range(1, SUBSTATIONS + 1)}
    out |= {f"mRetPip{p}": "kg/s" for p in range(1, PIPES + 1)}
    out |= {f"mSub{s}": "kg/s" for s in range(1, SUBSTATIONS + 1)}
    return out

FMU_OUTPUTS = _fmu_outputs()
FMU_INPUTS = {"TSupSet": "K"} | {f"QLoa{i}": "W" for i in range(1, LOAD_INPUTS + 1)}
FMU_INITIAL = {"TSupSet": 343.15} | {f"QLoa{i}": 80000.0 for i in range(1, LOAD_INPUTS + 1)}

# OPC UA nodes on the station's substation server (Lablink name -> unit).
OPCUA_TO_SERVER = {"mSub": "kg/s", "TSupSub": "K", "TRetSub": "K"}  # written to server
OPCUA_FROM_SERVER = {"QLoa": "W"}                                   # read from server


@dataclass(frozen=True)
class Route:
    src_client: str
    src_dp: str
    dst_client: str
    dst_dp: str
    unit: str


def build_routes() -> list[Route]:
    """The single source of truth for all signal routing."""
    r: list[Route] = []

    # FMU -> plotters. Supply temperature is only the last node of each pipe.
    r += [
        Route(FMU, f"TSupPip{p}_{NODES}", PLOT_TSUPPLY, f"TSupPip{p}_{NODES}", "K")
        for p in range(1, PIPES + 1)
    ]
    r += [Route(FMU, f"mSupPip{p}", PLOT_MFLOW, f"mSupPip{p}", "kg/s") for p in range(1, PIPES + 1)]
    r += [Route(FMU, f"TSupSub{s}", PLOT_TSUB, f"TSupSub{s}", "K") for s in range(1, SUBSTATIONS + 1)]

    # FMU -> Universal API (every FMU output is visible in the network display)
    r += [Route(FMU, name, UAPI, name, unit) for name, unit in FMU_OUTPUTS.items()]

    for s in range(1, SUBSTATIONS + 1):
        client = station_client(s)
        # FMU substation s -> station OPC UA server (hub -> station)
        r += [Route(FMU, f"{name}{s}", client, name, unit) for name, unit in OPCUA_TO_SERVER.items()]
        # Station load setpoint -> FMU load input and display (station -> hub)
        r.append(Route(client, "QLoa", FMU, f"QLoa{s}", "W"))
        r.append(Route(client, "QLoa", UAPI, f"QLoa{s}", "W"))
    return r


def dp_id(client: str, dp: str, is_fmu_input: bool = False) -> str:
    # FMU inputs get their own prefix so they can never collide with outputs.
    # Each station client gets its own prefix so the ten QLoa values stay distinct.
    if is_fmu_input:
        prefix = "fmu-in"
    elif client in PREFIX:
        prefix = PREFIX[client]
    elif client in STATION_CLIENTS:
        prefix = "opcua" + client[len("OpcUaClient"):]
    else:
        sys.exit(f"No datapoint prefix for client {client}")
    return f"{prefix}-{dp}"


def validate(routes: list[Route]) -> None:
    errors: list[str] = []
    dests = Counter((x.dst_client, x.dst_dp) for x in routes)
    errors += [f"{c}/{d} has {n} sources" for (c, d), n in dests.items() if n > 1]
    for x in routes:
        if x.src_client == FMU and x.src_dp not in FMU_OUTPUTS:
            errors.append(f"unknown FMU output {x.src_dp}")
        if x.dst_client == FMU and x.dst_dp not in FMU_INPUTS:
            errors.append(f"unknown FMU input {x.dst_dp}")
        if x.src_client in STATION_CLIENTS and x.src_dp not in OPCUA_FROM_SERVER:
            errors.append(f"unknown OPC UA output {x.src_client}/{x.src_dp}")
        if x.dst_client in STATION_CLIENTS and x.dst_dp not in OPCUA_TO_SERVER:
            errors.append(f"unknown OPC UA input {x.dst_client}/{x.dst_dp}")
    for name in FMU_INPUTS:
        if (FMU, name) not in dests and name not in FMU_INITIAL:
            errors.append(f"FMU input {name} is neither routed nor initialised")
    if errors:
        sys.exit("Routing errors:\n  " + "\n  ".join(errors))


# --------------------------------------------------------------------------
# Config builders
# --------------------------------------------------------------------------
class Urls:
    def __init__(self, hub_ip: str, hub_http_port: int) -> None:
        self.hub_ip = hub_ip
        self.hub_http_port = hub_http_port

    def base(self, client: str) -> str:
        if client in STATION_CLIENTS:
            # Through the hub's nginx, which maps /config/get to the config server.
            return f"http://{self.hub_ip}:{self.hub_http_port}/config/get?id="
        return f"http://lablink-config:{CONFIG_PORT}/get?id="

    def props(self, client: str) -> str:
        pid = ID_PROPS_STATION if client in STATION_CLIENTS else ID_PROPS_HUB
        return self.base(client) + pid

    def sync(self, client: str) -> str:
        return self.base(client) + ID_SYNC


def client_block(urls: Urls, name: str, desc: str, shell: bool = False) -> dict:
    return {
        "ClientDescription": desc,
        "ClientName": name,
        "ClientShell": shell,
        "GroupName": GROUP,
        "ScenarioName": SCENARIO,
        "labLinkPropertiesUrl": urls.props(name),
        "syncHostPropertiesUrl": urls.sync(name),
    }


def ll_properties(broker: str) -> str:
    return "\n".join([
        f"lowLevelComm.brokerAddress = {broker}",
        f"lowLevelComm.brokerPort = {MQTT_PORT}",
        "lowLevelComm.connectionProtocol = tcp",
        "lowLevelComm.mqttConnectionTimeout = 30",
        "lowLevelComm.enableReconnection = true",
        "lowLevelComm.reconnectInterval = 10",
        "lowLevelComm.reconnectNumberOfTries = -1",
    ]) + "\n"


LOG4J = """<?xml version='1.0' encoding='UTF-8'?>
<Configuration status="INFO">
    <Appenders>
        <Console target="SYSTEM_OUT" name="Console">
            <PatternLayout pattern="%d{HH:mm:ss.SSS} [%t] %-5level %logger{36} - %msg%n"/>
        </Console>
    </Appenders>
    <Loggers>
        <Root level="INFO">
            <AppenderRef ref="Console"/>
        </Root>
    </Loggers>
</Configuration>
"""


def fmu_config(urls: Urls) -> dict:
    var = lambda n, u: {"DataType": "double", "Unit": u, "VariableName": n}
    return {
        "Client": client_block(urls, FMU, "SimpleDH network FMU.", shell=True),
        "FMU": {
            "DefaulUpdatePeriod_ms": 1000,  # sic: Lablink's key name
            "IntegratorType": "bdf",
            "LoggingOn": False,
            "ModelTimeScaleFactor": 90,
            "URI": f"fmusim:NetworkFMU_nSub{SUBSTATIONS}.fmu",
        },
        "Input": [var(n, u) for n, u in FMU_INPUTS.items()],
        "Output": [var(n, u) for n, u in FMU_OUTPUTS.items()],
        "InitialValues": [
            {"DataType": "double", "Value": v, "VariableName": n} for n, v in FMU_INITIAL.items()
        ],
    }


def dpb_config(urls: Urls, routes: list[Route]) -> dict:
    points: dict[str, dict] = {}

    def add(client: str, dp: str, fmu_in: bool = False) -> str:
        pid = dp_id(client, dp, fmu_in)
        if pid in points and points[pid]["DPClientName"] != client:
            sys.exit(f"Datapoint ID {pid} is used by two clients; give them distinct prefixes")
        points.setdefault(pid, {
            "ID": pid,
            "DPGroupName": GROUP,
            "DPClientName": client,
            "DPName": dp,
            "DPIdentifier": dp,
            "DPDataType": "double",
        })
        return pid

    conns = [
        {"From": add(x.src_client, x.src_dp), "To": add(x.dst_client, x.dst_dp, x.dst_client == FMU)}
        for x in routes
    ]
    return {
        "ClientName": "DpBridge",
        "GroupName": GROUP,
        "ScenarioName": SCENARIO,
        "labLinkPropertiesUrl": urls.props("DpBridge"),
        "syncHostPropertiesUrl": urls.sync("DpBridge"),
        "DataPoints": list(points.values()),
        "Connections": conns,
    }


PLOTTERS = {
    # key: (client, description, title, y label)
    "tsupply": (PLOT_TSUPPLY, "Supply temperature at the last node of each pipe.", "T supply", "K"),
    "mflow": (PLOT_MFLOW, "Supply pipe mass flow rates.", "mass flow rate supply", "kg/s"),
    "tsub": (PLOT_TSUB, "Substation supply temperatures.", "T substation", "K"),
}


def plotter_config(urls: Urls, routes: list[Route], key: str) -> dict:
    client, desc, title, ylabel = PLOTTERS[key]
    return {
        "Client": client_block(urls, client, desc),
        "Input": [
            {"Connected": True, "DataType": "double", "InputID": x.dst_dp, "Unit": x.unit}
            for x in routes if x.dst_client == client
        ],
        "Plot": {
            "AutomaticRescale": True,
            "DisplayGrid": True,
            "Title": title,
            "XLabel": "runtime in s",
            "YLabel": ylabel,
        },
    }


def uapi_config(urls: Urls, routes: list[Route]) -> dict:
    return {
        "Channels": [
            {
                "DPName": x.dst_dp,
                "Datatype": "float",
                "Id": x.dst_dp,
                "Payload": "samples",
                "Readable": True,
                "Source": "simulated" if x.src_client == FMU else "unknown",
                "Unit": x.unit,
                "Writable": False,
            }
            for x in routes if x.dst_client == UAPI
        ],
        "Client": client_block(urls, UAPI, "REST access to the SimpleDH network FMU outputs."),
        "UniversalAPI": {"EndpointPrefix": "simpledh", "NodeId": "simpledh-network", "Port": 7000},
    }


def opcua_config(urls: Urls, routes: list[Route], substation: int, endpoint: str) -> dict:
    client = station_client(substation)
    node = lambda n, u: {"DataType": "double", "Name": n, "NodeIdString": f"SimpleDH/{n}", "Unit": u}
    inputs = sorted({(x.dst_dp, x.unit) for x in routes if x.dst_client == client})
    outputs = sorted({(x.src_dp, x.unit) for x in routes if x.src_client == client})
    return {
        "Client": client_block(
            urls, client, f"Station {substation} link: substation values and load setpoint via OPC UA."
        ),
        "Config-OPC-UA": {
            "ClientURI": f"urn:lablink:clients:opcuaclient:simpledh:station{substation}",
            "DefaulSamplingInterval_ms": 1000,  # sic: Lablink's key name
            "EndpointURL": endpoint,
            "NamespaceURI": "urn:lablink:simpledh",
        },
        "Input": [node(n, u) for n, u in inputs],
        "Output": [node(n, u) for n, u in outputs],
    }


def build_rows(hub_ip: str, stations: dict[int, str], hub_http_port: int = HUB_HTTP_PORT):
    routes = build_routes()
    validate(routes)
    urls = Urls(hub_ip, hub_http_port)
    station_ips = ", ".join(stations[k] for k in range(1, SUBSTATIONS + 1))
    rows = [
        (ID_LOG4J, LOG4J, "Default client logger configuration (info)"),
        (ID_PROPS_HUB, ll_properties("mqtt"), "Lablink connection properties (hub clients)"),
        (ID_PROPS_STATION, ll_properties(hub_ip), f"Lablink connection properties (stations, broker {hub_ip})"),
        (ID_SYNC, "# dummy configuration\n", "Sync host properties (unused by this asynchronous run)"),
        (ID_FMU, fmu_config(urls), "SimpleDH network FMU simulator"),
        (ID_DPB, dpb_config(urls, routes), f"Datapoint bridge, hub {hub_ip} <-> stations {station_ips}"),
        (ID_UAPI, uapi_config(urls, routes), "Universal API client for SimpleDH FMU outputs"),
    ]
    rows += [
        (
            f"station{k}",
            opcua_config(urls, routes, k, f"opc.tcp://{stations[k]}:12345/simpledh"),
            f"OPC UA client on station {stations[k]} (substation {k})",
        )
        for k in range(1, SUBSTATIONS + 1)
    ]
    rows += [
        (ID_PLOT.format(k), plotter_config(urls, routes, k), f"Plotter: {PLOTTERS[k][2]}")
        for k in PLOTTERS
    ]
    return routes, [
        (i, c if isinstance(c, str) else json.dumps(c, indent=2), d) for i, c, d in rows
    ]


SCHEMA = """CREATE TABLE IF NOT EXISTS "LablinkConfigSimple" (
  "identifier" TEXT NOT NULL UNIQUE,
  "config" TEXT NOT NULL,
  "invoke" TEXT,
  "description" TEXT NOT NULL,
  PRIMARY KEY("identifier")
)"""


def write_db(path: Path, rows) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(path)
    try:
        with con:
            con.execute(SCHEMA)
            con.execute('DELETE FROM "LablinkConfigSimple"')  # drop all stale rows
            con.executemany(
                'INSERT INTO "LablinkConfigSimple" (identifier, config, invoke, description) '
                "VALUES (?, ?, NULL, ?)",
                rows,
            )
        con.execute("VACUUM")  # also purge old row versions from free pages
    finally:
        con.close()


def parse_ip(value, label: str) -> str:
    try:
        return str(ipaddress.ip_address(str(value)))
    except ValueError as e:
        sys.exit(f"{label}: {e}")


def load_network(path: Path) -> tuple[str, int, dict[int, str]]:
    """Hub address and station number -> IP. Numbers must be exactly 1..SUBSTATIONS."""
    try:
        import yaml
    except ImportError:
        sys.exit("PyYAML is required: pip install pyyaml")
    if not path.is_file():
        sys.exit(f"Network file not found: {path}")
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
    except yaml.YAMLError as e:
        sys.exit(f"{path}: {e}")
    if not isinstance(data, dict):
        sys.exit(f"{path}: expected a mapping with hub_ip and stations")
    if "hub_ip" not in data:
        sys.exit(f"{path}: missing hub_ip")
    hub_ip = parse_ip(data["hub_ip"], f"{path}: hub_ip")
    port = data.get("hub_http_port", HUB_HTTP_PORT)
    if type(port) is not int or port < 1 or port > 65535:
        sys.exit(f"{path}: hub_http_port must be an integer from 1 to 65535")
    raw = data.get("stations")
    if not isinstance(raw, list):
        sys.exit(f"{path}: stations must be a list")

    stations: dict[int, str] = {}
    for i, row in enumerate(raw, start=1):
        if not isinstance(row, dict) or "number" not in row or "ip" not in row:
            sys.exit(f"{path}: stations[{i}] needs number and ip")
        number = row["number"]
        if type(number) is not int:
            sys.exit(f"{path}: stations[{i}].number must be an integer")
        if number in stations:
            sys.exit(f"{path}: duplicate station number {number}")
        stations[number] = parse_ip(row["ip"], f"{path}: station {number}")

    expected = set(range(1, SUBSTATIONS + 1))
    missing = expected - stations.keys()
    extra = stations.keys() - expected
    if missing or extra:
        parts = []
        if missing:
            parts.append("missing " + ", ".join(str(n) for n in sorted(missing)))
        if extra:
            parts.append("unknown " + ", ".join(str(n) for n in sorted(extra)))
        sys.exit(f"{path}: station numbers must be 1..{SUBSTATIONS} exactly: " + "; ".join(parts))
    return hub_ip, port, stations


def main() -> None:
    here = Path(__file__).resolve().parent
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--input", type=Path, default=here / "network.yaml",
                    help="YAML file with hub_ip and stations (default: network.yaml beside this script)")
    ap.add_argument("--db", type=Path, default=here / "config" / "hub-config.db")
    ap.add_argument("--dump-dir", type=Path, help="also write every config as a file for review")
    args = ap.parse_args()

    hub_ip, hub_http_port, stations = load_network(args.input)
    routes, rows = build_rows(hub_ip, stations, hub_http_port)
    write_db(args.db, rows)

    if args.dump_dir:
        args.dump_dir.mkdir(parents=True, exist_ok=True)
        for ident, cfg, _ in rows:
            ext = ".json" if cfg.lstrip().startswith("{") else ".txt"
            (args.dump_dir / f"{ident}{ext}").write_text(cfg, encoding="utf-8")

    print(f"Wrote {len(rows)} configs to {args.db}")
    print(f"{len(routes)} routes:")
    for x in routes:
        tag = "  hub->station" if x.dst_client in STATION_CLIENTS else (
            "  station->hub" if x.src_client in STATION_CLIENTS else "")
        print(f"  {x.src_client}/{x.src_dp} -> {x.dst_client}/{x.dst_dp}{tag}")


if __name__ == "__main__":
    main()

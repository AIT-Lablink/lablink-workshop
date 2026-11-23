#!/usr/bin/env python3
"""Generate the Lablink config server database for the SimpleDH hub/station split.

All signal routing is defined once in ROUTES. The datapoint bridge config, the
plotter inputs, the Universal API channels and the OPC UA client nodes are all
derived from it, so they cannot drift apart.

The database is rebuilt from scratch (old rows are removed), and it is
rewritten in place, so a running config server keeps its file handle and
serves the new rows. Restart the Lablink clients afterwards so they reload.

Usage:
    python3 gen_config.py --hub-ip 10.0.0.10 --station-ip 10.0.0.20
    python3 gen_config.py --hub-ip 10.0.0.10 --station-ip 10.0.0.20 --dump-dir out/
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
# The station OPC UA client sets OPCUA_CONFIG=station1 instead of the image default.
ID_LOG4J = "ait.all.log4j2"
ID_PROPS_HUB = "ait.annex.simpledh.llproperties"
ID_PROPS_STATION = "ait.annex.simpledh.llproperties.station"
ID_SYNC = "ait.annex.simpledh.sync-host.properties"
ID_FMU = "lablink-fmusim.config"
ID_DPB = "lablink-dpbridge.config"
ID_UAPI = "lablink-universalapiclient.config"
ID_OPCUA = "station1"
ID_PLOT = "ait.annex.simpledh.plotter.{}.config"

# --------------------------------------------------------------------------
# Clients: Lablink client name, datapoint-ID prefix in the bridge, and host.
# --------------------------------------------------------------------------
FMU = "NetworkFMU"
UAPI = "UniversalAPIClient"
OPCUA = "OpcUaClient"
PLOT_TSUPPLY = "PlotterTSupply"
PLOT_MFLOW = "PlotterMSupply"
PLOT_TSUB = "PlotterTSub"

PREFIX = {
    FMU: "fmu",
    UAPI: "uapi",
    OPCUA: "opcua",
    PLOT_TSUPPLY: "plot",
    PLOT_MFLOW: "plot",
    PLOT_TSUB: "plot",
}
STATION_CLIENTS = {OPCUA}

# --------------------------------------------------------------------------
# FMU interface (NetworkFMU_nSub2.fmu): 2 pipes with 4 nodes, 2 substations.
# --------------------------------------------------------------------------
PIPES, NODES, SUBSTATIONS = 2, 4, 2
LOAD_INPUTS = 10  # the FMU exposes QLoa1..QLoa10; only the first SUBSTATIONS matter

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


def build_routes(opcua_substation: int) -> list[Route]:
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

    # FMU substation n -> station OPC UA server (hub -> station)
    s = opcua_substation
    r += [Route(FMU, f"{name}{s}", OPCUA, name, unit) for name, unit in OPCUA_TO_SERVER.items()]

    # Station load setpoint -> FMU load input and display (station -> hub)
    r.append(Route(OPCUA, "QLoa", FMU, f"QLoa{s}", "W"))
    r.append(Route(OPCUA, "QLoa", UAPI, f"QLoa{s}", "W"))
    return r


def dp_id(client: str, dp: str, is_fmu_input: bool = False) -> str:
    # FMU inputs get their own prefix so they can never collide with outputs.
    prefix = "fmu-in" if is_fmu_input else PREFIX[client]
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
        if x.src_client == OPCUA and x.src_dp not in OPCUA_FROM_SERVER:
            errors.append(f"unknown OPC UA output {x.src_dp}")
        if x.dst_client == OPCUA and x.dst_dp not in OPCUA_TO_SERVER:
            errors.append(f"unknown OPC UA input {x.dst_dp}")
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
            "URI": "fmusim:NetworkFMU_nSub2.fmu",
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


def opcua_config(urls: Urls, routes: list[Route], endpoint: str) -> dict:
    node = lambda n, u: {"DataType": "double", "Name": n, "NodeIdString": f"SimpleDH/{n}", "Unit": u}
    inputs = sorted({(x.dst_dp, x.unit) for x in routes if x.dst_client == OPCUA})
    outputs = sorted({(x.src_dp, x.unit) for x in routes if x.src_client == OPCUA})
    return {
        "Client": client_block(urls, OPCUA, "Station link: substation values and load setpoint via OPC UA."),
        "Config-OPC-UA": {
            "ClientURI": "urn:lablink:clients:opcuaclient:simpledh",
            "DefaulSamplingInterval_ms": 1000,  # sic: Lablink's key name
            "EndpointURL": endpoint,
            "NamespaceURI": "urn:lablink:simpledh",
        },
        "Input": [node(n, u) for n, u in inputs],
        "Output": [node(n, u) for n, u in outputs],
    }


def build_rows(hub_ip: str, station_ip: str, opcua_substation: int, opcua_endpoint: str | None,
               hub_http_port: int = HUB_HTTP_PORT):
    routes = build_routes(opcua_substation)
    validate(routes)
    urls = Urls(hub_ip, hub_http_port)
    endpoint = opcua_endpoint or f"opc.tcp://{station_ip}:12345/simpledh"
    rows = [
        (ID_LOG4J, LOG4J, "Default client logger configuration (info)"),
        (ID_PROPS_HUB, ll_properties("mqtt"), "Lablink connection properties (hub clients)"),
        (ID_PROPS_STATION, ll_properties(hub_ip), f"Lablink connection properties (station {station_ip})"),
        (ID_SYNC, "# dummy configuration\n", "Sync host properties (unused by this asynchronous run)"),
        (ID_FMU, fmu_config(urls), "SimpleDH network FMU simulator"),
        (ID_DPB, dpb_config(urls, routes), f"Datapoint bridge, hub {hub_ip} <-> station {station_ip}"),
        (ID_UAPI, uapi_config(urls, routes), "Universal API client for SimpleDH FMU outputs"),
        (ID_OPCUA, opcua_config(urls, routes, endpoint), f"OPC UA client on station {station_ip}"),
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


def ip(value: str) -> str:
    try:
        return str(ipaddress.ip_address(value))
    except ValueError as e:
        raise argparse.ArgumentTypeError(str(e)) from e


def main() -> None:
    here = Path(__file__).resolve().parent
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--hub-ip", type=ip, required=True, help="IP of the hub host (MQTT, config server)")
    ap.add_argument("--station-ip", type=ip, required=True, help="IP of the station host (OPC UA substation)")
    ap.add_argument("--hub-http-port", type=int, default=HUB_HTTP_PORT,
                    help=f"published port of the hub reverse proxy (default {HUB_HTTP_PORT})")
    ap.add_argument("--db", type=Path, default=here / "config" / "hub-config.db")
    ap.add_argument("--opcua-substation", type=int, default=1, choices=range(1, SUBSTATIONS + 1),
                    help="FMU substation emulated by the station (default 1)")
    ap.add_argument("--opcua-endpoint", help="override the OPC UA endpoint URL "
                    "(default: opc.tcp://<station-ip>:12345/simpledh)")
    ap.add_argument("--dump-dir", type=Path, help="also write every config as a file for review")
    args = ap.parse_args()

    routes, rows = build_rows(args.hub_ip, args.station_ip, args.opcua_substation, args.opcua_endpoint,
                              args.hub_http_port)
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

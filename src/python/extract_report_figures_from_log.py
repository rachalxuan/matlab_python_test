#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Extract report figures from MATLAB console logs without rerunning MATLAB.

Usage:
  python extract_report_figures_from_log.py pasted-text.txt

The script writes CSV and SVG files into src/python/report_figures/offline_logs.
It intentionally uses only the Python standard library so it works in minimal
environments.
"""

from __future__ import annotations

import csv
import math
import re
import sys
from pathlib import Path
from xml.sax.saxutils import escape


ROOT = Path(__file__).resolve().parent
OUT_DIR = ROOT / "report_figures" / "offline_logs"


STAGE_RE = re.compile(
    r'^\s*"(?P<mod>[^"]+)"\s+"(?P<stage>Clean|Damaged|Recovered)"\s+'
    r"(?P<ifmhz>[-+0-9.]+)\s+(?P<ber>[-+0-9.eE]+)\s+"
    r"(?P<evm>[-+0-9.]+)\s+(?P<mer>[-+0-9.]+)\s+"
    r"(?P<snrest>[-+0-9.]+)\s+(?P<lock>[-+0-9.]+)\s+"
    r'"(?P<recovery>[^"]*)"',
    re.MULTILINE,
)

SWEEP_RE = re.compile(
    r'^\s*"(?P<mod>[^"]+)"\s+"(?P<stage>Clean|Recovered)"\s+'
    r"(?P<ifmhz>[-+0-9.]+)\s+(?P<snr>[-+0-9.]+)\s+"
    r"(?P<ber>[-+0-9.eE]+)\s+(?P<evm>[-+0-9.]+)\s+"
    r"(?P<mer>[-+0-9.]+)\s+(?P<snrest>[-+0-9.]+)\s+"
    r"(?P<lock>[-+0-9.]+)\s+\"(?P<recovery>[^\"]*)\"",
    re.MULTILINE,
)

IF_LINE_RE = re.compile(
    r"IF=(?P<ifmhz>[-+0-9.]+)MHz\s+SNR=\s*(?P<snr>[-+0-9.]+)dB\s+"
    r"(?P<stage>Clean|Recovered)\s+BER=\s*(?P<ber>[-+0-9.eE]+)\s+"
    r"EVM=\s*(?P<evm>[-+0-9.]+)%\s+SNRest=\s*(?P<snrest>[-+0-9.]+)dB\s+"
    r"Lock=\s*(?P<lock>[-+0-9.]+)%",
)

CODING_RE = re.compile(
    r"coding=(?P<coding>.+?)\s+SNR=\s*(?P<snr>[-+0-9.]+)dB\s+"
    r"BER=\s*(?P<ber>[-+0-9.eE]+)\s+EVM=\s*(?P<evm>[-+0-9.]+)%\s+"
    r"Lock=\s*(?P<lock>[-+0-9.]+)%",
)

LDPC_BLOCK_RE = re.compile(
    r"^=+\s*LDPC\s+(?P<rate>\S+)\s+K=(?P<k>\d+)\s+\|\s+SNR\s*=\s*(?P<snr>[-+0-9.]+)\s*dB\s*=+\s*"
    r"(?P<body>.*?)(?=^=+\s*LDPC\s+\S+\s+K=|\Z)",
    re.MULTILINE | re.DOTALL,
)

BER_RESULT_RE = re.compile(r"BER\s*:\s*(?P<ber>[-+0-9.eE]+)")
EVM_POST_RE = re.compile(r"EVM\s*\(sync后\)\s*:\s*(?P<evm>[-+0-9.]+)\s*%")
LOCK_RESULT_RE = re.compile(r"Frame\s+Lock\s*:\s*(?P<lock>[-+0-9.]+)\s*%")


def as_float(value: str) -> float:
    try:
        return float(value)
    except ValueError:
        return math.nan


def rows_from_regex(text: str, regex: re.Pattern[str]) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    for match in regex.finditer(text):
        row: dict[str, object] = {}
        for key, value in match.groupdict().items():
            row[key] = value.strip() if key in {"mod", "stage", "recovery", "coding"} else as_float(value)
        rows.append(row)
    return rows


def unique_rows(rows: list[dict[str, object]], keys: tuple[str, ...]) -> list[dict[str, object]]:
    seen = set()
    out = []
    for row in rows:
        sig = tuple(row.get(k) for k in keys)
        if sig in seen:
            continue
        seen.add(sig)
        out.append(row)
    return out


def write_csv(path: Path, rows: list[dict[str, object]], columns: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=columns)
        writer.writeheader()
        for row in rows:
            writer.writerow({col: row.get(col, "") for col in columns})


def read_csv(path: Path) -> list[dict[str, object]]:
    if not path.exists():
        return []
    for encoding in ("utf-8-sig", "utf-8", "gbk"):
        try:
            with path.open("r", newline="", encoding=encoding) as f:
                return list(csv.DictReader(f))
        except UnicodeDecodeError:
            continue
    with path.open("r", newline="", encoding="utf-8", errors="ignore") as f:
        return list(csv.DictReader(f))


def parse_ldpc_blocks(text: str, keep_rate: str = "1/2") -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    for match in LDPC_BLOCK_RE.finditer(text):
        rate = match.group("rate").strip()
        if rate != keep_rate:
            continue
        body = match.group("body")
        ber_m = BER_RESULT_RE.search(body)
        evm_m = EVM_POST_RE.search(body)
        lock_m = LOCK_RESULT_RE.search(body)
        if not (ber_m and evm_m and lock_m):
            continue
        rows.append(
            {
                "coding": f"LDPC {rate}",
                "snr": as_float(match.group("snr")),
                "ber": as_float(ber_m.group("ber")),
                "evm": as_float(evm_m.group("evm")),
                "lock": as_float(lock_m.group("lock")),
            }
        )
    return rows


def merge_rows(
    old_rows: list[dict[str, object]],
    new_rows: list[dict[str, object]],
    keys: tuple[str, ...],
) -> list[dict[str, object]]:
    merged: dict[tuple[object, ...], dict[str, object]] = {}
    for row in old_rows + new_rows:
        sig = tuple(row.get(k) for k in keys)
        merged[sig] = row
    return list(merged.values())


class Svg:
    def __init__(self, width: int, height: int, title: str):
        self.width = width
        self.height = height
        self.parts = [
            f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
            '<rect width="100%" height="100%" fill="#f0f0f0"/>',
            f'<text x="{width/2:.1f}" y="34" text-anchor="middle" font-size="22" font-family="Microsoft YaHei, Arial">{escape(title)}</text>',
        ]

    def add(self, text: str) -> None:
        self.parts.append(text)

    def text(self, x: float, y: float, text: str, size: int = 13, anchor: str = "middle", color: str = "#222") -> None:
        self.add(
            f'<text x="{x:.1f}" y="{y:.1f}" text-anchor="{anchor}" font-size="{size}" '
            f'fill="{color}" font-family="Microsoft YaHei, Arial">{escape(text)}</text>'
        )

    def save(self, path: Path) -> None:
        self.parts.append("</svg>")
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("\n".join(self.parts), encoding="utf-8")


def nice_ticks(vmin: float, vmax: float, count: int = 5) -> list[float]:
    if not math.isfinite(vmin) or not math.isfinite(vmax) or vmin == vmax:
        return [vmin]
    raw = (vmax - vmin) / max(count - 1, 1)
    step = 10 ** math.floor(math.log10(abs(raw)))
    for mult in (1, 2, 5, 10):
        if raw <= mult * step:
            step *= mult
            break
    start = math.floor(vmin / step) * step
    end = math.ceil(vmax / step) * step
    ticks = []
    v = start
    while v <= end + 1e-9:
        ticks.append(round(v, 10))
        v += step
    return ticks


def plot_area(svg: Svg, x: int, y: int, w: int, h: int, title: str, ylabel: str) -> None:
    svg.add(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="white" stroke="#333" stroke-width="1"/>')
    svg.text(x + w / 2, y - 10, title, 16)
    svg.text(x - 46, y + h / 2, ylabel, 13, color="#222")


def draw_axes(svg: Svg, x: int, y: int, w: int, h: int, xticks: list[float], yticks: list[float], xmap, ymap) -> None:
    for t in xticks:
        px = xmap(t)
        svg.add(f'<line x1="{px:.1f}" y1="{y}" x2="{px:.1f}" y2="{y+h}" stroke="#d7d7d7"/>')
        svg.text(px, y + h + 22, f"{t:g}", 12)
    for t in yticks:
        py = ymap(t)
        svg.add(f'<line x1="{x}" y1="{py:.1f}" x2="{x+w}" y2="{py:.1f}" stroke="#d7d7d7"/>')
        svg.text(x - 8, py + 4, f"{t:g}", 12, anchor="end")


def polyline(points: list[tuple[float, float]]) -> str:
    return " ".join(f"{x:.1f},{y:.1f}" for x, y in points)


def plot_lines_panel(
    svg: Svg,
    x: int,
    y: int,
    w: int,
    h: int,
    title: str,
    ylabel: str,
    series: dict[str, list[tuple[float, float]]],
    logy: bool = False,
    ylim: tuple[float, float] | None = None,
) -> None:
    colors = ["#1f77b4", "#2ca02c", "#d62728", "#9467bd", "#ff7f0e"]
    all_x = [p[0] for vals in series.values() for p in vals if math.isfinite(p[1])]
    all_y = [p[1] for vals in series.values() for p in vals if math.isfinite(p[1]) and p[1] > 0]
    if not all_x or not all_y:
        return
    xmin, xmax = min(all_x), max(all_x)
    if ylim:
        ymin, ymax = ylim
    else:
        ymin, ymax = min(all_y), max(all_y)
        pad = (ymax - ymin) * 0.08 or 1
        ymin, ymax = ymin - pad, ymax + pad
    if logy:
        ymin, ymax = max(ymin, 1e-6), max(ymax, 1)
        lymin, lymax = math.log10(ymin), math.log10(ymax)
        ymap = lambda v: y + h - (math.log10(max(v, ymin)) - lymin) / (lymax - lymin) * h
        yticks = [1e-6, 1e-5, 1e-4, 1e-3, 1e-2, 1e-1, 1]
    else:
        ymap = lambda v: y + h - (v - ymin) / (ymax - ymin) * h
        yticks = nice_ticks(ymin, ymax, 5)
    xmap = lambda v: x + (v - xmin) / (xmax - xmin or 1) * w

    plot_area(svg, x, y, w, h, title, ylabel)
    draw_axes(svg, x, y, w, h, nice_ticks(xmin, xmax, 8), yticks, xmap, ymap)
    for idx, (name, vals) in enumerate(series.items()):
        pts = [(xmap(a), ymap(b)) for a, b in sorted(vals) if math.isfinite(b) and (not logy or b > 0)]
        if not pts:
            continue
        color = colors[idx % len(colors)]
        svg.add(f'<polyline points="{polyline(pts)}" fill="none" stroke="{color}" stroke-width="2.4"/>')
        for px, py in pts:
            svg.add(f'<circle cx="{px:.1f}" cy="{py:.1f}" r="4" fill="white" stroke="{color}" stroke-width="2"/>')
        lx = x + w - 118
        ly = y + 24 + idx * 22
        svg.add(f'<line x1="{lx}" y1="{ly}" x2="{lx+28}" y2="{ly}" stroke="{color}" stroke-width="2.4"/>')
        svg.text(lx + 36, ly + 4, name, 12, anchor="start")


def make_stage_svg(rows: list[dict[str, object]], path: Path) -> None:
    rows = [r for r in rows if r.get("stage") in {"Clean", "Damaged", "Recovered"}]
    if not rows:
        return
    rows = unique_rows(rows, ("mod", "stage", "ifmhz"))
    labels = [str(r["stage"]) for r in rows]
    evm = [float(r["evm"]) for r in rows]
    snr = [float(r["snrest"]) for r in rows]
    svg = Svg(1000, 430, "8PSK 离线日志恢复指标")
    metrics = [("EVM (%)", evm, "#4f94d8"), ("SNR_est (dB)", snr, "#35a269")]
    for panel_idx, (title, values, color) in enumerate(metrics):
        x, y, w, h = 80 + panel_idx * 470, 86, 390, 250
        ymax = max(values) * 1.25
        ymap = lambda v: y + h - v / ymax * h
        plot_area(svg, x, y, w, h, title, title)
        draw_axes(svg, x, y, w, h, list(range(len(labels))), nice_ticks(0, ymax, 5), lambda v: x + (v + 0.5) / len(labels) * w, ymap)
        bw = w / len(labels) * 0.52
        for i, val in enumerate(values):
            cx = x + (i + 0.5) / len(labels) * w
            by = ymap(val)
            svg.add(f'<rect x="{cx-bw/2:.1f}" y="{by:.1f}" width="{bw:.1f}" height="{y+h-by:.1f}" fill="{color}"/>')
            svg.text(cx, by - 8, f"{val:.2g}", 12)
            svg.text(cx, y + h + 38, labels[i], 12)
    svg.save(path)


def make_sweep_svg(rows: list[dict[str, object]], path: Path) -> None:
    if not rows:
        return
    rows = unique_rows(rows, ("stage", "snr"))
    by_stage: dict[str, list[dict[str, object]]] = {}
    for row in rows:
        by_stage.setdefault(str(row["stage"]), []).append(row)
    svg = Svg(1500, 500, "8PSK 离线日志 SNR 扫描")
    panels = [
        ("BER vs SNR", "BER", "ber", True, (1e-6, 1)),
        ("EVM vs SNR", "EVM (%)", "evm", False, None),
        ("Frame Lock vs SNR", "锁帧率 (%)", "lock", False, (0, 105)),
    ]
    for i, (title, ylabel, field, logy, ylim) in enumerate(panels):
        series = {
            name: [(float(r["snr"]), max(float(r[field]), 1e-6) if field == "ber" else float(r[field])) for r in vals]
            for name, vals in by_stage.items()
        }
        plot_lines_panel(svg, 70 + i * 480, 90, 390, 300, title, ylabel, series, logy, ylim)
    svg.save(path)


def make_coding_svg(rows: list[dict[str, object]], path: Path) -> None:
    rows = unique_rows(rows, ("coding", "snr"))
    rows = [r for r in rows if math.isfinite(float(r["ber"]))]
    if not rows:
        return
    by_code: dict[str, list[dict[str, object]]] = {}
    for row in rows:
        by_code.setdefault(str(row["coding"]).strip(), []).append(row)
    series = {
        name: [(float(r["snr"]), max(float(r["ber"]), 1e-6)) for r in vals]
        for name, vals in by_code.items()
    }
    svg = Svg(900, 560, "8PSK 编译码 BER 对比（离线日志）")
    plot_lines_panel(svg, 90, 95, 680, 340, "BER vs SNR", "BER", series, True, (1e-6, 1))
    svg.save(path)


def main() -> int:
    if len(sys.argv) < 2:
        print("Usage: python extract_report_figures_from_log.py [--replace-coding] pasted-text.txt", file=sys.stderr)
        return 2
    args = sys.argv[1:]
    replace_coding = False
    if "--replace-coding" in args:
        replace_coding = True
        args.remove("--replace-coding")
    if not args:
        print("Missing log path.", file=sys.stderr)
        return 2
    log_path = Path(args[0])
    text = log_path.read_text(encoding="utf-8", errors="ignore")
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    stage_rows = rows_from_regex(text, STAGE_RE)
    sweep_rows = rows_from_regex(text, SWEEP_RE)
    if not sweep_rows:
        sweep_rows = rows_from_regex(text, IF_LINE_RE)
        for row in sweep_rows:
            row["mod"] = "8PSK"
            row["mer"] = row.get("snrest", math.nan)
            row["recovery"] = "from-console-line"
    coding_rows = rows_from_regex(text, CODING_RE)
    coding_rows.extend(parse_ldpc_blocks(text, keep_rate="1/2"))

    stage_rows = unique_rows(stage_rows, ("mod", "stage", "ifmhz"))
    sweep_rows = unique_rows(sweep_rows, ("mod", "stage", "snr"))
    coding_rows = unique_rows(coding_rows, ("coding", "snr"))

    if stage_rows:
        write_csv(OUT_DIR / "offline_stage_metrics.csv", stage_rows, ["mod", "stage", "ifmhz", "ber", "evm", "mer", "snrest", "lock", "recovery"])
    if sweep_rows:
        write_csv(OUT_DIR / "offline_snr_sweep.csv", sweep_rows, ["mod", "stage", "ifmhz", "snr", "ber", "evm", "mer", "snrest", "lock", "recovery"])
    if coding_rows:
        coding_path = OUT_DIR / "offline_coding_sweep.csv"
        existing_coding = [] if replace_coding else read_csv(coding_path)
        coding_rows = merge_rows(existing_coding, coding_rows, ("coding", "snr"))
        coding_rows = sorted(coding_rows, key=lambda r: (str(r.get("coding", "")), as_float(str(r.get("snr", "nan")))))
        write_csv(coding_path, coding_rows, ["coding", "snr", "ber", "evm", "lock"])

    make_stage_svg(stage_rows, OUT_DIR / "offline_8psk_stage_metrics.svg")
    make_sweep_svg(sweep_rows, OUT_DIR / "offline_8psk_snr_sweep.svg")
    make_coding_svg(coding_rows, OUT_DIR / "offline_8psk_coding_ber.svg")

    print(f"stage rows: {len(stage_rows)}")
    print(f"sweep rows: {len(sweep_rows)}")
    print(f"coding rows: {len(coding_rows)}")
    print(f"saved to: {OUT_DIR}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

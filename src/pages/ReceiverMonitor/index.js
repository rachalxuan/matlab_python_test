import React, { useEffect, useMemo, useRef, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";
import * as echarts from "echarts";
import { getReceiverMonitor } from "../../apis/simulation";
import { asArray, finite, countText, berText, groupRows, lockEvidence, stageText, constellationExplanation } from "./model";
import "./index.scss";

function Plot({ option, label, square = false }) {
  const element = useRef(null);
  const chart = useRef(null);
  useEffect(() => {
    chart.current = echarts.init(element.current);
    const resize = () => chart.current?.resize();
    const observer = typeof ResizeObserver !== "undefined" ? new ResizeObserver(resize) : null;
    observer?.observe(element.current);
    window.addEventListener("resize", resize);
    return () => { observer?.disconnect(); window.removeEventListener("resize", resize); chart.current?.dispose(); chart.current = null; };
  }, []);
  useEffect(() => { chart.current?.setOption(option, true); }, [option]);
  return <div className={`monitor-plot${square ? " square" : ""}`} ref={element} role="img" aria-label={label} />;
}

const axis = { axisLabel: { color: "#95acc2" }, axisLine: { lineStyle: { color: "#385066" } }, splitLine: { lineStyle: { color: "#213447" } } };
const plotBase = { animation: false, textStyle: { color: "#b9cadd" }, grid: { top: 30, right: 28, bottom: 38, left: 58 }, tooltip: { trigger: "axis" } };
const lampNames = [["Carrier", "载波恢复"], ["Timing", "码元同步"], ["Frame", "帧同步"]];
const terminalStates = ["completed", "failed", "cancelled"];

function rememberedTask() {
  try { return localStorage.getItem("receiverMonitorTaskId") || ""; } catch { return ""; }
}

export default function ReceiverMonitor() {
  const [query, setQuery] = useSearchParams();
  const taskId = query.get("task") || rememberedTask();
  const [enteredTask, setEnteredTask] = useState(taskId);
  const [monitor, setMonitor] = useState(null);
  const [rows, setRows] = useState([]);
  const [error, setError] = useState("");
  const [retry, setRetry] = useState(0);
  const [cursor, setCursor] = useState(null);
  const [playing, setPlaying] = useState(false);
  const [speed, setSpeed] = useState(1);
  const [onlyBad, setOnlyBad] = useState(false);

  useEffect(() => {
    setEnteredTask(taskId);
    setMonitor(null); setRows([]); setCursor(null); setPlaying(false); setError("");
    if (!taskId) return undefined;
    let stopped = false, timer, received = [], after = 0;
    const abort = new AbortController();
    const poll = async () => {
      try {
        const data = await getReceiverMonitor(taskId, after, abort.signal);
        if (stopped) return;
        if (!data.success) throw new Error(data.error || "无法读取监控数据");
        setError("");
        received = received.concat(asArray(data.rows));
        after = data.nextCursor;
        setRows(received);
        setMonitor((previous) => ({ ...previous, ...data,
          constellation: data.constellation || previous?.constellation,
          spectrum: data.spectrum || previous?.spectrum,
          locks: data.locks || previous?.locks,
          equalizer: data.equalizer || previous?.equalizer,
        }));
        if (after < data.totalRows) timer = setTimeout(poll, 0);
        else if (!terminalStates.includes(data.status)) timer = setTimeout(poll, 500);
      } catch (err) {
        if (stopped || err.name === "AbortError") return;
        setError(`监控连接中断：${err.message}。保留已收到的记录，不把旧状态当作实时锁定。`);
        timer = setTimeout(poll, 2000);
      }
    };
    poll();
    return () => { stopped = true; abort.abort(); clearTimeout(timer); };
  }, [taskId, retry]);

  const groups = useMemo(() => groupRows(rows), [rows]);
  const ready = Boolean(monitor?.metricsReady && rows.length === monitor?.totalRows && groups.length);
  const index = cursor === null ? groups.length - 1 : Math.min(cursor, groups.length - 1);
  const selected = ready ? groups[index] : null;
  const last = selected?.last;
  const modulation = monitor?.summary?.modType || "—";
  const coding = monitor?.summary?.channelCoding || "—";
  const finished = terminalStates.includes(monitor?.status);
  const coverage = monitor?.timeline?.MeasurementCoverage;

  useEffect(() => {
    if (!playing || !ready) return undefined;
    const timer = setInterval(() => {
      setCursor((value) => {
        const next = Math.min((value ?? 0) + speed, groups.length - 1);
        return next;
      });
    }, 500);
    return () => clearInterval(timer);
  }, [playing, ready, speed, groups.length]);
  useEffect(() => { if (cursor !== null && cursor >= groups.length - 1) setPlaying(false); }, [cursor, groups.length]);

  const lockChart = useMemo(() => ({ ...plotBase,
    legend: { data: ["载波", "码元", "帧同步"], textStyle: { color: "#b9cadd" }, top: 0 },
    xAxis: { ...axis, type: "value", name: "ms" },
    yAxis: { ...axis, type: "value", min: 0, max: 1, interval: 1, axisLabel: { color: "#95acc2", formatter: (v) => v ? "锁定" : "失锁" } },
    series: lampNames.map(([name], k) => ({ name: ["载波", "码元", "帧同步"][k], type: "line", step: "end", connectNulls: false, showSymbol: false,
      lineStyle: { width: 2 }, itemStyle: { color: ["#59d7ff", "#c4a4ff", "#67dea2"][k] },
      data: groups.map((g) => { const evidence = lockEvidence(g, name, monitor?.locks?.[name]); return [g.time * 1000, evidence.kind === "unknown" ? null : evidence.kind === "locked" ? 1 : 0]; }),
    })),
  }), [groups, monitor?.locks]);

  const errorChart = useMemo(() => ({ ...plotBase,
    legend: { data: ["窗口误码 bit", "累计误码 bit"], textStyle: { color: "#b9cadd" }, top: 0 },
    xAxis: { ...axis, type: "value", name: "ms" }, yAxis: { ...axis, type: "value", min: 0 },
    series: [
      { name: "窗口误码 bit", type: "bar", itemStyle: { color: "#ffbd70" }, data: groups.map((g) => [g.time * 1000, g.bits ? g.errors : null]) },
      { name: "累计误码 bit", type: "line", showSymbol: false, itemStyle: { color: "#ff6f84" }, data: groups.map((g) => [g.time * 1000, g.last.CumulativeErrorBits]) },
    ],
  }), [groups]);

  const constellation = monitor?.constellation;
  const constellationChart = useMemo(() => {
    const extent = Math.max(1e-6, ...asArray(constellation?.i).filter(finite).map(Math.abs), ...asArray(constellation?.q).filter(finite).map(Math.abs)) * 1.1;
    const iqAxis = { ...axis, type: "value", min: -extent, max: extent,
      axisLabel: { ...axis.axisLabel, formatter: (value) => Number(value.toPrecision(3)).toString() } };
    return { ...plotBase, grid: { top: 40, right: 40, bottom: 40, left: 40 }, tooltip: { trigger: "item" },
    xAxis: { ...iqAxis, name: "I" }, yAxis: { ...iqAxis, name: "Q" },
    series: [{ type: "scatter", symbolSize: 3, itemStyle: { color: "#5bd6ff", opacity: 0.65 }, data: asArray(constellation?.i).map((i, k) => [i, asArray(constellation?.q)[k]]) }],
  }; }, [constellation]);
  const spectrum = monitor?.spectrum;
  const spectrumChart = useMemo(() => ({ ...plotBase,
    xAxis: { ...axis, type: "value", name: "MHz" }, yAxis: { ...axis, type: "value", name: "相对 dB" },
    series: [{ type: "line", showSymbol: false, lineStyle: { width: 1 }, itemStyle: { color: "#f2c36b" }, data: asArray(spectrum?.frequencyMHz).map((f, k) => [f, asArray(spectrum?.relativeDB)[k]]) }],
  }), [spectrum]);
  const hasIssue = (r) => r.ErrorBitsDelta > 0 || (r.MeasurementEligible && !r.ComparedBitsDelta);
  const visibleRows = ready ? rows.filter((r) => r.TimeEnd_s <= selected.time && (!onlyBad || hasIssue(r))).slice(-80) : [];

  const download = () => {
    const blob = new Blob([JSON.stringify({ taskId, metadata: monitor?.timeline, rows }, null, 2)], { type: "application/json" });
    const url = URL.createObjectURL(blob); const anchor = document.createElement("a");
    anchor.href = url; anchor.download = `receiver-timeline-${taskId}.json`; anchor.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  };

  return <main className="receiver-monitor">
    <header className="monitor-heading">
      <div><p className="monitor-eyebrow">TELEMETRY / RECEIVER</p><h1>接收监控</h1><p>把锁定证据、误码增量与测量覆盖放在同一条仿真时间线上。</p></div>
      <Link className="monitor-button" to="/matlab">配置仿真 →</Link>
    </header>

    <section className="monitor-toolbar" aria-label="任务选择">
      <form onSubmit={(e) => { e.preventDefault(); if (enteredTask.trim()) setQuery({ task: enteredTask.trim() }); }}>
        <label htmlFor="monitor-task">任务 ID</label><input id="monitor-task" value={enteredTask} onChange={(e) => setEnteredTask(e.target.value)} placeholder="从信号调制页面启动后自动关联" />
        <button type="submit">连接任务</button>
      </form>
      <button onClick={() => setRetry((n) => n + 1)} disabled={!taskId}>重新读取</button>
      <span className={`monitor-badge ${error ? "danger" : ""}`}>{error ? "连接中断" : finished ? "已结束" : taskId ? "任务监控 · 500 ms 刷新" : "等待任务"}</span>
    </section>
    {error && <div className="monitor-alert" role="alert">{error}</div>}
    {monitor?.error && <div className="monitor-alert" role="alert">任务信息：{monitor.error}</div>}

    <section className="monitor-mode-note">
      <strong>处理方式：整段仿真</strong>
      <span>运行中推送真实处理阶段；可靠的 bit 计数在选定接收结果后发布。下方播放是结果回放，不是持续分块接收。</span>
    </section>
    {ready && coverage?.Available && !coverage.Complete && <div className="monitor-alert" role="alert">
      <strong>测量覆盖不足 · {coverage.Status}</strong><br />
      全任务实际比较 {countText(coverage.ComparedFrames)} / {countText(coverage.ExpectedFrames)} 帧；未恢复 {countText(coverage.UnrecoveredFrames)} 帧，已恢复但未比较 {countText(coverage.RecoveredNotComparedFrames)} 帧。
      当前 BER 只代表已比较数据，不能据此判定整个测量区无误码。
    </div>}

    <section className="monitor-panel">
      <div className="monitor-panel-title"><h2>接收链路状态</h2><span>{modulation} · {coding} · {monitor?.summary?.DataPathMode || "single"}</span></div>
      <div className="monitor-stage"><span className={finished ? "" : "monitor-pulse"} />{finished ? stageText(monitor.status) : stageText(monitor?.stage)}{monitor?.status === "queued" ? ` / 队列 ${monitor.position || 1}` : ""}</div>
      <div className="monitor-lamps">
        {lampNames.map(([name, title]) => {
          const state = error && !finished ? { kind: "unknown", label: "连接中断", detail: "不沿用旧锁定状态" } : lockEvidence(selected, name, monitor?.locks?.[name]);
          return <div className={`monitor-lamp ${state.kind}`} key={name} title={state.detail}><span className="lamp-dot" /><span>{title}<small>{ready ? "记录时刻的观测" : "等待审定记录"}</small></span><strong>{state.label}</strong></div>;
        })}
        <div className="monitor-lamp unknown" title="均衡器已执行，不等于已收敛；不伪造独立锁定灯"><span className="lamp-dot" /><span>均衡器<small>无独立锁定检测</small></span><strong>{monitor?.equalizer ? monitor.equalizer.applied ? "已执行" : "未启用" : "未观测"}</strong></div>
        <div className="monitor-lamp unknown" title="不通过 BER 或载波锁定推断译码器锁定"><span className="lamp-dot" /><span>译码器<small>{coding}</small></span><strong>{coding === "none" ? "旁路" : "无锁定遥测"}</strong></div>
      </div>
      <p className="monitor-footnote">绿：检测器锁定；红：检测器失锁；灰：未观测、证据过期或旁路。锁定不保证无误码。合路不复制一个虚假的 Q 路锁定灯。</p>
    </section>

    <section className="monitor-replay" aria-label="仿真时间回放">
      <div><span className="monitor-badge">{playing ? "回放中" : cursor === null ? "末次记录" : "回放已暂停"}</span><strong>{selected ? `${(selected.time * 1000).toFixed(4)} ms` : "尚无可比较记录"}</strong></div>
      <input aria-label="仿真时间位置" type="range" min={0} max={Math.max(0, groups.length - 1)} value={Math.max(0, index)} disabled={!ready} onChange={(e) => { setPlaying(false); setCursor(Number(e.target.value)); }} />
      <button disabled={!ready} onClick={() => { if (!playing && (cursor === null || index >= groups.length - 1)) setCursor(0); setPlaying(!playing); }}>{playing ? "暂停回放" : "播放记录"}</button>
      <select aria-label="回放步进" value={speed} onChange={(e) => setSpeed(Number(e.target.value))}><option value={1}>1 窗口 / 次</option><option value={4}>4 窗口 / 次</option><option value={16}>16 窗口 / 次</option></select>
      <button disabled={!ready} onClick={() => { setPlaying(false); setCursor(null); }}>回到末次</button>
    </section>

    <section className="monitor-metrics" aria-label="误码计数">
      {[
        ["总比较 bit", countText(last?.CumulativeComparedBits), "仅实际与参考配对的测量区数据"],
        ["累计误码 bit", countText(last?.CumulativeErrorBits), "不会因短时重新锁定而清零"],
        ["累计 BER", berText(last?.CumulativeBER), "分母为总比较 bit，不是发射总量"],
        ["当前窗口误码 bit", selected?.bits ? countText(selected.errors) : "N/A", selected?.bits ? `本窗口比较 ${countText(selected.bits)} bit` : "没有可比较数据 ≠ 零误码"],
        ["未恢复测量帧", countText(last?.CumulativeUnrecoveredFrames), "不计成零错误，也不伪造 bit 错误"],
        ["已比较 / 应测帧", last ? `${countText(last.CumulativeComparedFrames)} / ${countText(monitor?.timeline?.Summary?.MeasurementExpectedFrames)}` : "—", "完整覆盖须检查任务末次记录"],
      ].map(([label, value, detail]) => <div className="monitor-metric" key={label}><h3>{label}</h3><strong>{value}</strong><p>{detail}</p></div>)}
    </section>
    {ready && <p className="monitor-footnote">计数域：{monitor.timeline?.MetricDomain}。内部缺口 {countText(last?.CumulativeMissingWithinSpan)} 帧；首尾或无法定位的缺失 {countText(last?.CumulativeBoundaryUnobserved)} 帧。时间对齐包含接收链延迟，不能据此断言某次失锁就是某个错误的原因。</p>}
    {!ready && <div className="monitor-empty">{monitor?.metricsReady ? `正在接收完整时间记录：${rows.length} / ${monitor.totalRows} 行` : monitor?.timeline?.Reason || (finished ? "该任务没有导出统一时间记录，请启动一次新的仿真。" : "尚未产生审定的逐帧统计。后台计算期间不显示虚构的 0 BER 或绿色锁定灯。")}</div>}

    <div className="monitor-chart-grid">
      <section className="monitor-panel"><h2>锁定时间记录</h2><Plot label="载波码元帧同步锁定时间线" option={lockChart} /><p className="monitor-footnote">仿真时间 · 按帧窗口末次证据显示；空白为未观测，不补成锁定。</p></section>
      <section className="monitor-panel"><h2>错误增长记录</h2><Plot label="逐窗口误码与累计误码" option={errorChart} /><p className="monitor-footnote">累计曲线不再上升且比较量继续增长，才说明该区间没有新增可测误码。</p></section>
      <section className="monitor-panel"><div className="monitor-panel-title"><h2>接收 IQ 散点</h2><span>整段快照 · 不随回放变化</span></div>{constellation ? <Plot square label="实际接收IQ整段快照" option={constellationChart} /> : <div className="monitor-empty">等待接收样本</div>}<p className="monitor-footnote">{constellationExplanation(modulation)} 观察位置：选定整体相位后的 ctx.fineSynced，I/Q 等比例坐标。</p></section>
      <section className="monitor-panel"><div className="monitor-panel-title"><h2>接收基带频谱</h2><span>首窗快照 · 相对峰值</span></div>{spectrum ? <Plot label="接收基带相对频谱" option={spectrumChart} /> : <div className="monitor-empty">等待接收样本</div>}<p className="monitor-footnote">不是绝对 dBm/Hz，也不是当前回放时刻的频谱。</p></section>
    </div>

    <section className="monitor-panel">
      <div className="monitor-panel-title"><h2>逐帧核对</h2><div><label><input type="checkbox" checked={onlyBad} onChange={(e) => setOnlyBad(e.target.checked)} /> 仅错误 / 未比较</label><button disabled={!ready} onClick={download}>导出完整记录</button></div></div>
      <div className="monitor-table-scroll"><table><thead><tr>{["路", "发送帧", "仿真结束 ms", "比较 bit", "错误 bit", "帧 BER", "覆盖状态", "测量区"].map((x) => <th key={x}>{x}</th>)}</tr></thead><tbody>
        {visibleRows.map((r, k) => <tr key={`${r.Lane}-${r.TxFrameIndex}-${k}`} className={hasIssue(r) ? "bad-row" : ""}><td>{r.Lane}</td><td>{r.TxFrameIndex}</td><td>{finite(r.TimeEnd_s) ? (r.TimeEnd_s * 1000).toFixed(4) : "—"}</td><td>{countText(r.ComparedBitsDelta)}</td><td>{r.ComparedBitsDelta ? countText(r.ErrorBitsDelta) : "N/A"}</td><td>{berText(r.FrameBER)}</td><td>{r.Coverage}</td><td>{r.MeasurementEligible ? "是" : "预热"}</td></tr>)}
      </tbody></table></div>
      <p className="monitor-footnote">显示当前位置之前最近 80 条符合筛选的记录；导出包含所有帧与 I/Q 路。预热不进入测量计数，无法恢复的帧单列覆盖缺口。</p>
    </section>
  </main>;
}

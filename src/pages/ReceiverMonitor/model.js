export const finite = (v) => typeof v === "number" && Number.isFinite(v);
export const asArray = (v) => Array.isArray(v) ? v : v === null || v === undefined ? [] : [v];
export const countText = (v) => finite(v) ? v.toLocaleString("zh-CN") : "—";
export const berText = (v) => finite(v) ? v === 0 ? "0" : v.toExponential(3) : "N/A";

// Publish I/Q rows at an equal simulation time together, never double-count.
export function groupRows(rows) {
  const groups = [];
  for (const row of rows) {
    let group = groups[groups.length - 1];
    if (!group || group.time !== row.TimeEnd_s) {
      group = { time: row.TimeEnd_s, rows: [], last: row, bits: 0, errors: 0 };
      groups.push(group);
    }
    group.rows.push(row);
    group.last = row;
    group.bits += row.ComparedBitsDelta || 0;
    group.errors += row.ErrorBitsDelta || 0;
  }
  return groups;
}

export function lockEvidence(group, name, info) {
  if (!group || !info?.Available) {
    return { kind: "unknown", label: "未观测", detail: info?.Reason || "当前路径未提供检测证据" };
  }
  const states = group.rows.map((r) => r[`${name}LastObservedState`]);
  if (!states.every(finite)) return { kind: "unknown", label: "未观测", detail: "该时刻没有锁定观测" };
  const frameSpan = Math.max(...group.rows.map((r) => r.TimeEnd_s - r.TimeStart_s));
  const limit = Math.max(frameSpan * 2, (info.ObservationPeriod_s || 0) * 2, 1e-6);
  const stale = group.rows.some((r) => !finite(r[`${name}EvidenceAge_s`]) || r[`${name}EvidenceAge_s`] > limit);
  if (stale) return { kind: "unknown", label: "证据过期", detail: "保留的末次状态过旧，不判为当前锁定" };
  const locked = states.every((v) => v === 1);
  return { kind: locked ? "locked" : "unlocked", label: locked ? "锁定" : "失锁", detail: info.Source };
}

export const stageText = (stage) => ({
  queued: "等待 MATLAB", running: "MATLAB 处理中", starting: "构建发射数据",
  channel: "信道与射频损伤", synchronizing: "载波 / 定时 / 均衡处理",
  decoding: "帧同步、译码与参考配对", "results-ready": "统计已审定，生成输出图像",
  completed: "任务完成", cancelled: "任务已停止", cancelling: "正在停止", failed: "任务失败",
}[stage] || "等待后台数据");

export function constellationExplanation(modulation) {
  const mod = String(modulation || "").toUpperCase();
  if (mod === "GMSK" || mod === "MSK") return "MSK/GMSK 是有记忆的连续相位调制。此处绘制实际接收 IQ；不会重映射成四个 QPSK 判决点。图形取决于采样时刻与观察位置。";
  if (mod === "OQPSK") return "OQPSK 的 I/Q 相差半个符号。重对齐或判决后的图可呈四点，但原始相位轨迹与 QPSK 不同。此处不额外重对齐。";
  if (mod === "UQPSK") return "UQPSK 的 I/Q 功率或码率可不相等；等功率时也可能呈四点。图形不能单独证明两路码率、功率及同步是否正确。";
  return "显示接收机实际复样本；星座紧凑不等于没有相位歧义或误码。";
}

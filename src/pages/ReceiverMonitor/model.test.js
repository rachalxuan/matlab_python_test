import { asArray, groupRows, lockEvidence, berText, countText, constellationExplanation } from "./model";

test("zero comparisons and non-finite metrics are not zero BER", () => {
  expect(asArray(0)).toEqual([0]);
  expect(asArray(null)).toEqual([]);
  expect(berText(null)).toBe("N/A");
  expect(berText(NaN)).toBe("N/A");
  expect(berText(0)).toBe("0");
  expect(countText(null)).toBe("—");
});

test("equal-time I/Q observations publish together, last cumulative counter used once", () => {
  const rows = [
    { Lane: "I", TimeEnd_s: 1, ComparedBitsDelta: 100, ErrorBitsDelta: 2, CumulativeComparedBits: 100 },
    { Lane: "Q", TimeEnd_s: 1, ComparedBitsDelta: 100, ErrorBitsDelta: 3, CumulativeComparedBits: 200 },
    { Lane: "I", TimeEnd_s: 2, ComparedBitsDelta: 0, ErrorBitsDelta: 0, CumulativeComparedBits: 200 },
  ];
  const groups = groupRows(rows);
  expect(groups).toHaveLength(2);
  expect(groups[0].bits).toBe(200);
  expect(groups[0].errors).toBe(5);
  expect(groups[0].last.CumulativeComparedBits).toBe(200);
  expect(groups[1].bits).toBe(0);
});

test("missing, stale and unavailable lock evidence never lights green", () => {
  const row = { TimeStart_s: 0, TimeEnd_s: 0.001, CarrierLastObservedState: 1, CarrierEvidenceAge_s: 0 };
  const group = { rows: [row] };
  expect(lockEvidence(group, "Carrier", { Available: true }).kind).toBe("locked");
  expect(lockEvidence(group, "Carrier", { Available: false }).kind).toBe("unknown");
  expect(lockEvidence({ rows: [{ ...row, CarrierEvidenceAge_s: 1 }] }, "Carrier", { Available: true }).kind).toBe("unknown");
  expect(lockEvidence({ rows: [{ ...row, CarrierLastObservedState: null }] }, "Carrier", { Available: true }).kind).toBe("unknown");
  expect(lockEvidence({ rows: [{ ...row, CarrierLastObservedState: 0 }] }, "Carrier", { Available: true }).kind).toBe("unlocked");
});

test("CPM display is not labelled QPSK", () => {
  expect(constellationExplanation("GMSK")).toContain("不会重映射");
  expect(constellationExplanation("OQPSK")).toContain("半个符号");
  expect(constellationExplanation("UQPSK")).toContain("不相等");
});

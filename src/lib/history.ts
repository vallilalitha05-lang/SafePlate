import type { FlaggedItem } from "@/lib/evidence";
import type { OperatingStatus } from "@/lib/suspensions";

export type ChecklistEntry = {
  item: string;
  result: "pass" | "fail";
  comment: string | null;
  remediation_deadline: string | null;
  photo_path: string | null;
};

export type HistoryInspection = {
  id: string;
  created_at: string;
  overall_status: "pass" | "fail";
  notes: string | null;
  checklist: ChecklistEntry[];
  inspector_name: string;
  conducted_by_viewer: boolean;
  ticket: { id: string; status: string; items: FlaggedItem[] } | null;
};

export type HistorySuspension = {
  id: string;
  reason: string;
  item: string | null;
  suspended_at: string;
  lifted_at: string | null;
  lift_reason: string | null;
};

export type StoreHistory = {
  store: { id: string; name: string; address: string | null; operating_status: OperatingStatus; linked_at: string };
  inspections: HistoryInspection[];
  suspensions: HistorySuspension[];
};

export type ViolationTrend = { item: string; count: number; lastFailedAt: string };

export type HistorySummary = {
  total: number;
  passed: number;
  failed: number;
  passRate: number | null;
  lastInspectedAt: string | null;
  violations: ViolationTrend[];
  /** Overall results oldest → newest, for a quick trend strip. */
  results: ("pass" | "fail")[];
};

/** Trends across a store's inspections (inspections are newest first). */
export function summarizeHistory(inspections: HistoryInspection[]): HistorySummary {
  const passed = inspections.filter((inspection) => inspection.overall_status === "pass").length;
  const violations = new Map<string, ViolationTrend>();
  for (const inspection of inspections) {
    for (const entry of inspection.checklist) {
      if (entry.result !== "fail") continue;
      const existing = violations.get(entry.item);
      if (existing) {
        existing.count += 1;
        if (inspection.created_at > existing.lastFailedAt) existing.lastFailedAt = inspection.created_at;
      } else {
        violations.set(entry.item, { item: entry.item, count: 1, lastFailedAt: inspection.created_at });
      }
    }
  }
  return {
    total: inspections.length,
    passed,
    failed: inspections.length - passed,
    passRate: inspections.length ? Math.round((passed / inspections.length) * 100) : null,
    lastInspectedAt: inspections[0]?.created_at ?? null,
    violations: [...violations.values()].sort((a, b) => b.count - a.count || b.lastFailedAt.localeCompare(a.lastFailedAt) || a.item.localeCompare(b.item)),
    results: inspections.map((inspection) => inspection.overall_status).reverse(),
  };
}

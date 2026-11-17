import { describe, expect, it } from "vitest";
import { evidenceStatusForSubmission, getDaysRemaining, isOverdue, shouldFlagOverdue } from "@/lib/deadlines";

const today = "2026-11-15";
const yesterday = "2026-11-14";

describe("evidenceStatusForSubmission", () => {
  // AC12.2 — Story 12: Upload remediation evidence
  it("marks late evidence as resolved late", () => {
    const result = evidenceStatusForSubmission(yesterday, today);
    expect(result.accepted).toBe(true);
    expect(result.status).toBe("pending_inspector_review");
    expect(result.resolvedLate).toBe(true);
  });
});

describe("getDaysRemaining", () => {
  // AC13.1 — Story 13: View remediation deadlines
  it("returns the days left until the deadline", () => {
    expect(getDaysRemaining("2026-11-18", today)).toBe(3);
  });

  // Other test 1 — boundary: the deadline is today
  it("returns 0 on the deadline day", () => {
    expect(getDaysRemaining(today, today)).toBe(0);
  });
});

describe("isOverdue", () => {
  // AC13.2 — Story 13: View remediation deadlines
  it("is true after the deadline with no evidence", () => {
    expect(isOverdue({ remediation_deadline: yesterday }, today)).toBe(true);
  });
});

describe("shouldFlagOverdue", () => {
  // AC17.1 — Story 17: Flag overdue issues
  it("flags an expired item with no evidence", () => {
    expect(shouldFlagOverdue({ remediation_deadline: yesterday }, today)).toBe(true);
  });

  // AC17.2 — Story 17: Flag overdue issues
  it("does not flag an item with evidence already submitted", () => {
    expect(shouldFlagOverdue({ remediation_deadline: yesterday, status: "pending_inspector_review" }, today)).toBe(false);
  });

  // AC17.3 — Story 17: Flag overdue issues
  it("does not flag a resolved item", () => {
    expect(shouldFlagOverdue({ remediation_deadline: yesterday, status: "resolved" }, today)).toBe(false);
  });
});

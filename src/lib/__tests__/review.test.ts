import { describe, expect, it } from "vitest";
import { allItemsResolved, validateFollowUpDate, validateRejectionReason } from "@/lib/review";

const now = new Date("2026-11-15T18:00:00Z");

describe("allItemsResolved", () => {
  // AC15.3 — Story 15: Approve fix
  it("is true only when every item is resolved", () => {
    expect(allItemsResolved([{ status: "resolved" }, { status: "resolved" }])).toBe(true);
    expect(allItemsResolved([{ status: "resolved" }, { status: "pending_inspector_review" }])).toBe(false);
  });
});

describe("validateRejectionReason", () => {
  // AC16.2 — Story 16: Reject fix & schedule re-inspection
  it("rejects a blank reason", () => {
    const result = validateRejectionReason("");
    expect(result.valid).toBe(false);
    if (!result.valid) expect(result.message).toMatch(/provide a reason/i);
  });
});

describe("validateFollowUpDate", () => {
  // AC16.3 — Story 16: Reject fix & schedule re-inspection
  it("rejects a follow-up date in the past", () => {
    const yesterday = new Date(now.getTime() - 24 * 60 * 60 * 1000);
    const result = validateFollowUpDate(yesterday, now);
    expect(result.valid).toBe(false);
    if (!result.valid) expect(result.message).toMatch(/future date and time/i);
  });
});

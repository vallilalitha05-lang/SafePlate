import { describe, expect, it } from "vitest";
import {
  findUnmarkedItems,
  validateComment,
  validateDeadline,
  validateEmail,
  validateInspectionSubmit,
  validatePassword,
  validatePasswordMatch,
  validatePhoto,
} from "@/lib/validation";

const today = "2026-11-15";
const addDays = (date: string, days: number) => {
  const [y, m, d] = date.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d + days)).toISOString().slice(0, 10);
};
const fileOf = (type: string, size: number) => new File([new Uint8Array(size)], "upload", { type });

describe("validatePassword", () => {
  // AC1.4 — Story 1: Register with a role
  it("rejects a password shorter than 8 characters", () => {
    const result = validatePassword("abc123");
    expect(result.valid).toBe(false);
    if (!result.valid) expect(result.message).toMatch(/at least 8 characters/i);
  });
});

describe("validatePasswordMatch", () => {
  // AC1.5 — Story 1: Register with a role
  it("rejects mismatched passwords", () => {
    const result = validatePasswordMatch("Passw0rd!", "Passw0rd?");
    expect(result.valid).toBe(false);
    if (!result.valid) expect(result.message).toMatch(/passwords do not match/i);
  });
});

describe("validateEmail", () => {
  // AC1.6 — Story 1: Register with a role
  it("rejects an invalid email address", () => {
    const result = validateEmail("safeplate.com");
    expect(result.valid).toBe(false);
    if (!result.valid) expect(result.message).toMatch(/email is invalid/i);
  });

  // AC1.8 — Story 1: Register with a role (rejected before any database call)
  it("rejects a SQL-injection string", () => {
    expect(validateEmail("' OR 1=1--").valid).toBe(false);
  });
});

describe("findUnmarkedItems", () => {
  // AC5.3 — Story 5: Mark checklist items pass or fail
  it("lists every unmarked item", () => {
    const items = ["Food temperature", "Handwashing", "Surfaces"];
    const responses = { "Food temperature": { result: "pass" as const }, Surfaces: { result: "fail" as const } };
    expect(findUnmarkedItems(items, responses)).toEqual(["Handwashing"]);
  });
});

describe("validateComment", () => {
  // AC6.3 — Story 6: Attach a written comment
  it("rejects a whitespace-only comment", () => {
    expect(validateComment("   ").valid).toBe(false);
  });
});

describe("validatePhoto", () => {
  // AC7.2 — Story 7: Attach a photo
  it("rejects an unsupported file type", () => {
    const result = validatePhoto(fileOf("text/plain", 1024));
    expect(result.valid).toBe(false);
    if (!result.valid) expect(result.message).toMatch(/JPEG.*PNG.*WebP/);
  });

  // AC7.3 — Story 7: Attach a photo
  it("rejects a file larger than 5 MB", () => {
    const result = validatePhoto(fileOf("image/jpeg", 5 * 1024 * 1024 + 1));
    expect(result.valid).toBe(false);
    if (!result.valid) expect(result.message).toMatch(/5 MB/);
  });
});

describe("validateDeadline", () => {
  // AC8.1 — Story 8: Set a remediation deadline
  it("accepts a future date", () => {
    expect(validateDeadline(addDays(today, 7), today)).toEqual({ valid: true });
  });

  // AC8.2 — Story 8: Set a remediation deadline
  it("rejects a past date", () => {
    const result = validateDeadline(addDays(today, -1), today);
    expect(result.valid).toBe(false);
    if (!result.valid) expect(result.message).toMatch(/today or later/i);
  });
});

describe("validateInspectionSubmit", () => {
  // AC9.3 — Story 9: Submit a completed inspection
  it("rejects a failed item with no deadline", () => {
    const result = validateInspectionSubmit({
      storeId: "store-a",
      items: ["Handwashing"],
      responses: { Handwashing: { result: "fail", comment: "No soap at the sink" } },
      today,
    });
    expect(result.valid).toBe(false);
    if (!result.valid) expect(result.message).toMatch(/remediation deadline/i);
  });
});

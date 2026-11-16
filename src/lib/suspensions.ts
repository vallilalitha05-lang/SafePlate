import { storeNameOf, type StoreRelation } from "@/lib/stores";

export type OperatingStatus = "active" | "suspended";

export type ActiveSuspension = {
  id: string;
  store_id: string;
  store: string;
  reason: string;
  item: string | null;
  suspended_at: string;
  suspendedByViewer: boolean;
};

export type SuspensionRow = {
  id: string;
  store_id: string;
  reason: string;
  item: string | null;
  suspended_at: string;
  suspended_by: string;
  stores: StoreRelation;
};

export function toActiveSuspension({ stores, suspended_by, ...row }: SuspensionRow, viewerId?: string): ActiveSuspension {
  return { ...row, store: storeNameOf(stores, "Store"), suspendedByViewer: suspended_by === viewerId };
}

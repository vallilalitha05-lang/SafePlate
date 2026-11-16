import { storeNameOf, type StoreRelation } from "@/lib/stores";

export type InspectorNotificationRow = {
  id: string;
  ticket_id: string;
  kind: "item_overdue";
  item: string;
  created_at: string;
  remediation_tickets: { stores: StoreRelation } | { stores: StoreRelation }[] | null;
};

export type InspectorNotification = Omit<InspectorNotificationRow, "remediation_tickets"> & { store: string };

export function toInspectorNotification({ remediation_tickets: ticket, ...row }: InspectorNotificationRow): InspectorNotification {
  const joined = Array.isArray(ticket) ? ticket[0] : ticket;
  return { ...row, store: storeNameOf(joined?.stores, "Store") };
}

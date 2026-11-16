import { storeNameOf, type StoreRelation } from "@/lib/stores";

export type NotificationKind = "ticket_issued" | "item_approved" | "item_rejected" | "store_suspended" | "suspension_lifted";

type Suspension = { reason: string; lift_reason: string | null; stores: StoreRelation };

type FollowUp = { reason: string; scheduled_for: string };

export type OwnerNotification = {
  id: string;
  ticket_id: string | null;
  kind: NotificationKind;
  item: string | null;
  created_at: string;
  /** Joined follow-up inspection for rejection notices; Supabase returns an object for a to-one join. */
  follow_up_inspections?: FollowUp | FollowUp[] | null;
  /** Joined suspension record for suspension notices. */
  store_suspensions?: Suspension | Suspension[] | null;
};

export type NotificationView = OwnerNotification & { store: string; ticketResolved: boolean };

export function followUpOf(notification: OwnerNotification) {
  const followUp = notification.follow_up_inspections;
  return (Array.isArray(followUp) ? followUp[0] : followUp) ?? undefined;
}

export function suspensionOf(notification: OwnerNotification) {
  const suspension = notification.store_suspensions;
  return (Array.isArray(suspension) ? suspension[0] : suspension) ?? undefined;
}

/** Store name for a notification: from the suspension record or the ticket. */
export function notificationStore(notification: OwnerNotification, ticketStore: string) {
  const suspension = suspensionOf(notification);
  return suspension ? storeNameOf(suspension.stores, ticketStore) : ticketStore;
}

export function describeNotification(notification: NotificationView) {
  if (notification.kind === "store_suspended") {
    return { title: "Store suspended", message: `An inspector suspended the operating status of ${notification.store}.`, reason: suspensionOf(notification)?.reason, scheduledFor: undefined };
  }
  if (notification.kind === "suspension_lifted") {
    return { title: "Suspension lifted", message: `An inspector lifted the suspension of ${notification.store}. The store's operating status is active again.`, reason: suspensionOf(notification)?.lift_reason ?? undefined, scheduledFor: undefined };
  }
  if (notification.kind === "item_rejected") {
    const followUp = followUpOf(notification);
    return {
      title: "Fix rejected – follow-up inspection scheduled",
      message: `The inspector rejected the evidence for “${notification.item}” at ${notification.store} and will verify the fix in person.`,
      reason: followUp?.reason,
      scheduledFor: followUp?.scheduled_for,
    };
  }
  if (notification.kind === "item_approved") {
    return {
      title: "Fix approved",
      message: `The inspector approved your fix for “${notification.item}” at ${notification.store}. The issue is resolved and closed.${notification.ticketResolved ? " Every issue on this ticket is now resolved." : ""}`,
    };
  }
  return { title: "New inspection ticket", message: `A new remediation ticket has been issued for ${notification.store}.` };
}

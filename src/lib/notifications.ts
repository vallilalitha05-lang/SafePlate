export type NotificationKind = "ticket_issued" | "item_approved" | "item_rejected";

type FollowUp = { reason: string; scheduled_for: string };

export type OwnerNotification = {
  id: string;
  ticket_id: string;
  kind: NotificationKind;
  item: string | null;
  created_at: string;
  /** Joined follow-up inspection for rejection notices; Supabase returns an object for a to-one join. */
  follow_up_inspections?: FollowUp | FollowUp[] | null;
};

export type NotificationView = OwnerNotification & { store: string; ticketResolved: boolean };

export function followUpOf(notification: OwnerNotification) {
  const followUp = notification.follow_up_inspections;
  return (Array.isArray(followUp) ? followUp[0] : followUp) ?? undefined;
}

export function describeNotification(notification: NotificationView) {
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

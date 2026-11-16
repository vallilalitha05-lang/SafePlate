export type NotificationKind = "ticket_issued" | "item_approved";

export type OwnerNotification = {
  id: string;
  ticket_id: string;
  kind: NotificationKind;
  item: string | null;
  created_at: string;
};

export type NotificationView = OwnerNotification & { store: string; ticketResolved: boolean };

export function describeNotification(notification: NotificationView) {
  if (notification.kind === "item_approved") {
    return {
      title: "Fix approved",
      message: `The inspector approved your fix for “${notification.item}” at ${notification.store}. The issue is resolved and closed.${notification.ticketResolved ? " Every issue on this ticket is now resolved." : ""}`,
    };
  }
  return { title: "New inspection ticket", message: `A new remediation ticket has been issued for ${notification.store}.` };
}

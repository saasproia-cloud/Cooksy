/**
 * French date/number formatting shared by the notification templates.
 * Centralised so "24 mai 2026" and "39,99 €" render identically whether
 * the copy comes from the webhook path or a cron.
 */

const LONG_DATE = new Intl.DateTimeFormat("fr-FR", {
  day: "numeric",
  month: "long",
  year: "numeric",
  timeZone: "Europe/Paris"
});

/** "24 mai 2026" */
export function frenchLongDate(date: Date): string {
  return LONG_DATE.format(date);
}

/**
 * Number of whole days until the next ISO-week reset (Monday 00:00).
 * Drives the `{days_until_reset}` variable in quota_reached_d1_followup.
 * Always returns at least 1 (if it's Sunday evening, "1 jour").
 */
export function daysUntilNextMonday(now: Date = new Date()): number {
  // getUTCDay: 0 = Sunday … 6 = Saturday. Days until Monday:
  const day = now.getUTCDay();
  const daysUntilMonday = day === 1 ? 7 : (8 - day) % 7 || 7;
  return Math.max(1, daysUntilMonday);
}

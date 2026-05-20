/**
 * Shared types for the notifications subsystem.
 *
 * These mirror the SQL schema in
 * `supabase/migrations/20260519_notifications_schema.sql` — keep them in
 * sync if you alter the migrations.
 */

export type NotificationCategory =
  | "onboarding"
  | "quota"
  | "trial"
  | "premium"
  | "dormant"
  | "lapsed"
  | "gift"
  | "milestone";

export type NotificationPriority = 0 | 1 | 2 | 3; // P0 (critical) → P3 (nice-to-have)

export type DispatchStatus =
  | "queued"
  | "sent"
  | "skipped"
  | "failed"
  | "delivered"
  | "opened"
  | "tapped";

export type SkipReason =
  | "quiet_hours"
  | "cooldown"
  | "quota_exceeded_daily"
  | "quota_exceeded_weekly"
  | "holdout"
  | "muted_category"
  | "muted_marketing"
  | "no_token"
  | "template_inactive"
  | "user_in_app"
  | "duplicate";

export type ApnsEnvironment = "production" | "sandbox";

export interface NotificationTemplate {
  id: string;
  category: NotificationCategory;
  priority: NotificationPriority;
  is_marketing: boolean;
  is_active: boolean;
  title_fr: string;
  body_fr: string;
  deep_link: string | null;
  variables: string[];
  fallback_template_id: string | null;
  cooldown_days: number;
  version: number;
}

export interface DeviceTokenRow {
  id: string;
  user_id: string;
  apns_token: string;
  apns_environment: ApnsEnvironment;
  push_authorization_status: string;
  disabled_at: string | null;
}

export interface PushRequest {
  userId: string;
  templateId: string;
  variables?: Record<string, string | number>;
  /** Optional override of when to send (defaults to now). */
  scheduledFor?: Date;
  /** Optional A/B variant label, defaults to "control". */
  experimentVariant?: string;
  /** Optional bucket override for dedup. Defaults to "daily". */
  dedupBucket?: "daily" | "hourly" | "event";
  /** Optional event-id appended to dedup key (use with dedupBucket=event). */
  eventId?: string;
  /** Optional explicit overrides. */
  bypassEligibilityChecks?: boolean;
}

export interface PushResult {
  status: DispatchStatus;
  dispatchId?: string;
  skipReason?: SkipReason;
  apnsStatusCode?: number;
  apnsResponseBody?: string;
}

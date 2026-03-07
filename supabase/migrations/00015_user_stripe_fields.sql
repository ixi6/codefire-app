-- Add Stripe fields to users table for pre-team subscription support.
-- Users can subscribe before creating a team; the subscription is later
-- transferred to the team when they create one.

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS stripe_customer_id text,
  ADD COLUMN IF NOT EXISTS stripe_subscription_id text;

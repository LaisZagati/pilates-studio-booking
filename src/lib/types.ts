export type Service = {
  id: string;
  slug: string;
  name: string;
  short_description: string | null;
  description: string | null;
  duration_minutes: number;
  price_cents: number;
  capacity: number;
  reformers_required: number;
  uses_mat_space: boolean;
  is_group: boolean;
  image_url: string | null;
  sort_order: number;
  active: boolean;
};

export type Settings = {
  studio_name: string;
  tagline: string | null;
  logo_url: string | null;
  hero_image_url: string | null;
  about_text: string | null;
  address: string | null;
  maps_url: string | null;
  contact_email: string | null;
  contact_phone: string | null;
  instagram_url: string | null;
  timezone: string;
  currency: string;
  min_advance_minutes: number;
  max_advance_days: number;
  cancellation_window_hours: number;
  booking_policy: string | null;
  cancellation_policy: string | null;
};

export type OpeningRule = { weekday: number; start_time: string; end_time: string; service_id: string | null };

export type Slot = { startsAt: string; endsAt: string; spotsLeft: number };

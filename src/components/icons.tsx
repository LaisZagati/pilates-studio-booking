// Small inline icon set (no icon library = less JavaScript on mobile).
type P = { className?: string };
const base = { fill: "none", stroke: "currentColor", strokeWidth: 1.6, strokeLinecap: "round" as const, strokeLinejoin: "round" as const };

export const HomeIcon = ({ className }: P) => (
  <svg viewBox="0 0 24 24" aria-hidden className={className} {...base}><path d="M3 10.5 12 3l9 7.5V20a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z" /></svg>
);
export const SparkIcon = ({ className }: P) => (
  <svg viewBox="0 0 24 24" aria-hidden className={className} {...base}><circle cx="12" cy="12" r="8" /><path d="M8 12h8M12 8v8" /></svg>
);
export const CalendarIcon = ({ className }: P) => (
  <svg viewBox="0 0 24 24" aria-hidden className={className} {...base}><rect x="3" y="4.5" width="18" height="16" rx="3" /><path d="M3 9.5h18M8 3v3M16 3v3" /></svg>
);
export const UserIcon = ({ className }: P) => (
  <svg viewBox="0 0 24 24" aria-hidden className={className} {...base}><circle cx="12" cy="8" r="4" /><path d="M4 21c1.5-4 4.5-6 8-6s6.5 2 8 6" /></svg>
);
export const ClockIcon = ({ className }: P) => (
  <svg viewBox="0 0 24 24" aria-hidden className={className} {...base}><circle cx="12" cy="12" r="9" /><path d="M12 7v5l3 2" /></svg>
);
export const PeopleIcon = ({ className }: P) => (
  <svg viewBox="0 0 24 24" aria-hidden className={className} {...base}><circle cx="9" cy="8" r="3.5" /><path d="M2.5 20c1-3.5 3.5-5.5 6.5-5.5s5.5 2 6.5 5.5" /><path d="M16 4.5a3.5 3.5 0 0 1 0 7M18 14.8c1.7.8 2.9 2.6 3.5 5.2" /></svg>
);
export const PinIcon = ({ className }: P) => (
  <svg viewBox="0 0 24 24" aria-hidden className={className} {...base}><path d="M12 21s7-6.2 7-12a7 7 0 0 0-14 0c0 5.8 7 12 7 12z" /><circle cx="12" cy="9" r="2.5" /></svg>
);
export const ChevronLeft = ({ className }: P) => (
  <svg viewBox="0 0 24 24" aria-hidden className={className} {...base}><path d="m15 18-6-6 6-6" /></svg>
);
export const ChevronRight = ({ className }: P) => (
  <svg viewBox="0 0 24 24" aria-hidden className={className} {...base}><path d="m9 18 6-6-6-6" /></svg>
);
export const CheckIcon = ({ className }: P) => (
  <svg viewBox="0 0 24 24" aria-hidden className={className} {...base}><path d="m5 12.5 4.5 4.5L19 7.5" /></svg>
);

/**
 * Shows the owner's photo when one is set (Settings / Services in /admin),
 * otherwise a calm abstract artwork in the studio palette — never a broken
 * image. The fixed aspect ratio prevents layout shift either way.
 */
export function StudioImage({
  src,
  alt,
  className = "",
  ratio = "4/5",
  priority = false,
  variant = 0,
}: {
  src?: string | null;
  alt: string;
  className?: string;
  ratio?: string;
  priority?: boolean;
  variant?: number;
}) {
  return (
    <div className={`relative overflow-hidden bg-sand ${className}`} style={{ aspectRatio: ratio }}>
      {src ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img
          src={src}
          alt={alt}
          loading={priority ? "eager" : "lazy"}
          fetchPriority={priority ? "high" : "auto"}
          decoding="async"
          className="absolute inset-0 h-full w-full object-cover"
        />
      ) : (
        <Artwork variant={variant} label={alt} />
      )}
    </div>
  );
}

function Artwork({ variant, label }: { variant: number; label: string }) {
  const palettes = [
    ["#efe6d8", "#e2d3bd", "#c9b495", "#f7f1e8"],
    ["#f2ebe0", "#dccbb2", "#b9a184", "#faf6ef"],
    ["#ece3d4", "#d8c6ab", "#a88f70", "#f6f0e6"],
  ];
  const [bg, mid, deep, light] = palettes[variant % palettes.length];
  return (
    <svg viewBox="0 0 400 500" preserveAspectRatio="xMidYMid slice" role="img" aria-label={label} className="absolute inset-0 h-full w-full">
      <rect width="400" height="500" fill={bg} />
      <circle cx={variant % 2 ? 300 : 110} cy="150" r="120" fill={light} />
      <path d="M0 360 Q200 270 400 340 V500 H0Z" fill={mid} />
      <path d="M0 420 Q220 360 400 410 V500 H0Z" fill={deep} opacity=".55" />
      {/* a gentle arc, like a body in a Pilates roll-up */}
      <path d="M90 330 C140 210 260 210 310 300" stroke={deep} strokeWidth="3" fill="none" strokeLinecap="round" opacity=".7" />
      <circle cx="318" cy="288" r="11" fill={deep} opacity=".7" />
    </svg>
  );
}

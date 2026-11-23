"use client";
import { useState } from "react";
import { share, tapFeedback, type ShareData } from "@/lib/native";

/** Shares session details (never the private manage link). */
export function ShareButton({ data, className = "" }: { data: ShareData; className?: string }) {
  const [msg, setMsg] = useState<string | null>(null);
  return (
    <div className={className}>
      <button
        type="button"
        onClick={async () => {
          await tapFeedback();
          const r = await share(data);
          setMsg(r === "copied" ? "Copied to clipboard" : null);
        }}
        className="w-full rounded-full border border-taupe px-6 py-4"
      >
        Share
      </button>
      {msg && <p role="status" className="mt-2 text-center text-sm text-muted">{msg}</p>}
    </div>
  );
}

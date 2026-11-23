import { androidAssetLinks } from "@/lib/app-links";

// Digital Asset Links: proves the Android app (TWA) belongs to this site,
// so it opens full-screen without a browser bar. Values come from env vars.
export function GET() {
  return Response.json(androidAssetLinks(), { headers: { "Cache-Control": "public, max-age=3600" } });
}

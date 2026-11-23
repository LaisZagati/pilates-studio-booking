import { appleAppSiteAssociation } from "@/lib/app-links";

// Universal Links for the iOS app. Must be served as JSON without a redirect.
export function GET() {
  return Response.json(appleAppSiteAssociation(), { headers: { "Cache-Control": "public, max-age=3600" } });
}

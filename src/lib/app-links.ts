import "server-only";

/** Paths that open inside the installed apps (Universal Links / App Links). */
export const APP_LINK_PATHS = ["/", "/book*", "/manage*", "/account*", "/services*", "/login*", "/signup*"];

export function appleAppSiteAssociation() {
  const team = process.env.APPLE_TEAM_ID;
  const bundle = process.env.IOS_BUNDLE_ID;
  const appIDs = team && bundle ? [`${team}.${bundle}`] : [];
  return {
    applinks: {
      details: appIDs.length
        ? [{
            appIDs,
            // Order matters: exclusions first. The owner dashboard stays in the browser.
            components: [
              { "/": "/admin*", exclude: true } as Record<string, string | boolean>,
              ...APP_LINK_PATHS.map((p) => ({ "/": p }) as Record<string, string | boolean>),
            ],
          }]
        : [],
    },
    webcredentials: { apps: appIDs },
  };
}

export function androidAssetLinks() {
  const pkg = process.env.ANDROID_PACKAGE_NAME;
  const prints = (process.env.ANDROID_SHA256_CERT_FINGERPRINTS ?? "").split(",").map((s) => s.trim()).filter(Boolean);
  if (!pkg || prints.length === 0) return [];
  return [
    {
      relation: ["delegate_permission/common.handle_all_urls", "delegate_permission/common.get_login_creds"],
      target: { namespace: "android_app", package_name: pkg, sha256_cert_fingerprints: prints },
    },
  ];
}

import { requireAdmin } from "@/lib/auth";

export const dynamic = "force-dynamic";
export const metadata = { robots: { index: false, follow: false } };

// Every page inside /admin (except /admin/login) is re-checked on the server.
export default async function AdminLayout({ children }: { children: React.ReactNode }) {
  await requireAdmin();
  return <>{children}</>;
}

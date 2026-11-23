import { AuthForm } from "@/components/auth/AuthForm";
import { signIn } from "@/app/auth/actions";

export const metadata = { title: "Studio admin", robots: { index: false, follow: false } };

export default async function AdminLoginPage({ searchParams }: { searchParams: Promise<{ next?: string }> }) {
  const { next } = await searchParams;
  return <AuthForm mode="signin" action={signIn} next={next ?? "/admin"} title="Studio admin" showSignupLink={false} />;
}

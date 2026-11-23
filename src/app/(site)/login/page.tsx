import { AuthForm } from "@/components/auth/AuthForm";
import { signIn } from "@/app/auth/actions";

export const metadata = { title: "Sign in" };

export default async function LoginPage({ searchParams }: { searchParams: Promise<{ next?: string }> }) {
  const { next } = await searchParams;
  return <AuthForm mode="signin" action={signIn} next={next ?? "/account"} title="Welcome back" />;
}

import { AuthForm } from "@/components/auth/AuthForm";
import { signUp } from "@/app/auth/actions";

export const metadata = { title: "Create account" };

export default function SignupPage() {
  return <AuthForm mode="signup" action={signUp} title="Create your account" />;
}

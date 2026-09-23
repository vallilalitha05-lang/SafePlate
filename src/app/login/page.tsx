import { BriefcaseBusiness } from "lucide-react";
import { LoginForm } from "@/components/auth/login-form";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";

export default function LoginPage() { return <main className="flex min-h-screen items-center justify-center bg-slate-50 px-4"><Card className="w-full max-w-md"><CardHeader><div className="mb-4 flex items-center gap-2 text-emerald-700"><BriefcaseBusiness className="h-6 w-6" /><span className="font-semibold">SafePlate</span></div><CardTitle className="text-2xl">Welcome back</CardTitle><CardDescription>Sign in to continue to your workspace.</CardDescription></CardHeader><CardContent><LoginForm /></CardContent></Card></main>; }

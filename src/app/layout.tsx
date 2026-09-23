import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = { title: "SafePlate | F&B inspections", description: "Role-aware food and beverage inspection management." };

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="en"><body>{children}</body></html>;
}

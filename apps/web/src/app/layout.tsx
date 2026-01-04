import './globals.css';
import type { Metadata } from 'next';

const appTitle =
  process.env.NEXT_PUBLIC_APP_TITLE ?? 'Customer Support Workspace';

export const metadata: Metadata = {
  title: appTitle,
  description: 'White-label customer support workspace.'
};

export default function RootLayout({
  children
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}

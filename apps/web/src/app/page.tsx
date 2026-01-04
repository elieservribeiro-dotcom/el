export default function HomePage() {
  const appTitle =
    process.env.NEXT_PUBLIC_APP_TITLE ?? 'Customer Support Workspace';

  return (
    <main className="min-h-screen bg-slate-50 px-8 py-16 text-slate-900">
      <section className="mx-auto max-w-3xl space-y-6">
        <h1 className="text-3xl font-semibold">{appTitle}</h1>
        <p className="text-lg text-slate-600">
          Tenant-scoped support workspace with AI-assisted workflows.
        </p>
        <div className="rounded-xl border border-slate-200 bg-white p-6 shadow-sm">
          <h2 className="text-lg font-medium">Next steps</h2>
          <ul className="mt-3 list-disc space-y-2 pl-6 text-slate-600">
            <li>Connect a tenant-specific brand profile and theme.</li>
            <li>Configure AI prompts and knowledge bases.</li>
            <li>Invite supervisors and agents.</li>
          </ul>
        </div>
      </section>
    </main>
  );
}

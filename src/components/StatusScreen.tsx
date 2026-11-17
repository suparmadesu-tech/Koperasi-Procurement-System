import type { ReactNode } from 'react';

type Props = {
  title: string;
  message?: string;
  busy?: boolean;
  alert?: boolean;
  children?: ReactNode;
};

export default function StatusScreen({ title, message, busy, alert, children }: Props) {
  return (
    <main
      className="mx-auto flex min-h-screen max-w-md flex-col justify-center gap-4 px-5 py-10"
      aria-busy={busy ? true : undefined}
    >
      <h1 className="text-xl font-semibold">{title}</h1>
      {message ? (
        <p role={alert ? 'alert' : 'status'} className="text-base">
          {message}
        </p>
      ) : null}
      {children ? <div className="flex flex-col gap-3">{children}</div> : null}
    </main>
  );
}

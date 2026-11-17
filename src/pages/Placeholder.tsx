export default function Placeholder({ title, note }: { title: string; note: string }) {
  return (
    <section className="flex flex-col gap-3">
      <h1 className="text-xl font-semibold">{title}</h1>
      <p className="rounded-md bg-white px-4 py-3 text-base ring-1 ring-black/10">{note}</p>
    </section>
  );
}

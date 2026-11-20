// "1.5" menjadi "1,5"; ribuan dipisah titik.
export function formatQuantity(q: string): string {
  const [int, frac] = q.split('.')
  const grouped = (int ?? '0').replace(/\B(?=(\d{3})+(?!\d))/g, '.')
  return frac ? `${grouped},${frac}` : grouped
}

// Zona waktu tampilan Asia/Jakarta (FR-039).
export function formatTimeJakarta(iso: string): string {
  return new Intl.DateTimeFormat('id-ID', {
    hour: '2-digit',
    minute: '2-digit',
    timeZone: 'Asia/Jakarta',
  }).format(new Date(iso))
}

export const OTHER_DEVICES_REMINDER =
  'Pastikan perangkat lain yang Anda pakai sudah menyinkronkan perubahannya. Aplikasi hanya dapat memeriksa perangkat ini.'

export interface StartPlan {
  allowed: boolean
  message: string
}

// FR-045: antrean perangkat pemulai harus kosong. Operasi yang ditolak server tidak menghalangi (SYNC-003).
export function planStart(blocking: number | null): StartPlan {
  if (blocking === null) {
    return {
      allowed: false,
      message:
        'Aplikasi tidak dapat memeriksa antrean perubahan di perangkat ini, jadi sesi belum dapat dimulai. Muat ulang halaman lalu coba lagi.',
    }
  }
  if (blocking > 0) {
    return {
      allowed: false,
      message: `Ada ${blocking} perubahan di perangkat ini yang belum tersimpan di server. Sesi tidak dapat dimulai sebelum perubahan itu tersimpan atau dibuang.`,
    }
  }
  return { allowed: true, message: OTHER_DEVICES_REMINDER }
}

export interface EndPlan {
  needsConfirm: boolean
  message: string
}

// FR-028, SYNC-012: perubahan yang belum tersimpan tidak ikut perhitungan sisa, total aktual, dan riwayat.
export function planEnd(pending: number | null): EndPlan {
  if (pending === null) {
    return {
      needsConfirm: true,
      message: `Aplikasi tidak dapat memeriksa perubahan yang belum tersimpan di server pada perangkat ini. Jika sesi tetap diakhiri, perubahan yang belum tersimpan tidak ikut dihitung. ${OTHER_DEVICES_REMINDER}`,
    }
  }
  if (pending > 0) {
    return {
      needsConfirm: true,
      message: `Ada ${pending} perubahan di perangkat ini yang belum tersimpan di server. Jika sesi tetap diakhiri, perubahan itu tidak ikut dihitung dalam sisa, total aktual, dan riwayat, lalu ditolak server dan ditandai gagal. ${OTHER_DEVICES_REMINDER}`,
    }
  }
  return { needsConfirm: false, message: OTHER_DEVICES_REMINDER }
}

async function safeCount(count: () => Promise<number>): Promise<number | null> {
  try {
    return await count()
  } catch {
    return null
  }
}

export async function checkStart(count: () => Promise<number>): Promise<StartPlan> {
  return planStart(await safeCount(count))
}

export async function checkEnd(count: () => Promise<number>): Promise<EndPlan> {
  return planEnd(await safeCount(count))
}

import { describe, expect, it } from 'vitest'
import { CANCEL_DIALOG_MESSAGE, endDialogMessage, startDialogMessage } from './flowText'
import { OTHER_DEVICES_REMINDER } from './sessionGuards'

describe('startDialogMessage', () => {
  it('menyebut jumlah barang, estimasi dalam Rupiah, barang tanpa harga, dan pengingat', () => {
    const m = startDialogMessage({ itemCount: 3, total: '15000', unpricedCount: 1 }, false, OTHER_DEVICES_REMINDER)
    expect(m).toContain('3 barang')
    expect(m).toContain('Rp 15.000')
    expect(m).toContain('Belum mencakup 1 barang tanpa harga')
    expect(m).toContain(OTHER_DEVICES_REMINDER)
  })

  it('tidak menyiratkan perangkat lain sudah sinkron (SYNC-013)', () => {
    const m = startDialogMessage({ itemCount: 2, total: '0', unpricedCount: 2 }, false, OTHER_DEVICES_REMINDER)
    expect(m).not.toMatch(/perangkat lain (sudah|telah) (tersinkron|tersimpan|sinkron)/i)
  })

  it('daftar kosong boleh dimulai tanpa angka estimasi (FR-022)', () => {
    const m = startDialogMessage({ itemCount: 0, total: '0', unpricedCount: 0 }, false, '')
    expect(m).toContain('tanpa barang')
    expect(m).not.toContain('Rp')
  })

  it('katalog belum termuat menambah peringatan, barang berharga semua tidak menambah label tanpa harga', () => {
    expect(startDialogMessage({ itemCount: 1, total: '1000', unpricedCount: 0 }, true, '')).toContain('Katalog belum termuat')
    expect(startDialogMessage({ itemCount: 1, total: '1000', unpricedCount: 0 }, false, '')).not.toContain('tanpa harga')
  })
})

describe('endDialogMessage', () => {
  it('pratinjau barang yang kembali, termasuk nol', () => {
    expect(endDialogMessage(2, '')).toContain('2 barang memiliki sisa')
    expect(endDialogMessage(0, '')).toContain('Tidak ada barang yang perlu dikembalikan')
  })

  it('membawa catatan pengingat dan menyebut hitungan dari perangkat ini', () => {
    const m = endDialogMessage(1, OTHER_DEVICES_REMINDER)
    expect(m).toContain(OTHER_DEVICES_REMINDER)
    expect(m).toContain('dari data di perangkat ini')
  })
})

describe('CANCEL_DIALOG_MESSAGE', () => {
  it('memuat konsekuensi FR-029', () => {
    expect(CANCEL_DIALOG_MESSAGE).toContain('dikembalikan ke daftar kebutuhan')
    expect(CANCEL_DIALOG_MESSAGE).toContain('tidak masuk riwayat')
    expect(CANCEL_DIALOG_MESSAGE).toContain('tidak dapat diurungkan')
  })
})

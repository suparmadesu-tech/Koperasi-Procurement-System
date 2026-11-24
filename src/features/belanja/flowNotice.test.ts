import { describe, expect, it } from 'vitest'
import { clearFlowNotice, flowNoticeFor, getFlowNotice, setFlowNotice, subscribeFlowNotice } from './flowNotice'

describe('flowNoticeFor', () => {
  it('penolakan menjadi pesan galat apa adanya', () => {
    expect(flowNoticeFor('end', { ok: false, message: 'Sesi ini sudah selesai.' })).toEqual({
      tone: 'error',
      text: 'Sesi ini sudah selesai.',
    })
  })

  it('mulai: menyebut jumlah barang bila server mengirimnya', () => {
    expect(flowNoticeFor('start', { ok: true, data: { item_count: 3 } }).text).toBe(
      'Sesi belanja dimulai di server dengan 3 barang.',
    )
    expect(flowNoticeFor('start', { ok: true, data: {} }).text).toBe('Sesi belanja dimulai di server.')
  })

  it('akhiri: returned_items sebagai angka atau larik, selain itu teks umum', () => {
    expect(flowNoticeFor('end', { ok: true, data: { returned_items: 2 } }).text).toContain('2 barang dikembalikan')
    expect(flowNoticeFor('end', { ok: true, data: { returned_items: [{}, {}, {}] } }).text).toContain('3 barang dikembalikan')
    expect(flowNoticeFor('end', { ok: true, data: { returned_items: 'x' } }).text).toBe(
      'Sesi belanja diakhiri di server.',
    )
  })

  it('batalkan: semua barang kembali ke daftar', () => {
    const n = flowNoticeFor('cancel', { ok: true, data: {} })
    expect(n.tone).toBe('info')
    expect(n.text).toContain('dibatalkan di server')
  })
})

describe('penyimpanan pesan', () => {
  it('set, baca, beri tahu pelanggan, dan hapus', () => {
    clearFlowNotice()
    let hits = 0
    const off = subscribeFlowNotice(() => {
      hits += 1
    })
    setFlowNotice({ tone: 'info', text: 'a' })
    expect(getFlowNotice()).toEqual({ tone: 'info', text: 'a' })
    clearFlowNotice()
    expect(getFlowNotice()).toBeNull()
    expect(hits).toBe(2)
    off()
    setFlowNotice({ tone: 'error', text: 'b' })
    expect(hits).toBe(2)
    clearFlowNotice()
  })
})

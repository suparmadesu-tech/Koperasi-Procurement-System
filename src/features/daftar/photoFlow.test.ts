import { describe, expect, it } from 'vitest'
import type { CompressedPhoto } from '../katalog/photoCompress'
import type { Result } from '../katalog/types'
import { preparePhoto, uploadPrepared, type PhotoFlowDeps } from './photoFlow'

const blob = new Blob(['x'])
const file = blob as unknown as File

function makeDeps(compress: Result<CompressedPhoto>, upload: Result<string>) {
  const counts = { compress: 0, upload: 0 }
  const deps: PhotoFlowDeps = {
    compress: async () => {
      counts.compress += 1
      return compress
    },
    upload: async () => {
      counts.upload += 1
      return upload
    },
  }
  return { deps, counts }
}

const compressed: Result<CompressedPhoto> = { ok: true, data: { blob, mime: 'image/webp' } }
const uploaded: Result<string> = { ok: true, data: 'w/abc.webp' }
const err = (message: string) => ({ ok: false as const, error: { code: 'E', message } })

describe('preparePhoto', () => {
  it('tanpa berkas tidak memanggil apa pun', async () => {
    const { deps, counts } = makeDeps(compressed, uploaded)
    expect(await preparePhoto(deps, 'w', null)).toEqual({ kind: 'none' })
    expect(counts).toEqual({ compress: 0, upload: 0 })
  })

  it('gagal kompres berarti tidak valid dan tidak mengunggah', async () => {
    const { deps, counts } = makeDeps(err('terlalu besar'), uploaded)
    expect(await preparePhoto(deps, 'w', file)).toEqual({ kind: 'invalid', message: 'terlalu besar' })
    expect(counts.upload).toBe(0)
  })

  it('gagal unggah mempertahankan hasil kompres untuk dicoba lagi', async () => {
    const { deps } = makeDeps(compressed, err('Tidak ada koneksi internet.'))
    expect(await preparePhoto(deps, 'w', file)).toEqual({
      kind: 'upload_failed',
      blob,
      mime: 'image/webp',
      message: 'Tidak ada koneksi internet.',
    })
  })

  it('sukses mengembalikan path baru', async () => {
    const { deps } = makeDeps(compressed, uploaded)
    expect(await preparePhoto(deps, 'w', file)).toEqual({ kind: 'ready', path: 'w/abc.webp', blob, mime: 'image/webp' })
  })
})

describe('uploadPrepared', () => {
  it('mengunggah ulang blob tersimpan tanpa kompres lagi', async () => {
    const { deps, counts } = makeDeps(compressed, uploaded)
    const r = await uploadPrepared(deps, 'w', blob, 'image/webp')
    expect(r.kind).toBe('ready')
    expect(counts).toEqual({ compress: 0, upload: 1 })
  })
})

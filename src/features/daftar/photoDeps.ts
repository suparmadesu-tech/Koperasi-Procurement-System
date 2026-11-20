import { compressImage } from '../katalog/photoCompress'
import { uploadProductPhoto } from '../katalog/photoUpload'
import type { PhotoFlowDeps } from './photoFlow'

export const photoDeps: PhotoFlowDeps = { compress: compressImage, upload: uploadProductPhoto }

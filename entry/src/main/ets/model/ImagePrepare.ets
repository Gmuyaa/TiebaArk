
export const IMAGE_SOURCE_BYTES: number = 32 * 1024 * 1024;
export const IMAGE_UPLOAD_BYTES: number = 8 * 1024 * 1024;
export const IMAGE_SOURCE_PIXELS: number = 32 * 1024 * 1024;
export const IMAGE_UPLOAD_EDGE: number = 2048;
export class PreparedImageSize { width: number = 0; height: number = 0; }
export function prepareImageSize(width: number, height: number): PreparedImageSize | undefined {
  if (!Number.isSafeInteger(width) || !Number.isSafeInteger(height) || width <= 0 || height <= 0 ||
    width * height > IMAGE_SOURCE_PIXELS) { return undefined; }
  const scale: number = Math.min(1, IMAGE_UPLOAD_EDGE / Math.max(width, height));
  const result: PreparedImageSize = new PreparedImageSize();
  result.width = Math.max(1, Math.floor(width * scale)); result.height = Math.max(1, Math.floor(height * scale)); return result;
}

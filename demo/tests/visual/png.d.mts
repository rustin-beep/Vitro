// png.mjs 的类型面（零依赖运行时实现 + 手写声明；tests tsconfig 会做发射检查）。
export interface RGBAImage {
  width: number;
  height: number;
  data: Buffer;
}

export interface DiffResult {
  changed: number;
  total: number;
  ratio: number;
  bbox: { x: number; y: number; w: number; h: number } | null;
}

export function decodePNG(buf: Buffer): RGBAImage;
export function encodePNG(img: RGBAImage): Buffer;
export function diffRGBA(a: RGBAImage, b: RGBAImage): DiffResult;
export function diffImage(a: RGBAImage, b: RGBAImage): RGBAImage;
export function maskRect(img: RGBAImage, rect: { x: number; y: number; w: number; h: number }, color?: number): RGBAImage;

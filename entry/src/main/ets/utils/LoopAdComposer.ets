import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'MyDomaiAd';

interface AdPackOption {
  format: string;
  quality: number;
}

/**
 * 闭环广告图片：选图后立刻解码并落到沙箱 JPEG，保证地图可读。
 */
export class LoopAdComposer {
  static ensureAdDir(context: common.UIAbilityContext): string {
    const dir = `${context.filesDir}/loop_ads`;
    try {
      fileIo.accessSync(dir);
    } catch (_e) {
      fileIo.mkdirSync(dir);
    }
    return dir;
  }

  static toDisplayUri(pathOrUri: string): string {
    if (pathOrUri.length === 0) {
      return '';
    }
    if (pathOrUri.startsWith('file://') || pathOrUri.startsWith('datashare://') ||
      pathOrUri.startsWith('http://') || pathOrUri.startsWith('https://')) {
      return pathOrUri;
    }
    if (pathOrUri.startsWith('/')) {
      return `file://${pathOrUri}`;
    }
    return pathOrUri;
  }

  /** 字节拷贝（可能对部分相册 URI 失败） */
  static persistPhotoCopy(context: common.UIAbilityContext, photoUri: string): string | null {
    try {
      const dir = LoopAdComposer.ensureAdDir(context);
      const destPath = `${dir}/ad_${Date.now()}.jpg`;
      const srcFile = fileIo.openSync(photoUri, fileIo.OpenMode.READ_ONLY);
      const destFile = fileIo.openSync(
        destPath,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC
      );
      const stat = fileIo.statSync(srcFile.fd);
      const buffer = new ArrayBuffer(stat.size);
      fileIo.readSync(srcFile.fd, buffer);
      fileIo.writeSync(destFile.fd, buffer);
      fileIo.closeSync(srcFile);
      fileIo.closeSync(destFile);
      hilog.info(LOG_DOMAIN, LOG_TAG, '[Ad] copy persisted bytes=%{public}d', stat.size);
      return destPath;
    } catch (error) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, '[Ad] copy persist failed %{public}s', JSON.stringify(error));
      return null;
    }
  }

  /** 解码相册图再打包成 JPEG 写入沙箱（更稳妥） */
  static async persistPhotoByDecode(context: common.UIAbilityContext, photoUri: string): Promise<string | null> {
    try {
      const source = image.createImageSource(photoUri);
      const pixelMap = await source.createPixelMap();
      source.release();
      const packer = image.createImagePacker();
      const packOpts: AdPackOption = { format: 'image/jpeg', quality: 92 };
      const packed = await packer.packing(pixelMap, packOpts);
      packer.release();
      const dir = LoopAdComposer.ensureAdDir(context);
      const destPath = `${dir}/ad_${Date.now()}.jpg`;
      const destFile = fileIo.openSync(
        destPath,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC
      );
      fileIo.writeSync(destFile.fd, packed);
      fileIo.closeSync(destFile);
      hilog.info(LOG_DOMAIN, LOG_TAG, '[Ad] decode-pack persisted path=%{public}s', destPath);
      return destPath;
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, '[Ad] decode-pack failed %{public}s', JSON.stringify(error));
      return null;
    }
  }

  static async persistPhoto(context: common.UIAbilityContext, photoUri: string): Promise<string | null> {
    if (photoUri.length === 0) {
      return null;
    }
    if (photoUri.indexOf('/loop_ads/') >= 0 && photoUri.indexOf(context.filesDir) >= 0) {
      return photoUri;
    }
    const byDecode = await LoopAdComposer.persistPhotoByDecode(context, photoUri);
    if (byDecode !== null) {
      return byDecode;
    }
    return LoopAdComposer.persistPhotoCopy(context, photoUri);
  }

  static async loadPhotoPixelMap(pathOrUri: string): Promise<image.PixelMap | null> {
    if (pathOrUri.length === 0) {
      return null;
    }
    const candidates: Array<string> = [pathOrUri];
    const display = LoopAdComposer.toDisplayUri(pathOrUri);
    if (display !== pathOrUri) {
      candidates.push(display);
    }
    for (let i = 0; i < candidates.length; i++) {
      const src = candidates[i];
      try {
        const source = image.createImageSource(src);
        const pixelMap = await source.createPixelMap();
        source.release();
        hilog.info(LOG_DOMAIN, LOG_TAG, '[Ad] photo pixelmap ok src=%{public}s', src);
        return pixelMap;
      } catch (error) {
        hilog.warn(LOG_DOMAIN, LOG_TAG, '[Ad] load fail src=%{public}s err=%{public}s',
          src, JSON.stringify(error));
      }
    }
    return null;
  }
}

import { common } from '@kit.AbilityKit';
import { picker, fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'MyDomaiLoop';

export class TerritoryFileIO {
  static async exportText(context: common.UIAbilityContext, content: string, fileName: string): Promise<boolean> {
    if (content.length === 0) {
      // #region agent log
      hilog.warn(LOG_DOMAIN, LOG_TAG, '[X] export skipped empty content');
      // #endregion
      return false;
    }
    const documentPicker = new picker.DocumentViewPicker(context);
    const saveOptions = new picker.DocumentSaveOptions();
    saveOptions.newFileNames = [fileName];
    saveOptions.fileSuffixChoices = ['MyDomai 领地数据|json'];
    const uris = await documentPicker.save(saveOptions);
    if (uris === null || uris.length === 0) {
      return false;
    }
    const written = TerritoryFileIO.writeUriText(uris[0], content);
    // #region agent log
    hilog.info(LOG_DOMAIN, LOG_TAG, '[X] export write uri=%{public}s bytes=%{public}d content=%{public}d',
      uris[0], written, content.length);
    // #endregion
    return written > 0;
  }

  static async importText(context: common.UIAbilityContext): Promise<string | null> {
    const documentPicker = new picker.DocumentViewPicker(context);
    const selectOptions = new picker.DocumentSelectOptions();
    selectOptions.maxSelectNumber = 1;
    const uris = await documentPicker.select(selectOptions);
    if (uris === null || uris.length === 0) {
      return null;
    }
    return TerritoryFileIO.readUriText(uris[0]);
  }

  private static readUriText(uri: string): string {
    const file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
    const stat = fileIo.statSync(file.fd);
    const buffer = new ArrayBuffer(stat.size);
    fileIo.readSync(file.fd, buffer);
    fileIo.closeSync(file);
    const decoder = util.TextDecoder.create('utf-8');
    return decoder.decodeToString(new Uint8Array(buffer));
  }

  private static writeUriText(uri: string, content: string): number {
    const file = fileIo.openSync(uri, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    const written = fileIo.writeSync(file.fd, content);
    fileIo.closeSync(file);
    return written;
  }
}

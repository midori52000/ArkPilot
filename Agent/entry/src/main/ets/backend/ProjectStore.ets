import fileIo from '@ohos.file.fs';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ProjectRecord } from './ConsoleModels';

const STORE_DOMAIN = 0x0ff3;
const STORE_TAG = 'ProjectStore';
const STORE_FILE_NAME = 'projects.json';

function storeFilePath(): string {
  const codexHome: string = (AppStorage.get('codexHome') as string) ?? '';
  if (codexHome.trim().length > 0) {
    return `${codexHome}/${STORE_FILE_NAME}`;
  }
  return STORE_FILE_NAME;
}

function ensureParentDirectory(path: string): void {
  const slashIndex: number = path.lastIndexOf('/');
  if (slashIndex <= 0) {
    return;
  }
  const parentPath: string = path.substring(0, slashIndex);
  try {
    fileIo.mkdirSync(parentPath, true);
  } catch (err) {
    hilog.error(STORE_DOMAIN, STORE_TAG, 'ensureParentDirectory failed: %{public}s', `${err}`);
  }
}

function safeParseSnapshot(rawText: string): ProjectRecord[] {
  try {
    const parsed: Object = JSON.parse(rawText) as Object;
    const record: Record<string, Object> = parsed as Record<string, Object>;
    const itemsRaw: Object | undefined = record['projects'];
    if (Array.isArray(itemsRaw)) {
      return itemsRaw.map((itemRaw: Object) => {
        const itemRecord: Record<string, Object> = itemRaw as Record<string, Object>;
        const id: string = typeof itemRecord['id'] === 'string' ? (itemRecord['id'] as string) : '';
        const name: string = typeof itemRecord['name'] === 'string' ? (itemRecord['name'] as string) : '';
        const path: string = typeof itemRecord['path'] === 'string' ? (itemRecord['path'] as string) : '';
        const expanded: boolean = typeof itemRecord['expanded'] === 'boolean' ? (itemRecord['expanded'] as boolean) : true;
        if (id.length > 0 && name.length > 0) {
          return new ProjectRecord(id, name, path, expanded);
        }
        return null;
      }).filter((item: ProjectRecord | null) => item !== null) as ProjectRecord[];
    }
    return [];
  } catch (_err) {
    return [];
  }
}

export class ProjectStore {
  load(): ProjectRecord[] {
    const path: string = storeFilePath();
    try {
      fileIo.statSync(path);
    } catch (_err) {
      return [];
    }
    try {
      const rawText: string = fileIo.readTextSync(path);
      return safeParseSnapshot(rawText);
    } catch (err) {
      hilog.error(STORE_DOMAIN, STORE_TAG, 'load failed: %{public}s', `${err}`);
      return [];
    }
  }

  save(projects: ProjectRecord[]): void {
    const path: string = storeFilePath();
    ensureParentDirectory(path);
    const payload: string = JSON.stringify({ projects }, null, 2);
    try {
      const file = fileIo.openSync(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(file.fd, payload);
      fileIo.closeSync(file);
    } catch (err) {
      hilog.error(STORE_DOMAIN, STORE_TAG, 'save failed: %{public}s', `${err}`);
    }
  }
}

export const projectStore = new ProjectStore();

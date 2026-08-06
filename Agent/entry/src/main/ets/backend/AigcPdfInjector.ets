/**
 * AIGC 隐式标识 PDF 写入器 —— 向 Document Information Dictionary 追加 /AIGC({json})。
 *
 * 策略：纯 append 增量更新段，不重写原字节。
 * 1. 校验适用性：%PDF 头、无 /Encrypt、非 linearized、尾部可解析 startxref+%%EOF
 * 2. 解析 trailer：/Size、/Root、/Info、startxref
 * 3. 有 Info → 重定义该对象（追加 /AIGC）；无 → 新建对象 size，trailer 加 /Info
 * 4. append 新对象 + xref + trailer（/Prev <oldStartxref>）+ startxref + %%EOF
 *
 * 依据：TC260《文本文件》指南 6.3，/AIGC({"Label":"1",...}) 写入 Document Information Dictionary。
 */
import fileIo from '@ohos.file.fs';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';

const PDF_DOMAIN: number = 0x0ff8;
const PDF_TAG: string = 'AigcPdfInjector';
const TAIL_SCAN_BYTES: number = 64 * 1024;
const MAX_PDF_BYTES: number = 200 * 1024 * 1024;

/** PDF 字符串字面量转义：\ ( ) 控制符 非 ASCII → \ooo 八进制（字节级）。 */
export function escapePdfLiteralString(jsonText: string): string {
  const encoder: util.TextEncoder = new util.TextEncoder();
  const bytes: Uint8Array = encoder.encodeInto(jsonText);
  const parts: string[] = [];
  for (let i: number = 0; i < bytes.length; i += 1) {
    const b: number = bytes[i];
    if (b === 0x5c) { // backslash
      parts.push('\\\\');
    } else if (b === 0x28) { // (
      parts.push('\\(');
    } else if (b === 0x29) { // )
      parts.push('\\)');
    } else if (b === 0x0a) { // LF
      parts.push('\\n');
    } else if (b === 0x0d) { // CR
      parts.push('\\r');
    } else if (b === 0x09) { // TAB
      parts.push('\\t');
    } else if (b < 0x20 || b >= 0x80) {
      parts.push(`\\${b.toString(8).padStart(3, '0')}`);
    } else {
      parts.push(String.fromCharCode(b));
    }
  }
  return parts.join('');
}

/** 读取文件尾部字节并解码为字符串。 */
function readFileTailText(absPath: string): string {
  const stat = fileIo.statSync(absPath);
  const readLen: number = Math.min(stat.size, TAIL_SCAN_BYTES);
  const offset: number = stat.size - readLen;
  const file = fileIo.openSync(absPath, fileIo.OpenMode.READ_ONLY);
  try {
    const buffer = new ArrayBuffer(readLen);
    fileIo.readSync(file.fd, buffer, { offset, length: readLen });
    const decoder: util.TextDecoder = new util.TextDecoder('utf-8');
    return decoder.decode(new Uint8Array(buffer, 0, readLen));
  } finally {
    fileIo.closeSync(file);
  }
}

interface PdfTrailerInfo {
  oldStartxref: number;
  size: number;
  rootRef: number;
  infoRef: number;
  infoDictBody: string; // 原 Info 对象字典内容（无外层 << >>），无则空串
}

/** 解析 PDF trailer；不适用返回 null。 */
function parsePdfTrailer(absPath: string, tailText: string): PdfTrailerInfo | null {
  // 找最后一个 startxref
  const sxIndex: number = tailText.lastIndexOf('startxref');
  if (sxIndex < 0) {
    return null;
  }
  const afterSx: string = tailText.substring(sxIndex);
  const sxMatch = afterSx.match(/startxref\s+(\d+)\s*%%EOF/);
  if (sxMatch === null || sxMatch.length < 2) {
    return null;
  }
  const oldStartxref: number = parseInt(sxMatch[1], 10);

  // 找 trailer 字典
  const trailerIndex: number = tailText.lastIndexOf('trailer');
  if (trailerIndex < 0) {
    return null;
  }
  const trailerSection: string = tailText.substring(trailerIndex);
  const dictStart: number = trailerSection.indexOf('<<');
  const dictEnd: number = trailerSection.lastIndexOf('>>');
  if (dictStart < 0 || dictEnd <= dictStart) {
    return null;
  }
  const dict: string = trailerSection.substring(dictStart + 2, dictEnd);

  const sizeMatch = dict.match(/\/Size\s+(\d+)/);
  const rootMatch = dict.match(/\/Root\s+(\d+)\s+0\s+R/);
  const infoMatch = dict.match(/\/Info\s+(\d+)\s+0\s+R/);
  if (rootMatch === null || rootMatch.length < 2) {
    return null; // 必须有 /Root
  }
  const size: number = sizeMatch !== null && sizeMatch.length > 1 ? parseInt(sizeMatch[1], 10) : 0;
  const rootRef: number = parseInt(rootMatch[1], 10);
  const infoRef: number = infoMatch !== null && infoMatch.length > 1 ? parseInt(infoMatch[1], 10) : -1;

  // 尝试读取原 Info 对象字典
  let infoDictBody: string = '';
  if (infoRef > 0) {
    infoDictBody = readInfoObjectDict(absPath, infoRef);
  }
  const result: PdfTrailerInfo = {
    oldStartxref: oldStartxref,
    size: size,
    rootRef: rootRef,
    infoRef: infoRef,
    infoDictBody: infoDictBody
  };
  return result;
}

/** 定位并读取指定对象号的字典体（无 << >> 包裹）。 */
function readInfoObjectDict(absPath: string, objNum: number): string {
  try {
    const stat = fileIo.statSync(absPath);
    const file = fileIo.openSync(absPath, fileIo.OpenMode.READ_ONLY);
    try {
      // 扫描对象：找 "<objNum> 0 obj" 到 "endobj"
      const chunkSize: number = 64 * 1024;
      let offset: number = 0;
      const marker: string = `${objNum.toString()} 0 obj`;
      while (offset < stat.size) {
        const readLength: number = Math.min(chunkSize, stat.size - offset);
        const buffer = new ArrayBuffer(readLength);
        const bytesRead: number = fileIo.readSync(file.fd, buffer, { offset, length: readLength });
        if (bytesRead <= 0) {
          break;
        }
        const chunk: string = new util.TextDecoder('utf-8').decode(new Uint8Array(buffer, 0, bytesRead));
        const idx: number = chunk.indexOf(marker);
        if (idx >= 0) {
          const afterObj: string = chunk.substring(idx + marker.length);
          const dictStart: number = afterObj.indexOf('<<');
          const dictEnd: number = afterObj.lastIndexOf('>>');
          if (dictStart >= 0 && dictEnd > dictStart) {
            return afterObj.substring(dictStart + 2, dictEnd);
          }
          return '';
        }
        // 避免漏跨块：重叠 8 字节
        offset += (bytesRead > 8 ? bytesRead - 8 : bytesRead);
      }
      return '';
    } finally {
      fileIo.closeSync(file);
    }
  } catch (_err) {
    return '';
  }
}

/** 追加 PDF 增量更新段。返回是否成功。 */
export function injectPdfIncremental(absPath: string, targetPath: string, payloadJson: string): boolean {
  try {
    const stat = fileIo.statSync(absPath);
    if (stat.size > MAX_PDF_BYTES) {
      return false;
    }
    const head: string = readFileHead(absPath);
    if (!head.startsWith('%PDF-')) {
      return false;
    }
    const fullTail: string = readFileTailText(absPath);
    // 加密 / 线性化检查
    if (fullTail.indexOf('/Encrypt') >= 0) {
      return false;
    }
    const headBlock: string = readFileHead(absPath);
    if (headBlock.indexOf('/Linearized') >= 0) {
      return false;
    }

    const trailer: PdfTrailerInfo | null = parsePdfTrailer(absPath, fullTail);
    if (trailer === null) {
      return false;
    }

    const escaped: string = escapePdfLiteralString(payloadJson);
    let newSize: number = trailer.size;
    let infoRefUsed: number = trailer.infoRef;
    let objNum: number = -1;

    // 构建对象段（先确定对象号）
    let objectSegment: string = '';
    if (trailer.infoRef > 0) {
      // 重定义 Info 对象：保留原字段 + /AIGC
      objNum = trailer.infoRef;
      let dictBody: string = trailer.infoDictBody.trim();
      if (dictBody.length > 0) {
        dictBody = `${dictBody} /AIGC(${escaped})`;
      } else {
        dictBody = `/AIGC(${escaped})`;
      }
      objectSegment = `${objNum.toString()} 0 obj\n<< ${dictBody} >>\nendobj\n`;
      newSize = Math.max(trailer.size, objNum + 1);
    } else {
      // 新建 Info 对象：对象号 = max(size, rootRef+1)
      objNum = Math.max(trailer.size, trailer.rootRef + 1);
      objectSegment = `${objNum.toString()} 0 obj\n<< /AIGC(${escaped}) >>\nendobj\n`;
      infoRefUsed = objNum;
      newSize = Math.max(trailer.size, objNum + 1);
    }

    // 对象段的字节偏移（在最终文件中的位置）= 原文件大小
    const objOffset: number = stat.size;
    // 用 TextEncoder 计算对象段字节数（中文 ProduceID 等非 ASCII 时字符串长度≠字节数）
    const encoder: util.TextEncoder = new util.TextEncoder();
    const objectBytes: Uint8Array = encoder.encodeInto(objectSegment);
    const objectBytesLen: number = objectBytes.length;
    // xref 表在最终文件中的字节偏移 = 原文件大小 + 对象段字节数
    const xrefOffset: number = objOffset + objectBytesLen;

    // xref 段：子段从 objNum 开始，1 个条目；条目第一列是对象字节偏移（10 位）
    const xrefSegment: string =
      'xref\n' +
      `${objNum.toString()} 1\n` +
      `${objOffset.toString().padStart(10, '0')} 00000 n \n` +
      'trailer\n' +
      `<< /Size ${newSize.toString()} /Root ${trailer.rootRef.toString()} 0 R ` +
      `/Info ${infoRefUsed.toString()} 0 R /Prev ${trailer.oldStartxref.toString()} >>\n` +
      'startxref\n' +
      `${xrefOffset.toString()}\n` +
      '%%EOF\n';

    const fullSegment: string = objectSegment + xrefSegment;

    // 写目标：先复制原文件，再追加新段
    copyFileAppend(absPath, targetPath, fullSegment);
    return true;
  } catch (err) {
    hilog.warn(PDF_DOMAIN, PDF_TAG, 'injectPdfIncremental failed: %{public}s', `${err}`);
    return false;
  }
}

function readFileHead(absPath: string): string {
  const file = fileIo.openSync(absPath, fileIo.OpenMode.READ_ONLY);
  try {
    const buffer = new ArrayBuffer(4096);
    const bytesRead: number = fileIo.readSync(file.fd, buffer, { offset: 0, length: 4096 });
    return new util.TextDecoder('utf-8').decode(new Uint8Array(buffer, 0, bytesRead));
  } finally {
    fileIo.closeSync(file);
  }
}

/** 复制原文件到目标，然后追加增量段。 */
function copyFileAppend(sourcePath: string, targetPath: string, appendSegment: string): void {
  let source: fileIo.File | null = null;
  let target: fileIo.File | null = null;
  try {
    source = fileIo.openSync(sourcePath, fileIo.OpenMode.READ_ONLY);
    target = fileIo.openSync(targetPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
    const stat = fileIo.statSync(sourcePath);
    const chunkSize: number = 64 * 1024;
    let offset: number = 0;
    while (offset < stat.size) {
      const readLength: number = Math.min(chunkSize, stat.size - offset);
      const buffer = new ArrayBuffer(readLength);
      const bytesRead: number = fileIo.readSync(source.fd, buffer, { offset, length: readLength });
      if (bytesRead <= 0) {
        break;
      }
      const data: ArrayBuffer = bytesRead === readLength ? buffer : buffer.slice(0, bytesRead);
      fileIo.writeSync(target.fd, data);
      offset += bytesRead;
    }
    const encoder: util.TextEncoder = new util.TextEncoder();
    const encoded: Uint8Array = encoder.encodeInto(appendSegment);
    // encodeInto 返回 Uint8Array，其底层 buffer 可能含多余字节；取精确切片转 ArrayBuffer
    const exactBytes: Uint8Array = encoded.subarray(0, encoded.byteLength);
    fileIo.writeSync(target.fd, exactBytes.buffer as ArrayBuffer);
  } finally {
    if (source !== null) {
      fileIo.closeSync(source);
    }
    if (target !== null) {
      fileIo.closeSync(target);
    }
  }
}

/**
 * AIGC 隐式标识 zip 容器格式修改器。
 *
 * 作用于"已解压出的目录树"，就地修改目标条目（docProps/custom.xml、OFD.xml、
 * metadata.json、meta.json 等），随后由调用方重新打包。
 *
 * 依据：TC260《网络安全标准实践指南——人工智能生成合成内容标识方法
 *       文件元数据隐式标识 文本文件》。
 */
import fileIo from '@ohos.file.fs';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  buildOfdCustomDataXml,
  buildOoxmlContentTypesOverride,
  buildOoxmlCustomPropertyXml,
  buildOoxmlFreshCustomXml,
  buildOoxmlRelsRelationship,
  OOXML_CUSTOM_PROPS_CONTENT_TYPE,
  OOXML_CUSTOM_PROPS_RELATIONSHIP_TYPE
} from './AigcProvenance';

const MODIFIER_DOMAIN: number = 0x0ff7;
const MODIFIER_TAG: string = 'AigcZipModifiers';

/** zip 容器条目修改器接口。 */
export interface AigcZipEntryModifier {
  /** 重打包后必须存在于 zip 根的条目名（验证门用）。 */
  rootVerifyEntry: string;
  /** 就地修改解压目录；返回是否成功。 */
  modify(extractedDir: string, payloadJson: string, fileName: string): boolean;
}

function fileExists(absPath: string): boolean {
  try {
    fileIo.statSync(absPath);
    return true;
  } catch (_err) {
    return false;
  }
}

function readText(absPath: string): string {
  return fileIo.readTextSync(absPath);
}

function writeText(absPath: string, content: string): void {
  const file = fileIo.openSync(absPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
  try {
    fileIo.writeSync(file.fd, content);
  } finally {
    fileIo.closeSync(file);
  }
}

/** 从现有 custom.xml 提取最大 pid；无则返回 1（新属性从 2 起）。 */
function extractMaxPid(customXml: string): number {
  let maxPid: number = 1;
  const matches: string[] = customXml.match(/pid="(\d+)"/g) ?? [];
  for (let i: number = 0; i < matches.length; i += 1) {
    const pid: number = parseInt(matches[i].replace(/[^0-9]/g, ''), 10);
    if (!isNaN(pid) && pid > maxPid) {
      maxPid = pid;
    }
  }
  return maxPid;
}

/**
 * 提取文本块中的 ProduceID。
 * 兼容：原始 JSON（"ProduceID":"..."）与 XML 转义后的 JSON（&quot;ProduceID&quot;:&quot;...&quot;）。
 */
function extractProduceIdFromBlock(block: string): string {
  // 匹配 "ProduceID":"..." 或 &quot;ProduceID&quot;:&quot;...&quot;
  const pattern: RegExp = /ProduceID(?:&quot;|["'])?\s*:\s*(?:&quot;|["'])([^"&]{8,64})(?:&quot;|["'])/;
  const matchResult = block.match(pattern);
  if (matchResult !== null && matchResult.length > 1) {
    return matchResult[1];
  }
  return '';
}

/** 提取现有 custom.xml 中 AIGC property 的 ProduceID（无则空串）。 */
function extractAigcProduceIdFromCustomXml(customXml: string): string {
  // 找 name="AIGC" 的 property 块
  const propMatch = customXml.match(/<property[^>]*name="AIGC"[^>]*>[\s\S]*?<\/property>/);
  if (propMatch === null) {
    return '';
  }
  return extractProduceIdFromBlock(propMatch[0]);
}

/** 在 custom.xml 中替换 AIGC property（ProduceID 不同时）。 */
function replaceAigcPropertyInCustomXml(customXml: string, payloadJson: string): string {
  const propPattern: RegExp = /<property[^>]*name="AIGC"[^>]*>[\s\S]*?<\/property>/;
  const newProp: string = buildOoxmlCustomPropertyXml(2, payloadJson); // pid 用 2（替换场景，pid 不重要）
  return customXml.replace(propPattern, newProp);
}

/** 在 custom.xml 的 </Properties> 前插入新 property。 */
function insertPropertyIntoCustomXml(customXml: string, payloadJson: string): string {
  const nextPid: number = extractMaxPid(customXml) + 1;
  const newProp: string = buildOoxmlCustomPropertyXml(nextPid, payloadJson);
  const closeIndex: number = customXml.lastIndexOf('</Properties>');
  if (closeIndex < 0) {
    return '';
  }
  return `${customXml.substring(0, closeIndex)}${newProp}${customXml.substring(closeIndex)}`;
}

/** OOXML 修改器（docx/xlsx/pptx 共用）。 */
class OoxmlModifier implements AigcZipEntryModifier {
  rootVerifyEntry: string = '[Content_Types].xml';

  modify(extractedDir: string, payloadJson: string, _fileName: string): boolean {
    const docPropsDir: string = `${extractedDir}/docProps`;
    try {
      fileIo.mkdirSync(docPropsDir, true);
    } catch (_err) {
    }
    const customPath: string = `${docPropsDir}/custom.xml`;
    if (fileExists(customPath)) {
      const text: string = readText(customPath);
      const existingProduceId: string = extractAigcProduceIdFromCustomXml(text);
      let result: string = text;
      if (existingProduceId.length > 0) {
        // 幂等：ProduceID 相同则跳过（不重复）
        const currentProduceId: string = extractProduceIdFromJson(payloadJson);
        if (existingProduceId === currentProduceId) {
          return true;
        }
        result = replaceAigcPropertyInCustomXml(text, payloadJson);
      } else {
        result = insertPropertyIntoCustomXml(text, payloadJson);
        if (result.length === 0) {
          return false;
        }
      }
      writeText(customPath, result);
      return true;
    }
    // custom.xml 不存在 → 新建 + 补 [Content_Types].xml + _rels/.rels
    if (!fileExists(`${extractedDir}/[Content_Types].xml`) || !fileExists(`${extractedDir}/_rels/.rels`)) {
      return false;
    }
    writeText(customPath, buildOoxmlFreshCustomXml(payloadJson));
    // [Content_Types].xml 加 Override
    const ctPath: string = `${extractedDir}/[Content_Types].xml`;
    const ct: string = readText(ctPath);
    if (ct.indexOf(OOXML_CUSTOM_PROPS_CONTENT_TYPE) < 0) {
      const override: string = buildOoxmlContentTypesOverride();
      const ctClose: number = ct.lastIndexOf('</Types>');
      if (ctClose < 0) {
        return false;
      }
      writeText(ctPath, `${ct.substring(0, ctClose)}${override}${ct.substring(ctClose)}`);
    }
    // _rels/.rels 加关系
    const relsPath: string = `${extractedDir}/_rels/.rels`;
    const rels: string = readText(relsPath);
    if (rels.indexOf(OOXML_CUSTOM_PROPS_RELATIONSHIP_TYPE) < 0) {
      const nextRid: number = extractMaxRid(rels) + 1;
      const relation: string = buildOoxmlRelsRelationship(`rId${nextRid.toString()}`);
      const relsClose: number = rels.lastIndexOf('</Relationships>');
      if (relsClose < 0) {
        return false;
      }
      writeText(relsPath, `${rels.substring(0, relsClose)}${relation}${rels.substring(relsClose)}`);
    }
    return true;
  }
}

/** 从 _rels/.rels 提取最大 rId 数字。 */
function extractMaxRid(rels: string): number {
  let maxRid: number = 0;
  const matches: string[] = rels.match(/rId(\d+)/g) ?? [];
  for (let i: number = 0; i < matches.length; i += 1) {
    const rid: number = parseInt(matches[i].replace(/[^0-9]/g, ''), 10);
    if (!isNaN(rid) && rid > maxRid) {
      maxRid = rid;
    }
  }
  return maxRid;
}

/** 从 payloadJson（原始 JSON）提取 ProduceID。 */
function extractProduceIdFromJson(payloadJson: string): string {
  return extractProduceIdFromBlock(payloadJson);
}

/** OFD 修改器：OFD.xml 的 CustomDatas。 */
class OfdModifier implements AigcZipEntryModifier {
  rootVerifyEntry: string = 'OFD.xml';

  modify(extractedDir: string, payloadJson: string, _fileName: string): boolean {
    const ofdPath: string = `${extractedDir}/OFD.xml`;
    if (!fileExists(ofdPath)) {
      return false;
    }
    const text: string = readText(ofdPath);
    // 已有 AIGC CustomData → 幂等/替换
    const existing = text.match(/<CustomData\s+Name="AIGC"[^>]*>[\s\S]*?<\/CustomData>/);
    if (existing !== null) {
      const existingProduceId: string = extractProduceIdFromText(existing[0]);
      const currentProduceId: string = extractProduceIdFromJson(payloadJson);
      if (existingProduceId === currentProduceId) {
        return true;
      }
      writeText(ofdPath, text.replace(existing[0], buildOfdCustomDataXml(payloadJson)));
      return true;
    }
    const newElem: string = buildOfdCustomDataXml(payloadJson);
    const customDatasClose: number = text.lastIndexOf('</CustomDatas>');
    if (customDatasClose >= 0) {
      writeText(ofdPath, `${text.substring(0, customDatasClose)}${newElem}${text.substring(customDatasClose)}`);
      return true;
    }
    // 无 CustomDatas → 在 </DocInfo> 前建块
    const docInfoClose: number = text.lastIndexOf('</DocInfo>');
    if (docInfoClose >= 0) {
      const block: string = `<CustomDatas>${newElem}</CustomDatas>`;
      writeText(ofdPath, `${text.substring(0, docInfoClose)}${block}${text.substring(docInfoClose)}`);
      return true;
    }
    return false;
  }
}

function extractProduceIdFromText(block: string): string {
  return extractProduceIdFromBlock(block);
}

/** JSON 容器修改器（xmind: metadata.json；posm/posf: meta.json）。 */
class JsonContainerModifier implements AigcZipEntryModifier {
  rootVerifyEntry: string;

  constructor(rootVerifyEntry: string) {
    this.rootVerifyEntry = rootVerifyEntry;
  }

  modify(extractedDir: string, payloadJson: string, _fileName: string): boolean {
    const entryPath: string = `${extractedDir}/${this.rootVerifyEntry}`;
    if (!fileExists(entryPath)) {
      return false;
    }
    try {
      const text: string = readText(entryPath);
      const obj: Record<string, Object> = JSON.parse(text) as Record<string, Object>;
      const aigcObj: Object | undefined = obj['AIGC'];
      if (aigcObj !== undefined) {
        const existingProduceId: string = extractProduceIdFromJson(JSON.stringify(aigcObj));
        const currentProduceId: string = extractProduceIdFromJson(payloadJson);
        if (existingProduceId === currentProduceId) {
          return true; // 幂等
        }
      }
      obj['AIGC'] = JSON.parse(payloadJson) as Object;
      writeText(entryPath, JSON.stringify(obj));
      return true;
    } catch (_err) {
      return false;
    }
  }
}

/** 根据扩展名返回修改器；未知返回 null。 */
export function zipModifierForExt(ext: string): AigcZipEntryModifier | null {
  switch (ext.toLowerCase()) {
    case 'docx':
    case 'xlsx':
    case 'pptx':
      return new OoxmlModifier();
    case 'ofd':
      return new OfdModifier();
    case 'xmind':
      return new JsonContainerModifier('metadata.json');
    case 'posm':
    case 'posf':
      return new JsonContainerModifier('meta.json');
    default:
      return null;
  }
}

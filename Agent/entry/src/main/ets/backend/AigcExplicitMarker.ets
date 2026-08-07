/**
 * AIGC 显式标注纯逻辑模块 —— 无 fileIo 依赖，可单测。
 *
 * 在 AI 生成文件的内容部分开头加"本文件由AI生成，请注意甄别"，配合隐式标注。
 * - 位置：隐式标注（frontmatter/注释）之后、正文开头
 * - 代码文件用注释形式（不破坏可编译性）
 * - 依据：华为文档要求应用提供 AI 生成内容的显式标识
 */
import { AigcCommentSyntax, commentPrefixForFormat } from './AigcProvenance';

/** 显式标注文案。 */
export const EXPLICIT_MARKER_TEXT: string = '本文件由AI生成，请注意甄别';

/** 幂等检测范围（前 N 字符）。 */
const EXPLICIT_SCAN_BYTES: number = 8192;

/** 隐式标注块定位结果。 */
export interface AigcMarkerSpan {
  span: string;
  endIndex: number;
}

/**
 * 生成一行显式标注。
 * - md/markdown/txt → 纯文本行（打开即见）
 * - html/xml/svg → HTML 注释（不破坏结构）
 * - css → /* *​/
 * - py/sh/rb 等 → #
 * - 其它（ts/js/java/go 等）→ //
 */
export function buildExplicitMarkerLine(fileName: string): string {
  const lower: string = fileName.toLowerCase();
  const idx: number = lower.lastIndexOf('.');
  const ext: string = idx >= 0 ? lower.substring(idx + 1) : '';
  if (ext === 'md' || ext === 'markdown' || ext === 'txt') {
    return EXPLICIT_MARKER_TEXT;
  }
  const comment: AigcCommentSyntax = commentPrefixForFormat(fileName);
  if (comment.close.length > 0) {
    return `${comment.open} ${EXPLICIT_MARKER_TEXT} ${comment.close}`;
  }
  return `${comment.open} ${EXPLICIT_MARKER_TEXT}`;
}

/** 判断文本是否已包含显式标注（前 EXPLICIT_SCAN_BYTES 字符）。 */
export function hasExplicitMarker(text: string): boolean {
  const head: string = text.substring(0, EXPLICIT_SCAN_BYTES);
  return head.indexOf(EXPLICIT_MARKER_TEXT) >= 0;
}

/**
 * 定位文本头部的隐式标注块。
 * 返回 { span, endIndex }：span 是完整隐式块（含末尾换行），endIndex 是其后的索引。
 * 支持：YAML frontmatter、<!--AIGC-->、# AIGC、// AIGC、/* AIGC*​/、AIGC: 多行键值对。
 */
export function matchImplicitMarkerAtHead(text: string): AigcMarkerSpan | null {
  const head: string = text.substring(0, EXPLICIT_SCAN_BYTES);
  // YAML frontmatter：--- 开头，含 AIGC:，到第二个 --- 结束
  const lines: string[] = head.split('\n');
  if (lines.length > 0 && lines[0].trim() === '---') {
    let endLine: number = -1;
    for (let i: number = 1; i < lines.length; i += 1) {
      if (lines[i].trim() === '---') {
        endLine = i;
        break;
      }
    }
    if (endLine > 0 && head.indexOf('AIGC:') >= 0) {
      // 计算 span：0 到 endLine 行末尾（含换行）
      const pos: number = head.split('\n').slice(0, endLine + 1).join('\n').length;
      const endIdx: number = pos < head.length && head.charAt(pos) === '\n' ? pos + 1 : pos;
      const frontmatterSpan: AigcMarkerSpan = {
        span: head.substring(0, endIdx),
        endIndex: endIdx
      };
      return frontmatterSpan;
    }
  }
  // 单行/多行注释
  const patterns: RegExp[] = [
    /^<!--AIGC:[\s\S]*?-->\s*\n?/,
    /^#\s*AIGC:[^\n]*\n?/,
    /^\/\/\s*AIGC:[^\n]*\n?/,
    /^\/\*\s*AIGC:[\s\S]*?\*\/\s*\n?/,
    /^AIGC:[\s\S]*?ReservedCode2:[^\n]*\n?/
  ];
  for (let i: number = 0; i < patterns.length; i += 1) {
    const m = head.match(patterns[i]);
    if (m !== null && m.length > 0) {
      const commentSpan: AigcMarkerSpan = {
        span: m[0],
        endIndex: m[0].length
      };
      return commentSpan;
    }
  }
  return null;
}

/** 在隐式标注之后、正文开头插入显式标注行。 */
export function insertExplicitAfterImplicit(rawText: string, explicitLine: string): string {
  const m: AigcMarkerSpan | null = matchImplicitMarkerAtHead(rawText);
  if (m === null) {
    // 无隐式块 → 直接插到头部
    return `${explicitLine}\n${rawText}`;
  }
  const endIdx: number = m.endIndex;
  return `${rawText.substring(0, endIdx)}${explicitLine}\n${rawText.substring(endIdx)}`;
}

/** 轻量 XML 良构校验：维护标签栈，处理自闭合、CDATA、注释、属性含 >。 */
export function isWellFormedXml(xmlText: string): boolean {
  let text: string = xmlText;
  // 去 XML 声明
  text = text.replace(/<\?xml[\s\S]*?\?>/g, '');
  // 去注释
  text = text.replace(/<!--[\s\S]*?-->/g, '');
  // 去 DOCTYPE
  text = text.replace(/<!DOCTYPE[\s\S]*?>/g, '');
  // 去 CDATA
  text = text.replace(/<!\[CDATA\[[\s\S]*?\]\]>/g, '');
  const stack: string[] = [];
  const tagPattern: RegExp = /<\/?([a-zA-Z][\w:.-]*)((?:[^>"']|"[^"]*"|'[^']*')*?)(\/?)>/g;
  // String.match(global) 返回所有匹配的字符串数组（含捕获组不可直接取，改用 matchAll 语义的循环）
  // ArkTS 限制：不用 RegExp.exec / RegExpMatchArray 显式类型，改用 match + 逐项解析
  const matched: string[] = text.match(tagPattern) ?? [];
  for (let i: number = 0; i < matched.length; i += 1) {
    const tagText: string = matched[i];
    // 解析标签名：< 或 </ 后到空白/属性/结束
    const nameMatch = tagText.match(/^<\/?([a-zA-Z][\w:.-]*)/);
    if (nameMatch === null) {
      continue;
    }
    const name: string = nameMatch[1];
    const isClosing: boolean = tagText.startsWith('</');
    const isSelfClosing: boolean = tagText.endsWith('/>');
    if (isClosing) {
      const top: string | undefined = stack.pop();
      if (top !== name) {
        return false;
      }
    } else if (!isSelfClosing) {
      stack.push(name);
    }
  }
  return stack.length === 0;
}

/** JSON 有效性校验。 */
export function isValidJson(jsonText: string): boolean {
  try {
    JSON.parse(jsonText);
    return true;
  } catch (_err) {
    return false;
  }
}

/** 构建 docx 显式标注段落（在 <w:body> 后插入）。 */
export function buildDocxExplicitParagraph(markerText: string): string {
  const escaped: string = escapeXmlText(markerText);
  return `<w:p><w:r><w:t xml:space="preserve">${escaped}</w:t></w:r></w:p>`;
}

/** 构建 xlsx 显式标注行。 */
export function buildXlsxExplicitRow(markerText: string): string {
  const escaped: string = escapeXmlText(markerText);
  return `<row r="1" spans="1:1"><c r="A1" t="inlineStr"><is><t>${escaped}</t></is></c></row>`;
}

/** 构建 xlsx 显式标注单元格（追加到首行，列号自增）。 */
export function buildXlsxExplicitCell(markerText: string, colLetter: string): string {
  const escaped: string = escapeXmlText(markerText);
  return `<c r="${colLetter}1" t="inlineStr"><is><t>${escaped}</t></is></c>`;
}

/** 构建 pptx 显式标注文本框（shapeId 递增）。 */
export function buildPptxExplicitShape(markerText: string, shapeId: number): string {
  const escaped: string = escapeXmlText(markerText);
  return `<p:sp><p:nvSpPr><p:cNvPr id="${shapeId.toString()}" name="AI生成显式标注"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>` +
    `<p:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="9144000" cy="320000"/></a:xfrm>` +
    `<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr>` +
    `<p:txBody><a:bodyPr wrap="none"/><a:lstStyle/><a:p><a:r><a:rPr lang="zh-CN" dirty="0" b="1" sz="1400"/><a:t>${escaped}</a:t></a:r></a:p></p:txBody></p:sp>`;
}

/** xmind 显式标注子 topic 结构。 */
export interface AigcXmindTopic {
  id: string;
  topicClass: string;
  title: string;
  structureClass: string;
}

/** 构建 xmind 显式标注子 topic。 */
export function buildXmindExplicitTopic(markerText: string, produceId: string): AigcXmindTopic {
  const topic: AigcXmindTopic = {
    id: `aigc-note-${produceId}`,
    topicClass: 'topic',
    title: markerText,
    structureClass: 'org.xmind.ui.map.clockwise'
  };
  return topic;
}

/** 构建 OFD 显式标注 TextObject。 */
export function buildOfdExplicitTextObject(markerText: string, nextId: number, fontId: string): string {
  const escaped: string = escapeXmlText(markerText);
  return `<ofd:TextObject ID="${nextId.toString()}" CTM="1 0 0 1 0 0" Boundary="10 10 100 15" Font="${fontId}">` +
    `<ofd:TextCode X="10" Y="10">${escaped}</ofd:TextCode></ofd:TextObject>`;
}

/** XML 文本转义。 */
function escapeXmlText(input: string): string {
  return input
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

/** 列字母转数字（A=1, B=2, ..., AA=27）。 */
export function columnLetterToNumber(letter: string): number {
  let result: number = 0;
  for (let i: number = 0; i < letter.length; i += 1) {
    result = result * 26 + (letter.charCodeAt(i) - 64);
  }
  return result;
}

/** 数字转列字母。 */
export function numberToColumnLetter(num: number): string {
  let n: number = num;
  let result: string = '';
  while (n > 0) {
    const rem: number = (n - 1) % 26;
    result = String.fromCharCode(65 + rem) + result;
    n = Math.floor((n - 1) / 26);
  }
  return result;
}

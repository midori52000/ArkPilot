import { breakpointManager } from '../adaptive/BreakpointManager';
import { getArkPilotLayoutProfile } from '../adaptive/LayoutProfiles';
import { ArkPilotBreakpoint } from '../adaptive/BreakpointTypes';
import {
  codexBackend,
  CodexApprovalRequest,
  CodexBackendSnapshot,
  CodexConnectionState,
  CodexDiffLine,
  CodexRequestUserInput,
  CodexRequestUserInputOption,
  CodexRequestUserInputQuestion,
  CodexTurnRequest,
  CodexTurnResult
} from '../backend/CodexBackend';
import {
  CollaborationModeOption,
  CodexProviderConfig,
  WorkspaceAccessStatus,
  checkWorkspaceAccess,
  getEmbeddedCodexHostStatus,
  getEmbeddedCodexHostStatusAsync,
  getEmbeddedCodexProviderCatalog,
  getEmbeddedCodexProviderConfig,
  saveEmbeddedCodexProviderConfig
} from '../backend/CodexNative';
import { providerCatalogService } from '../backend/ProviderCatalogService';
import { SessionSummary, WorkspaceAccessKind, WorkspacePermissionState, TurnTokenUsage, TokenUsageAggregate, TokenUsageBreakdown, WorkspaceItem, WorkspaceBindingDraft, WorkspaceDirectorySelection, SelectorOption, DailyTokenSnapshot, ProjectRecord } from '../backend/ConsoleModels';
import { StoredWorkspaceItem, workspaceBindingStore } from '../backend/WorkspaceBindingStore';
import { projectStore } from '../backend/ProjectStore';
import { common, OpenLinkOptions, Want, wantConstant } from '@kit.AbilityKit';
import router from '@ohos.router';
import pasteboard from '@ohos.pasteboard';
import { promptAction } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileShare, fileUri, picker } from '@kit.CoreFileKit';
import fileIo from '@ohos.file.fs';
import uri from '@ohos.uri';

const INDEX_DOMAIN = 0x0000;
const INDEX_TAG = 'IndexProviderDebug';
const WAITING_FOR_DIFF_TEXT: string = '\u7b49\u5f85 turn/diff/updated \u901a\u77e5\u3002';
const NO_DIFF_TEXT: string = '\u672c\u8f6e\u5c1a\u672a\u4ea7\u751f diff\u3002';
const NO_FILE_CHANGES_TEXT: string = '\u5c1a\u672a\u4ea7\u751f\u6587\u4ef6\u6539\u52a8';
const UNKNOWN_DIFF_FILE_TEXT: string = '\u672a\u8bc6\u522b\u6587\u4ef6';
const USER_FILE_SERVICE_SYSCAP: string = 'SystemCapability.FileManagement.UserFileService';
const FOLDER_SELECTION_SYSCAP: string = 'SystemCapability.FileManagement.UserFileService.FolderSelection';
const FOLDER_AUTHORIZATION_SYSCAP: string = 'SystemCapability.FileManagement.AppFileService.FolderAuthorization';
const LEGACY_FOLDER_AUTHORIZATION_SYSCAP: string = 'SystemCapability.FileManagement.File.Environment.FolderObtain';

class ChatMessage {
  id: string;
  author: string;
  role: string;
  content: string;
  timestamp: string;
  itemType?: string;
  status?: string;
  metadata?: Record<string, Object>;

  constructor(id: string, author: string, role: string, content: string, timestamp: string, itemType?: string, status?: string, metadata?: Record<string, Object>) {
    this.id = id;
    this.author = author;
    this.role = role;
    this.content = content;
    this.timestamp = timestamp;
    this.itemType = itemType;
    this.status = status;
    this.metadata = metadata;
  }
}

class CodeDiffLine {
  id: string;
  lineNumber: string;
  sign: string;
  content: string;
  kind: string;
  filePath: string;

  constructor(id: string, lineNumber: string, sign: string, content: string, kind: string, filePath?: string) {
    this.id = id;
    this.lineNumber = lineNumber;
    this.sign = sign;
    this.content = content;
    this.kind = kind;
    this.filePath = filePath ?? '';
  }
}

class CodeDiffFile {
  path: string;
  label: string;
  diffStat: string;
  lines: CodeDiffLine[];

  constructor(path: string, label: string, diffStat: string, lines: CodeDiffLine[]) {
    this.path = path;
    this.label = label;
    this.diffStat = diffStat;
    this.lines = lines;
  }
}

class CompactionNotice {
  id: string;
  threadId: string;
  status: string;
  errorMessage: string;
  savedTokens: number;
  oldTotalTokens: number;
  newTotalTokens: number;
  timestamp: string;

  constructor(
    id: string,
    threadId: string,
    status: string,
    errorMessage: string,
    savedTokens: number,
    oldTotalTokens: number,
    newTotalTokens: number,
    timestamp: string
  ) {
    this.id = id;
    this.threadId = threadId;
    this.status = status;
    this.errorMessage = errorMessage;
    this.savedTokens = savedTokens;
    this.oldTotalTokens = oldTotalTokens;
    this.newTotalTokens = newTotalTokens;
    this.timestamp = timestamp;
  }
}

class MarkdownBlock {
  id: string;
  kind: string;
  text: string;
  rawText: string;
  level: number;
  language: string;
  rows: string[][];

  constructor(id: string, kind: string, text: string, level?: number, language?: string, rows?: string[][], rawText?: string) {
    this.id = id;
    this.kind = kind;
    this.text = text;
    this.rawText = rawText ?? text;
    this.level = level ?? 0;
    this.language = language ?? '';
    this.rows = rows ?? [];
  }
}

class MathSegment {
  id: string;
  kind: string;
  text: string;
  rawText: string;
  target: string;

  constructor(id: string, kind: string, text: string, rawText?: string, target?: string) {
    this.id = id;
    this.kind = kind;
    this.text = text;
    this.rawText = rawText ?? text;
    this.target = target ?? '';
  }
}

class InlineWebTargetMatch {
  start: number;
  end: number;
  target: string;

  constructor(start: number, end: number, target: string) {
    this.start = start;
    this.end = end;
    this.target = target;
  }
}

class LocalPathResolution {
  path: string;
  matchedExistingFile: boolean;

  constructor(path: string, matchedExistingFile?: boolean) {
    this.path = path;
    this.matchedExistingFile = matchedExistingFile ?? false;
  }
}

class MarkdownTextRun {
  id: string;
  text: string;
  blockKind: string;
  inlineKind: string;
  level: number;

  constructor(id: string, text: string, blockKind: string, inlineKind?: string, level?: number) {
    this.id = id;
    this.text = text;
    this.blockKind = blockKind;
    this.inlineKind = inlineKind ?? 'text';
    this.level = level ?? 0;
  }
}

class HtmlTextRun {
  id: string;
  text: string;
  isLink: boolean;

  constructor(id: string, text: string, isLink: boolean) {
    this.id = id;
    this.text = text;
    this.isLink = isLink;
  }
}

type RightPanelTab = 'diff' | 'browser';

class CodeToken {
  id: string;
  kind: string;
  text: string;

  constructor(id: string, kind: string, text: string) {
    this.id = id;
    this.kind = kind;
    this.text = text;
  }
}

class FormulaNode {
  kind: string;
  text: string;
  variant: string;
  children: FormulaNode[];
  numerator: FormulaNode | null;
  denominator: FormulaNode | null;
  base: FormulaNode | null;
  superscript: FormulaNode | null;
  subscript: FormulaNode | null;
  radicand: FormulaNode | null;

  constructor(kind: string, text?: string, children?: FormulaNode[], variant?: string) {
    this.kind = kind;
    this.text = text ?? '';
    this.variant = variant ?? 'roman';
    this.children = children ?? [];
    this.numerator = null;
    this.denominator = null;
    this.base = null;
    this.superscript = null;
    this.subscript = null;
    this.radicand = null;
  }
}

class FormulaParseResult {
  node: FormulaNode;
  nextIndex: number;

  constructor(node: FormulaNode, nextIndex: number) {
    this.node = node;
    this.nextIndex = nextIndex;
  }
}

class DirectoryMirrorResult {
  copiedFiles: number;
  deletedEntries: number;

  constructor(copiedFiles: number, deletedEntries: number) {
    this.copiedFiles = copiedFiles;
    this.deletedEntries = deletedEntries;
  }
}

class MermaidScaleEntry {
  key: string;
  scale: number;

  constructor(key: string, scale: number) {
    this.key = key;
    this.scale = scale;
  }
}

@Component
struct MermaidWebDiagram {
  @Prop source: string = '';
  @Prop diagramHeight: number = 260;
  @Prop
  @Watch('onFontScaleChanged')
  fontScale: number = 1;

  private controller: webview.WebviewController = new webview.WebviewController();

  private mermaidDataUrl(): string {
    return `data:text/html;charset=utf-8,${encodeURIComponent(this.mermaidHtml())}`;
  }

  private mermaidHtml(): string {
    const sourceText: string = this.escapeHtml(this.source);
    return `<!doctype html>
<html>
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1, minimum-scale=1, maximum-scale=1, user-scalable=no" />
  <style>
    html, body {
      margin: 0;
      padding: 0;
      background: #FFFFFF;
      background-color: #FFFFFF !important;
      color: #0F172A;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      overflow: auto;
      color-scheme: light;
    }
    body {
      padding: 12px;
      box-sizing: border-box;
    }
    #diagram {
      width: 100%;
      min-height: 40px;
      background: #FFFFFF !important;
      background-color: #FFFFFF !important;
      overflow: visible;
      transform-origin: 0 0;
    }
    #diagram svg {
      display: block;
      max-width: 180%;
      height: auto;
      background: #FFFFFF !important;
      background-color: #FFFFFF !important;
      transform-origin: 0 0;
    }
    .render-error {
      white-space: pre-wrap;
      word-break: break-word;
      font: 12px ui-monospace, SFMono-Regular, Consolas, monospace;
      line-height: 18px;
      color: #B91C1C;
      background: #FEF2F2;
      border: 1px solid #FECACA;
      border-radius: 8px;
      padding: 10px;
    }
  </style>
</head>
<body>
  <div id="diagram"></div>
  <pre id="source" style="display:none">${sourceText}</pre>
  <script>
    const source = document.getElementById('source').textContent || '';
    const target = document.getElementById('diagram');
    const minScale = 0.6;
    const maxScale = 1.8;
    let diagramScale = 1;
    const mermaidUrls = [
      'https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js',
      'https://unpkg.com/mermaid@11/dist/mermaid.min.js'
    ];
    function clampScale(value) {
      if (!Number.isFinite(value)) {
        return 1;
      }
      return Math.min(maxScale, Math.max(minScale, Math.round(value * 100) / 100));
    }
    function baseSvgWidth(svg) {
      const cachedWidth = parseFloat(svg.getAttribute('data-arkpilot-base-width') || '0');
      if (Number.isFinite(cachedWidth) && cachedWidth > 0) {
        return cachedWidth;
      }
      svg.style.width = '100%';
      svg.style.minWidth = '';
      svg.style.maxWidth = 'none';
      svg.style.height = 'auto';
      const rect = svg.getBoundingClientRect();
      let width = rect.width;
      if (!Number.isFinite(width) || width <= 0) {
        const attrWidth = parseFloat(svg.getAttribute('width') || '0');
        width = Number.isFinite(attrWidth) && attrWidth > 0 ? attrWidth : 0;
      }
      if (width <= 0) {
        width = Math.max(target.clientWidth, 320);
      }
      svg.setAttribute('data-arkpilot-base-width', width.toString());
      return width;
    }
    function applyDiagramScale() {
      diagramScale = clampScale(diagramScale);
      target.style.zoom = '';
      target.style.transform = 'none';
      target.style.width = '100%';
      const svg = target.querySelector('svg');
      if (svg) {
        const nextWidth = baseSvgWidth(svg) * diagramScale;
        const nextWidthText = nextWidth.toFixed(2) + 'px';
        svg.style.display = 'block';
        svg.style.transform = 'none';
        svg.style.transformOrigin = '0 0';
        svg.style.width = nextWidthText;
        svg.style.minWidth = nextWidthText;
        svg.style.maxWidth = '180%';
        svg.style.height = 'auto';
        svg.setAttribute('width', nextWidth.toFixed(2));
        return 'applied:' + nextWidthText;
      }
      return 'pending';
    }
    window.__arkpilotApplyMermaidScale = function(value) {
      diagramScale = clampScale(value);
      return applyDiagramScale();
    };
    function showError(error) {
      const detail = error && error.message ? error.message : String(error || 'Unknown Mermaid render error');
      target.innerHTML = '<div class="render-error">Mermaid 渲染失败\\n\\n' + detail.replace(/[&<>"']/g, function(ch) {
        return ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[ch];
      }) + '</div>';
    }
    function loadMermaid(index) {
      if (window.mermaid) {
        return Promise.resolve();
      }
      if (index >= mermaidUrls.length) {
        return Promise.reject(new Error('Mermaid.js 未加载。请确认设备可以访问 jsdelivr 或 unpkg，或后续改为内置 mermaid.min.js。'));
      }
      return new Promise(function(resolve, reject) {
        const script = document.createElement('script');
        script.src = mermaidUrls[index];
        script.onload = function() { resolve(); };
        script.onerror = function() {
          loadMermaid(index + 1).then(resolve).catch(reject);
        };
        document.head.appendChild(script);
      });
    }
    async function renderDiagram() {
      try {
        await loadMermaid(0);
        mermaid.initialize({
          startOnLoad: false,
          securityLevel: 'loose',
          theme: 'base',
          themeVariables: {
            primaryColor: '#DBEAFE',
            primaryTextColor: '#0F172A',
            primaryBorderColor: '#93C5FD',
            lineColor: '#2563EB',
            secondaryColor: '#F8FAFC',
            tertiaryColor: '#FFFFFF',
            background: '#FFFFFF',
            mainBkg: '#DBEAFE',
            secondBkg: '#F8FAFC',
            textColor: '#0F172A',
            fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif'
          }
        });
        const result = await mermaid.render('arkpilot-mermaid-' + Date.now().toString(), source);
        target.innerHTML = result.svg;
        if (result.bindFunctions) {
          result.bindFunctions(target);
        }
        applyDiagramScale();
      } catch (error) {
        showError(error);
      }
    }
    if (document.readyState === 'loading') {
      window.addEventListener('DOMContentLoaded', renderDiagram);
    } else {
      renderDiagram();
    }
  </script>
</body>
</html>`;
  }

  private escapeHtml(text: string): string {
    return text
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  private normalizedScale(value: number): number {
    if (value !== value) {
      return 1;
    }
    return Math.min(1.8, Math.max(0.6, value));
  }

  private onFontScaleChanged(): void {
    const scaleText: string = this.normalizedScale(this.fontScale).toFixed(2);
    try {
      void this.controller.runJavaScript(
        `window.__arkpilotApplyMermaidScale && window.__arkpilotApplyMermaidScale(${scaleText});`
      );
    } catch (_err) {
    }
  }

  build() {
    Web({ src: this.mermaidDataUrl(), controller: this.controller })
      .javaScriptAccess(true)
      .darkMode(WebDarkMode.Off)
      .forceDarkAccess(false)
      .zoomAccess(false)
      .initialScale(100)
      .textZoomRatio(100)
      .onPageEnd(() => {
        this.onFontScaleChanged();
      })
      .width('100%')
      .height(this.diagramHeight)
      .backgroundColor('#FFFFFF')
      .zIndex(0)
      .hitTestBehavior(HitTestMode.Transparent)
  }
}

@CustomDialog
struct ArkPilotProjectCreateDialog {
  controller?: CustomDialogController;
  @Link projectName: string;
  @Link sourceUri: string;
  canSelectExternalFolder: () => boolean = () => false;
  chooseFolder: () => void = () => {};
  cancel: () => void = () => {};
  confirm: () => void = () => {};
  @State private sourceInfoHovering: boolean = false;
  @State private sourceInfoPinned: boolean = false;

  private sourceFolderText(): string {
    if (this.sourceUri.length > 0) {
      return `同步文件夹：${this.sourceUri}`;
    }
    return this.canSelectExternalFolder() ? '未选择同步文件夹' : '未启用下载目录同步';
  }

  private sourceFolderColor(): ResourceColor {
    return this.sourceUri.length > 0 ? '#182431' : '#7A869A';
  }

  private shouldShowSourceInfo(): boolean {
    return this.sourceInfoHovering || this.sourceInfoPinned;
  }

  @Builder
  private sourceInfoPopup() {
    Column() {
      Text('同步文件夹')
        .copyOption(CopyOptions.None)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor('#18181B')
        .width('100%')

      Text('同步文件夹是项目和本地目录之间的交换入口。项目在应用内运行，需要时再手动与该文件夹导入或导出项目文件。')
        .copyOption(CopyOptions.None)
        .fontSize(12)
        .fontColor('#4E5969')
        .lineHeight(18)
        .width('100%')
        .margin({ top: 8 })

      Column() {
        Text('• 导出项目内容：创建项目后，可以在项目菜单中，把应用内该项目文件夹内容导出到同步文件夹。')
          .copyOption(CopyOptions.None)
          .fontSize(12)
          .fontColor('#4E5969')
          .lineHeight(18)
          .width('100%')

        Text('• 导入文件夹内容：可以在项目菜单中，把同步文件夹中的内容导入到项目文件夹内。')
          .copyOption(CopyOptions.None)
          .fontSize(12)
          .fontColor('#4E5969')
          .lineHeight(18)
          .width('100%')
          .margin({ top: 6 })

        Text('• 未选择时：仅使用应用内项目目录，可以在项目菜单中重新关联同步文件夹。')
          .copyOption(CopyOptions.None)
          .fontSize(12)
          .fontColor('#4E5969')
          .lineHeight(18)
          .width('100%')
          .margin({ top: 6 })
      }
      .width('100%')
      .margin({ top: 10 })
    }
    .width(292)
    .padding({ left: 14, right: 14, top: 14, bottom: 14 })
  }

  build() {
    Column() {
      Text('新建项目')
        .copyOption(CopyOptions.None)
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor('#182431')
        .width('100%')

      Text('运行目录将自动创建在应用内项目目录。')
        .copyOption(CopyOptions.None)
        .fontSize(14)
        .fontColor('#7A869A')
        .lineHeight(20)
        .width('100%')
        .margin({ top: 8 })

      TextInput({ placeholder: '输入项目名称', text: this.projectName })
        .width('100%')
        .height(48)
        .fontSize(15)
        .fontColor('#182431')
        .placeholderColor('#9EA7B3')
        .backgroundColor('#F7F8FA')
        .borderRadius(12)
        .padding({ left: 14, right: 14 })
        .margin({ top: 22 })
        .enterKeyType(EnterKeyType.Done)
        .onChange((value: string) => {
          this.projectName = value;
        })

      Column() {
        Row() {
          Text('同步文件夹')
            .copyOption(CopyOptions.None)
            .fontSize(12)
            .fontColor('#7A869A')

          Blank()
            .layoutWeight(1)

          Text('i')
            .copyOption(CopyOptions.None)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.shouldShowSourceInfo() ? '#18181B' : '#4E5969')
            .textAlign(TextAlign.Center)
            .width(22)
            .height(22)
            .backgroundColor(this.shouldShowSourceInfo() ? '#E5E7EB' : '#FFFFFF')
            .border({ width: 1, color: '#D1D5DB' })
            .borderRadius(11)
            .onHover((isHover: boolean) => {
              this.sourceInfoHovering = isHover;
            })
            .onClick(() => {
              if (this.sourceInfoPinned) {
                this.sourceInfoPinned = false;
                this.sourceInfoHovering = false;
              } else {
                this.sourceInfoPinned = true;
              }
            })
            .bindPopup(this.shouldShowSourceInfo(), {
              builder: this.sourceInfoPopup,
              placement: Placement.Right,
              targetSpace: 8,
              width: 320,
              radius: 16,
              mask: false,
              autoCancel: true,
              enableArrow: true,
              popupColor: '#FFFFFF',
              shadow: { radius: 16, color: '#26000000', offsetX: 0, offsetY: 6 },
              onStateChange: (event) => {
                if (!event.isVisible) {
                  this.sourceInfoHovering = false;
                  this.sourceInfoPinned = false;
                }
              }
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Text(this.sourceFolderText())
          .copyOption(CopyOptions.None)
          .fontSize(13)
          .fontColor(this.sourceFolderColor())
          .lineHeight(18)
          .width('100%')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 6 })

      }
      .width('100%')
      .padding(14)
      .margin({ top: 12 })
      .backgroundColor('#F7F8FA')
      .borderRadius(12)

      Button(this.canSelectExternalFolder() ? '选择同步文件夹' : '启用下载目录同步')
        .type(ButtonType.Normal)
        .width('100%')
        .height(40)
        .fontSize(14)
        .fontColor('#18181B')
        .backgroundColor('#F2F3F5')
        .borderRadius(12)
        .margin({ top: 12 })
        .onClick(() => {
          this.chooseFolder();
        })

      Row() {
        Button('取消')
          .type(ButtonType.Normal)
          .layoutWeight(1)
          .height(40)
          .fontSize(14)
          .fontColor('#182431')
          .backgroundColor('#F2F3F5')
          .borderRadius(20)
          .onClick(() => {
            this.cancel();
            if (this.controller !== undefined) {
              this.controller.close();
            }
          })

        Button('创建')
          .type(ButtonType.Normal)
          .layoutWeight(1)
          .height(40)
          .fontSize(14)
          .fontColor('#FFFFFF')
          .backgroundColor('#18181B')
          .borderRadius(20)
          .margin({ left: 12 })
          .onClick(() => {
            this.confirm();
          })
      }
      .width('100%')
      .margin({ top: 24 })
    }
    .width('100%')
    .padding({ left: 24, right: 24, top: 24, bottom: 20 })
    .backgroundColor('#FFFFFF')
    .borderRadius(24)
  }
}

@CustomDialog
struct ArkPilotNameDialog {
  controller?: CustomDialogController;
  @Link textValue: string;
  title: string = '';
  subtitle: string = '';
  placeholder: string = '';
  confirmText: string = '确认';
  cancel: () => void = () => {};
  confirm: () => void = () => {};

  build() {
    Column() {
      Text(this.title)
        .copyOption(CopyOptions.None)
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor('#182431')
        .width('100%')

      if (this.subtitle.length > 0) {
        Text(this.subtitle)
          .copyOption(CopyOptions.None)
          .fontSize(14)
          .fontColor('#7A869A')
          .lineHeight(20)
          .width('100%')
          .margin({ top: 8 })
      }

      TextInput({ placeholder: this.placeholder, text: this.textValue })
        .width('100%')
        .height(48)
        .fontSize(15)
        .fontColor('#182431')
        .placeholderColor('#9EA7B3')
        .backgroundColor('#F7F8FA')
        .borderRadius(12)
        .padding({ left: 14, right: 14 })
        .margin({ top: 22 })
        .enterKeyType(EnterKeyType.Done)
        .onChange((value: string) => {
          this.textValue = value;
        })

      Row() {
        Button('取消')
          .type(ButtonType.Normal)
          .layoutWeight(1)
          .height(40)
          .fontSize(14)
          .fontColor('#182431')
          .backgroundColor('#F2F3F5')
          .borderRadius(20)
          .onClick(() => {
            this.cancel();
            if (this.controller !== undefined) {
              this.controller.close();
            }
          })

        Button(this.confirmText)
          .type(ButtonType.Normal)
          .layoutWeight(1)
          .height(40)
          .fontSize(14)
          .fontColor('#FFFFFF')
          .backgroundColor('#18181B')
          .borderRadius(20)
          .margin({ left: 12 })
          .onClick(() => {
            this.confirm();
          })
      }
      .width('100%')
      .margin({ top: 24 })
    }
    .width('100%')
    .padding({ left: 24, right: 24, top: 24, bottom: 20 })
    .backgroundColor('#FFFFFF')
    .borderRadius(24)
  }
}

@CustomDialog
struct ArkPilotDeleteDialog {
  controller?: CustomDialogController;
  @Link targetName: string;
  title: string = '';
  targetType: string = '';
  description: string = '';
  cancel: () => void = () => {};
  confirm: () => void = () => {};

  build() {
    Column() {
      Text(this.title)
        .copyOption(CopyOptions.None)
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor('#182431')
        .width('100%')

      Text(`确认删除${this.targetType}「${this.targetName}」？`)
        .copyOption(CopyOptions.None)
        .fontSize(15)
        .fontColor('#182431')
        .lineHeight(22)
        .width('100%')
        .margin({ top: 16 })

      if (this.description.length > 0) {
        Text(this.description)
          .copyOption(CopyOptions.None)
          .fontSize(13)
          .fontColor('#7A869A')
          .lineHeight(19)
          .width('100%')
          .margin({ top: 8 })
      }

      Row() {
        Button('取消')
          .type(ButtonType.Normal)
          .layoutWeight(1)
          .height(40)
          .fontSize(14)
          .fontColor('#182431')
          .backgroundColor('#F2F3F5')
          .borderRadius(20)
          .onClick(() => {
            this.cancel();
            if (this.controller !== undefined) {
              this.controller.close();
            }
          })

        Button('删除')
          .type(ButtonType.Normal)
          .layoutWeight(1)
          .height(40)
          .fontSize(14)
          .fontColor('#FFFFFF')
          .backgroundColor('#E84026')
          .borderRadius(20)
          .margin({ left: 12 })
          .onClick(() => {
            this.confirm();
          })
      }
      .width('100%')
      .margin({ top: 26 })
    }
    .width('100%')
    .padding({ left: 24, right: 24, top: 24, bottom: 20 })
    .backgroundColor('#FFFFFF')
    .borderRadius(24)
  }
}

@Entry
@Component
struct Index {
  @StorageProp('arkPilotBreakpoint')
  @Watch('onBreakpointChanged')
  currentBreakpoint: ArkPilotBreakpoint = 'sm';
  private readonly thinkingStatusPhrases: string[] = [
    '正在厘清问题',
    '正在读取上下文',
    '正在规划下一步',
    '正在组织回答'
  ];
  private readonly longThinkingStatusPhrases: string[] = [
    '摸鱼中',
    '泡咖啡中',
    '炒股中',
    '灵感加载中',
    '翻资料中',
    '灵感排队中',
    '给脑子预热中',
    '和 bug 讲道理中',
    '整理灵感碎片中'
  ];
  private readonly longThinkingPulseThreshold: number = 50;
  private readonly thinkingPhrasePulseSpan: number = 30;
  private readonly idleThinkingDelayMs: number = 3000;
  private readonly conversationFontScaleMin: number = 0.6;
  private readonly conversationFontScaleMax: number = 1.8;
  private readonly conversationFontScaleStep: number = 0.05;
  private readonly keyCodeMinus: number = 2057;
  private readonly keyCodeEquals: number = 2058;
  private readonly keyCodePlus: number = 2066;
  private readonly keyCodeNumpadSubtract: number = 2115;
  private readonly keyCodeNumpadAdd: number = 2116;
  private readonly keyCodeNumpadEquals: number = 2120;
  private readonly thinkingLogoFrames: string[] = [
    '◎>_',
    '◎>=',
    '◎>-',
    '◎>·'
  ];
  private readonly effortOptions: SelectorOption[] = [
    new SelectorOption('默认', 'default'),
    new SelectorOption('minimal', 'minimal'),
    new SelectorOption('low', 'low'),
    new SelectorOption('medium', 'medium'),
    new SelectorOption('high', 'high'),
    new SelectorOption('xhigh', 'xhigh')
  ];
  private backendSubscriptionId: number = -1;
  private reconnectTimerId: number = -1;
  private reconnectAttemptCount: number = 0;
  private thinkingTimerId: number = -1;
  private idleThinkingTimerId: number = -1;
  private lastTextOutputAt: number = 0;
  private lastTextOutputSignature: string = '';
  private readonly workspaceRoots: Map<number, string> = new Map();
  private readonly workspaceIds: Map<number, string> = new Map();
  private readonly workspaceUris: Map<number, string> = new Map();
  private readonly collaborationModeByWorkspaceId: Map<string, string> = new Map();
  private readonly requestUserInputDrafts: Map<string, string> = new Map();
  private readonly messageScroller: Scroller = new Scroller();

  @State private workspaces: WorkspaceItem[] = [];
  @State private activeWorkspaceId: number = 1;
  @State private activeWorkspaceBindingId: string = 'session:1';
  @State private backendActiveThreadId: string = '';
  @State private currentWorkspaceTitle: string = '新会话 1';
  @State private currentWorkspaceDescription: string = '等待通过 app-server 创建真实会话';
  @State private activeWorkspacePermissionState: WorkspacePermissionState = 'unavailable';
  @State private activeWorkspaceAccessKind: WorkspaceAccessKind = 'unknown';
  @State private workspaceStatusText: string = 'å°šæœªæ£€æµ‹å·¥ä½œåŒºæƒé™';
  @State private selectedEffortIndex: number = 0;
  @State private showEffortOptions: boolean = false;
  @State private collaborationModes: CollaborationModeOption[] = [];
  @State private selectedCollaborationModeName: string = 'default';
  @State private collaborationModeVersion: number = 0;
  @State private showCollaborationModeOptions: boolean = false;
  @State private serverUrl: string = 'ws://127.0.0.1:7456';
  @State private workspaceRoot: string = '';
  @State private workspaceDraftText: string = '';
  @State private workspaceSelectionText: string = '使用默认工作区';
  @State private providerBaseUrl: string = '';
  @State private providerApiKey: string = '';
  @State private manualModel: string = '';
  @State private providerStatusText: string = 'Provider config not loaded yet.';
  @State private providerName: string = '未选择';
  @State private isSavingProvider: boolean = false;
  @State private apiKey: string = '';
  @State private isAuthenticating: boolean = false;
  @State private authStatusText: string = '未登录';
  @State private connectionState: CodexConnectionState = 'disconnected';
  @State private connectionText: string = '未连接';
  @State private summaryTitle: string = '';
  @State private summaryPoints: string[] = [
    '应用启动时会自动拉起内置 Rust ArkPilot host。',
    '这里通过 libentry.so 同步调用原生桥接层，而不是本地 mock。',
    '发送消息后会刷新对话、计划和 diff。'
  ];
  @State private changedFiles: string = '尚未产生文件改动';
  @State private diffStat: string = '+0 -0';
  @State private diffFiles: CodeDiffFile[] = [];
  @State private selectedDiffFilePath: string = '';
  @State private rightPanelTab: RightPanelTab = 'diff';
  @State private browserPreviewSrc: string = '';
  @State private browserPreviewTitle: string = '';
  @State private browserPreviewError: string = '';
  @State private isRunning: boolean = false;
  @State private showLeftDrawer: boolean = true;
  @State private showRightDrawer: boolean = true;
  @State private leftPanelWidth: number = 280;
  @State private rightPanelWidth: number = 360;
  private leftScrollOffset: number = 0;
  private leftScrollController: Scroller = new Scroller();
  private browserPreviewController: webview.WebviewController = new webview.WebviewController();
  private readonly leftDrawerMinWidth: number = 100;
  private readonly rightDrawerMinWidth: number = 120;
  private readonly motionFastDuration: number = 160;
  private readonly motionNormalDuration: number = 240;
  private readonly motionPanelDuration: number = 280;
  private dragStartLeftW: number = 0;
  private dragStartRightW: number = 0;
  private leftHiding: boolean = false;
  private rightHiding: boolean = false;
  @State private recentWorkspaces: WorkspaceItem[] = [];
  @State private directoryFilter: string = '';
  @State private directoryFilterText: string = '使用默认工作区';
  @State private draft: string = '';
  private savedDraft: string = '';
  @State private pendingApproval: CodexApprovalRequest | null = null;
  @State private pendingRequestUserInput: CodexRequestUserInput | null = null;
  @State private requestUserInputVersion: number = 0;
  @State private expandedIntermediateMessageIds: string[] = [];
  @State private isTurnActivityCollapsed: boolean = true;
  @State private expandedCompactionIds: string[] = [];
  @State private selectableMessageIds: string[] = [];
  @State private hoveredMessageId: string = '';
  @State private conversationFontScale: number = 1;
  @State private mermaidScaleEntries: MermaidScaleEntry[] = [];
  @State private compactionNotices: CompactionNotice[] = [];
  @State private compactionNoticeVersion: number = 0;
  @State private currentTurnId: string = '';
  @State private currentTurnStatus: string = '';
  @State private thinkingPulseIndex: number = 0;
  @State private thinkingSessionId: number = 0;
  @State private thinkingNormalPhrase: string = '';
  @State private thinkingFunPhrase: string = '';
  @State private showIdleThinkingIndicator: boolean = false;
  @State private liveThinkingActive: boolean = false;
  @State private liveThinkingContent: string = '';
  @State private pendingUserPrompt: string = '';
  private thinkingMessageBoundary: number = -1;
  private liveThinkingReasoningSignature: string = '';
  private liveThinkingAssistantSignature: string = '';
  private thinkingNormalPhraseBucket: number = -1;
  private thinkingFunPhraseBucket: number = -1;
  @State private messageAutoFollowToBottom: boolean = true;
  private messageProgrammaticScroll: boolean = false;
  private messageProgrammaticScrollTimerId: number = -1;
  private messageScheduledScrollTimerId: number = -1;
  private messageScheduledFollowUpScrollTimerId: number = -1;
  private messageUserScrollActive: boolean = false;
  private messageUserScrollTimerId: number = -1;
  private messageZoomWheelActiveUntil: number = 0;
  @State private messages: ChatMessage[] = [
    new ChatMessage(
      'welcome-1',
      'ArkPilot',
      'assistant',
      '前端会自动连接应用内置 app-server。必要时你仍然可以手动重连或修改工作目录。',
      '刚刚'
    )
  ];
  @State private codeLines: CodeDiffLine[] = [
    new CodeDiffLine('placeholder-1', '1', ' ', '等待 turn/diff/updated 通知。', 'context')
  ];
  @State private tokenUsage: TurnTokenUsage | null = null;
  @State private tokenAggregate: TokenUsageAggregate | null = null;
  @State private tokenCardExpanded: boolean = true;
  @State private tokenCardHeight: number = 280;
  @State private tokenCardDragStartY: number = 0;
  @State private tokenCardDragStartH: number = 0;
  @State private tokenTab: number = 0;
  @State private tokenTrendRange: number = 0;
  @State private compacting: boolean = false;
  @State private compactError: string = '';
  private activeCompactionNoticeId: string = '';
  private compactionClearTimerId: number = -1;
  @State private projects: ProjectRecord[] = [];
  @State private newProjectName: string = '';
  @State private newProjectSourceUri: string = '';
  @State private renamingProjectId: string = '';
  @State private renameProjectText: string = '';
  @State private showAboutDialog: boolean = false;
  @State private newSessionProjectId: string = '';
  @State private newSessionName: string = '';
  @State private renamingSessionId: string = '';
  @State private renameSessionText: string = '';
  @State private hoveredProjectId: string = '';
  @State private hoveredSessionId: string = '';
  @State private hasPointerHover: boolean = false;
  @State private lastMenuTouchWindowX: number = 0;
  @State private lastMenuTouchWindowY: number = 0;
  @State private suppressProjectClickId: string = '';
  @State private suppressSessionClickId: string = '';
  @State private mouseNearRightEdge: boolean = false;
  @State private chatAreaWidth: number = 0;
  @State private showProjectMenuId: string = '';
  @State private showSessionMenuId: string = '';
  @State private floatingMenuX: number = 0;
  @State private floatingMenuY: number = 0;
  @State private floatingMenuWidth: number = 120;
  @State private renameSessionDialogText: string = '';
  @State private renameSessionDialogId: string = '';
  @State private deleteSessionDialogId: string = '';
  @State private deleteSessionDialogTitle: string = '';
  @State private renameProjectDialogText: string = '';
  @State private renameProjectDialogId: string = '';
  @State private deleteProjectDialogId: string = '';
  @State private deleteProjectDialogName: string = '';
  @State private lastAppliedBreakpoint: ArkPilotBreakpoint = 'sm';

  private createProjectDialogController: CustomDialogController | null = new CustomDialogController({
    builder: ArkPilotProjectCreateDialog({
      projectName: this.newProjectName,
      sourceUri: this.newProjectSourceUri,
      canSelectExternalFolder: () => this.canSelectExternalFolder(),
      chooseFolder: () => {
        void this.pickWorkspaceDirectoryForProject();
      },
      cancel: () => {
        this.cancelCreateProjectDialog();
      },
      confirm: () => {
        void this.createProject();
      }
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center,
    customStyle: false,
    cornerRadius: 24,
    maskColor: '#66000000',
    backgroundColor: '#FFFFFF',
    shadow: { radius: 24, color: '#26000000', offsetX: 0, offsetY: 8 },
    cancel: () => {
      this.cancelCreateProjectDialog();
    }
  });

  private newSessionDialogController: CustomDialogController | null = new CustomDialogController({
    builder: ArkPilotNameDialog({
      textValue: this.newSessionName,
      title: '新建会话',
      subtitle: '会话会创建在当前项目下。',
      placeholder: '输入会话名称',
      confirmText: '创建',
      cancel: () => {
        this.cancelNewSessionDialog();
      },
      confirm: () => {
        void this.confirmCreateSession();
      }
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center,
    customStyle: false,
    cornerRadius: 24,
    maskColor: '#66000000',
    backgroundColor: '#FFFFFF',
    shadow: { radius: 24, color: '#26000000', offsetX: 0, offsetY: 8 },
    cancel: () => {
      this.cancelNewSessionDialog();
    }
  });

  private renameProjectDialogController: CustomDialogController | null = new CustomDialogController({
    builder: ArkPilotNameDialog({
      textValue: this.renameProjectDialogText,
      title: '重命名项目',
      placeholder: '输入项目名称',
      confirmText: '确认',
      cancel: () => {
        this.cancelRenameProjectDialog();
      },
      confirm: () => {
        this.confirmRenameProjectDialog();
      }
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center,
    customStyle: false,
    cornerRadius: 24,
    maskColor: '#66000000',
    backgroundColor: '#FFFFFF',
    shadow: { radius: 24, color: '#26000000', offsetX: 0, offsetY: 8 },
    cancel: () => {
      this.cancelRenameProjectDialog();
    }
  });

  private deleteProjectDialogController: CustomDialogController | null = new CustomDialogController({
    builder: ArkPilotDeleteDialog({
      targetName: this.deleteProjectDialogName,
      title: '删除项目',
      targetType: '项目',
      description: '项目下的会话会一并从侧边栏移除。',
      cancel: () => {
        this.cancelDeleteProjectDialog();
      },
      confirm: () => {
        this.confirmDeleteProjectDialog();
      }
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center,
    customStyle: false,
    cornerRadius: 24,
    maskColor: '#66000000',
    backgroundColor: '#FFFFFF',
    shadow: { radius: 24, color: '#26000000', offsetX: 0, offsetY: 8 },
    cancel: () => {
      this.cancelDeleteProjectDialog();
    }
  });

  private renameSessionDialogController: CustomDialogController | null = new CustomDialogController({
    builder: ArkPilotNameDialog({
      textValue: this.renameSessionDialogText,
      title: '重命名会话',
      placeholder: '输入会话名称',
      confirmText: '确认',
      cancel: () => {
        this.cancelRenameSessionDialog();
      },
      confirm: () => {
        this.confirmRenameSessionDialog();
      }
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center,
    customStyle: false,
    cornerRadius: 24,
    maskColor: '#66000000',
    backgroundColor: '#FFFFFF',
    shadow: { radius: 24, color: '#26000000', offsetX: 0, offsetY: 8 },
    cancel: () => {
      this.cancelRenameSessionDialog();
    }
  });

  private deleteSessionDialogController: CustomDialogController | null = new CustomDialogController({
    builder: ArkPilotDeleteDialog({
      targetName: this.deleteSessionDialogTitle,
      title: '删除会话',
      targetType: '会话',
      description: '删除后会话将从列表中移除。',
      cancel: () => {
        this.cancelDeleteSessionDialog();
      },
      confirm: () => {
        this.confirmDeleteSessionDialog();
      }
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center,
    customStyle: false,
    cornerRadius: 24,
    maskColor: '#66000000',
    backgroundColor: '#FFFFFF',
    shadow: { radius: 24, color: '#26000000', offsetX: 0, offsetY: 8 },
    cancel: () => {
      this.cancelDeleteSessionDialog();
    }
  });

  aboutToAppear(): void {
    const mediaQuery = this.getUIContext().getMediaQuery();
    breakpointManager.initialize((condition: string) => mediaQuery.matchMediaSync(condition));
    this.applyResponsiveLayoutProfile(true);

    this.backendSubscriptionId = codexBackend.subscribe((snapshot: CodexBackendSnapshot) => {
      this.applyBackendSnapshot(snapshot);
    });
    this.applyBackendSnapshot(codexBackend.snapshot());
    this.applyEmbeddedHostStatus();
    this.loadProviderConfig();
    this.restoreWorkspaceBindings();
    this.loadProjects();

    void this.restoreSessionsFromBackend();

    this.scheduleEmbeddedHostReconnect(2000);
    this.scheduleMessageScrollToBottom();
  }

  aboutToDisappear(): void {
    if (this.backendSubscriptionId >= 0) {
      codexBackend.unsubscribe(this.backendSubscriptionId);
    }
    this.clearReconnectTimer();
    this.stopThinkingAnimation();
    this.clearIdleThinkingTimer();
    this.clearCompactionClearTimer();
    this.clearMessageScheduledScrollTimers();
    this.clearMessageProgrammaticScrollTimer();
    this.clearMessageUserScrollTimer();
  }

  private applyBackendSnapshot(snapshot: CodexBackendSnapshot): void {
    hilog.info(0x0001, 'ArkPilot', `applyBackendSnapshot: conn=${snapshot.connectionState} modes=${snapshot.collaborationModes.length} selected=${this.selectedCollaborationModeName}`);
    this.serverUrl = snapshot.serverUrl;
    this.connectionState = snapshot.connectionState;
    this.connectionText = snapshot.connectionText;
    this.pendingApproval = snapshot.pendingApproval;
    const previousRequestId: string = this.pendingRequestUserInput !== null ? `${this.pendingRequestUserInput.requestId}` : '';
    const nextRequestId: string = snapshot.pendingRequestUserInput !== null ? `${snapshot.pendingRequestUserInput.requestId}` : '';
    this.pendingRequestUserInput = snapshot.pendingRequestUserInput;
    this.collaborationModes = snapshot.collaborationModes;
    if (previousRequestId !== nextRequestId) {
      this.requestUserInputDrafts.clear();
      this.requestUserInputVersion += 1;
    }
    this.syncSelectedCollaborationMode();
    this.backendActiveThreadId = snapshot.activeThreadId.trim();
    this.tokenUsage = snapshot.tokenUsage;
    this.applyCompactionSnapshot(snapshot);
    if (codexBackend.shouldStartFallbackCompaction(this.backendActiveThreadId)) {
      this.retryCurrentCompaction(this.backendActiveThreadId);
    }
  }

  private applyCompactionSnapshot(snapshot: CodexBackendSnapshot): void {
    const compaction = snapshot.compaction;
    const hadError: boolean = this.compactError.length > 0;
    const wasCompacting: boolean = this.compacting;
    const isCurrentThread: boolean = this.isCurrentCompactionThreadId(compaction.threadId);
    const nextCompacting: boolean = isCurrentThread && (compaction.status === 'starting' || compaction.status === 'running');
    this.compacting = nextCompacting;
    if (compaction.status === 'idle') {
      this.compactError = '';
      return;
    }
    if (compaction.threadId.trim().length > 0) {
      this.upsertCompactionNotice(
        compaction.threadId,
        compaction.status,
        compaction.errorMessage,
        compaction.savedTokens,
        compaction.oldTotalTokens,
        compaction.newTotalTokens
      );
    }
    if (!isCurrentThread) {
      this.compactError = '';
      return;
    }
    if (compaction.status === 'failed' || compaction.status === 'timeout') {
      this.compactError = compaction.errorMessage;
      return;
    }
    if (compaction.status === 'completed') {
      this.compactError = '';
      if (wasCompacting || hadError) {
        if (compaction.savedTokens > 0) {
          promptAction.showToast({ message: `压缩完成，释放 ${this.formatTokenCount(compaction.savedTokens)} tokens`, duration: 3000 });
        } else {
          promptAction.showToast({ message: '压缩完成', duration: 2000 });
        }
      }
      this.scheduleBackendCompactionClear(compaction.threadId);
      return;
    }
    if (!nextCompacting) {
      this.compactError = '';
    }
  }

  private upsertCompactionNotice(
    threadId: string,
    status: string,
    errorMessage: string,
    savedTokens: number,
    oldTotalTokens: number,
    newTotalTokens: number
  ): void {
    const noticeId: string = `compaction:${threadId}`;
    const previous: CompactionNotice | null = this.compactionNoticeById(noticeId);
    const isNewRun: boolean = previous === null || (this.isTerminalCompactionStatus(previous.status) && (status === 'starting' || status === 'running'));
    const effectiveOldTotal: number = oldTotalTokens > 0
      ? oldTotalTokens
      : (!isNewRun && previous !== null ? previous.oldTotalTokens : 0);
    const effectiveNewTotal: number = newTotalTokens > 0
      ? newTotalTokens
      : (!isNewRun && previous !== null ? previous.newTotalTokens : 0);
    const computedSaved: number = effectiveOldTotal > 0 && effectiveNewTotal > 0 && effectiveOldTotal > effectiveNewTotal
      ? effectiveOldTotal - effectiveNewTotal
      : 0;
    const effectiveSaved: number = savedTokens > 0
      ? savedTokens
      : (computedSaved > 0 ? computedSaved : (!isNewRun && previous !== null ? previous.savedTokens : 0));
    const next = new CompactionNotice(
      noticeId,
      threadId,
      status,
      errorMessage,
      effectiveSaved,
      effectiveOldTotal,
      effectiveNewTotal,
      isNewRun || previous === null ? this.currentClockLabel() : previous.timestamp
    );
    this.compactionNotices = [
      ...this.compactionNotices.filter((item: CompactionNotice) => item.id !== noticeId),
      next
    ];
    this.activeCompactionNoticeId = noticeId;
    this.compactionNoticeVersion += 1;
    this.scheduleMessageScrollToBottom();
  }

  private isTerminalCompactionStatus(status: string): boolean {
    return status === 'completed' || status === 'failed' || status === 'timeout';
  }

  private currentCompactionThreadIds(): string[] {
    const threadIds: string[] = [];
    this.pushUniqueCompactionThreadId(threadIds, this.activeWorkspaceBindingId);
    this.pushUniqueCompactionThreadId(threadIds, this.backendActiveThreadId);
    const workspace: WorkspaceItem | undefined = this.activeWorkspace();
    if (workspace !== undefined) {
      this.pushUniqueCompactionThreadId(threadIds, workspace.workspaceId);
    }
    return threadIds;
  }

  private pushUniqueCompactionThreadId(threadIds: string[], threadId: string): void {
    const trimmedThreadId: string = threadId.trim();
    if (trimmedThreadId.length === 0 || threadIds.indexOf(trimmedThreadId) >= 0) {
      return;
    }
    threadIds.push(trimmedThreadId);
  }

  private isCurrentCompactionThreadId(threadId: string): boolean {
    const trimmedThreadId: string = threadId.trim();
    if (trimmedThreadId.length === 0) {
      return false;
    }
    return this.currentCompactionThreadIds().indexOf(trimmedThreadId) >= 0;
  }

  private latestActiveCompactionNotice(): CompactionNotice | null {
    this.compactionNoticeVersion;
    const threadIds: string[] = this.currentCompactionThreadIds();
    if (threadIds.length === 0) {
      return this.activeCompactionNoticeById();
    }
    for (let index: number = this.compactionNotices.length - 1; index >= 0; index -= 1) {
      if (threadIds.indexOf(this.compactionNotices[index].threadId) >= 0) {
        return this.compactionNotices[index];
      }
    }
    return this.activeCompactionNoticeById();
  }

  private activeCompactionNoticeById(): CompactionNotice | null {
    if (this.activeCompactionNoticeId.length === 0) {
      return null;
    }
    return this.compactionNoticeById(this.activeCompactionNoticeId);
  }

  private scheduleBackendCompactionClear(threadId: string): void {
    this.clearCompactionClearTimer();
    this.compactionClearTimerId = setTimeout(() => {
      codexBackend.clearCompactionNotice(threadId);
      this.compactionClearTimerId = -1;
    }, 800);
  }

  private clearCompactionClearTimer(): void {
    if (this.compactionClearTimerId >= 0) {
      clearTimeout(this.compactionClearTimerId);
      this.compactionClearTimerId = -1;
    }
  }

  private compactionNoticeById(id: string): CompactionNotice | null {
    for (let index: number = 0; index < this.compactionNotices.length; index += 1) {
      if (this.compactionNotices[index].id === id) {
        return this.compactionNotices[index];
      }
    }
    return null;
  }

  private currentClockLabel(): string {
    const date: Date = new Date();
    const hours: string = date.getHours().toString().padStart(2, '0');
    const minutes: string = date.getMinutes().toString().padStart(2, '0');
    return `${hours}:${minutes}`;
  }

  private async applyEmbeddedHostStatus(): Promise<void> {
    const hostStatus = await getEmbeddedCodexHostStatusAsync();
    if (hostStatus.serverUrl.trim().length > 0) {
      this.serverUrl = hostStatus.serverUrl;
    }

    if (hostStatus.running) {
      this.summaryTitle = '应用内后端已启动';
      this.summaryPoints = [
        hostStatus.message,
        '页面会自动尝试连接本地 原生桥接 服务。',
        '如果需要调试，也可以手动断开后重新连接。'
      ];
      return;
    }

    if (hostStatus.message.trim().length > 0) {
      this.summaryTitle = '应用内后端未就绪';
      this.summaryPoints = [
        hostStatus.message,
        '可以稍后点击连接重试。',
        '如果持续失败，需要检查 native/Rust 构建产物是否被正确打包。'
      ];
    }
  }

  private clearReconnectTimer(): void {
    if (this.reconnectTimerId >= 0) {
      clearTimeout(this.reconnectTimerId);
      this.reconnectTimerId = -1;
    }
  }

  private scheduleEmbeddedHostReconnect(delayMs: number): void {
    this.clearReconnectTimer();
    this.reconnectTimerId = setTimeout(() => {
      this.reconnectTimerId = -1;
      void this.connectEmbeddedHost();
    }, delayMs);
  }

  private activeWorkspace(): WorkspaceItem | undefined {
    if (this.workspaces.length === 0) {
      return undefined;
    }
    for (let index: number = 0; index < this.workspaces.length; index += 1) {
      if (this.workspaces[index].id === this.activeWorkspaceId) {
        return this.workspaces[index];
      }
    }
    return this.workspaces[0];
  }

  private syncCurrentWorkspaceState(): void {
    const workspace: WorkspaceItem | undefined = this.activeWorkspace();
    if (workspace === undefined) {
      this.currentWorkspaceTitle = '';
      this.currentWorkspaceDescription = '';
      return;
    }
    this.currentWorkspaceTitle = workspace.title;
    this.currentWorkspaceDescription = workspace.description;
  }

  private syncRecentWorkspaces(): void {
    const filter = this.directoryFilter.trim();
    if (filter.length === 0) {
      this.recentWorkspaces = [...this.workspaces].reverse();
      return;
    }
    const filtered = this.workspaces.filter((item: WorkspaceItem) => {
      const root = this.workspaceRoots.get(item.id) ?? '';
      return root.trim().length === 0 || root.trim() === filter;
    });
    this.recentWorkspaces = [...filtered].reverse();
  }

  private ensureWorkspaceBinding(item: WorkspaceItem): string {
    const existing: string | undefined = this.workspaceIds.get(item.id);
    if (existing !== undefined && existing.trim().length > 0) {
      item.workspaceId = existing;
      return existing;
    }
    const workspaceId: string = item.workspaceId.trim().length > 0 ? item.workspaceId : `session:${item.id.toString()}`;
    item.workspaceId = workspaceId;
    this.workspaceIds.set(item.id, workspaceId);
    return workspaceId;
  }

  private refreshWorkspaceBindingState(): void {
    if (this.workspaces.length === 0) {
      this.activeWorkspaceBindingId = '';
      this.activeWorkspacePermissionState = 'unavailable';
      this.activeWorkspaceAccessKind = 'unknown';
      this.workspaceStatusText = '';
      return;
    }
    const active: WorkspaceItem = this.activeWorkspace()!;
    this.activeWorkspaceBindingId = this.ensureWorkspaceBinding(active);
    const currentWorkspaceRoot: string = this.workspaceDraftText.trim().length > 0 ? this.workspaceDraftText.trim() : this.workspaceRoot.trim();
    if (currentWorkspaceRoot.length > 0) {
      const status: WorkspaceAccessStatus = checkWorkspaceAccess(currentWorkspaceRoot);
      this.activeWorkspacePermissionState = this.mapWorkspacePermissionState(status.permissionState);
      this.activeWorkspaceAccessKind = this.mapWorkspaceAccessKind(status.accessKind);
      this.workspaceStatusText = status.message.trim().length > 0 ? status.message : 'å·¥ä½œåŒºå·²é…ç½®';
      return;
    }
    this.activeWorkspacePermissionState = 'unavailable';
    this.activeWorkspaceAccessKind = 'unknown';
    this.workspaceStatusText = 'å½“å‰æœªé…ç½®å·¥ä½œåŒº';
  }

  private nextWorkspaceId(): number {
    let nextId: number = this.activeWorkspaceId > 0 ? this.activeWorkspaceId + 1 : 1;
    for (let index: number = 0; index < this.workspaces.length; index += 1) {
      if (this.workspaces[index].id >= nextId) {
        nextId = this.workspaces[index].id + 1;
      }
    }
    this.workspaceIds.forEach((_workspaceId: string, key: number) => {
      if (key >= nextId) {
        nextId = key + 1;
      }
    });
    return nextId;
  }

  private isRemoteThreadId(workspaceId: string): boolean {
    const trimmedWorkspaceId: string = workspaceId.trim();
    return trimmedWorkspaceId.length > 0 && !trimmedWorkspaceId.startsWith('session:');
  }

  private workspaceDescriptionFromSummary(summary: SessionSummary): string {
    const changedFiles: string = summary.changedFiles.trim();
    if (changedFiles.length > 0 && changedFiles !== '尚未产生文件改动') {
      return changedFiles;
    }
    const summaryTitle: string = summary.summaryTitle.trim();
    if (summaryTitle.length > 0) {
      return summaryTitle;
    }
    return '已从 app-server 恢复的历史会话';
  }

  private resetConversationSurface(title: string, points?: string[]): void {
    this.messages = [
      new ChatMessage(
        'welcome-1',
        'ArkPilot',
        'assistant',
        '前端会自动连接应用内置 app-server。必要时你仍然可以手动重连或修改工作目录。',
        '刚刚'
      )
    ];
    this.codeLines = [
      new CodeDiffLine('placeholder-1', '1', ' ', '等待 turn/diff/updated 通知。', 'context')
    ];
    this.diffFiles = [];
    this.selectedDiffFilePath = '';
    this.summaryTitle = title;
    this.summaryPoints = points ?? ['当前会话尚未产生历史消息。'];
    this.changedFiles = '尚未产生文件改动';
    this.diffStat = '+0 -0';
    this.currentTurnId = '';
    this.expandedCompactionIds = [];
    this.clearLiveThinking();
    this.resumeMessageAutoFollow();
    this.scheduleMessageScrollToBottom(true);
  }

  private async restoreSessionsFromBackend(preferredThreadId?: string): Promise<void> {
    const sessions: SessionSummary[] = await codexBackend.loadPersistedSessions();
    this.applySessionSummariesToWorkspaces(sessions, preferredThreadId);
    await this.loadSelectedWorkspaceHistory();
  }

  private syncSessionSummariesFromCache(preferredThreadId?: string): void {
    const sessions: SessionSummary[] = codexBackend.sessionSummaries();
    this.applySessionSummariesToWorkspaces(sessions, preferredThreadId);
  }

  private applySessionSummariesToWorkspaces(summaries: SessionSummary[], preferredThreadId?: string): void {
    if (summaries.length === 0) {
      if (this.workspaces.length === 0) {
        this.activeWorkspaceId = 0;
        this.workspaceRoot = '';
        this.workspaceDraftText = '';
        this.currentWorkspaceTitle = '';
        this.currentWorkspaceDescription = '';
      }
      this.syncRecentWorkspaces();
      this.syncWorkspaceSelectionText();
      this.refreshWorkspaceBindingState();
      this.syncCurrentWorkspaceState();
      this.persistWorkspaceBindings();
      return;
    }

    const currentWorkspaceByThreadId: Map<string, WorkspaceItem> = new Map();
    for (let index: number = 0; index < this.workspaces.length; index += 1) {
      const workspace: WorkspaceItem = this.workspaces[index];
      if (this.isRemoteThreadId(workspace.workspaceId)) {
        currentWorkspaceByThreadId.set(workspace.workspaceId, workspace);
      }
    }

    const bindingSnapshot = workspaceBindingStore.load();
    const bindingByThreadId: Map<string, StoredWorkspaceItem> = new Map();
    for (let index: number = 0; index < bindingSnapshot.items.length; index += 1) {
      const item: StoredWorkspaceItem = bindingSnapshot.items[index];
      if (this.isRemoteThreadId(item.workspaceId)) {
        bindingByThreadId.set(item.workspaceId, item);
      }
    }

    const activeWorkspace: WorkspaceItem | undefined = this.activeWorkspace();
    const activePlaceholderId: number = activeWorkspace !== undefined && !this.isRemoteThreadId(activeWorkspace.workspaceId) ? activeWorkspace.id : 0;
    const nextWorkspaces: WorkspaceItem[] = [];
    const nextWorkspaceIds: Map<number, string> = new Map();
    const nextWorkspaceRoots: Map<number, string> = new Map();
    const nextWorkspaceUris: Map<number, string> = new Map();
    const usedIds: Set<number> = new Set();
    const newProjects: ProjectRecord[] = [];
    let nextIdSeed: number = this.nextWorkspaceId();
    let nextActiveWorkspaceId: number = 0;

    for (let index: number = 0; index < summaries.length; index += 1) {
      const summary: SessionSummary = summaries[index];
      let workspaceId: number | undefined = currentWorkspaceByThreadId.get(summary.sessionId)?.id;
      if (workspaceId === undefined) {
        workspaceId = bindingByThreadId.get(summary.sessionId)?.id;
      }
      if (workspaceId === undefined && preferredThreadId !== undefined && summary.sessionId === preferredThreadId && activePlaceholderId > 0) {
        workspaceId = activePlaceholderId;
      }
      while (workspaceId === undefined || usedIds.has(workspaceId)) {
        workspaceId = nextIdSeed;
        nextIdSeed += 1;
      }
      usedIds.add(workspaceId);

      const workspace: WorkspaceItem = new WorkspaceItem(
        workspaceId,
        summary.title,
        this.workspaceDescriptionFromSummary(summary),
        summary.sessionId
      );
      nextWorkspaces.push(workspace);
      nextWorkspaceIds.set(workspace.id, summary.sessionId);

      const existingRoot: string = this.workspaceRoots.get(workspace.id) ?? bindingByThreadId.get(summary.sessionId)?.workspaceRoot ?? '';
      const nextRoot: string = existingRoot.trim().length > 0 ? existingRoot : summary.workspaceRoot.trim();
      nextWorkspaceRoots.set(workspace.id, nextRoot);
      nextWorkspaceUris.set(workspace.id, this.workspaceUris.get(workspace.id) ?? bindingByThreadId.get(summary.sessionId)?.workspaceUri ?? '');

      // Assign project by matching session root to project path
      const sessionRoot: string = nextRoot.trim();
      if (sessionRoot.length > 0) {
        let matchedProject: ProjectRecord | undefined = undefined;
        for (let pi: number = 0; pi < this.projects.length; pi += 1) {
          if (this.projects[pi].path.trim() === sessionRoot) {
            matchedProject = this.projects[pi];
            break;
          }
        }
        if (matchedProject !== undefined) {
          workspace.projectId = matchedProject.id;
        } else if (!projectStore.isDeletedPath(sessionRoot)) {
          const projId: string = `proj_${Date.now().toString()}_${index.toString()}`;
          const projName: string = sessionRoot.substring(sessionRoot.lastIndexOf('/') + 1);
          const newProj: ProjectRecord = new ProjectRecord(projId, projName.length > 0 ? projName : sessionRoot, sessionRoot, true);
          newProjects.push(newProj);
          workspace.projectId = projId;
        }
      }

      if (summary.sessionId === preferredThreadId || (nextActiveWorkspaceId === 0 && summary.sessionId === this.activeWorkspaceBindingId)) {
        nextActiveWorkspaceId = workspace.id;
      }
    }

    // Preserve manually created workspaces that have local session IDs
    for (let index: number = 0; index < this.workspaces.length; index += 1) {
      const ws: WorkspaceItem = this.workspaces[index];
      if (!this.isRemoteThreadId(ws.workspaceId) && !usedIds.has(ws.id)) {
        usedIds.add(ws.id);
        nextWorkspaces.push(ws);
        nextWorkspaceIds.set(ws.id, ws.workspaceId);
        const preservedRoot: string = this.workspaceRoots.get(ws.id) ?? '';
        nextWorkspaceRoots.set(ws.id, preservedRoot);
        nextWorkspaceUris.set(ws.id, this.workspaceUris.get(ws.id) ?? '');
      }
    }

    if (nextActiveWorkspaceId === 0) {
      const matched: WorkspaceItem | undefined = nextWorkspaces.find((item: WorkspaceItem) => item.id === this.activeWorkspaceId);
      nextActiveWorkspaceId = matched?.id ?? nextWorkspaces[0].id;
    }

    this.workspaces = [...nextWorkspaces];
    if (newProjects.length > 0) {
      this.projects = [...this.projects, ...newProjects];
    }
    this.saveProjects();
    this.syncRecentWorkspaces();
    this.workspaceIds.clear();
    this.workspaceRoots.clear();
    this.workspaceUris.clear();
    nextWorkspaceIds.forEach((value: string, key: number) => this.workspaceIds.set(key, value));
    nextWorkspaceRoots.forEach((value: string, key: number) => this.workspaceRoots.set(key, value));
    nextWorkspaceUris.forEach((value: string, key: number) => this.workspaceUris.set(key, value));
    this.activeWorkspaceId = nextActiveWorkspaceId;
    this.syncSelectedCollaborationMode();
    this.workspaceRoot = this.workspaceRoots.get(this.activeWorkspaceId) ?? '';
    this.workspaceDraftText = this.workspaceRoot;
    this.syncWorkspaceSelectionText();
    this.refreshWorkspaceBindingState();
    this.syncCurrentWorkspaceState();
    this.persistWorkspaceBindings();
  }

  private async loadSelectedWorkspaceHistory(): Promise<void> {
    this.resumeMessageAutoFollow();
    this.clearLiveThinking();
    if (this.workspaces.length === 0) {
      codexBackend.setActiveThread('');
      this.resetConversationSurface('当前目录下暂无会话', ['请先创建一个新会话。']);
      return;
    }
    const workspace: WorkspaceItem = this.activeWorkspace()!;
    if (!this.isRemoteThreadId(workspace.workspaceId)) {
      codexBackend.setActiveThread('');
      this.resetConversationSurface('等待创建新会话', ['当前会话尚未在 app-server 中创建，发送第一条消息后会自动建立线程。']);
      return;
    }
    codexBackend.setActiveThread(workspace.workspaceId);
    try {
      const result: CodexTurnResult = await codexBackend.loadThreadHistory(workspace.workspaceId);
      this.applyBackendResult(result);
    } catch (err) {
      this.summaryTitle = '恢复会话失败';
      this.summaryPoints = [this.describeError(err)];
    }
  }

  private syncWorkspaceWithRemoteThreadId(remoteThreadId: string): void {
    const trimmedThreadId: string = remoteThreadId.trim();
    if (trimmedThreadId.length === 0 || this.workspaces.length === 0) {
      return;
    }
    const workspace: WorkspaceItem | undefined = this.activeWorkspace();
    if (workspace === undefined) {
      return;
    }
    workspace.workspaceId = trimmedThreadId;
    this.workspaceIds.set(workspace.id, trimmedThreadId);
    this.activeWorkspaceBindingId = trimmedThreadId;
    codexBackend.setActiveThread(trimmedThreadId);
    this.persistWorkspaceBindings();
  }

  private restoreWorkspaceBindings(): void {
    const snapshot = workspaceBindingStore.load();
    const restoredItems: WorkspaceBindingDraft[] = [];
    this.workspaceIds.clear();
    this.workspaceRoots.clear();
    this.workspaceUris.clear();
    this.workspaces = [];
    for (let index: number = 0; index < snapshot.items.length; index += 1) {
      const item = snapshot.items[index];
      if (item.id <= 0) {
        continue;
      }
      restoredItems.push(new WorkspaceBindingDraft(
        item.id,
        item.title.trim().length > 0 ? item.title : `ä¼šè¯ ${item.id}`,
        item.description,
        item.workspaceId.trim().length > 0 ? item.workspaceId : `session:${item.id.toString()}`,
        item.workspaceRoot,
        item.workspaceUri,
        item.projectId
      ));
    }

    if (restoredItems.length === 0) {
      this.workspaces = [];
      this.activeWorkspaceId = 0;
      this.workspaceRoot = '';
      this.workspaceDraftText = '';
      this.currentWorkspaceTitle = '';
      this.currentWorkspaceDescription = '';
      this.syncWorkspaceSelectionText();
      this.syncCurrentWorkspaceState();
      this.persistWorkspaceBindings();
      return;
    }

    const restoredWorkspaces: WorkspaceItem[] = [];
    for (let index: number = 0; index < restoredItems.length; index += 1) {
      const restored: WorkspaceBindingDraft = restoredItems[index];
      const workspace: WorkspaceItem = new WorkspaceItem(restored.id, restored.title, restored.description, restored.workspaceId, restored.projectId);
      restoredWorkspaces.push(workspace);
      this.workspaceIds.set(restored.id, restored.workspaceId);
      this.workspaceRoots.set(restored.id, restored.workspaceRoot);
      this.workspaceUris.set(restored.id, restored.workspaceUri);
    }
    this.workspaces = restoredWorkspaces;
    this.syncRecentWorkspaces();

    const preferredActiveId: number = snapshot.activeWorkspaceId > 0 ? snapshot.activeWorkspaceId : restoredItems[0].id;
    const matched: WorkspaceItem | undefined = this.workspaces.find((item: WorkspaceItem) => item.id === preferredActiveId);
    this.activeWorkspaceId = matched?.id ?? this.workspaces[0].id;
    this.syncSelectedCollaborationMode();
    this.workspaceRoot = this.workspaceRoots.get(this.activeWorkspaceId) ?? '';
    this.workspaceDraftText = this.workspaceRoot;
    this.syncWorkspaceSelectionText();
    this.refreshWorkspaceBindingState();
    this.syncCurrentWorkspaceState();
  }

  private persistWorkspaceBindings(): void {
    const items: StoredWorkspaceItem[] = [];
    for (let index: number = 0; index < this.workspaces.length; index += 1) {
      const workspace: WorkspaceItem = this.workspaces[index];
      const item: StoredWorkspaceItem = new StoredWorkspaceItem();
      item.id = workspace.id;
      item.title = workspace.title;
      item.description = workspace.description;
      item.workspaceId = this.ensureWorkspaceBinding(workspace);
      item.workspaceRoot = this.workspaceRoots.get(workspace.id) ?? '';
      item.workspaceUri = this.workspaceUris.get(workspace.id) ?? '';
      item.projectId = workspace.projectId;
      items.push(item);
    }
    workspaceBindingStore.saveBindings(this.activeWorkspaceId, items);
  }

  // ── Project management ──────────────────────────────────────────

  private loadProjects(): void {
    this.projects = projectStore.load();
  }

  private saveProjects(): void {
    projectStore.save(this.projects);
  }

  private openCreateProjectDialog(): void {
    this.newProjectName = '';
    this.newProjectSourceUri = '';
    this.showProjectMenuId = '';
    this.showSessionMenuId = '';
    if (this.createProjectDialogController !== null) {
      this.createProjectDialogController.open();
    }
  }

  private cancelCreateProjectDialog(): void {
    this.newProjectSourceUri = '';
  }

  private closeCreateProjectDialog(): void {
    if (this.createProjectDialogController !== null) {
      this.createProjectDialogController.close();
    }
  }

  private cancelNewSessionDialog(): void {
    this.newSessionProjectId = '';
    this.newSessionName = '';
  }

  private closeNewSessionDialog(): void {
    if (this.newSessionDialogController !== null) {
      this.newSessionDialogController.close();
    }
  }

  private openRenameProjectDialog(proj: ProjectRecord): void {
    this.renameProjectDialogId = proj.id;
    this.renameProjectDialogText = proj.name;
    if (this.renameProjectDialogController !== null) {
      this.renameProjectDialogController.open();
    }
  }

  private cancelRenameProjectDialog(): void {
    this.renameProjectDialogId = '';
    this.renameProjectDialogText = '';
  }

  private confirmRenameProjectDialog(): void {
    const name: string = this.renameProjectDialogText.trim();
    if (name.length === 0 || this.renameProjectDialogId.length === 0) {
      promptAction.showToast({ message: '请输入项目名称', duration: 2000 });
      return;
    }
    const targetId: string = this.renameProjectDialogId;
    const next: ProjectRecord[] = [];
    for (let i: number = 0; i < this.projects.length; i += 1) {
      const p: ProjectRecord = this.projects[i];
      if (p.id === targetId) {
        next.push(new ProjectRecord(p.id, name, p.path, p.expanded, p.sourceUri));
      } else {
        next.push(new ProjectRecord(p.id, p.name, p.path, p.expanded, p.sourceUri));
      }
    }
    this.projects = next;
    this.saveProjects();
    this.cancelRenameProjectDialog();
    if (this.renameProjectDialogController !== null) {
      this.renameProjectDialogController.close();
    }
  }

  private openDeleteProjectDialog(proj: ProjectRecord): void {
    this.deleteProjectDialogId = proj.id;
    this.deleteProjectDialogName = proj.name;
    if (this.deleteProjectDialogController !== null) {
      this.deleteProjectDialogController.open();
    }
  }

  private cancelDeleteProjectDialog(): void {
    this.deleteProjectDialogId = '';
    this.deleteProjectDialogName = '';
  }

  private confirmDeleteProjectDialog(): void {
    const targetId: string = this.deleteProjectDialogId;
    if (targetId.length === 0) {
      return;
    }
    this.cancelDeleteProjectDialog();
    if (this.deleteProjectDialogController !== null) {
      this.deleteProjectDialogController.close();
    }
    void this.deleteProject(targetId);
  }

  private openRenameSessionDialog(item: WorkspaceItem): void {
    this.renameSessionDialogId = this.ensureWorkspaceBinding(item);
    this.renameSessionDialogText = item.title;
    if (this.renameSessionDialogController !== null) {
      this.renameSessionDialogController.open();
    }
  }

  private cancelRenameSessionDialog(): void {
    this.renameSessionDialogId = '';
    this.renameSessionDialogText = '';
  }

  private confirmRenameSessionDialog(): void {
    const name: string = this.renameSessionDialogText.trim();
    if (name.length === 0 || this.renameSessionDialogId.length === 0) {
      promptAction.showToast({ message: '请输入会话名称', duration: 2000 });
      return;
    }
    const targetId: string = this.renameSessionDialogId;
    const next: WorkspaceItem[] = [];
    for (let i: number = 0; i < this.workspaces.length; i += 1) {
      const w: WorkspaceItem = this.workspaces[i];
      if (this.ensureWorkspaceBinding(w) === targetId) {
        next.push(new WorkspaceItem(w.id, name, w.description, w.workspaceId, w.projectId));
      } else {
        next.push(new WorkspaceItem(w.id, w.title, w.description, w.workspaceId, w.projectId));
      }
    }
    this.workspaces = next;
    this.syncRecentWorkspaces();
    this.syncCurrentWorkspaceState();
    this.persistWorkspaceBindings();
    this.cancelRenameSessionDialog();
    if (this.renameSessionDialogController !== null) {
      this.renameSessionDialogController.close();
    }
    void codexBackend.renameSession(targetId, name);
  }

  private openDeleteSessionDialog(item: WorkspaceItem): void {
    this.deleteSessionDialogId = this.ensureWorkspaceBinding(item);
    this.deleteSessionDialogTitle = item.title;
    if (this.deleteSessionDialogController !== null) {
      this.deleteSessionDialogController.open();
    }
  }

  private cancelDeleteSessionDialog(): void {
    this.deleteSessionDialogId = '';
    this.deleteSessionDialogTitle = '';
  }

  private confirmDeleteSessionDialog(): void {
    const targetId: string = this.deleteSessionDialogId;
    if (targetId.length === 0) {
      return;
    }
    this.cancelDeleteSessionDialog();
    if (this.deleteSessionDialogController !== null) {
      this.deleteSessionDialogController.close();
    }
    void this.deleteSession(targetId);
  }

  private sessionsForProject(projectId: string): WorkspaceItem[] {
    const result: WorkspaceItem[] = [];
    for (let i: number = 0; i < this.workspaces.length; i += 1) {
      if (this.workspaces[i].projectId === projectId) {
        result.push(this.workspaces[i]);
      }
    }
    return result;
  }

  private async createProject(): Promise<void> {
    const name: string = this.newProjectName.trim();
    if (name.length === 0) {
      promptAction.showToast({ message: '请输入项目名称', duration: 2000 });
      return;
    }
    const path: string = this.sandboxProjectPath();
    const sourceUri: string = this.newProjectSourceUri.trim();
    const id: string = `proj_${Date.now().toString()}`;
    const next: ProjectRecord[] = [...this.projects, new ProjectRecord(id, name, path, true, sourceUri)];
    this.projects = next;
    this.saveProjects();
    this.closeCreateProjectDialog();
    this.newProjectName = '';
    this.newProjectSourceUri = '';
    promptAction.showToast({ message: sourceUri.length > 0 ? `项目"${name}"已创建，外部同步文件夹已记录` : `项目"${name}"已创建`, duration: 2000 });
  }

  private startRenameProject(projectId: string): void {
    const proj: ProjectRecord | undefined = this.projects.find((p: ProjectRecord) => p.id === projectId);
    if (proj !== undefined) {
      this.renamingProjectId = projectId;
      this.renameProjectText = proj.name;
    }
  }

  private confirmRenameProject(): void {
    const name: string = this.renameProjectText.trim();
    if (name.length === 0 || this.renamingProjectId.length === 0) {
      return;
    }
    const next: ProjectRecord[] = [];
    for (let i: number = 0; i < this.projects.length; i += 1) {
      const p: ProjectRecord = this.projects[i];
      if (p.id === this.renamingProjectId) {
        next.push(new ProjectRecord(p.id, name, p.path, p.expanded, p.sourceUri));
      } else {
        next.push(new ProjectRecord(p.id, p.name, p.path, p.expanded, p.sourceUri));
      }
    }
    this.projects = next;
    this.saveProjects();
    this.renamingProjectId = '';
    this.renameProjectText = '';
  }

  private cancelRenameProject(): void {
    this.renamingProjectId = '';
    this.renameProjectText = '';
  }

  private runMotion(action: () => void, duration: number = this.motionNormalDuration): void {
    this.getUIContext().animateTo({ duration: duration, curve: Curve.FastOutSlowIn }, action);
  }

  private runPanelMotion(action: () => void): void {
    this.runMotion(action, this.motionPanelDuration);
  }

  private runFastMotion(action: () => void): void {
    this.runMotion(action, this.motionFastDuration);
  }

  private toggleProjectExpanded(projectId: string): void {
    const savedOffset: number = this.leftScrollController.currentOffset().yOffset;
    const next: ProjectRecord[] = [];
    for (let i: number = 0; i < this.projects.length; i += 1) {
      const p: ProjectRecord = this.projects[i];
      if (p.id === projectId) {
        next.push(new ProjectRecord(p.id, p.name, p.path, !p.expanded, p.sourceUri));
      } else {
        next.push(new ProjectRecord(p.id, p.name, p.path, p.expanded, p.sourceUri));
      }
    }
    this.runFastMotion(() => {
      this.projects = next;
    });
    this.saveProjects();
    setTimeout(() => {
      this.leftScrollController.scrollTo({ yOffset: savedOffset, xOffset: 0 });
    }, 50);
  }

  private openNewSessionDialog(projectId: string): void {
    this.newSessionProjectId = projectId;
    this.newSessionName = '';
    this.showProjectMenuId = '';
    this.showSessionMenuId = '';
    if (this.newSessionDialogController !== null) {
      this.newSessionDialogController.open();
    }
  }

  private async confirmCreateSession(): Promise<void> {
    const name: string = this.newSessionName.trim();
    if (name.length === 0 || this.newSessionProjectId.length === 0) {
      promptAction.showToast({ message: '请输入会话名称', duration: 2000 });
      return;
    }
    const proj: ProjectRecord | undefined = this.projects.find((p: ProjectRecord) => p.id === this.newSessionProjectId);
    if (proj === undefined) {
      return;
    }
    const nextId: number = this.nextWorkspaceId();
    const workspace: WorkspaceItem = new WorkspaceItem(nextId, name, '', `session:${nextId.toString()}`, proj.id);
    this.workspaces.push(workspace);
    this.workspaceRoots.set(nextId, proj.path);
    this.workspaceIds.set(nextId, `session:${nextId.toString()}`);
    this.closeNewSessionDialog();
    this.newSessionProjectId = '';
    this.newSessionName = '';
    this.syncRecentWorkspaces();
    this.persistWorkspaceBindings();
    await this.selectWorkspace(workspace);
  }

  private startRenameSession(sessionId: string): void {
    const ws: WorkspaceItem | undefined = this.workspaces.find((w: WorkspaceItem) => this.ensureWorkspaceBinding(w) === sessionId);
    if (ws !== undefined) {
      this.renamingSessionId = sessionId;
      this.renameSessionText = ws.title;
    }
  }

  private confirmRenameSession(): void {
    const name: string = this.renameSessionText.trim();
    if (name.length === 0 || this.renamingSessionId.length === 0) {
      return;
    }
    const next: WorkspaceItem[] = [];
    for (let i: number = 0; i < this.workspaces.length; i += 1) {
      const w: WorkspaceItem = this.workspaces[i];
      if (this.ensureWorkspaceBinding(w) === this.renamingSessionId) {
        next.push(new WorkspaceItem(w.id, name, w.description, w.workspaceId, w.projectId));
      } else {
        next.push(new WorkspaceItem(w.id, w.title, w.description, w.workspaceId, w.projectId));
      }
    }
    this.workspaces = next;
    this.syncRecentWorkspaces();
    this.syncCurrentWorkspaceState();
    this.persistWorkspaceBindings();
    void codexBackend.renameSession(this.renamingSessionId, name);
    this.renamingSessionId = '';
    this.renameSessionText = '';
  }

  private cancelRenameSession(): void {
    this.renamingSessionId = '';
    this.renameSessionText = '';
  }

  private async deleteSession(sessionId: string): Promise<void> {
    let targetIndex: number = -1;
    for (let i: number = 0; i < this.workspaces.length; i += 1) {
      if (this.ensureWorkspaceBinding(this.workspaces[i]) === sessionId) {
        targetIndex = i;
        break;
      }
    }
    if (targetIndex < 0) {
      return;
    }
    // Archive backend session data
    try {
      await codexBackend.archiveSession(sessionId);
    } catch (_err) {
      // ignore archive errors
    }
    this.workspaces.splice(targetIndex, 1);
    if (this.workspaces.length === 0) {
      this.activeWorkspaceId = 0;
    } else if (targetIndex <= this.workspaces.length) {
      const newIndex: number = targetIndex < this.workspaces.length ? targetIndex : this.workspaces.length - 1;
      await this.selectWorkspace(this.workspaces[newIndex]);
    }
    this.syncRecentWorkspaces();
    this.persistWorkspaceBindings();
  }

  private async deleteProject(projectId: string): Promise<void> {
    let targetIndex: number = -1;
    for (let i: number = 0; i < this.projects.length; i += 1) {
      if (this.projects[i].id === projectId) {
        targetIndex = i;
        break;
      }
    }
    if (targetIndex < 0) {
      return;
    }
    projectStore.addDeletedPath(this.projects[targetIndex].path);

    // Archive all backend sessions belonging to this project
    for (let i: number = this.workspaces.length - 1; i >= 0; i -= 1) {
      if (this.workspaces[i].projectId === projectId) {
        const sessionId: string = this.ensureWorkspaceBinding(this.workspaces[i]);
        try {
          await codexBackend.archiveSession(sessionId);
        } catch (_err) {
          // ignore archive errors
        }
      }
    }

    const next: ProjectRecord[] = [];
    for (let i: number = 0; i < this.projects.length; i += 1) {
      if (this.projects[i].id !== projectId) {
        next.push(this.projects[i]);
      }
    }
    this.projects = next;
    this.saveProjects();
    for (let i: number = this.workspaces.length - 1; i >= 0; i -= 1) {
      if (this.workspaces[i].projectId === projectId) {
        this.workspaces.splice(i, 1);
      }
    }
    this.syncRecentWorkspaces();
    this.persistWorkspaceBindings();
  }

  private relativeTime(updatedAt: string): string {
    const parsed: number = Date.parse(updatedAt);
    if (isNaN(parsed)) {
      return '';
    }
    const diffMs: number = Date.now() - parsed;
    if (diffMs < 0) {
      return '刚刚';
    }
    const minutes: number = Math.floor(diffMs / 60000);
    if (minutes < 1) {
      return '刚刚';
    }
    if (minutes < 60) {
      return `${minutes.toString()} 分`;
    }
    const hours: number = Math.floor(minutes / 60);
    if (hours < 24) {
      return `${hours.toString()} 时`;
    }
    const days: number = Math.floor(hours / 24);
    return `${days.toString()} 天`;
  }

  private applyWorkspaceRootBinding(): void {
    const trimmedWorkspaceRoot: string = this.workspaceDraftText.trim();
    this.workspaceRoot = trimmedWorkspaceRoot;
    this.workspaceRoots.set(this.activeWorkspaceId, trimmedWorkspaceRoot);
    this.workspaceUris.set(this.activeWorkspaceId, '');
    this.syncWorkspaceSelectionText();
    this.refreshWorkspaceBindingState();
    this.persistWorkspaceBindings();
  }

  private applyWorkspaceDirectorySelection(workspaceRoot: string, workspaceUri: string): void {
    const trimmedWorkspaceRoot: string = workspaceRoot.trim();
    this.directoryFilter = trimmedWorkspaceRoot;
    this.directoryFilterText = trimmedWorkspaceRoot.length > 0 ? trimmedWorkspaceRoot : '使用默认工作区';
    this.syncRecentWorkspaces();
  }

  private syncWorkspaceSelectionText(): void {
    const workspaceUri: string = this.workspaceUris.get(this.activeWorkspaceId) ?? '';
    if (workspaceUri.trim().length > 0) {
      this.workspaceSelectionText = `已选择目录: ${workspaceUri}`;
      return;
    }
    if (this.workspaceRoot.trim().length > 0) {
      this.workspaceSelectionText = `当前工作目录: ${this.workspaceRoot}`;
      return;
    }
    this.workspaceSelectionText = '使用默认工作区';
  }

  private canSelectExternalFolder(): boolean {
    try {
      return canIUse(FOLDER_SELECTION_SYSCAP);
    } catch (_err) {
      return false;
    }
  }

  private canUseUserFileService(): boolean {
    try {
      return canIUse(USER_FILE_SERVICE_SYSCAP);
    } catch (_err) {
      return false;
    }
  }

  private canPersistExternalFolderPermission(): boolean {
    try {
      return canIUse(FOLDER_AUTHORIZATION_SYSCAP) || canIUse(LEGACY_FOLDER_AUTHORIZATION_SYSCAP);
    } catch (_err) {
      return false;
    }
  }

  private projectSourcePermissionMode(): number {
    return fileShare.OperationMode.READ_MODE | fileShare.OperationMode.WRITE_MODE;
  }

  private async persistProjectSourcePermission(sourceUri: string): Promise<boolean> {
    if (sourceUri.trim().length === 0 || !this.canPersistExternalFolderPermission()) {
      return false;
    }
    try {
      await fileShare.persistPermission([{ uri: sourceUri, operationMode: this.projectSourcePermissionMode() }]);
      return true;
    } catch (err) {
      hilog.warn(INDEX_DOMAIN, INDEX_TAG, 'persist source permission failed: %{public}s', this.describeError(err));
      return false;
    }
  }

  private async activateProjectSourcePermission(sourceUri: string): Promise<void> {
    if (sourceUri.trim().length === 0) {
      throw new Error('项目没有同步文件夹。');
    }
    if (!this.canPersistExternalFolderPermission()) {
      return;
    }
    await fileShare.activatePermission([{ uri: sourceUri, operationMode: this.projectSourcePermissionMode() }]);
  }

  private sanitizeProjectDirectoryName(projectName: string): string {
    const sanitized: string = projectName.trim().replace(/[\/\\:*?"<>|]/g, '_');
    if (sanitized.length === 0 || sanitized === '.' || sanitized === '..') {
      return `proj_${Date.now().toString()}`;
    }
    return sanitized;
  }

  private isProjectPathUsed(projectPath: string): boolean {
    const trimmedPath: string = projectPath.trim();
    for (let index: number = 0; index < this.projects.length; index += 1) {
      if (this.projects[index].path.trim() === trimmedPath) {
        return true;
      }
    }
    return false;
  }

  private sandboxProjectPath(): string {
    const context: common.UIAbilityContext | null = this.currentAbilityContext();
    if (context === null) {
      throw new Error('当前页面上下文不可用，无法创建应用内项目目录。');
    }
    const basePath: string = `${context.filesDir}/projects`;
    const directoryName: string = this.sanitizeProjectDirectoryName(this.newProjectName);
    let candidatePath: string = `${basePath}/${directoryName}`;
    let suffix: number = 2;
    while (this.isProjectPathUsed(candidatePath)) {
      candidatePath = `${basePath}/${directoryName}_${suffix.toString()}`;
      suffix += 1;
    }
    fileIo.mkdirSync(candidatePath, true);
    return candidatePath;
  }

  private async pickDirectorySelection(): Promise<WorkspaceDirectorySelection | null> {
    const hostContext = this.getUIContext().getHostContext();
    if (hostContext === undefined) {
      throw new Error('当前页面上下文不可用，无法打开目录选择器。');
    }
    if (!this.canSelectExternalFolder()) {
      throw new Error('当前设备不支持选择外部目录。');
    }
    const documentPicker = new picker.DocumentViewPicker(hostContext);
    const selectedUris: Array<string> = await documentPicker.select({
      selectMode: picker.DocumentSelectMode.FOLDER
    });
    if (selectedUris.length === 0) {
      return null;
    }
    const selectedUri: string = selectedUris[0];
    const parsedUri = new uri.URI(selectedUri);
    const candidatePath: string = decodeURIComponent(parsedUri.path ?? '');
    if (candidatePath.trim().length === 0) {
      throw new Error(`目录已选择，但暂时无法解析路径: ${selectedUri}`);
    }
    return new WorkspaceDirectorySelection(candidatePath, selectedUri);
  }

  private async pickDownloadDirectorySelection(projectDirectoryName?: string): Promise<WorkspaceDirectorySelection | null> {
    const hostContext = this.getUIContext().getHostContext();
    if (hostContext === undefined) {
      throw new Error('当前页面上下文不可用，无法打开下载目录授权。');
    }
    if (!this.canUseUserFileService()) {
      throw new Error('当前设备不支持下载目录授权。');
    }
    const documentSaveOptions = new picker.DocumentSaveOptions();
    documentSaveOptions.pickerMode = picker.DocumentPickerMode.DOWNLOAD;
    const documentPicker = new picker.DocumentViewPicker(hostContext);
    const selectedUris: Array<string> = await documentPicker.save(documentSaveOptions);
    if (selectedUris.length === 0) {
      return null;
    }
    let selectedUri: string = selectedUris[0];
    if (projectDirectoryName !== undefined && projectDirectoryName.trim().length > 0) {
      selectedUri = this.childUri(this.childUri(selectedUri, 'projects'), projectDirectoryName.trim());
    }
    const candidatePath: string = this.fileUriToFsPath(selectedUri);
    return new WorkspaceDirectorySelection(candidatePath, selectedUri);
  }

  private async pickWorkspaceDirectory(): Promise<void> {
    try {
      const selection: WorkspaceDirectorySelection | null = await this.pickDirectorySelection();
      if (selection === null) {
        this.workspaceStatusText = '未选择目录，继续使用当前工作区。';
        return;
      }
      this.applyWorkspaceDirectorySelection(selection.rootPath, selection.sourceUri);
    } catch (err) {
      this.workspaceStatusText = `选择目录失败: ${this.describeError(err)}`;
    }
  }

  private async pickWorkspaceDirectoryForProject(): Promise<void> {
    try {
      if (!this.canSelectExternalFolder()) {
        if (this.newProjectName.trim().length === 0) {
          promptAction.showToast({ message: '请先输入项目名称，再启用下载目录同步', duration: 2500 });
          return;
        }
        const downloadSelection: WorkspaceDirectorySelection | null = await this.pickDownloadDirectorySelection(this.sanitizeProjectDirectoryName(this.newProjectName));
        if (downloadSelection !== null) {
          this.newProjectSourceUri = downloadSelection.sourceUri;
          promptAction.showToast({ message: '已启用下载目录同步，项目将使用应用内目录', duration: 3000 });
        }
        return;
      }
      const selection: WorkspaceDirectorySelection | null = await this.pickDirectorySelection();
      if (selection !== null) {
        this.newProjectSourceUri = selection.sourceUri;
        const persisted: boolean = await this.persistProjectSourcePermission(selection.sourceUri);
        promptAction.showToast({
          message: persisted
            ? '外部目录已记录为同步文件夹，读写授权已持久化'
            : '外部目录已记录为同步文件夹；授权未持久化，重启后同步可能需要重新选择',
          duration: 3000
        });
      }
    } catch (err) {
      promptAction.showToast({ message: `选择同步文件夹失败: ${this.describeError(err)}`, duration: 3000 });
    }
  }

  private async reselectProjectImportSource(projectId: string): Promise<void> {
    try {
      let selection: WorkspaceDirectorySelection | null = null;
      let persisted: boolean = false;
      let downloadMode: boolean = false;
      if (this.canSelectExternalFolder()) {
        selection = await this.pickDirectorySelection();
        if (selection !== null) {
          persisted = await this.persistProjectSourcePermission(selection.sourceUri);
        }
      } else {
        let projectDirectoryName: string = '';
        for (let i: number = 0; i < this.projects.length; i += 1) {
          if (this.projects[i].id === projectId) {
            projectDirectoryName = this.sanitizeProjectDirectoryName(this.projects[i].name);
            break;
          }
        }
        selection = await this.pickDownloadDirectorySelection(projectDirectoryName);
        downloadMode = true;
      }
      if (selection === null) {
        return;
      }
      const next: ProjectRecord[] = [];
      for (let i: number = 0; i < this.projects.length; i += 1) {
        const p: ProjectRecord = this.projects[i];
        if (p.id === projectId) {
          next.push(new ProjectRecord(p.id, p.name, p.path, p.expanded, selection.sourceUri));
        } else {
          next.push(new ProjectRecord(p.id, p.name, p.path, p.expanded, p.sourceUri));
        }
      }
      this.projects = next;
      this.saveProjects();
      promptAction.showToast({
        message: downloadMode
          ? '下载目录同步文件夹已更新'
          : (persisted ? '同步文件夹已更新，读写授权已持久化' : '同步文件夹已更新；授权未持久化，重启后同步可能需要重新选择'),
        duration: 3000
      });
    } catch (err) {
      promptAction.showToast({ message: `更新同步文件夹失败: ${this.describeError(err)}`, duration: 3000 });
    }
  }

  private mapWorkspacePermissionState(value: string): WorkspacePermissionState {
    if (value === 'writable' || value === 'readonly' || value === 'revoked') {
      return value;
    }
    return 'unavailable';
  }

  private mapWorkspaceAccessKind(value: string): WorkspaceAccessKind {
    if (value === 'sandbox' || value === 'user_granted' || value === 'readonly') {
      return value;
    }
    return 'unknown';
  }

  private currentModelLabel(): string {
    return this.currentModelValue();
  }

  private currentModelValue(): string {
    const mode: CollaborationModeOption | null = this.selectedCollaborationMode();
    const modeModel: string = mode?.model?.trim() ?? '';
    if (modeModel.length > 0) {
      return modeModel;
    }
    const model: string = this.manualModel.trim();
    if (model.length === 0) {
      return 'default';
    }
    return model;
  }

  private currentEffortLabel(): string {
    const currentValue: string = this.currentEffortValue();
    const matched: SelectorOption | undefined = this.effortOptions.find((item: SelectorOption) => item.value === currentValue);
    return matched?.label ?? currentValue;
  }

  private currentEffortValue(): string {
    const mode: CollaborationModeOption | null = this.selectedCollaborationMode();
    const modeEffort: string | null | undefined = mode?.reasoningEffort;
    // If the collaboration mode explicitly sets an effort (non-null string), use it.
    if (typeof modeEffort === 'string' && modeEffort.trim().length > 0) {
      return modeEffort.trim();
    }
    // Otherwise fall back to the user-selected effort from the UI picker.
    return this.effortOptions[this.selectedEffortIndex].value;
  }

  private collaborationModeKey(): string {
    return this.activeWorkspaceBindingId;
  }

  private syncSelectedCollaborationMode(): void {
    if (this.collaborationModes.length === 0) {
      hilog.info(0x0001, 'ArkPilot', `syncSelectedCollaborationMode: modes empty, resetting to default`);
      this.selectedCollaborationModeName = 'default';
      return;
    }
    const modeKey: string = this.collaborationModeKey();
    const mappedName: string | undefined = this.collaborationModeByWorkspaceId.get(modeKey);
    const currentName: string = mappedName ?? this.selectedCollaborationModeName;
    hilog.info(0x0001, 'ArkPilot', `syncSelectedCollaborationMode: key=${modeKey} mappedName=${mappedName} currentName=${currentName} modes=${this.collaborationModes.map((m: CollaborationModeOption) => m.name).join(',')}`);
    const matched: CollaborationModeOption | undefined = this.collaborationModes.find((item: CollaborationModeOption) => item.name === currentName);
    if (matched !== undefined) {
      hilog.info(0x0001, 'ArkPilot', `syncSelectedCollaborationMode: matched=${matched.name}`);
      this.selectedCollaborationModeName = matched.name;
      this.collaborationModeByWorkspaceId.set(modeKey, matched.name);
      this.collaborationModeVersion += 1;
      return;
    }
    const defaultMode: CollaborationModeOption | undefined = this.collaborationModes.find((item: CollaborationModeOption) => item.mode === 'default');
    const fallback: CollaborationModeOption = defaultMode ?? this.collaborationModes[0];
    hilog.info(0x0001, 'ArkPilot', `syncSelectedCollaborationMode: fallback=${fallback.name}`);
    this.selectedCollaborationModeName = fallback.name;
    this.collaborationModeByWorkspaceId.set(modeKey, fallback.name);
    this.collaborationModeVersion += 1;
  }

  private selectedCollaborationMode(): CollaborationModeOption | null {
    const matched: CollaborationModeOption | undefined = this.collaborationModes.find((item: CollaborationModeOption) => item.name === this.selectedCollaborationModeName);
    if (this.selectedCollaborationModeName !== 'default') {
      hilog.info(0x0001, 'ArkPilot', `selectedCollaborationMode: searching=${this.selectedCollaborationModeName} found=${matched !== undefined} modes=[${this.collaborationModes.map((m: CollaborationModeOption) => `"${m.name}"`).join(',')}]`);
    }
    return matched ?? null;
  }

  private currentCollaborationModeLabel(): string {
    this.collaborationModeVersion; // touch to register as dependency
    const mode: CollaborationModeOption | null = this.selectedCollaborationMode();
    const label: string = mode !== null ? mode.name : 'Default';
    hilog.info(0x0001, 'ArkPilot', `currentCollaborationModeLabel: selected=${this.selectedCollaborationModeName} modes=${this.collaborationModes.length} label=${label}`);
    return label;
  }

  private chooseCollaborationMode(mode: CollaborationModeOption): void {
    hilog.info(0x0001, 'ArkPilot', `chooseCollaborationMode: name=${mode.name} mode=${mode.mode} key=${this.collaborationModeKey()}`);
    this.selectedCollaborationModeName = mode.name;
    this.collaborationModeByWorkspaceId.set(this.collaborationModeKey(), mode.name);
    this.showCollaborationModeOptions = false;
    this.collaborationModeVersion += 1;
    hilog.info(0x0001, 'ArkPilot', `chooseCollaborationMode done: selectedCollaborationModeName=${this.selectedCollaborationModeName} version=${this.collaborationModeVersion}`);
  }

  private visibleMessages(): ChatMessage[] {
    const hasPendingTailMessage: boolean = (this.isRunning && this.pendingUserPrompt.trim().length > 0) ||
      this.pendingRequestUserInput !== null;
    let visible: ChatMessage[] = this.messages.filter((item: ChatMessage, index: number) => {
      return this.shouldRenderMessageAt(index, hasPendingTailMessage);
    });
    if (this.isRunning && this.pendingUserPrompt.trim().length > 0) {
      visible = [...visible, this.pendingUserMessage()];
    }
    if (this.pendingRequestUserInput !== null) {
      const request: CodexRequestUserInput = this.pendingRequestUserInput;
      const promptMessage = new ChatMessage(
        `request-user-input:${request.requestId}`,
        'ArkPilot',
        'plan',
        request.detail.trim().length > 0 ? request.detail : request.title,
        '刚刚',
        'plan'
      );
      visible = [...visible, promptMessage];
    }
    return visible;
  }

  private shouldRenderMessageAt(index: number, hasPendingTailMessage: boolean): boolean {
    const item: ChatMessage = this.messages[index];
    if (!this.shouldRenderMessage(item)) {
      return false;
    }
    if (this.isReasoningMessage(item)) {
      return !this.hasRenderableMessageAfter(index, hasPendingTailMessage);
    }
    return true;
  }

  private shouldRenderMessage(item: ChatMessage): boolean {
    if (this.isCompactionSystemMessage(item)) {
      return false;
    }
    return !this.isEmptyReasoningMessage(item);
  }

  private hasRenderableMessageAfter(index: number, hasPendingTailMessage: boolean): boolean {
    if (hasPendingTailMessage) {
      return true;
    }
    for (let nextIndex = index + 1; nextIndex < this.messages.length; nextIndex += 1) {
      if (this.shouldRenderMessage(this.messages[nextIndex])) {
        return true;
      }
    }
    return false;
  }

  private isEmptyReasoningMessage(item: ChatMessage): boolean {
    const type: string = item.itemType ?? item.role;
    return type === 'reasoning' && item.content.trim().length === 0;
  }

  private isCompactionSystemMessage(item: ChatMessage): boolean {
    const type: string = item.itemType ?? item.role;
    if (type !== 'system' && item.role !== 'system') {
      return false;
    }
    const content: string = item.content.trim();
    return content.indexOf('上下文已压缩') >= 0 ||
      content.toLowerCase().indexOf('context has been compacted') >= 0;
  }

  private shouldShowTurnActivityLine(): boolean {
    if (!this.shouldTrackIdleThinking()) {
      return false;
    }
    if (this.pendingApproval !== null || this.pendingRequestUserInput !== null) {
      return false;
    }
    return this.liveThinkingActive || this.currentTurnHasIntermediateOutput();
  }

  private toggleTurnActivityExpanded(): void {
    this.isTurnActivityCollapsed = !this.isTurnActivityCollapsed;
  }

  private latestCurrentTurnThoughtStage(messages: ChatMessage[]): string {
    const startIndex: number = this.currentTurnMessageStartIndex();
    let latestStage: string = '';
    for (let index: number = startIndex; index < messages.length; index += 1) {
      const item: ChatMessage = messages[index];
      if (this.isReasoningMessage(item)) {
        latestStage = 'reasoning';
      } else if (this.isAssistantOutputMessage(item)) {
        latestStage = 'assistant';
      } else if (this.isActivityMessage(item)) {
        latestStage = 'activity';
      }
    }
    return latestStage;
  }

  private currentTurnAssistantOutputSignature(messages: ChatMessage[]): string {
    const parts: string[] = [];
    const startIndex: number = this.currentTurnMessageStartIndex();
    for (let index: number = startIndex; index < messages.length; index += 1) {
      const item: ChatMessage = messages[index];
      if (this.isAssistantOutputMessage(item)) {
        parts.push(`${item.id}:${item.content.length}`);
      }
    }
    return parts.join('|');
  }

  private currentTurnReasoningSignature(messages: ChatMessage[]): string {
    const parts: string[] = [];
    const startIndex: number = this.currentTurnMessageStartIndex();
    for (let index: number = startIndex; index < messages.length; index += 1) {
      const item: ChatMessage = messages[index];
      if (this.isReasoningMessage(item)) {
        parts.push(`${item.id}:${item.content.length}`);
      }
    }
    return parts.join('|');
  }

  private currentTurnTextOutputSignature(): string {
    const parts: string[] = [];
    const startIndex: number = this.currentTurnMessageStartIndex();
    for (let index: number = startIndex; index < this.messages.length; index += 1) {
      const item: ChatMessage = this.messages[index];
      if (this.isTextOutputMessage(item)) {
        parts.push(`${item.id}:${item.role}:${item.itemType ?? ''}:${item.content.length}`);
      }
    }
    return parts.join('|');
  }

  private isTextOutputMessage(item: ChatMessage): boolean {
    if (item.content.trim().length === 0) {
      return false;
    }
    const type: string = item.itemType ?? item.role;
    if (type === 'system' || item.role === 'system' || item.role === 'user') {
      return false;
    }
    return true;
  }

  private isAssistantOutputMessage(item: ChatMessage): boolean {
    if (item.content.trim().length === 0) {
      return false;
    }
    const type: string = item.itemType ?? item.role;
    if (this.isIntermediateMessageType(type)) {
      return false;
    }
    return item.role === 'assistant' || item.role === 'agent';
  }

  private isCurrentTurnAssistantOutput(item: ChatMessage, index: number): boolean {
    if (!this.isAssistantOutputMessage(item)) {
      return false;
    }
    if (this.currentTurnId.trim().length > 0 && item.id.startsWith(`${this.currentTurnId}:`)) {
      return true;
    }
    return index >= this.currentTurnMessageStartIndex();
  }

  private isStreamingAssistantMessage(item: ChatMessage): boolean {
    if (this.currentTurnStatus !== 'inProgress') {
      return false;
    }
    const index: number = this.messages.findIndex((message: ChatMessage) => message.id === item.id);
    return this.isCurrentTurnAssistantOutput(item, index);
  }

  private isActivityMessage(item: ChatMessage): boolean {
    const type: string = item.itemType ?? item.role;
    if (this.isIntermediateMessageType(type)) {
      return true;
    }
    return item.role !== 'user' &&
      item.role !== 'system' &&
      item.role !== 'assistant' &&
      item.role !== 'agent';
  }

  private currentTurnHasIntermediateOutput(): boolean {
    const startIndex: number = this.currentTurnMessageStartIndex();
    for (let index: number = startIndex; index < this.messages.length; index += 1) {
      const item: ChatMessage = this.messages[index];
      if (this.isActivityMessage(item) && !this.isEmptyReasoningMessage(item)) {
        return true;
      }
    }
    return false;
  }

  private isIntermediateMessageType(type: string): boolean {
    return type === 'reasoning' ||
      type === 'command' ||
      type === 'tool' ||
      type === 'file' ||
      type === 'search' ||
      type === 'plan' ||
      type === 'image' ||
      type === 'hook' ||
      type === 'review';
  }

  private currentTurnMessageStartIndex(): number {
    return this.thinkingMessageBoundary >= 0 ? this.thinkingMessageBoundary : this.messages.length;
  }

  private thinkingStatusPhraseText(): string {
    const isLongThinking: boolean = this.thinkingPulseIndex >= this.longThinkingPulseThreshold;
    if (isLongThinking) {
      const phrase: string = this.thinkingFunPhrase.length > 0 ? this.thinkingFunPhrase : '思考中';
      return `${phrase}${this.thinkingDots()}`;
    }
    const phrase: string = this.thinkingNormalPhrase.length > 0 ? this.thinkingNormalPhrase : this.thinkingStatusPhrases[0];
    return `${phrase}${this.thinkingDots()}`;
  }

  private pendingUserMessage(): ChatMessage {
    return new ChatMessage(
      `pending-user:${this.thinkingSessionId}`,
      '你',
      'user',
      this.pendingUserPrompt,
      '刚刚'
    );
  }

  private startThinkingAnimation(): void {
    if (this.thinkingTimerId >= 0) {
      return;
    }
    this.thinkingTimerId = setInterval(() => {
      this.thinkingPulseIndex = (this.thinkingPulseIndex + 1) % 144;
      this.refreshThinkingNormalPhrase();
      this.refreshThinkingFunPhrase();
    }, 500);
  }

  private shouldTrackIdleThinking(): boolean {
    return this.isRunning && this.currentTurnStatus === 'inProgress';
  }

  private resetIdleThinkingTimer(): void {
    this.lastTextOutputAt = Date.now();
    this.showIdleThinkingIndicator = false;
    this.clearIdleThinkingTimer();
    if (!this.shouldTrackIdleThinking()) {
      return;
    }
    this.idleThinkingTimerId = setTimeout(() => {
      this.idleThinkingTimerId = -1;
      this.updateIdleThinkingIndicator();
    }, this.idleThinkingDelayMs);
  }

  private clearIdleThinkingTimer(): void {
    if (this.idleThinkingTimerId >= 0) {
      clearTimeout(this.idleThinkingTimerId);
      this.idleThinkingTimerId = -1;
    }
  }

  private updateIdleThinkingIndicator(): void {
    if (!this.shouldTrackIdleThinking()) {
      this.showIdleThinkingIndicator = false;
      this.clearIdleThinkingTimer();
      return;
    }
    const elapsedMs: number = Date.now() - this.lastTextOutputAt;
    if (elapsedMs >= this.idleThinkingDelayMs) {
      if (!this.showIdleThinkingIndicator) {
        this.showIdleThinkingIndicator = true;
        this.scheduleMessageScrollToBottom();
      }
      if (this.idleThinkingTimerId < 0) {
        this.idleThinkingTimerId = setTimeout(() => {
          this.idleThinkingTimerId = -1;
          this.updateIdleThinkingIndicator();
        }, 500);
      }
      return;
    }
    this.clearIdleThinkingTimer();
    this.idleThinkingTimerId = setTimeout(() => {
      this.idleThinkingTimerId = -1;
      this.updateIdleThinkingIndicator();
    }, this.idleThinkingDelayMs - elapsedMs);
  }

  private syncTextOutputIdleState(): void {
    if (!this.shouldTrackIdleThinking()) {
      this.lastTextOutputSignature = '';
      this.showIdleThinkingIndicator = false;
      this.clearIdleThinkingTimer();
      return;
    }
    const signature: string = this.currentTurnTextOutputSignature();
    if (signature !== this.lastTextOutputSignature) {
      this.lastTextOutputSignature = signature;
      this.resetIdleThinkingTimer();
      return;
    }
    this.updateIdleThinkingIndicator();
  }

  private stopThinkingAnimation(): void {
    if (this.thinkingTimerId >= 0) {
      clearInterval(this.thinkingTimerId);
      this.thinkingTimerId = -1;
    }
  }

  private clearLiveThinking(): void {
    this.liveThinkingActive = false;
    this.liveThinkingContent = '';
    this.liveThinkingReasoningSignature = '';
    this.liveThinkingAssistantSignature = '';
    this.isTurnActivityCollapsed = true;
  }

  private isReasoningPlaceholderText(content: string): boolean {
    return content.trim() === '正在思考...';
  }

  private updateLiveThinking(result: CodexTurnResult, rawMessages: ChatMessage[]): void {
    if (result.status !== 'inProgress') {
      this.clearLiveThinking();
      return;
    }
    const latestStage: string = this.latestCurrentTurnThoughtStage(rawMessages);
    const assistantSignature: string = this.currentTurnAssistantOutputSignature(rawMessages);
    const reasoningSignature: string = this.currentTurnReasoningSignature(rawMessages);
    if (assistantSignature !== this.liveThinkingAssistantSignature) {
      this.liveThinkingAssistantSignature = assistantSignature;
      this.liveThinkingActive = false;
      this.liveThinkingContent = '';
    }
    if (latestStage === 'assistant' && reasoningSignature === this.liveThinkingReasoningSignature) {
      this.clearLiveThinking();
      this.liveThinkingReasoningSignature = reasoningSignature;
      this.liveThinkingAssistantSignature = assistantSignature;
      return;
    }
    if (latestStage === '' || latestStage === 'activity') {
      this.liveThinkingActive = true;
      this.liveThinkingContent = '';
      this.liveThinkingReasoningSignature = reasoningSignature;
      this.liveThinkingAssistantSignature = assistantSignature;
      return;
    }
    const startIndex: number = this.currentTurnMessageStartIndex();
    let latestReasoning: ChatMessage | null = null;
    for (let index: number = startIndex; index < rawMessages.length; index += 1) {
      const item: ChatMessage = rawMessages[index];
      if (this.isReasoningMessage(item)) {
        latestReasoning = item;
      }
    }
    if (latestReasoning === null || this.isReasoningPlaceholderText(latestReasoning.content)) {
      this.liveThinkingActive = true;
      this.liveThinkingContent = '';
      this.liveThinkingReasoningSignature = reasoningSignature;
      this.liveThinkingAssistantSignature = assistantSignature;
      return;
    }
    this.liveThinkingActive = true;
    this.liveThinkingContent = latestReasoning.content;
    this.liveThinkingReasoningSignature = reasoningSignature;
    this.liveThinkingAssistantSignature = assistantSignature;
  }

  private syncThinkingAnimation(): void {
    if (this.isRunning) {
      this.startThinkingAnimation();
      return;
    }
    this.stopThinkingAnimation();
  }

  private thinkingStatusText(): string {
    return `${this.thinkingLogoText()} ${this.thinkingStatusPhraseText()}`;
  }

  private displayBrandText(text: string): string {
    return text.replace(/Codex/g, 'ArkPilot');
  }

  private turnActivityDetailLines(): string[] {
    const reasoningText: string = this.liveThinkingContent.trim();
    if (reasoningText.length === 0) {
      return ['正在等待可展示的思考内容。'];
    }
    const lines: string[] = reasoningText
      .replace(/\r\n/g, '\n')
      .replace(/\r/g, '\n')
      .split('\n')
      .map((line: string) => this.displayBrandText(line).trim())
      .filter((line: string) => line.length > 0);
    if (lines.length === 0) {
      lines.push('正在等待可展示的思考内容。');
    }
    return lines;
  }

  private refreshThinkingNormalPhrase(): void {
    if (this.thinkingPulseIndex >= this.longThinkingPulseThreshold) {
      this.thinkingNormalPhraseBucket = -1;
      return;
    }
    const bucket: number = Math.floor(this.thinkingPulseIndex / this.thinkingPhrasePulseSpan);
    if (bucket === this.thinkingNormalPhraseBucket && this.thinkingNormalPhrase.length > 0) {
      return;
    }
    this.thinkingNormalPhraseBucket = bucket;
    this.thinkingNormalPhrase = this.randomThinkingPhrase(this.thinkingStatusPhrases, this.thinkingNormalPhrase, '');
  }

  private refreshThinkingFunPhrase(): void {
    if (this.thinkingPulseIndex < this.longThinkingPulseThreshold) {
      if (this.thinkingFunPhrase.length > 0) {
        this.thinkingFunPhrase = '';
      }
      this.thinkingFunPhraseBucket = -1;
      return;
    }
    const bucket: number = Math.floor((this.thinkingPulseIndex - this.longThinkingPulseThreshold) / this.thinkingPhrasePulseSpan);
    if (bucket === this.thinkingFunPhraseBucket && this.thinkingFunPhrase.length > 0) {
      return;
    }
    this.thinkingFunPhraseBucket = bucket;
    this.thinkingFunPhrase = this.randomThinkingLongPhrase(this.thinkingFunPhrase);
  }

  private randomThinkingPhrase(phrases: string[], previousPhrase: string, fallbackPhrase: string): string {
    if (phrases.length === 0) {
      return fallbackPhrase;
    }
    if (phrases.length === 1) {
      return phrases[0];
    }
    let phraseIndex: number = Math.floor(Math.random() * phrases.length);
    if (phrases[phraseIndex] === previousPhrase) {
      phraseIndex = (phraseIndex + 1 + Math.floor(Math.random() * (phrases.length - 1))) % phrases.length;
    }
    return phrases[phraseIndex];
  }

  private randomThinkingLongPhrase(previousPhrase: string): string {
    const defaultPhrase: string = '思考中';
    if (Math.random() < 0.75) {
      return defaultPhrase;
    }
    const phrases: string[] = this.longThinkingStatusPhrases;
    if (phrases.length === 1) {
      return phrases[0];
    }
    return this.randomThinkingPhrase(phrases, previousPhrase !== defaultPhrase ? previousPhrase : '', defaultPhrase);
  }

  private thinkingLogoText(): string {
    const frameIndex: number = Math.floor(this.thinkingPulseIndex / 2) % this.thinkingLogoFrames.length;
    return this.thinkingLogoFrames[frameIndex];
  }

  private thinkingDots(): string {
    switch (Math.floor(this.thinkingPulseIndex / 2) % 4) {
      case 0:
        return '…';
      case 1:
        return '.';
      case 2:
        return '..';
      default:
        return '...';
    }
  }

  private requestUserInputAnswer(questionId: string): string {
    this.requestUserInputVersion;
    return this.requestUserInputDrafts.get(questionId) ?? '';
  }

  private setRequestUserInputAnswer(questionId: string, value: string): void {
    this.requestUserInputDrafts.set(questionId, value);
    this.requestUserInputVersion += 1;
  }

  private async submitRequestUserInput(): Promise<void> {
    const request: CodexRequestUserInput | null = this.pendingRequestUserInput;
    if (request === null) {
      return;
    }
    const answers: Record<string, string[]> = {};
    for (let index: number = 0; index < request.questions.length; index += 1) {
      const question = request.questions[index];
      const value: string = this.requestUserInputAnswer(question.id).trim();
      if (value.length === 0) {
        this.summaryTitle = '需要补充信息';
        this.summaryPoints = [`请先回答“${question.header}”再继续。`];
        return;
      }
      answers[question.id] = [value];
    }
    await codexBackend.submitPendingUserInput(answers);
    this.requestUserInputDrafts.clear();
    this.requestUserInputVersion += 1;
  }

  private async declineRequestUserInput(): Promise<void> {
    await codexBackend.declinePendingUserInput();
    this.requestUserInputDrafts.clear();
    this.requestUserInputVersion += 1;
  }

  private sendMessage(): void {
    const prompt: string = this.draft.trim();
    if (prompt.length === 0 || this.isRunning) {
      return;
    }
    this.resumeMessageAutoFollow();
    this.scheduleMessageScrollToBottom(true);
    this.savedDraft = this.draft;
    this.draft = '';
    void this.runTurn(prompt);
  }

  private stopTurn(): void {
    codexBackend.interruptTurn();
  }

  private async runTurn(prompt: string): Promise<void> {
    if (this.workspaces.length === 0) {
      return;
    }
    this.isRunning = true;
    this.currentTurnStatus = 'inProgress';
    this.pendingUserPrompt = prompt;
    this.thinkingMessageBoundary = this.messages.length;
    this.thinkingPulseIndex = 0;
    this.thinkingNormalPhrase = '';
    this.thinkingNormalPhraseBucket = -1;
    this.thinkingFunPhrase = '';
    this.thinkingFunPhraseBucket = -1;
    this.liveThinkingActive = true;
    this.liveThinkingContent = '';
    this.liveThinkingReasoningSignature = '';
    this.liveThinkingAssistantSignature = '';
    this.showIdleThinkingIndicator = false;
    this.lastTextOutputAt = Date.now();
    this.lastTextOutputSignature = '';
    this.clearIdleThinkingTimer();
    this.thinkingSessionId += 1;
    this.refreshThinkingNormalPhrase();
    this.startThinkingAnimation();
    this.resetIdleThinkingTimer();
    if (this.workspaceDraftText.trim() !== this.workspaceRoot.trim()) {
      this.applyWorkspaceRootBinding();
    }
    this.workspaceRoots.set(this.activeWorkspaceId, this.workspaceRoot);
    this.refreshWorkspaceBindingState();
    codexBackend.configureServerUrl(this.serverUrl);

    const workspace: WorkspaceItem | undefined = this.activeWorkspace();
    if (workspace === undefined) {
      this.isRunning = false;
      this.currentTurnStatus = '';
      this.pendingUserPrompt = '';
      this.thinkingMessageBoundary = -1;
      this.showIdleThinkingIndicator = false;
      this.lastTextOutputSignature = '';
      this.clearLiveThinking();
      this.clearIdleThinkingTimer();
      this.syncThinkingAnimation();
      return;
    }
    const trimmedWorkspaceRoot: string = this.workspaceRoot.trim();
    const threadKey: string = workspace.workspaceId.trim().length > 0 ? workspace.workspaceId : this.activeWorkspaceBindingId;
    await this.applyEmbeddedHostStatus();
    try {
      const result: CodexTurnResult = await codexBackend.startTurn(
        new CodexTurnRequest(
          threadKey,
          workspace.title,
          this.activeWorkspaceBindingId,
          trimmedWorkspaceRoot,
          this.activeWorkspacePermissionState,
          this.activeWorkspaceAccessKind,
          trimmedWorkspaceRoot.length > 0 ? [trimmedWorkspaceRoot] : [],
          this.currentModelValue(),
          this.currentEffortValue(),
          this.selectedCollaborationMode(),
          prompt
        ),
        (update: CodexTurnResult) => {
          this.applyBackendResult(update);
        }
      );
      this.applyBackendResult(result);
      if (result.status === 'interrupted' || result.status === 'failed') {
        this.draft = this.savedDraft;
      }
      this.savedDraft = '';
    } catch (err) {
      this.currentTurnStatus = 'failed';
      this.summaryTitle = '调用失败';
      this.summaryPoints = [this.describeError(err)];
      this.draft = this.savedDraft;
      this.savedDraft = '';
    } finally {
      this.isRunning = false;
      this.pendingUserPrompt = '';
      this.thinkingMessageBoundary = -1;
      this.showIdleThinkingIndicator = false;
      this.lastTextOutputSignature = '';
      this.clearLiveThinking();
      this.clearIdleThinkingTimer();
      this.syncThinkingAnimation();
    }
  }

  private applyBackendResult(result: CodexTurnResult): void {
    this.syncWorkspaceWithRemoteThreadId(result.threadId);
    this.currentTurnId = result.turnId;
    this.currentTurnStatus = result.status;
    this.syncThinkingAnimation();
    if (this.backendResultContainsPendingPrompt(result)) {
      this.pendingUserPrompt = '';
    }
    const rawMessages: ChatMessage[] = result.messages.map((item) => {
      return new ChatMessage(item.messageId, this.displayBrandText(item.author), item.role, this.displayBrandText(item.content), item.timestamp, item.itemType, item.status, item.metadata);
    });
    const displayMessages: ChatMessage[] = this.preserveStableMessageTimestamps(this.mergeStreamingDisplayMessages(rawMessages, result));
    this.updateLiveThinking(result, displayMessages);
    this.messages = displayMessages.filter((item: ChatMessage) => {
      return !this.isReasoningMessage(item);
    });
    this.codeLines = result.diffLines.length > 0
      ? result.diffLines.map((line: CodexDiffLine) => {
          return new CodeDiffLine(line.lineId, line.lineNumber, line.sign, line.content, line.kind, line.filePath);
        })
      : [new CodeDiffLine('placeholder-2', '1', ' ', '本轮尚未产生 diff。', 'context')];
    if (result.diffLines.length > 0) {
      this.applyDiffFiles(this.buildDiffFiles(this.codeLines));
    } else {
      this.diffFiles = [];
      this.selectedDiffFilePath = '';
    }
    this.summaryTitle = this.displayBrandText(result.summaryTitle);
    this.summaryPoints = result.summaryPoints.length > 0 ? result.summaryPoints.map((point: string) => this.displayBrandText(point)) : ['没有可展示的摘要信息。'];
    this.changedFiles = result.changedFiles;
    this.diffStat = result.diffStat;
    if (result.tokenUsage !== null) {
      this.tokenUsage = result.tokenUsage;
    }
    this.tokenAggregate = codexBackend.fetchTokenUsageAggregate();
    this.syncTextOutputIdleState();
    this.scheduleMessageScrollToBottom();
  }

  private preserveStableMessageTimestamps(messages: ChatMessage[]): ChatMessage[] {
    if (this.messages.length === 0 || messages.length === 0) {
      return messages;
    }
    return messages.map((incoming: ChatMessage) => {
      const existing: ChatMessage | undefined = this.findStableTimestampMessage(incoming);
      if (existing === undefined || existing.timestamp.trim().length === 0 || existing.timestamp === incoming.timestamp) {
        return incoming;
      }
      return new ChatMessage(
        incoming.id,
        incoming.author,
        incoming.role,
        incoming.content,
        existing.timestamp,
        incoming.itemType,
        incoming.status,
        incoming.metadata
      );
    });
  }

  private findStableTimestampMessage(incoming: ChatMessage): ChatMessage | undefined {
    const exact: ChatMessage | undefined = this.messages.find((message: ChatMessage) => message.id === incoming.id);
    if (exact !== undefined) {
      return exact;
    }
    for (let index: number = 0; index < this.messages.length; index += 1) {
      const existing: ChatMessage = this.messages[index];
      if (this.isSameStreamingAssistantMessage(existing, incoming)) {
        return existing;
      }
    }
    return undefined;
  }

  private mergeStreamingDisplayMessages(rawMessages: ChatMessage[], result: CodexTurnResult): ChatMessage[] {
    if (result.status !== 'inProgress') {
      return rawMessages;
    }
    const merged: ChatMessage[] = rawMessages.map((item: ChatMessage, index: number) => {
      if (!this.isCurrentTurnAssistantOutput(item, index)) {
        return item;
      }
      const existing: ChatMessage | undefined = this.findStreamingDisplayMessage(item);
      if (existing === undefined) {
        return item;
      }
      const mergedContent: string = this.mergeStreamingMessageContent(existing.content, item.content);
      if (mergedContent === item.content && existing.id === item.id) {
        return item;
      }
      return new ChatMessage(
        item.id,
        item.author,
        item.role,
        mergedContent,
        item.timestamp,
        item.itemType,
        item.status,
        item.metadata
      );
    });
    this.messages.forEach((existing: ChatMessage, index: number) => {
      if (!this.isCurrentTurnAssistantOutput(existing, index)) {
        return;
      }
      const mergeIndex: number = this.findStreamingDisplayMergeIndex(merged, existing);
      if (mergeIndex >= 0) {
        const incoming: ChatMessage = merged[mergeIndex];
        const mergedContent: string = this.mergeStreamingMessageContent(existing.content, incoming.content);
        if (mergedContent !== incoming.content) {
          merged[mergeIndex] = new ChatMessage(
            incoming.id,
            incoming.author,
            incoming.role,
            mergedContent,
            incoming.timestamp,
            incoming.itemType,
            incoming.status,
            incoming.metadata
          );
        }
        return;
      }
      const insertIndex: number = Math.min(index, merged.length);
      merged.splice(insertIndex, 0, existing);
    });
    return merged;
  }

  private findStreamingDisplayMessage(incoming: ChatMessage): ChatMessage | undefined {
    const exact: ChatMessage | undefined = this.messages.find((message: ChatMessage) => message.id === incoming.id);
    if (exact !== undefined) {
      return exact;
    }
    const startIndex: number = this.currentTurnMessageStartIndex();
    for (let index: number = startIndex; index < this.messages.length; index += 1) {
      const existing: ChatMessage = this.messages[index];
      if (this.isSameStreamingAssistantMessage(existing, incoming)) {
        return existing;
      }
    }
    return undefined;
  }

  private findStreamingDisplayMergeIndex(messages: ChatMessage[], existing: ChatMessage): number {
    for (let index: number = 0; index < messages.length; index += 1) {
      if (messages[index].id === existing.id) {
        return index;
      }
    }
    for (let index: number = 0; index < messages.length; index += 1) {
      if (this.isSameStreamingAssistantMessage(existing, messages[index])) {
        return index;
      }
    }
    return -1;
  }

  private isSameStreamingAssistantMessage(left: ChatMessage, right: ChatMessage): boolean {
    if (!this.isAssistantOutputMessage(left) || !this.isAssistantOutputMessage(right)) {
      return false;
    }
    if (this.currentTurnId.trim().length > 0) {
      const leftInTurn: boolean = left.id.startsWith(`${this.currentTurnId}:`);
      const rightInTurn: boolean = right.id.startsWith(`${this.currentTurnId}:`);
      if ((leftInTurn || rightInTurn) && this.isCompatibleStreamingMessageContent(left.content, right.content)) {
        return true;
      }
    }
    if (this.streamingMessageAlias(left.id) === this.streamingMessageAlias(right.id)) {
      return this.isCompatibleStreamingMessageContent(left.content, right.content);
    }
    return false;
  }

  private streamingMessageAlias(messageId: string): string {
    const separatorIndex: number = messageId.lastIndexOf(':');
    return separatorIndex >= 0 ? messageId.substring(separatorIndex + 1) : messageId;
  }

  private isCompatibleStreamingMessageContent(left: string, right: string): boolean {
    if (left.trim().length === 0 || right.trim().length === 0) {
      return true;
    }
    if (left.indexOf(right) >= 0 || right.indexOf(left) >= 0) {
      return true;
    }
    return this.streamingMessageContentOverlapSize(left, right) > 0 || this.streamingMessageContentOverlapSize(right, left) > 0;
  }

  private mergeStreamingMessageContent(existingContent: string, incomingContent: string): string {
    if (existingContent.length === 0 || incomingContent.startsWith(existingContent)) {
      return incomingContent;
    }
    if (incomingContent.length === 0 || existingContent.indexOf(incomingContent) >= 0) {
      return existingContent;
    }
    const overlapSize: number = this.streamingMessageContentOverlapSize(existingContent, incomingContent);
    if (overlapSize > 0) {
      return `${existingContent}${incomingContent.substring(overlapSize)}`;
    }
    return incomingContent.length >= existingContent.length ? incomingContent : existingContent;
  }

  private streamingMessageContentOverlapSize(left: string, right: string): number {
    const maxOverlap: number = Math.min(left.length, right.length);
    for (let size: number = maxOverlap; size > 0; size -= 1) {
      if (left.endsWith(right.substring(0, size))) {
        return size;
      }
    }
    return 0;
  }

  private backendResultContainsPendingPrompt(result: CodexTurnResult): boolean {
    const prompt: string = this.pendingUserPrompt.trim();
    if (prompt.length === 0) {
      return false;
    }
    for (let index: number = result.messages.length - 1; index >= 0; index -= 1) {
      const item = result.messages[index];
      if (item.role === 'user' && item.content.trim() === prompt) {
        return true;
      }
    }
    return false;
  }

  private clampConversationFontScale(value: number): number {
    const clamped: number = Math.min(this.conversationFontScaleMax, Math.max(this.conversationFontScaleMin, value));
    return Math.round(clamped * 100) / 100;
  }

  private setConversationFontScale(value: number): void {
    const nextScale: number = this.clampConversationFontScale(value);
    if (nextScale === this.conversationFontScale) {
      return;
    }
    this.conversationFontScale = nextScale;
    this.scheduleMessageScrollToBottom();
  }

  private adjustConversationFontScale(steps: number): void {
    if (steps === 0) {
      return;
    }
    this.setConversationFontScale(this.conversationFontScale + (this.conversationFontScaleStep * steps));
  }

  private adjustConversationFontScaleFromWheel(steps: number): void {
    this.messageZoomWheelActiveUntil = Date.now() + 120;
    this.adjustConversationFontScale(steps);
  }

  private conversationFontSize(base: number): number {
    return Math.round(base * this.conversationFontScale * 10) / 10;
  }

  private conversationLineHeight(base: number): number {
    return Math.round(base * this.conversationFontScale * 10) / 10;
  }

  private conversationZoomLabel(): string {
    return `${Math.round(this.conversationFontScale * 100).toString()}%`;
  }

  private isConversationFontAtMin(): boolean {
    return this.conversationFontScale <= this.conversationFontScaleMin;
  }

  private isConversationFontAtMax(): boolean {
    return this.conversationFontScale >= this.conversationFontScaleMax;
  }

  private mermaidScaleKey(messageId: string, block: MarkdownBlock): string {
    return `${messageId}:${block.id}`;
  }

  private mermaidScale(key: string): number {
    for (let index: number = 0; index < this.mermaidScaleEntries.length; index += 1) {
      if (this.mermaidScaleEntries[index].key === key) {
        return this.mermaidScaleEntries[index].scale;
      }
    }
    return 1;
  }

  private setMermaidScale(key: string, value: number): void {
    const nextScale: number = this.clampConversationFontScale(value);
    const nextEntries: MermaidScaleEntry[] = [];
    let updated: boolean = false;
    for (let index: number = 0; index < this.mermaidScaleEntries.length; index += 1) {
      const entry: MermaidScaleEntry = this.mermaidScaleEntries[index];
      if (entry.key === key) {
        updated = true;
        if (nextScale !== 1) {
          nextEntries.push(new MermaidScaleEntry(key, nextScale));
        }
      } else {
        nextEntries.push(entry);
      }
    }
    if (!updated && nextScale !== 1) {
      nextEntries.push(new MermaidScaleEntry(key, nextScale));
    }
    this.mermaidScaleEntries = nextEntries;
  }

  private adjustMermaidScale(key: string, steps: number): void {
    if (steps === 0) {
      return;
    }
    this.setMermaidScale(key, this.mermaidScale(key) + (this.conversationFontScaleStep * steps));
  }

  private isMermaidScaleAtMin(key: string): boolean {
    return this.mermaidScale(key) <= this.conversationFontScaleMin;
  }

  private isMermaidScaleAtMax(key: string): boolean {
    return this.mermaidScale(key) >= this.conversationFontScaleMax;
  }

  private isModifierPressed(event: KeyEvent | AxisEvent, primary: string): boolean {
    if (event.getModifierKeyState === undefined) {
      return false;
    }
    try {
      if (event.getModifierKeyState([primary])) {
        return true;
      }
    } catch (_err) {
    }
    try {
      return event.getModifierKeyState([primary.toLowerCase()]);
    } catch (_err) {
      return false;
    }
  }

  private isConversationZoomInKey(event: KeyEvent): boolean {
    return event.keyText === '+' ||
      event.keyText === '=' ||
      event.keyCode === this.keyCodePlus ||
      event.keyCode === this.keyCodeEquals ||
      event.keyCode === this.keyCodeNumpadAdd ||
      event.keyCode === this.keyCodeNumpadEquals;
  }

  private isConversationZoomOutKey(event: KeyEvent): boolean {
    return event.keyText === '-' ||
      event.keyCode === this.keyCodeMinus ||
      event.keyCode === this.keyCodeNumpadSubtract;
  }

  private handleConversationKeyEvent(event: KeyEvent): boolean {
    if (event.type !== KeyType.Down || !this.isModifierPressed(event, 'Ctrl')) {
      return false;
    }
    if (this.isConversationZoomInKey(event)) {
      this.adjustConversationFontScale(1);
      event.stopPropagation();
      return true;
    }
    if (this.isConversationZoomOutKey(event)) {
      this.adjustConversationFontScale(-1);
      event.stopPropagation();
      return true;
    }
    return false;
  }

  private axisVerticalValue(event: AxisEvent): number {
    let value: number = event.getVerticalAxisValue();
    if (value === 0 && event.axisVertical !== undefined) {
      value = event.axisVertical;
    }
    return value;
  }

  private handleConversationAxisZoom(event: AxisEvent): void {
    if (!this.isModifierPressed(event, 'Ctrl')) {
      return;
    }
    const vertical: number = this.axisVerticalValue(event);
    if (vertical === 0 || vertical !== vertical) {
      return;
    }
    this.adjustConversationFontScaleFromWheel(vertical < 0 ? 1 : -1);
  }

  private scheduleMessageScrollToBottom(force: boolean = false): void {
    if (!force && !this.messageAutoFollowToBottom) {
      return;
    }
    if (force) {
      this.clearMessageScheduledScrollTimers();
    }
    if (this.messageScheduledScrollTimerId < 0) {
      this.messageScheduledScrollTimerId = setTimeout(() => {
        this.messageScheduledScrollTimerId = -1;
        this.scrollMessagesToBottom(force);
      }, 0);
    }
    if (this.messageScheduledFollowUpScrollTimerId < 0) {
      this.messageScheduledFollowUpScrollTimerId = setTimeout(() => {
        this.messageScheduledFollowUpScrollTimerId = -1;
        this.scrollMessagesToBottom(force);
      }, 48);
    }
  }

  private scrollMessagesToBottom(force: boolean = false): void {
    if (!force && !this.messageAutoFollowToBottom) {
      return;
    }
    this.beginMessageProgrammaticScroll();
    try {
      this.messageScroller.scrollEdge(Edge.Bottom);
      this.messageAutoFollowToBottom = true;
    } catch (_err) {
    }
  }

  private clearMessageProgrammaticScrollTimer(): void {
    if (this.messageProgrammaticScrollTimerId >= 0) {
      clearTimeout(this.messageProgrammaticScrollTimerId);
      this.messageProgrammaticScrollTimerId = -1;
    }
  }

  private clearMessageScheduledScrollTimers(): void {
    if (this.messageScheduledScrollTimerId >= 0) {
      clearTimeout(this.messageScheduledScrollTimerId);
      this.messageScheduledScrollTimerId = -1;
    }
    if (this.messageScheduledFollowUpScrollTimerId >= 0) {
      clearTimeout(this.messageScheduledFollowUpScrollTimerId);
      this.messageScheduledFollowUpScrollTimerId = -1;
    }
  }

  private clearMessageUserScrollTimer(): void {
    if (this.messageUserScrollTimerId >= 0) {
      clearTimeout(this.messageUserScrollTimerId);
      this.messageUserScrollTimerId = -1;
    }
  }

  private beginMessageProgrammaticScroll(): void {
    this.clearMessageProgrammaticScrollTimer();
    this.messageProgrammaticScroll = true;
    this.messageProgrammaticScrollTimerId = setTimeout(() => {
      this.messageProgrammaticScroll = false;
      this.messageProgrammaticScrollTimerId = -1;
    }, 120);
  }

  private resumeMessageAutoFollow(): void {
    this.messageUserScrollActive = false;
    this.clearMessageUserScrollTimer();
    this.messageAutoFollowToBottom = true;
  }

  private beginMessageUserScroll(): void {
    this.clearMessageUserScrollTimer();
    this.messageUserScrollActive = true;
    this.messageUserScrollTimerId = setTimeout(() => {
      this.messageUserScrollActive = false;
      this.messageUserScrollTimerId = -1;
    }, 240);
  }

  private isUserMessageScrollSource(source: ScrollSource): boolean {
    return source === ScrollSource.DRAG ||
      source === ScrollSource.FLING ||
      source === ScrollSource.OTHER_USER_INPUT ||
      source === ScrollSource.SCROLL_BAR ||
      source === ScrollSource.SCROLL_BAR_FLING;
  }

  private isMessageScrollerAtEnd(): boolean {
    try {
      return this.messageScroller.isAtEnd();
    } catch (_err) {
      return true;
    }
  }

  private handleMessageWillScroll(_xOffset: number, yOffset: number, _scrollState: ScrollState, scrollSource: ScrollSource): OffsetResult | void {
    if (this.messageZoomWheelActiveUntil > Date.now() && scrollSource === ScrollSource.OTHER_USER_INPUT) {
      return { xOffset: 0, yOffset: 0 };
    }
    if (!this.isUserMessageScrollSource(scrollSource)) {
      return;
    }
    this.beginMessageUserScroll();
    this.messageProgrammaticScroll = false;
    if (yOffset < 0 || !this.isMessageScrollerAtEnd()) {
      this.messageAutoFollowToBottom = false;
    }
  }

  private handleMessageDidScroll(_xOffset: number, _yOffset: number, _scrollState: ScrollState): void {
    const atEnd: boolean = this.isMessageScrollerAtEnd();
    if (this.messageProgrammaticScroll) {
      if (atEnd) {
        this.messageAutoFollowToBottom = true;
      }
      return;
    }
    if (atEnd) {
      this.resumeMessageAutoFollow();
      return;
    }
    if (this.messageUserScrollActive) {
      this.messageAutoFollowToBottom = false;
    }
  }

  private handleMessageScrollEdge(side: Edge): void {
    if (side === Edge.Bottom) {
      this.messageAutoFollowToBottom = true;
      return;
    }
    if (side === Edge.Top) {
      this.messageAutoFollowToBottom = false;
    }
  }

  private jumpToLatestMessage(): void {
    this.resumeMessageAutoFollow();
    this.scrollMessagesToBottom(true);
  }

  private handleMessageScrollStop(): void {
    if (this.isMessageScrollerAtEnd()) {
      this.resumeMessageAutoFollow();
      return;
    }
    this.messageUserScrollActive = false;
    this.clearMessageUserScrollTimer();
  }

  private messageRenderKey(item: ChatMessage): string {
    const type: string = item.itemType ?? item.role;
    const status: string = item.status ?? '';
    const metadataText: string = item.metadata !== undefined ? JSON.stringify(item.metadata) : '';
    return `${item.id}:${type}:${status}:${metadataText.length}`;
  }

  private async connectOrDisconnect(): Promise<void> {
    codexBackend.configureServerUrl(this.serverUrl);
    if (this.connectionState === 'connected' || this.connectionState === 'connecting') {
      await codexBackend.disconnect();
      return;
    }

    try {
      await codexBackend.connect();
      this.loadProviderConfig();
      await this.restoreSessionsFromBackend();
      this.reconnectAttemptCount = 0;
      this.clearReconnectTimer();
      this.summaryTitle = '连接成功';
      this.summaryPoints = [
        'initialize / initialized 握手已经完成。',
        '现在可以直接发送 turn/start 请求。',
        '如需针对项目操作，请填写真实工作目录。'
      ];
    } catch (err) {
      this.summaryTitle = '连接失败';
      this.summaryPoints = [this.describeError(err)];
    }
  }

  private async connectEmbeddedHost(): Promise<void> {
    if (this.connectionState === 'connected' || this.connectionState === 'connecting') {
      return;
    }

    try {
      codexBackend.configureServerUrl(this.serverUrl);
      await codexBackend.connect();
      this.loadProviderConfig();
      await this.restoreSessionsFromBackend();
      this.summaryTitle = '应用内后端连接成功';
      this.summaryPoints = [
        'initialize / initialized 握手已经完成。',
        '当前页面连接的是应用内自启动的 Rust app-server。',
        '现在可以直接发送 turn/start 请求。'
      ];
    } catch (err) {
      this.reconnectAttemptCount += 1;
      const hostStatus = getEmbeddedCodexHostStatus();
      const retryDelayMs: number = Math.min(1500 * this.reconnectAttemptCount, 6000);
      this.summaryTitle = '应用内后端连接失败';
      this.summaryPoints = [
        hostStatus.message.length > 0 ? hostStatus.message : 'embedded host status unavailable',
        this.describeError(err),
        `系统将在 ${retryDelayMs} ms 后自动重试连接。`,
        '可以点击连接按钮重试，或者检查 native 日志。'
      ];
      this.scheduleEmbeddedHostReconnect(retryDelayMs);
    }
  }

  private async loginWithApiKey(): Promise<void> {
    if (this.isAuthenticating) {
      return;
    }

    const apiKey: string = this.apiKey.trim();
    if (apiKey.length === 0) {
      this.summaryTitle = '登录失败';
      this.summaryPoints = ['请先输入 OpenAI API Key。'];
      return;
    }

    this.isAuthenticating = true;
    try {
      await codexBackend.loginWithApiKey(apiKey);
      this.summaryTitle = 'OpenAI 认证已就绪';
      this.summaryPoints = [
        '已经通过 account/login/start 完成 API Key 登录。',
        '现在可以重新发送你的问题。',
        this.authStatusText
      ];
    } catch (err) {
      this.summaryTitle = '登录失败';
      this.summaryPoints = [this.describeError(err)];
    } finally {
      this.isAuthenticating = false;
    }
  }

  private loadProviderConfig(): void {
    const config: CodexProviderConfig = getEmbeddedCodexProviderConfig();
    const catalog = getEmbeddedCodexProviderCatalog();
    this.providerBaseUrl = config.baseUrl;
    this.providerApiKey = config.apiKey;
    this.manualModel = config.model;
    this.providerStatusText = this.describeProviderConfig(config);
    // 从 catalog 中获取当前激活的 provider 名称
    let activeName: string = '未选择';
    for (let i = 0; i < catalog.providers.length; i++) {
      if (catalog.providers[i].isActive) {
        activeName = catalog.providers[i].name;
        break;
      }
    }
    if (activeName === '未选择' && catalog.providers.length > 0) {
      activeName = catalog.providers[0].name;
    }
    this.providerName = activeName;
    hilog.info(
      INDEX_DOMAIN,
      INDEX_TAG,
      'loadProviderConfig baseUrl=%{public}s model=%{public}s apiKeyLen=%{public}d catalogProviders=%{public}d',
      config.baseUrl,
      config.model,
      config.apiKey.length,
      catalog.providers.length
    );
  }

  private async saveProviderConfig(): Promise<void> {
    if (this.isSavingProvider) {
      return;
    }

    this.isSavingProvider = true;
    try {
      hilog.info(
        INDEX_DOMAIN,
        INDEX_TAG,
        'saveProviderConfig input baseUrl=%{public}s model=%{public}s apiKeyLen=%{public}d',
        this.providerBaseUrl.trim(),
        this.manualModel.trim(),
        this.providerApiKey.trim().length
      );
      const config: CodexProviderConfig = saveEmbeddedCodexProviderConfig(
        this.providerBaseUrl.trim(),
        this.providerApiKey.trim(),
        this.manualModel.trim()
      );
      hilog.info(
        INDEX_DOMAIN,
        INDEX_TAG,
        'saveProviderConfig native returned baseUrl=%{public}s model=%{public}s apiKeyLen=%{public}d',
        config.baseUrl,
        config.model,
        config.apiKey.length
      );
      this.providerBaseUrl = config.baseUrl;
      this.providerApiKey = config.apiKey;
      this.manualModel = config.model;
      const importedCatalog = providerCatalogService.importCurrentProvider();
      hilog.info(
        INDEX_DOMAIN,
        INDEX_TAG,
        'saveProviderConfig imported catalog activeProviderId=%{public}s providers=%{public}d',
        importedCatalog.activeProviderId,
        importedCatalog.providers.length
      );
      this.providerStatusText = this.describeProviderConfig(config);
      this.summaryTitle = 'Provider config saved';
      this.summaryPoints = [
        'base_url, api_key, and default model were written to CODEX_HOME and synced to the active provider catalog.',
        'Restart the app to apply provider changes to the embedded app-server runtime.',
        this.providerStatusText
      ];
    } catch (err) {
      hilog.error(
        INDEX_DOMAIN,
        INDEX_TAG,
        'saveProviderConfig failed: %{public}s',
        this.describeError(err)
      );
      hilog.error(
        INDEX_DOMAIN,
        INDEX_TAG,
        'saveProviderConfig error details: %{public}s',
        JSON.stringify(err)
      );
      if (err instanceof Error && err.stack !== undefined) {
        hilog.error(
          INDEX_DOMAIN,
          INDEX_TAG,
          'saveProviderConfig stack: %{public}s',
          err.stack
        );
      }
      this.summaryTitle = 'Provider config failed';
      this.summaryPoints = [this.describeError(err)];
    } finally {
      this.isSavingProvider = false;
    }
  }

  private async approvePending(): Promise<void> {
    await codexBackend.approvePendingRequest();
  }

  private async declinePending(): Promise<void> {
    await codexBackend.declinePendingRequest();
  }

  private async selectWorkspace(item: WorkspaceItem): Promise<void> {
    this.activeCompactionNoticeId = '';
    this.activeWorkspaceId = item.id;
    this.syncSelectedCollaborationMode();
    this.workspaceRoot = this.workspaceRoots.get(item.id) ?? '';
    this.workspaceDraftText = this.workspaceRoot;
    this.directoryFilter = this.workspaceRoot;
    this.directoryFilterText = this.workspaceRoot.length > 0 ? this.workspaceRoot : '使用默认工作区';
    this.syncRecentWorkspaces();
    this.refreshWorkspaceBindingState();
    this.syncCurrentWorkspaceState();
    this.persistWorkspaceBindings();
    await this.loadSelectedWorkspaceHistory();
  }

  private lastConversationMessage(): ChatMessage | null {
    for (let index = this.messages.length - 1; index >= 0; index -= 1) {
      const item: ChatMessage = this.messages[index];
      const content: string = item.content.trim();
      if (content.length === 0 || item.id === 'welcome-1') {
        continue;
      }
      if (item.role === 'user' || item.role === 'assistant' || item.role === 'agent') {
        return item;
      }
    }
    return null;
  }

  private hasFailureSignal(text: string): boolean {
    const lowerText: string = text.toLowerCase();
    return lowerText.indexOf('失败') >= 0 ||
      lowerText.indexOf('错误') >= 0 ||
      lowerText.indexOf('异常') >= 0 ||
      lowerText.indexOf('error') >= 0 ||
      lowerText.indexOf('failed') >= 0 ||
      lowerText.indexOf('exception') >= 0;
  }


  private hasDiffSignal(): boolean {
    return this.diffFiles.length > 0 ||
      (this.changedFiles.trim().length > 0 && this.changedFiles !== NO_FILE_CHANGES_TEXT) ||
      this.diffStat.trim() !== '+0 -0';
  }

  private activeCompactionNotices(): CompactionNotice[] {
    const latest: CompactionNotice | null = this.latestActiveCompactionNotice();
    return latest === null ? [] : [latest];
  }

  private compactionNoticeRenderKey(notice: CompactionNotice): string {
    return `${notice.id}:${notice.status}:${notice.savedTokens}:${notice.oldTotalTokens}:${notice.newTotalTokens}:${this.compactionNoticeVersion}`;
  }

  private isCompactionNoticeExpanded(noticeId: string): boolean {
    return this.expandedCompactionIds.indexOf(noticeId) >= 0;
  }

  private toggleCompactionNoticeExpanded(noticeId: string): void {
    if (this.isCompactionNoticeExpanded(noticeId)) {
      this.expandedCompactionIds = this.expandedCompactionIds.filter((id: string) => id !== noticeId);
      return;
    }
    this.expandedCompactionIds = [...this.expandedCompactionIds, noticeId];
  }

  private retryCurrentCompaction(threadId: string = ''): void {
    const preferredThreadId: string = threadId.trim();
    const targetThreadId: string = preferredThreadId.length > 0
      ? preferredThreadId
      : (this.backendActiveThreadId.trim().length > 0 ? this.backendActiveThreadId.trim() : this.activeWorkspaceBindingId.trim());
    if (targetThreadId.length === 0 || this.compacting) {
      return;
    }
    this.resumeMessageAutoFollow();
    this.compactError = '';
    codexBackend.clearCompactionNotice(targetThreadId);
    void codexBackend.compactThread(targetThreadId).catch((err: Error) => {
      this.compactError = err.message.trim().length > 0 ? err.message : codexBackend.getLastCompactError();
    });
  }

  private accentBorderColor(role: string): string {
    switch (role) {
      case 'reasoning': return '#F59E0B';
      case 'command': return '#10B981';
      case 'tool': return '#3B82F6';
      case 'file': return '#A855F7';
      case 'search': return '#14B8A6';
      case 'plan': return '#F97316';
      case 'image': return '#EC4899';
      case 'hook': return '#EAB308';
      case 'review': return '#FACC15';
      case 'user': return '#3B82F6';
      default: return '#D4D4D8';
    }
  }

  private operationLabel(role: string): string {
    switch (role) {
      case 'reasoning': return '思考';
      case 'command': return '命令';
      case 'tool': return '工具';
      case 'file': return '文件';
      case 'search': return '搜索';
      case 'plan': return '计划';
      case 'image': return '图片';
      case 'hook': return '钩子';
      case 'review': return '审查';
      default: return role;
    }
  }


  private dynamicInputPlaceholder(): string {
    if (this.pendingRequestUserInput !== null) {
      return '上方有待补充问题，也可以输入追加说明...';
    }
    if (this.pendingApproval !== null) {
      return '上方有待确认操作，也可以输入替代指令...';
    }
    if (this.isRunning) {
      return '任务执行中，输入下一步想法会先保留为草稿...';
    }
    if (this.connectionState !== 'connected') {
      return '连接后输入要发送给 ArkPilot 的指令...';
    }

    const lastMessage: ChatMessage | null = this.lastConversationMessage();
    if (lastMessage === null) {
      return '输入要发送给 ArkPilot 的指令...';
    }
    if (this.hasFailureSignal(`${this.summaryTitle}\n${lastMessage.content}`)) {
      return '描述期望结果，或要求继续修复最新错误...';
    }
    if (this.hasDiffSignal()) {
      return '围绕当前 diff 提问、要求检查或继续修改...';
    }
    if (lastMessage.role === 'user') {
      return '补充上条需求的背景、路径或验收条件...';
    }
    return '基于最新回复继续追问...';
  }

  private connectionButtonLabel(): string {
    if (this.connectionState === 'connected') {
      return '断开';
    }
    if (this.connectionState === 'connecting') {
      return '连接中';
    }
    return '连接';
  }

  private authButtonLabel(): string {
    return 'Log in';
  }

  private providerButtonLabel(): string {
    if (this.isSavingProvider) {
      return 'Saving...';
    }
    return 'Save provider';
  }

  private describeProviderConfig(config: CodexProviderConfig): string {
    const baseUrl: string = config.baseUrl.trim().length > 0 ? config.baseUrl.trim() : 'https://api.openai.com/v1';
    const model: string = config.model.trim().length > 0 ? config.model.trim() : 'default';
    const auth: string = config.apiKey.trim().length > 0 ? 'API key set' : 'No API key';
    return `base_url: ${baseUrl} | model: ${model} | ${auth}`;
  }

  private connectionChipBackground(): string {
    if (this.connectionState === 'connected') {
      return '#DCFCE7';
    }
    if (this.connectionState === 'connecting') {
      return '#fffefbc7';
    }
    if (this.connectionState === 'error') {
      return '#FEE2E2';
    }
    return '#E2E8F0';
  }

  private connectionChipColor(): string {
    if (this.connectionState === 'connected') {
      return '#166534';
    }
    if (this.connectionState === 'connecting') {
      return '#92400E';
    }
    if (this.connectionState === 'error') {
      return '#B91C1C';
    }
    return '#475569';
  }

  private messageBackground(role: string): string {
    switch (role) {
      case 'assistant':
      case 'agent':
        return '#00000000';
      case 'user':
        return '#EFF6FF';
      default:
        return '#FFFFFF';
    }
  }

  private authorColor(role: string): string {
    switch (role) {
      case 'assistant':
      case 'agent':
        return '#3B82F6';
      case 'system':
        return '#71717A';
      case 'reasoning':
        return '#D97706';
      case 'command':
        return '#059669';
      case 'tool':
        return '#2563EB';
      case 'file':
        return '#9333EA';
      case 'search':
        return '#10B981';
      case 'plan':
        return '#EA580C';
      case 'image':
        return '#DB2777';
      case 'hook':
        return '#B45309';
      case 'review':
        return '#A16207';
      case 'user':
        return '#2563EB';
      default:
        return '#7C3AED';
    }
  }

  private diffBackground(kind: string): string {
    if (kind === 'add') {
      return '#ECFDF3';
    }
    if (kind === 'delete') {
      return '#FEF2F2';
    }
    return '#F8FAFC';
  }

  private diffColor(kind: string): string {
    if (kind === 'add') {
      return '#15803D';
    }
    if (kind === 'delete') {
      return '#DC2626';
    }
    return '#475569';
  }

  private isWorkspaceActive(item: WorkspaceItem): boolean {
    return this.activeWorkspaceId === item.id;
  }

  private toggleLeftDrawer(): void {
    this.runPanelMotion(() => {
      this.showLeftDrawer = !this.showLeftDrawer;
    });
  }

  private toggleRightDrawer(): void {
    this.runPanelMotion(() => {
      this.showRightDrawer = !this.showRightDrawer;
    });
  }

  private selectRightPanelTab(tab: RightPanelTab): void {
    this.rightPanelTab = tab;
  }

  private hasBrowserPreview(): boolean {
    return this.browserPreviewSrc.trim().length > 0;
  }

  private browserPreviewTitleText(): string {
    const title: string = this.browserPreviewTitle.trim();
    if (title.length > 0) {
      return title;
    }
    if (this.browserPreviewSrc.trim().length > 0) {
      return this.fileNameFromTarget(this.browserPreviewSrc);
    }
    return '网页预览';
  }

  private browserPreviewSubtitleText(): string {
    const src: string = this.browserPreviewSrc.trim();
    return src.length > 0 ? src : '点击对话中的 HTML 文件后会在这里预览';
  }

  private showHtmlPreviewInRightPanel(targetUri: string, title: string): void {
    this.browserPreviewSrc = targetUri;
    this.browserPreviewTitle = title.length > 0 ? title : this.fileNameFromTarget(targetUri);
    this.browserPreviewError = '';
    this.rightPanelTab = 'browser';
    this.showRightDrawer = true;
  }

  private closeBrowserPreview(): void {
    this.browserPreviewSrc = '';
    this.browserPreviewTitle = '';
    this.browserPreviewError = '';
    this.rightPanelTab = 'diff';
  }

  private refreshBrowserPreview(): void {
    if (!this.hasBrowserPreview()) {
      return;
    }
    try {
      this.browserPreviewController.refresh();
    } catch (err) {
      promptAction.showToast({ message: `刷新网页预览失败: ${this.describeError(err)}`, duration: 2200 });
    }
  }

  private applyResponsiveLayoutProfile(force: boolean = false): void {
    if (!force && this.lastAppliedBreakpoint === this.currentBreakpoint) {
      return;
    }
    const profile = getArkPilotLayoutProfile(this.currentBreakpoint);
    if (profile.leftPanelWidth > 0) {
      this.leftPanelWidth = profile.leftPanelWidth;
    }
    if (profile.rightPanelWidth > 0) {
      this.rightPanelWidth = profile.rightPanelWidth;
    }
    this.showLeftDrawer = profile.leftPanelPersistent;
    this.showRightDrawer = profile.rightPanelPersistent;
    this.lastAppliedBreakpoint = this.currentBreakpoint;
  }

  private onBreakpointChanged(): void {
    this.applyResponsiveLayoutProfile();
  }

  private isPhoneBreakpoint(): boolean {
    return this.currentBreakpoint === 'xs' || this.currentBreakpoint === 'sm';
  }

  private describeError(err: Object): string {
    if (err instanceof Error) {
      return err.message;
    }
    return JSON.stringify(err);
  }

  private normalizedDirectoryUri(rawUri: string): string {
    let result: string = rawUri.trim();
    while (result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }

  private fileUriToFsPath(rawUri: string): string {
    try {
      return new fileUri.FileUri(rawUri).path;
    } catch (_err) {
      return rawUri;
    }
  }

  private encodeUriPathSegment(segment: string): string {
    return encodeURIComponent(segment).replace(/%2F/g, '/');
  }

  private childUri(parentUri: string, childName: string): string {
    return `${this.normalizedDirectoryUri(parentUri)}/${this.encodeUriPathSegment(childName)}`;
  }

  private copyProjectFileToUri(sourcePath: string, targetUri: string): void {
    const targetPath: string = this.fileUriToFsPath(targetUri);
    let source: fileIo.File | null = null;
    let target: fileIo.File | null = null;
    try {
      source = fileIo.openSync(sourcePath, fileIo.OpenMode.READ_ONLY);
    } catch (err) {
      throw new Error(`打开源文件失败: ${sourcePath}; ${this.describeError(err)}`);
    }
    try {
      target = fileIo.openSync(targetPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
    } catch (err) {
      fileIo.closeSync(source);
      throw new Error(`打开目标文件失败: ${targetUri}; ${this.describeError(err)}`);
    }
    try {
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
    } catch (err) {
      throw new Error(`复制文件失败: ${sourcePath} -> ${targetUri}; ${this.describeError(err)}`);
    } finally {
      fileIo.closeSync(source);
      fileIo.closeSync(target);
    }
  }

  private copyProjectDirectoryToUri(sourceRoot: string, targetRootUri: string): number {
    const targetRootPath: string = this.fileUriToFsPath(targetRootUri);
    try {
      const sourceStat = fileIo.statSync(sourceRoot);
      if (!sourceStat.isDirectory()) {
        throw new Error('源路径不是目录');
      }
    } catch (err) {
      throw new Error(`读取源目录失败: ${sourceRoot}; ${this.describeError(err)}`);
    }
    try {
      fileIo.mkdirSync(targetRootPath, true);
    } catch (_err) {
    }
    let copiedCount: number = 0;
    let entries: string[] = [];
    try {
      entries = fileIo.listFileSync(sourceRoot) as string[];
    } catch (err) {
      throw new Error(`列出源目录失败: ${sourceRoot}; ${this.describeError(err)}`);
    }
    for (let index: number = 0; index < entries.length; index += 1) {
      const entry: string = entries[index];
      const sourcePath: string = `${sourceRoot}/${entry}`;
      const targetUri: string = this.childUri(targetRootUri, entry);
      try {
        const stat = fileIo.statSync(sourcePath);
        if (stat.isDirectory()) {
          copiedCount += this.copyProjectDirectoryToUri(sourcePath, targetUri);
        } else if (stat.isFile()) {
          this.copyProjectFileToUri(sourcePath, targetUri);
          copiedCount += 1;
        }
      } catch (err) {
        throw new Error(`同步条目失败: ${sourcePath} -> ${targetUri}; ${this.describeError(err)}`);
      }
    }
    return copiedCount;
  }

  private copyFileByPath(sourcePath: string, targetPath: string): void {
    if (sourcePath === targetPath) {
      return;
    }
    let source: fileIo.File | null = null;
    let target: fileIo.File | null = null;
    try {
      source = fileIo.openSync(sourcePath, fileIo.OpenMode.READ_ONLY);
    } catch (err) {
      throw new Error(`打开源文件失败: ${sourcePath}; ${this.describeError(err)}`);
    }
    try {
      target = fileIo.openSync(targetPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
    } catch (err) {
      fileIo.closeSync(source);
      throw new Error(`打开目标文件失败: ${targetPath}; ${this.describeError(err)}`);
    }
    try {
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
    } catch (err) {
      throw new Error(`复制文件失败: ${sourcePath} -> ${targetPath}; ${this.describeError(err)}`);
    } finally {
      fileIo.closeSync(source);
      fileIo.closeSync(target);
    }
  }

  private deletePathRecursively(path: string): number {
    try {
      const stat = fileIo.statSync(path);
      if (stat.isDirectory()) {
        let deletedCount: number = 0;
        const entries: string[] = fileIo.listFileSync(path) as string[];
        for (let index: number = 0; index < entries.length; index += 1) {
          deletedCount += this.deletePathRecursively(`${path}/${entries[index]}`);
        }
        fileIo.rmdirSync(path);
        return deletedCount + 1;
      }
      fileIo.unlinkSync(path);
      return 1;
    } catch (err) {
      throw new Error(`删除路径失败: ${path}; ${this.describeError(err)}`);
    }
  }

  private ensureMirrorTargetDirectory(path: string): void {
    try {
      const stat = fileIo.statSync(path);
      if (stat.isDirectory()) {
        return;
      }
      this.deletePathRecursively(path);
    } catch (_err) {
    }
    try {
      fileIo.mkdirSync(path, true);
    } catch (err) {
      try {
        const stat = fileIo.statSync(path);
        if (stat.isDirectory()) {
          return;
        }
      } catch (_statErr) {
      }
      throw new Error(`创建项目目录失败: ${path}; ${this.describeError(err)}`);
    }
  }

  private mirrorDirectoryByPath(sourceRoot: string, targetRoot: string): DirectoryMirrorResult {
    try {
      const sourceStat = fileIo.statSync(sourceRoot);
      if (!sourceStat.isDirectory()) {
        throw new Error('同步文件夹不是目录');
      }
    } catch (err) {
      throw new Error(`读取同步文件夹失败: ${sourceRoot}; ${this.describeError(err)}`);
    }
    this.ensureMirrorTargetDirectory(targetRoot);

    let sourceEntries: string[] = [];
    let targetEntries: string[] = [];
    try {
      sourceEntries = fileIo.listFileSync(sourceRoot) as string[];
    } catch (err) {
      throw new Error(`列出同步文件夹失败: ${sourceRoot}; ${this.describeError(err)}`);
    }
    try {
      targetEntries = fileIo.listFileSync(targetRoot) as string[];
    } catch (err) {
      throw new Error(`列出项目目录失败: ${targetRoot}; ${this.describeError(err)}`);
    }

    let copiedFiles: number = 0;
    let deletedEntries: number = 0;
    for (let index: number = 0; index < targetEntries.length; index += 1) {
      const entry: string = targetEntries[index];
      if (sourceEntries.indexOf(entry) < 0) {
        deletedEntries += this.deletePathRecursively(`${targetRoot}/${entry}`);
      }
    }

    for (let index: number = 0; index < sourceEntries.length; index += 1) {
      const entry: string = sourceEntries[index];
      const sourcePath: string = `${sourceRoot}/${entry}`;
      const targetPath: string = `${targetRoot}/${entry}`;
      try {
        const sourceStat = fileIo.statSync(sourcePath);
        if (sourceStat.isDirectory()) {
          try {
            const targetStat = fileIo.statSync(targetPath);
            if (!targetStat.isDirectory()) {
              deletedEntries += this.deletePathRecursively(targetPath);
            }
          } catch (_err) {
          }
          const childResult: DirectoryMirrorResult = this.mirrorDirectoryByPath(sourcePath, targetPath);
          copiedFiles += childResult.copiedFiles;
          deletedEntries += childResult.deletedEntries;
        } else if (sourceStat.isFile()) {
          try {
            const targetStat = fileIo.statSync(targetPath);
            if (targetStat.isDirectory()) {
              deletedEntries += this.deletePathRecursively(targetPath);
            }
          } catch (_err) {
          }
          this.copyFileByPath(sourcePath, targetPath);
          copiedFiles += 1;
        }
      } catch (err) {
        throw new Error(`导入条目失败: ${sourcePath} -> ${targetPath}; ${this.describeError(err)}`);
      }
    }
    return new DirectoryMirrorResult(copiedFiles, deletedEntries);
  }

  private async syncProjectToImportSource(proj: ProjectRecord): Promise<void> {
    const sourceUri: string = proj.sourceUri.trim();
    if (sourceUri.length === 0) {
      promptAction.showToast({ message: '该项目没有同步文件夹', duration: 2000 });
      return;
    }
    const projectPath: string = proj.path.trim();
    if (projectPath.length === 0) {
      promptAction.showToast({ message: '项目运行目录为空，无法同步', duration: 2000 });
      return;
    }
    const targetLabel: string = this.canSelectExternalFolder() ? '同步文件夹' : '下载目录';
    promptAction.showToast({ message: `开始同步到${targetLabel}...`, duration: 1200 });
    try {
      try {
        await this.activateProjectSourcePermission(sourceUri);
      } catch (activationErr) {
        hilog.warn(INDEX_DOMAIN, INDEX_TAG, 'activate source permission failed: %{public}s', this.describeError(activationErr));
      }
      const copiedCount: number = this.copyProjectDirectoryToUri(projectPath, sourceUri);
      promptAction.showToast({ message: `已同步 ${copiedCount.toString()} 个文件到${targetLabel}`, duration: 2600 });
    } catch (err) {
      hilog.error(INDEX_DOMAIN, INDEX_TAG, 'sync project to import source failed: %{public}s', this.describeError(err));
      promptAction.showToast({ message: `同步失败: ${this.describeError(err)}；同步文件夹可能已被删除或授权失效，请重新选择同步文件夹`, duration: 3200 });
    }
  }

  private async importProjectFromSyncFolder(proj: ProjectRecord): Promise<void> {
    const sourceUri: string = proj.sourceUri.trim();
    if (sourceUri.length === 0) {
      promptAction.showToast({ message: '该项目没有同步文件夹', duration: 2000 });
      return;
    }
    const projectPath: string = proj.path.trim();
    if (projectPath.length === 0) {
      promptAction.showToast({ message: '项目运行目录为空，无法导入', duration: 2000 });
      return;
    }
    promptAction.showToast({ message: '开始导入同步文件夹内容...', duration: 1200 });
    try {
      try {
        await this.activateProjectSourcePermission(sourceUri);
      } catch (activationErr) {
        hilog.warn(INDEX_DOMAIN, INDEX_TAG, 'activate source permission failed: %{public}s', this.describeError(activationErr));
      }
      const sourcePath: string = this.fileUriToFsPath(sourceUri);
      const result: DirectoryMirrorResult = this.mirrorDirectoryByPath(sourcePath, projectPath);
      promptAction.showToast({ message: `已导入 ${result.copiedFiles.toString()} 个文件，删除 ${result.deletedEntries.toString()} 个多余条目`, duration: 3000 });
    } catch (err) {
      hilog.error(INDEX_DOMAIN, INDEX_TAG, 'import project from sync folder failed: %{public}s', this.describeError(err));
      promptAction.showToast({ message: `导入失败: ${this.describeError(err)}；同步文件夹可能已被删除或授权失效，请重新选择同步文件夹`, duration: 3600 });
    }
  }

  private openWebTarget(rawTarget: string, label: string, sourceMessageId?: string): void {
    const target: string = this.cleanMarkdownLinkTarget(rawTarget);
    if (target.length === 0) {
      promptAction.showToast({ message: '链接地址为空', duration: 1600 });
      return;
    }
    if (this.isHttpUrl(target)) {
      this.openHttpTarget(target, label);
      return;
    }
    if (this.isHtmlFileTarget(target)) {
      const htmlUri: string = this.htmlTargetToUri(target, sourceMessageId);
      if (htmlUri.length > 0) {
        this.showHtmlPreviewInRightPanel(htmlUri, label.length > 0 ? label : this.fileNameFromTarget(target));
      }
      return;
    }
    if (this.isMarkdownFileTarget(target)) {
      const markdownUri: string = this.markdownTargetToUri(target, sourceMessageId);
      if (markdownUri.length > 0) {
        this.openViewDataTarget(markdownUri, 'text/markdown', label.length > 0 ? label : this.fileNameFromTarget(target), true);
      }
      return;
    }
    promptAction.showToast({ message: '当前仅支持打开 HTTP/HTTPS 链接、HTML 文件和 Markdown 文件', duration: 2200 });
  }

  private openHtmlPreviewTarget(targetUri: string, title: string): void {
    try {
      router.pushUrl({
        url: 'pages/WebPreviewPage',
        params: {
          src: targetUri,
          title: title.length > 0 ? title : this.fileNameFromTarget(targetUri)
        }
      }).catch((err: Object) => {
        promptAction.showToast({ message: `打开网页预览失败: ${this.describeError(err)}`, duration: 2600 });
      });
    } catch (err) {
      promptAction.showToast({ message: `打开网页预览失败: ${this.describeError(err)}`, duration: 2600 });
    }
  }

  private openHttpTarget(target: string, label: string): void {
    const context: common.UIAbilityContext | null = this.currentAbilityContext();
    if (context === null) {
      promptAction.showToast({ message: '当前页面上下文不可用，无法打开浏览器', duration: 2200 });
      return;
    }
    const options: OpenLinkOptions = {
      appLinkingOnly: false
    };
    try {
      context.openLink(target, options)
        .then(() => {
          promptAction.showToast({ message: '已在浏览器中打开', duration: 1400 });
        })
        .catch((_err: Object) => {
          this.openViewDataTarget(target, 'text/html', label.length > 0 ? label : target, false);
        });
    } catch (_err) {
      this.openViewDataTarget(target, 'text/html', label.length > 0 ? label : target, false);
    }
  }

  private openViewDataTarget(targetUri: string, mimeType: string, title: string, grantRead: boolean): void {
    const context: common.UIAbilityContext | null = this.currentAbilityContext();
    if (context === null) {
      promptAction.showToast({ message: '当前页面上下文不可用，无法打开链接', duration: 2200 });
      return;
    }
    const params: Record<string, Object> = {};
    params[wantConstant.Params.CONTENT_TITLE_KEY] = title;
    if (grantRead) {
      params[wantConstant.Params.PARAMS_STREAM] = [targetUri];
    }
    const want: Want = {
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: targetUri,
      type: mimeType,
      parameters: params,
      flags: grantRead ? wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION : 0
    };
    try {
      context.startAbility(want)
        .then(() => {
          promptAction.showToast({ message: '已打开链接', duration: 1400 });
        })
        .catch((err: Object) => {
          promptAction.showToast({ message: `打开失败: ${this.describeError(err)}`, duration: 2600 });
        });
    } catch (err) {
      promptAction.showToast({ message: `打开失败: ${this.describeError(err)}`, duration: 2600 });
    }
  }

  private currentAbilityContext(): common.UIAbilityContext | null {
    const hostContext = this.getUIContext().getHostContext();
    if (hostContext === undefined || hostContext === null) {
      return null;
    }
    return hostContext as common.UIAbilityContext;
  }

  private isHttpUrl(target: string): boolean {
    const lower: string = target.trim().toLowerCase();
    return lower.startsWith('http://') || lower.startsWith('https://');
  }

  private isFileUri(target: string): boolean {
    return target.trim().toLowerCase().startsWith('file://');
  }

  private isOpenableWebTarget(target: string): boolean {
    const cleanTarget: string = this.cleanMarkdownLinkTarget(target);
    return this.isHttpUrl(cleanTarget) || this.isHtmlFileTarget(cleanTarget) || this.isMarkdownFileTarget(cleanTarget);
  }

  private isHtmlFileTarget(target: string): boolean {
    const pathPart: string = this.localFilePathPart(target);
    return pathPart.endsWith('.html') || pathPart.endsWith('.htm');
  }

  private isMarkdownFileTarget(target: string): boolean {
    const pathPart: string = this.localFilePathPart(target);
    return pathPart.endsWith('.md') || pathPart.endsWith('.markdown');
  }

  private localFilePathPart(target: string): string {
    return this.localFileTargetPath(target).toLowerCase();
  }

  private localFileTargetPath(target: string): string {
    const cleanTarget: string = target.trim();
    let end: number = cleanTarget.length;
    const queryIndex: number = cleanTarget.indexOf('?');
    if (queryIndex >= 0 && queryIndex < end) {
      end = queryIndex;
    }
    const hashIndex: number = cleanTarget.indexOf('#');
    if (hashIndex >= 0 && hashIndex < end) {
      end = hashIndex;
    }
    return cleanTarget.substring(0, end);
  }

  private localFileTargetSuffix(target: string): string {
    const cleanTarget: string = target.trim();
    const pathPart: string = this.localFileTargetPath(cleanTarget);
    return cleanTarget.substring(pathPart.length);
  }

  private htmlTargetToUri(target: string, sourceMessageId?: string): string {
    const cleanTarget: string = target.trim();
    if (!this.isHtmlFileTarget(cleanTarget)) {
      return '';
    }
    if (this.isHttpUrl(cleanTarget)) {
      return cleanTarget;
    }
    if (this.isFileUri(cleanTarget)) {
      return cleanTarget;
    }
    const resolved: LocalPathResolution = this.resolveLocalFileTarget(this.localFileTargetPath(cleanTarget), sourceMessageId);
    if (resolved.path.length === 0) {
      promptAction.showToast({ message: '无法定位相对 HTML 文件，请先设置工作目录或让回复包含绝对路径', duration: 2600 });
      return '';
    }
    const resolvedUri: string = this.pathToFileUri(resolved.path);
    return resolvedUri.length > 0 ? `${resolvedUri}${this.localFileTargetSuffix(cleanTarget)}` : '';
  }

  private markdownTargetToUri(target: string, sourceMessageId?: string): string {
    const cleanTarget: string = target.trim();
    if (!this.isMarkdownFileTarget(cleanTarget)) {
      return '';
    }
    if (this.isHttpUrl(cleanTarget)) {
      return cleanTarget;
    }
    if (this.isFileUri(cleanTarget)) {
      return cleanTarget;
    }
    const resolved: LocalPathResolution = this.resolveLocalFileTarget(this.localFileTargetPath(cleanTarget), sourceMessageId);
    if (resolved.path.length === 0) {
      promptAction.showToast({ message: '无法定位相对 Markdown 文件，请先设置工作目录或让回复包含绝对路径', duration: 2600 });
      return '';
    }
    const resolvedUri: string = this.pathToFileUri(resolved.path);
    return resolvedUri.length > 0 ? `${resolvedUri}${this.localFileTargetSuffix(cleanTarget)}` : '';
  }

  private resolveLocalFileTarget(target: string, sourceMessageId?: string): LocalPathResolution {
    const normalizedTarget: string = this.collapseLocalPathSegments(target.replace(/\\/g, '/'));
    if (this.isAbsoluteLocalPath(normalizedTarget)) {
      return new LocalPathResolution(normalizedTarget, this.localFileExists(normalizedTarget));
    }

    const roots: string[] = this.localFileResolutionRoots(sourceMessageId);
    if (roots.length === 0) {
      return new LocalPathResolution('');
    }

    const candidates: string[] = [];
    for (let index: number = 0; index < roots.length; index += 1) {
      const candidate: string = this.joinLocalPath(roots[index], normalizedTarget);
      candidates.push(candidate);
      if (this.localFileExists(candidate)) {
        return new LocalPathResolution(candidate, true);
      }
    }

    return new LocalPathResolution(candidates[0] ?? '');
  }

  private localFileResolutionRoots(sourceMessageId?: string): string[] {
    const roots: string[] = [];
    const sourceIndex: number = this.messageIndexById(sourceMessageId ?? '');
    if (sourceIndex >= 0) {
      this.addMessageLocalPathRoots(roots, this.messages[sourceIndex]);
      for (let index: number = sourceIndex - 1; index >= 0; index -= 1) {
        this.addMessageLocalPathRoots(roots, this.messages[index]);
      }
    } else {
      for (let index: number = this.messages.length - 1; index >= 0; index -= 1) {
        this.addMessageLocalPathRoots(roots, this.messages[index]);
      }
    }

    this.addLocalPathRoot(roots, this.workspaceRoot);
    this.workspaceRoots.forEach((root: string) => {
      this.addLocalPathRoot(roots, root);
    });
    for (let index: number = 0; index < this.projects.length; index += 1) {
      this.addLocalPathRoot(roots, this.projects[index].path);
    }
    return roots;
  }

  private messageIndexById(messageId: string): number {
    if (messageId.trim().length === 0) {
      return -1;
    }
    for (let index: number = 0; index < this.messages.length; index += 1) {
      if (this.messages[index].id === messageId) {
        return index;
      }
    }
    return -1;
  }

  private addMessageLocalPathRoots(roots: string[], message: ChatMessage): void {
    const metadata: Record<string, Object> | undefined = message.metadata;
    if (metadata === undefined || metadata === null) {
      return;
    }

    const cwdValue: Object | undefined = metadata['cwd'];
    if (typeof cwdValue === 'string') {
      this.addLocalPathRoot(roots, cwdValue as string);
    }

    this.addMetadataPathParentRoot(roots, metadata['path']);
    this.addMetadataPathParentRoot(roots, metadata['savedPath']);

    const filesValue: Object | undefined = metadata['files'];
    if (Array.isArray(filesValue)) {
      const files: Object[] = filesValue as Object[];
      for (let index: number = 0; index < files.length; index += 1) {
        this.addMetadataPathParentRoot(roots, files[index]);
      }
    }
  }

  private addMetadataPathParentRoot(roots: string[], rawValue: Object | undefined): void {
    if (typeof rawValue !== 'string') {
      return;
    }
    const normalizedPath: string = this.collapseLocalPathSegments((rawValue as string).trim().replace(/\\/g, '/'));
    if (!this.isAbsoluteLocalPath(normalizedPath)) {
      return;
    }
    this.addLocalPathRoot(roots, this.parentLocalPath(normalizedPath));
  }

  private addLocalPathRoot(roots: string[], rawRoot: string): void {
    let normalizedRoot: string = this.collapseLocalPathSegments(rawRoot.trim().replace(/\\/g, '/'));
    if (normalizedRoot.length > 1) {
      normalizedRoot = normalizedRoot.replace(/\/+$/g, '');
    }
    if (normalizedRoot.length === 0) {
      return;
    }
    for (let index: number = 0; index < roots.length; index += 1) {
      if (roots[index].toLowerCase() === normalizedRoot.toLowerCase()) {
        return;
      }
    }
    roots.push(normalizedRoot);
  }

  private joinLocalPath(base: string, target: string): string {
    return this.collapseLocalPathSegments(`${base.replace(/\/+$/g, '')}/${target.replace(/^\/+/g, '')}`);
  }

  private parentLocalPath(path: string): string {
    const normalizedPath: string = path.replace(/\\/g, '/');
    const slashIndex: number = normalizedPath.lastIndexOf('/');
    if (slashIndex <= 0) {
      return '';
    }
    return normalizedPath.substring(0, slashIndex);
  }

  private localFileExists(path: string): boolean {
    try {
      const stat = fileIo.statSync(path);
      return stat !== undefined && stat.isFile();
    } catch (_err) {
      return false;
    }
  }

  private collapseLocalPathSegments(path: string): string {
    const normalizedPath: string = path.trim().replace(/\\/g, '/');
    if (normalizedPath.length === 0) {
      return '';
    }

    let prefix: string = '';
    let rest: string = normalizedPath;
    if (/^[A-Za-z]:\//.test(normalizedPath)) {
      prefix = normalizedPath.substring(0, 3);
      rest = normalizedPath.substring(3);
    } else if (normalizedPath.startsWith('/')) {
      prefix = '/';
      rest = normalizedPath.replace(/^\/+/g, '');
    }

    const parts: string[] = [];
    const rawParts: string[] = rest.split('/');
    for (let index: number = 0; index < rawParts.length; index += 1) {
      const part: string = rawParts[index];
      if (part.length === 0 || part === '.') {
        continue;
      }
      if (part === '..') {
        if (parts.length > 0 && parts[parts.length - 1] !== '..') {
          parts.pop();
        } else if (prefix.length === 0) {
          parts.push(part);
        }
        continue;
      }
      parts.push(part);
    }

    if (prefix.length > 0) {
      return `${prefix}${parts.join('/')}`;
    }
    return parts.join('/');
  }

  private isAbsoluteLocalPath(path: string): boolean {
    const normalizedPath: string = path.replace(/\\/g, '/');
    return normalizedPath.startsWith('/') || /^[A-Za-z]:\//.test(normalizedPath);
  }

  private pathToFileUri(path: string): string {
    const normalizedPath: string = path.replace(/\\/g, '/');
    const publicDocsUri: string = this.publicDocsFileUriFromPath(normalizedPath);
    if (publicDocsUri.length > 0) {
      return publicDocsUri;
    }
    try {
      return fileUri.getUriFromPath(normalizedPath);
    } catch (_err) {
      return this.fallbackFileUriFromPath(normalizedPath);
    }
  }

  private publicDocsFileUriFromPath(path: string): string {
    const normalizedPath: string = path.replace(/\\/g, '/');
    const pathWithoutLeadingSlash: string = normalizedPath.replace(/^\/+/g, '');
    if (pathWithoutLeadingSlash.toLowerCase().startsWith('storage/users/currentuser/')) {
      return `file://docs/${this.encodeFileUriPath(pathWithoutLeadingSlash)}`;
    }
    return '';
  }

  private fallbackFileUriFromPath(path: string): string {
    const normalizedPath: string = path.replace(/\\/g, '/');
    const encodedPath: string = this.encodeFileUriPath(normalizedPath);
    if (/^[A-Za-z]:\//.test(normalizedPath)) {
      return `file:///${encodedPath}`;
    }
    if (normalizedPath.startsWith('/')) {
      return `file://${encodedPath}`;
    }
    return `file://${encodedPath}`;
  }

  private encodeFileUriPath(path: string): string {
    return encodeURI(path).replace(/#/g, '%23').replace(/\?/g, '%3F');
  }

  private fileNameFromTarget(target: string): string {
    const pathPart: string = target.split('?')[0].split('#')[0].replace(/\\/g, '/');
    const slashIndex: number = pathPart.lastIndexOf('/');
    return slashIndex >= 0 ? pathPart.substring(slashIndex + 1) : pathPart;
  }

  private copyPlainText(text: string, successMessage: string): void {
    if (text.length === 0) {
      promptAction.showToast({ message: '没有可复制内容', duration: 1600 });
      return;
    }
    try {
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      const systemPasteboard = pasteboard.getSystemPasteboard();
      void systemPasteboard.setData(pasteData);
      promptAction.showToast({ message: successMessage, duration: 1600 });
    } catch (_err) {
      promptAction.showToast({ message: '复制失败', duration: 2000 });
    }
  }

  private messageCopyText(item: ChatMessage): string {
    return this.messageOriginalText(item.content);
  }

  private copyMessage(item: ChatMessage): void {
    this.copyPlainText(this.messageCopyText(item), '消息已复制');
  }

  private messageOriginalText(content: string): string {
    return content.trimEnd();
  }

  private placeholderDiffLine(id: string, content: string): CodeDiffLine {
    return new CodeDiffLine(id, '1', ' ', content, 'context');
  }

  private diffFileKey(filePath: string): string {
    const trimmedFilePath: string = filePath.trim();
    return trimmedFilePath.length > 0 ? trimmedFilePath : UNKNOWN_DIFF_FILE_TEXT;
  }

  private diffFileDisplayName(filePath: string): string {
    const normalizedPath: string = this.diffFileKey(filePath).replace(/\\/g, '/');
    const slashIndex: number = normalizedPath.lastIndexOf('/');
    return slashIndex >= 0 ? normalizedPath.substring(slashIndex + 1) : normalizedPath;
  }

  private buildDiffFiles(lines: CodeDiffLine[]): CodeDiffFile[] {
    const orderedPaths: string[] = [];
    const groupedLines: Map<string, CodeDiffLine[]> = new Map();
    const addCounts: Map<string, number> = new Map();
    const deleteCounts: Map<string, number> = new Map();

    for (let index: number = 0; index < lines.length; index += 1) {
      const line: CodeDiffLine = lines[index];
      const filePath: string = this.diffFileKey(line.filePath);
      if (!groupedLines.has(filePath)) {
        groupedLines.set(filePath, []);
        addCounts.set(filePath, 0);
        deleteCounts.set(filePath, 0);
        orderedPaths.push(filePath);
      }
      (groupedLines.get(filePath) as CodeDiffLine[]).push(line);
      if (line.kind === 'add') {
        addCounts.set(filePath, (addCounts.get(filePath) ?? 0) + 1);
      } else if (line.kind === 'delete') {
        deleteCounts.set(filePath, (deleteCounts.get(filePath) ?? 0) + 1);
      }
    }

    const files: CodeDiffFile[] = [];
    for (let index: number = 0; index < orderedPaths.length; index += 1) {
      const filePath: string = orderedPaths[index];
      files.push(
        new CodeDiffFile(
          filePath,
          this.diffFileDisplayName(filePath),
          `+${addCounts.get(filePath) ?? 0} -${deleteCounts.get(filePath) ?? 0}`,
          groupedLines.get(filePath) ?? []
        )
      );
    }
    return files;
  }

  private diffFileByPath(path: string, files?: CodeDiffFile[]): CodeDiffFile | null {
    const sourceFiles: CodeDiffFile[] = files ?? this.diffFiles;
    for (let index: number = 0; index < sourceFiles.length; index += 1) {
      if (sourceFiles[index].path === path) {
        return sourceFiles[index];
      }
    }
    return null;
  }

  private applyDiffFiles(files: CodeDiffFile[]): void {
    this.diffFiles = files;
    if (files.length === 0) {
      this.selectedDiffFilePath = '';
      this.codeLines = [this.placeholderDiffLine('placeholder-2', NO_DIFF_TEXT)];
      return;
    }

    let selectedFile: CodeDiffFile | null = this.diffFileByPath(this.selectedDiffFilePath, files);
    if (selectedFile === null) {
      selectedFile = files[0];
    }
    this.selectedDiffFilePath = selectedFile.path;
    this.codeLines = selectedFile.lines.length > 0
      ? selectedFile.lines
      : [this.placeholderDiffLine('placeholder-empty-file', NO_DIFF_TEXT)];
  }

  private selectDiffFile(path: string): void {
    const selectedFile: CodeDiffFile | null = this.diffFileByPath(path);
    if (selectedFile === null) {
      return;
    }
    this.selectedDiffFilePath = selectedFile.path;
    this.codeLines = selectedFile.lines.length > 0
      ? selectedFile.lines
      : [this.placeholderDiffLine('placeholder-empty-file', NO_DIFF_TEXT)];
  }

  private selectedDiffFile(): CodeDiffFile | null {
    return this.diffFileByPath(this.selectedDiffFilePath);
  }

  private currentDiffFilePath(): string {
    const selectedFile: CodeDiffFile | null = this.selectedDiffFile();
    return selectedFile !== null ? selectedFile.path : NO_FILE_CHANGES_TEXT;
  }

  private currentDiffFileStat(): string {
    const selectedFile: CodeDiffFile | null = this.selectedDiffFile();
    return selectedFile !== null ? selectedFile.diffStat : this.diffStat;
  }

  private isDiffFileSelected(file: CodeDiffFile): boolean {
    return this.selectedDiffFilePath === file.path;
  }

  @Builder
  private chip(label: string, background: string, color: string) {
    Text(label)
      .copyOption(CopyOptions.None)
      .fontSize(10)
      .fontColor(color)
      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
      .backgroundColor(background)
      .borderRadius(6)
  }

  @Builder
  private panelTitle(title: string, subtitle: string) {
    Column() {
      Text(title)
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor('#18181B')

      Text(subtitle)
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(10)
        .fontColor('#A1A1AA')
        .margin({ top: 4 })
    }
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private selectorButton(label: string, value: string, active: boolean, onPress: () => void) {
    Row() {
      Text(label)
        .copyOption(CopyOptions.None)
        .fontSize(10)
        .fontColor('#71717A')

      Text(value)
        .copyOption(CopyOptions.None)
        .fontSize(10)
        .fontColor('#18181B')
        .margin({ left: 6 })

      Text('▾')
        .copyOption(CopyOptions.None)
        .fontSize(10)
        .fontColor('#A1A1AA')
        .margin({ left: 6 })
    }
    .padding({ left: 10, right: 10, top: 7, bottom: 7 })
    .backgroundColor(active ? '#F4F4F5' : '#FAFAFA')
    .border({ width: 0.5, color: active ? '#D4D4D8' : '#E4E4E7' })
    .borderRadius(8)
    .scale({ x: active ? 1.02 : 1, y: active ? 1.02 : 1 })
    .animation({ duration: this.motionFastDuration, curve: Curve.FastOutSlowIn })
    .onClick(() => {
      onPress();
    })
  }

  @Builder
  private optionChip(option: SelectorOption, selected: boolean, onPress: () => void) {
    Text(option.label)
      .copyOption(CopyOptions.None)
      .fontSize(10)
      .fontColor(selected ? '#0F172A' : '#64748B')
      .fontWeight(selected ? FontWeight.Medium : FontWeight.Normal)
      .padding({ left: 11, right: 11, top: 6, bottom: 6 })
      .backgroundColor(selected ? '#EEF6FF' : '#FFFFFF')
      .border({ width: 0.5, color: selected ? '#93C5FD' : '#E2E8F0' })
      .borderRadius(10)
      .shadow(selected ? { radius: 8, color: '#143B82F6', offsetY: 2 } : { radius: 0, color: '#00000000', offsetY: 0 })
      .scale({ x: selected ? 1.03 : 1, y: selected ? 1.03 : 1 })
      .animation({ duration: this.motionFastDuration, curve: Curve.FastOutSlowIn })
      .margin({ right: 7, bottom: 7 })
      .onClick(() => {
        onPress();
      })
  }

  @Builder
  private zoomStepButton(label: string, disabled: boolean, onPress: () => void) {
    Text(label)
      .copyOption(CopyOptions.None)
      .fontSize(12)
      .fontColor(disabled ? '#A1A1AA' : '#0F172A')
      .fontWeight(FontWeight.Medium)
      .textAlign(TextAlign.Center)
      .width(24)
      .height(24)
      .backgroundColor(disabled ? '#F4F4F5' : '#FFFFFF')
      .border({ width: 0.5, color: disabled ? '#E4E4E7' : '#D4D4D8' })
      .borderRadius(6)
      .opacity(disabled ? 0.55 : 1)
      .scale({ x: disabled ? 0.96 : 1, y: disabled ? 0.96 : 1 })
      .animation({ duration: this.motionFastDuration, curve: Curve.FastOutSlowIn })
      .onClick(() => {
        if (!disabled) {
          onPress();
        }
      })
  }

  @Builder
  private conversationZoomControl() {
    Row() {
      this.zoomStepButton('-', this.isConversationFontAtMin(), () => {
        this.adjustConversationFontScale(-1);
      })

      Text(this.conversationZoomLabel())
        .copyOption(CopyOptions.None)
        .fontSize(10)
        .fontColor('#64748B')
        .fontWeight(FontWeight.Medium)
        .textAlign(TextAlign.Center)
        .width(42)

      this.zoomStepButton('+', this.isConversationFontAtMax(), () => {
        this.adjustConversationFontScale(1);
      })
    }
    .height(28)
    .padding({ left: 2, right: 2 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor('#FAFAFA')
    .border({ width: 0.5, color: '#E4E4E7' })
    .borderRadius(8)
  }

  @Builder
  private magnifierZoomIcon(kind: string, color: string) {
    Stack({ alignContent: Alignment.TopStart }) {
      Circle()
        .width(11)
        .height(11)
        .fill('#00000000')
        .stroke(color)
        .strokeWidth(1.4)
        .position({ x: 2, y: 2 })

      Column()
        .width(6)
        .height(1.4)
        .backgroundColor(color)
        .borderRadius(1)
        .rotate({ angle: 45 })
        .position({ x: 11.2, y: 12.2 })

      Column()
        .width(6)
        .height(1.3)
        .backgroundColor(color)
        .borderRadius(1)
        .position({ x: 4.5, y: 6.8 })

      if (kind === 'in') {
        Column()
          .width(1.3)
          .height(6)
          .backgroundColor(color)
          .borderRadius(1)
          .position({ x: 6.85, y: 4.45 })
      }
    }
    .width(19)
    .height(19)
  }

  @Builder
  private mermaidZoomIconButton(kind: string, disabled: boolean, onPress: () => void) {
    Row() {
      this.magnifierZoomIcon(kind, disabled ? '#A1A1AA' : '#2563EB')
    }
    .width(26)
    .height(24)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .borderRadius(6)
    .backgroundColor(disabled ? '#F8FAFC' : '#FFFFFF')
    .border({ width: 0.5, color: disabled ? '#E4E4E7' : '#BFDBFE' })
    .opacity(disabled ? 0.55 : 1)
    .scale({ x: disabled ? 0.96 : 1, y: disabled ? 0.96 : 1 })
    .animation({ duration: this.motionFastDuration, curve: Curve.FastOutSlowIn })
    .onClick(() => {
      if (!disabled) {
        onPress();
      }
    })
  }

  @Builder
  private copyIcon(color: string) {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width(10)
        .height(12)
        .border({ width: 1.2, color: color })
        .borderRadius(2)
        .backgroundColor('#00000000')
        .position({ x: 4, y: 1 })

      Column()
        .width(10)
        .height(12)
        .border({ width: 1.2, color: color })
        .borderRadius(2)
        .backgroundColor('#00000000')
        .position({ x: 1, y: 4 })
    }
    .width(16)
    .height(18)
  }

  @Builder
  private iconCopyButton(onPress: () => void) {
    Row() {
      this.copyIcon('#64748B')
    }
    .width(26)
    .height(26)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .borderRadius(6)
    .backgroundColor('#00000000')
    .onClick(() => {
      onPress();
    })
  }

  @Builder
  private selectTextIcon(color: string) {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        Column().width(12).height(1.3).backgroundColor(color).borderRadius(1)
        Column().width(12).height(1.3).backgroundColor(color).borderRadius(1).margin({ top: 4 })
        Column().width(8).height(1.3).backgroundColor(color).borderRadius(1).margin({ top: 4 })
      }
      .position({ x: 1, y: 3 })

      Column()
        .width(1.4)
        .height(15)
        .backgroundColor(color)
        .borderRadius(1)
        .position({ x: 17, y: 2 })

      Column()
        .width(5)
        .height(1.2)
        .backgroundColor(color)
        .borderRadius(1)
        .position({ x: 15, y: 1 })

      Column()
        .width(5)
        .height(1.2)
        .backgroundColor(color)
        .borderRadius(1)
        .position({ x: 15, y: 17 })
    }
    .width(22)
    .height(20)
  }

  @Builder
  private iconSelectTextButton(active: boolean, onPress: () => void) {
    Row() {
      this.selectTextIcon(active ? '#2563EB' : '#64748B')
    }
    .width(30)
    .height(26)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .borderRadius(6)
    .backgroundColor(active ? '#EFF6FF' : '#00000000')
    .onClick(() => {
      onPress();
    })
  }

  private floatingMenuWidthForMaxLabelLength(maxLabelLength: number): number {
    return Math.min(180, Math.max(96, maxLabelLength * 13 + 28));
  }

  private projectSyncMenuLabel(): string {
    return this.canSelectExternalFolder() ? '导出到同步文件夹' : '导出到下载目录';
  }

  private projectSourceMenuLabel(proj: ProjectRecord): string {
    if (this.canSelectExternalFolder()) {
      return proj.sourceUri.trim().length > 0 ? '重新选择同步文件夹' : '选择同步文件夹';
    }
    return proj.sourceUri.trim().length > 0 ? '重新启用下载目录同步' : '启用下载目录同步';
  }

  private projectFloatingMenuWidth(proj: ProjectRecord): number {
    let maxLabelLength: number = '重命名项目'.length;
    maxLabelLength = Math.max(maxLabelLength, '删除项目'.length);
    if (proj.sourceUri.trim().length > 0) {
      maxLabelLength = Math.max(maxLabelLength, this.projectSyncMenuLabel().length);
      maxLabelLength = Math.max(maxLabelLength, '导入同步文件夹内容'.length);
    }
    maxLabelLength = Math.max(maxLabelLength, this.projectSourceMenuLabel(proj).length);
    maxLabelLength = Math.max(maxLabelLength, '复制路径'.length);
    return this.floatingMenuWidthForMaxLabelLength(maxLabelLength);
  }

  private sessionFloatingMenuWidth(): number {
    let maxLabelLength: number = '重命名会话'.length;
    maxLabelLength = Math.max(maxLabelLength, '删除会话'.length);
    return this.floatingMenuWidthForMaxLabelLength(maxLabelLength);
  }

  private placeFloatingMenu(windowX: number, windowY: number, menuWidth: number): void {
    this.floatingMenuWidth = menuWidth;
    this.floatingMenuX = Math.max(8, windowX - menuWidth + 2);
    this.floatingMenuY = Math.max(8, windowY - 20);
  }

  private rememberMenuTouchPosition(event: TouchEvent): void {
    if (event.touches.length > 0) {
      const touch: TouchObject = event.touches[0];
      this.lastMenuTouchWindowX = touch.windowX;
      this.lastMenuTouchWindowY = touch.windowY;
    }
  }

  private showProjectFloatingMenu(proj: ProjectRecord, windowX: number, windowY: number): void {
    this.placeFloatingMenu(windowX, windowY, this.projectFloatingMenuWidth(proj));
    this.showSessionMenuId = '';
    this.showProjectMenuId = this.showProjectMenuId === proj.id ? '' : proj.id;
  }

  private showProjectFloatingMenuFromTouch(proj: ProjectRecord): void {
    const menuWidth: number = this.projectFloatingMenuWidth(proj);
    const windowX: number = this.lastMenuTouchWindowX > 0 ? this.lastMenuTouchWindowX : menuWidth + 8;
    const windowY: number = this.lastMenuTouchWindowY > 0 ? this.lastMenuTouchWindowY : 48;
    this.showProjectFloatingMenu(proj, windowX, windowY);
    this.suppressProjectClickId = proj.id;
  }

  private showSessionFloatingMenu(item: WorkspaceItem, windowX: number, windowY: number): void {
    const sid: string = this.ensureWorkspaceBinding(item);
    this.placeFloatingMenu(windowX, windowY, this.sessionFloatingMenuWidth());
    this.showProjectMenuId = '';
    this.showSessionMenuId = this.showSessionMenuId === sid ? '' : sid;
  }

  private showSessionFloatingMenuFromTouch(item: WorkspaceItem): void {
    const menuWidth: number = this.sessionFloatingMenuWidth();
    const windowX: number = this.lastMenuTouchWindowX > 0 ? this.lastMenuTouchWindowX : menuWidth + 8;
    const windowY: number = this.lastMenuTouchWindowY > 0 ? this.lastMenuTouchWindowY : 48;
    this.showSessionFloatingMenu(item, windowX, windowY);
    this.suppressSessionClickId = this.ensureWorkspaceBinding(item);
  }

  private closeFloatingMenus(): void {
    this.showProjectMenuId = '';
    this.showSessionMenuId = '';
  }

  @Builder
  private topLevelFloatingMenus() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#00000000')
        .onClick(() => {
          this.closeFloatingMenus();
        })

      if (this.showProjectMenuId.length > 0) {
        ForEach(this.projects, (proj: ProjectRecord) => {
          if (proj.id === this.showProjectMenuId) {
            this.projectFloatingMenu(proj)
          }
        }, (proj: ProjectRecord) => proj.id)
      }

      if (this.showSessionMenuId.length > 0) {
        ForEach(this.workspaces, (item: WorkspaceItem) => {
          if (this.ensureWorkspaceBinding(item) === this.showSessionMenuId) {
            this.sessionFloatingMenu(item)
          }
        }, (item: WorkspaceItem) => this.ensureWorkspaceBinding(item))
      }
    }
    .width('100%')
    .height('100%')
    .zIndex(1000)
  }

  @Builder
  private projectGroup(proj: ProjectRecord) {
      Column() {
        // Project header row
        Row() {
          Text(proj.expanded ? '▾' : '▸')
            .fontSize(13)
            .fontColor('#71717A')
            .width(16)

          Stack({ alignContent: Alignment.TopStart }) {
            Column()
              .width(14)
              .height(10)
              .border({ width: 1, color: '#A1A1AA' })
              .borderRadius({ bottomLeft: 2, bottomRight: 2, topLeft: 0, topRight: 2 })
            Column()
              .width(7)
              .height(3)
              .border({ width: 1, color: '#A1A1AA' })
              .borderRadius({ topLeft: 2, topRight: 2 })
              .backgroundColor('#FAFAFA')
              .position({ x: 0, y: -1 })
          }
          .width(14)
          .height(12)
          .margin({ right: 6 })

          Text(proj.name)
            .copyOption(CopyOptions.None)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor('#18181B')
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          // Floating menu button (hover-visible)
          Text('···')
            .fontSize(16)
            .fontColor('#52525B')
            .padding({ left: 6, right: 6, top: 0, bottom: 0 })
            .height(20)
            .visibility(this.hasPointerHover && this.hoveredProjectId === proj.id ? Visibility.Visible : Visibility.Hidden)
            .onClick((event: ClickEvent) => {
              this.showProjectFloatingMenu(proj, event.windowX, event.windowY);
            })

          // New session button (plus)
          Text('+')
            .fontSize(18)
            .fontColor('#71717A')
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .onClick(() => {
              this.openNewSessionDialog(proj.id);
            })
        }
        .width('100%')
        .padding({ left: 8, right: 8, top: 6, bottom: 6 })
        .borderRadius(6)
        .backgroundColor(this.hoveredProjectId === proj.id ? '#F4F4F5' : 'transparent')
        .scale({ x: this.hoveredProjectId === proj.id ? 1.01 : 1, y: this.hoveredProjectId === proj.id ? 1.01 : 1 })
        .animation({ duration: this.motionFastDuration, curve: Curve.FastOutSlowIn })
        .onHover((isHover: boolean) => {
          if (isHover) {
            this.hasPointerHover = true;
          }
          if (this.showProjectMenuId.length === 0) {
            this.hoveredProjectId = isHover ? proj.id : '';
          }
        })
        .onTouch((event: TouchEvent) => {
          this.rememberMenuTouchPosition(event);
        })
        .gesture(
          LongPressGesture({ repeat: false, duration: 500 })
            .onAction(() => {
              this.showProjectFloatingMenuFromTouch(proj);
            })
        )
        .onClick(() => {
          if (this.suppressProjectClickId === proj.id) {
            this.suppressProjectClickId = '';
            return;
          }
          this.toggleProjectExpanded(proj.id);
        })

        // Inline rename input
        if (this.renamingProjectId === proj.id) {
          Row() {
            TextInput({ text: this.renameProjectText })
              .layoutWeight(1)
              .height(28)
              .fontSize(12)
              .backgroundColor('#FFFFFF')
              .border({ width: 0.5, color: '#D4D4D8' })
              .borderRadius(6)
              .padding({ left: 8, right: 8 })
              .onChange((value: string) => {
                this.renameProjectText = value;
              })

            Text('✓')
              .fontSize(14)
              .fontColor('#16A34A')
              .padding({ left: 8 })
              .onClick(() => {
                this.confirmRenameProject();
              })

            Text('✕')
              .fontSize(14)
              .fontColor('#DC2626')
              .padding({ left: 4 })
              .onClick(() => {
                this.cancelRenameProject();
              })
          }
          .width('100%')
          .padding({ left: 24, right: 8, bottom: 6 })
        }

        // Sessions under this project
        if (proj.expanded) {
          Column() {
            if (this.sessionsForProject(proj.id).length === 0) {
              Text('暂无会话')
                .fontSize(10)
                .fontColor('#D4D4D8')
                .padding({ left: 24, top: 4, bottom: 4 })
            } else {
              ForEach(this.sessionsForProject(proj.id), (session: WorkspaceItem) => {
                this.sessionItem(session)
              }, (session: WorkspaceItem) => `${session.id.toString()}:${session.title}`)
            }
          }
          .width('100%')
          .padding({ left: 16 })
          .transition(TransitionEffect.OPACITY.animation({ duration: this.motionFastDuration, curve: Curve.FastOutSlowIn }))
        }
      }
      .width('100%')
      .margin({ bottom: 4 })
  }

  @Builder
  private projectFloatingMenu(proj: ProjectRecord) {
    Column() {
        this.floatingMenuItem('重命名项目', () => {
          this.showProjectMenuId = '';
          this.openRenameProjectDialog(proj);
        })

        this.floatingMenuItem('删除项目', () => {
          this.showProjectMenuId = '';
          this.openDeleteProjectDialog(proj);
        })

        this.floatingMenuItem('复制路径', () => {
          this.showProjectMenuId = '';
          let targetPath: string = '';
          for (let i: number = 0; i < this.projects.length; i += 1) {
            if (this.projects[i].id === proj.id) {
              targetPath = this.projects[i].path;
              break;
            }
          }
          if (targetPath.length > 0) {
            this.copyPlainText(targetPath, '路径已复制');
          }
        })

        this.floatingMenuSeparator()
        this.floatingMenuSectionTitle('同步文件夹')

        if (proj.sourceUri.trim().length > 0) {
          this.floatingMenuItem(this.projectSyncMenuLabel(), () => {
            this.showProjectMenuId = '';
            void this.syncProjectToImportSource(proj);
          })

          this.floatingMenuItem('导入同步文件夹内容', () => {
            this.showProjectMenuId = '';
            void this.importProjectFromSyncFolder(proj);
          })
        }

        this.floatingMenuItem(this.projectSourceMenuLabel(proj), () => {
          this.showProjectMenuId = '';
          void this.reselectProjectImportSource(proj.id);
        })
    }
    .width(this.floatingMenuWidth)
    .padding({ top: 4, bottom: 4 })
    .borderRadius(8)
    .backgroundColor('#FFFFFF')
    .border({ width: 0.5, color: '#E4E4E7' })
    .shadow({ radius: 12, color: '#1A000000', offsetX: 0, offsetY: 4 })
    .position({ x: this.floatingMenuX, y: this.floatingMenuY })
    .zIndex(1000)
  }

  @Builder
  private floatingMenuItem(label: string, onPress: () => void) {
    Text(label)
      .copyOption(CopyOptions.None)
      .fontSize(12)
      .fontColor('#18181B')
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .onClick(() => {
        onPress();
      })
  }

  @Builder
  private floatingMenuSeparator() {
    Divider()
      .width('100%')
      .color('#E4E4E7')
      .strokeWidth(0.5)
      .margin({ top: 4, bottom: 4 })
  }

  @Builder
  private floatingMenuSectionTitle(label: string) {
    Text(label)
      .copyOption(CopyOptions.None)
      .fontSize(10)
      .fontColor('#A1A1AA')
      .width('100%')
      .padding({ left: 12, right: 12, top: 2, bottom: 2 })
  }


  @Builder
  private sessionItem(item: WorkspaceItem) {
      Column() {
        if (this.renamingSessionId === this.ensureWorkspaceBinding(item)) {
          // Inline rename mode
          Row() {
            TextInput({ text: this.renameSessionText })
              .layoutWeight(1)
              .height(24)
              .fontSize(11)
              .backgroundColor('#FFFFFF')
              .border({ width: 0.5, color: '#D4D4D8' })
              .borderRadius(4)
              .padding({ left: 6, right: 6 })
              .onChange((value: string) => {
                this.renameSessionText = value;
              })

            Text('✓')
              .fontSize(12)
              .fontColor('#16A34A')
              .padding({ left: 6 })
              .onClick(() => {
                this.confirmRenameSession();
              })

            Text('✕')
              .fontSize(12)
              .fontColor('#DC2626')
              .padding({ left: 4 })
              .onClick(() => {
                this.cancelRenameSession();
              })
          }
          .width('100%')
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        } else {
          // Normal session display
          Row() {
            Text(item.title)
              .copyOption(CopyOptions.None)
              .fontSize(11)
              .fontWeight(this.isWorkspaceActive(item) ? FontWeight.Medium : FontWeight.Regular)
              .fontColor(this.isWorkspaceActive(item) ? '#18181B' : '#52525B')
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            Text(this.relativeTime(this.findSessionUpdatedAt(item)))
              .fontSize(9)
              .fontColor('#A1A1AA')
              .margin({ right: 4 })

            Text('···')
              .fontSize(16)
              .fontColor('#52525B')
              .padding({ left: 2, right: 2 })
              .visibility(this.hasPointerHover && this.hoveredSessionId === this.ensureWorkspaceBinding(item) ? Visibility.Visible : Visibility.Hidden)
              .onClick((event: ClickEvent) => {
                this.showSessionFloatingMenu(item, event.windowX, event.windowY);
              })
          }
          .width('100%')
          .padding({ left: 8, right: 8, top: 5, bottom: 5 })
          .borderRadius(6)
          .backgroundColor(this.isWorkspaceActive(item) ? '#F4F4F5' : (this.hoveredSessionId === this.ensureWorkspaceBinding(item) ? '#F9FAFB' : 'transparent'))
          .scale({ x: this.isWorkspaceActive(item) || this.hoveredSessionId === this.ensureWorkspaceBinding(item) ? 1.01 : 1, y: this.isWorkspaceActive(item) || this.hoveredSessionId === this.ensureWorkspaceBinding(item) ? 1.01 : 1 })
          .animation({ duration: this.motionFastDuration, curve: Curve.FastOutSlowIn })
          .onTouch((event: TouchEvent) => {
            this.rememberMenuTouchPosition(event);
          })
          .gesture(
            LongPressGesture({ repeat: false, duration: 500 })
              .onAction(() => {
                this.showSessionFloatingMenuFromTouch(item);
              })
          )
          .onClick(() => {
            const sid: string = this.ensureWorkspaceBinding(item);
            if (this.suppressSessionClickId === sid) {
              this.suppressSessionClickId = '';
              return;
            }
            void this.selectWorkspace(item);
          })
        }
      }
        .width('100%')
        .hitTestBehavior(HitTestMode.Transparent)
        .onHover((isHover: boolean) => {
          if (isHover) {
            this.hasPointerHover = true;
          }
          if (this.showSessionMenuId.length === 0) {
            this.hoveredSessionId = isHover ? this.ensureWorkspaceBinding(item) : '';
          }
        })
  }

  @Builder
  private sessionFloatingMenu(item: WorkspaceItem) {
    Column() {
        this.floatingMenuItem('重命名会话', () => {
          this.showSessionMenuId = '';
          this.openRenameSessionDialog(item);
        })

        this.floatingMenuItem('删除会话', () => {
          this.showSessionMenuId = '';
          this.openDeleteSessionDialog(item);
        })
    }
    .width(this.floatingMenuWidth)
    .padding({ top: 4, bottom: 4 })
    .borderRadius(8)
    .backgroundColor('#FFFFFF')
    .border({ width: 0.5, color: '#E4E4E7' })
    .shadow({ radius: 12, color: '#1A000000', offsetX: 0, offsetY: 4 })
    .position({ x: this.floatingMenuX, y: this.floatingMenuY })
    .zIndex(1000)
  }

  private findSessionUpdatedAt(item: WorkspaceItem): string {
    const summaries: SessionSummary[] = codexBackend.sessionSummaries();
    const sessionId: string = this.ensureWorkspaceBinding(item);
    for (let i: number = 0; i < summaries.length; i += 1) {
      if (summaries[i].sessionId === sessionId) {
        return summaries[i].lastUpdatedAt;
      }
    }
    return '';
  }


  @Builder
  private infoRow(label: string, value: string) {
    Row() {
      Text(label)
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(10)
        .fontColor('#A1A1AA')
        .width(78)

      Text(value)
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(11)
        .fontColor('#27272A')
        .layoutWeight(1)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .margin({ top: 8 })
  }



  @Builder
  private markdownModeChip(label: string) {
    Text(label)
      .copyOption(CopyOptions.None)
      .fontSize(9)
      .fontColor('#64748B')
      .padding({ left: 7, right: 7, top: 3, bottom: 3 })
      .backgroundColor('#F8FAFC')
      .border({ width: 0.5, color: '#E2E8F0' })
      .borderRadius(6)
  }

  @Builder
  private messageBody(item: ChatMessage) {
    if (item.status === 'inProgress' && item.content.trim().length === 0) {
      Text(this.emptyMessageBodyText(item))
        .copyOption(CopyOptions.None)
        .fontSize(this.conversationFontSize(12))
        .lineHeight(this.conversationLineHeight(19))
        .fontColor(this.messageContentColor(item.itemType ?? item.role))
        .fontWeight(FontWeight.Medium)
        .margin({ top: 6 })
    } else if (this.isMessageCollapsed(item)) {
      if (this.hasHtmlFileLinkContent(this.collapsedMessagePreview(item))) {
        Column() {
          Text() {
            ForEach(this.htmlTextRuns(this.collapsedMessagePreview(item), `${item.id}:collapsed-html-runs`), (run: HtmlTextRun) => {
              Span(run.text)
                .fontSize(this.conversationFontSize(12))
                .fontColor(run.isLink ? '#2563EB' : this.messageContentColor(item.itemType ?? item.role))
                .fontWeight(run.isLink ? FontWeight.Medium : FontWeight.Regular)
                .decoration(run.isLink ? { type: TextDecorationType.Underline, color: '#93C5FD' } : { type: TextDecorationType.None, color: 'transparent' })
            }, (run: HtmlTextRun) => run.id)
          }
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(this.conversationFontSize(12))
            .lineHeight(this.conversationLineHeight(19))
            .fontColor(this.messageContentColor(item.itemType ?? item.role))
            .wordBreak(WordBreak.BREAK_WORD)
            .margin({ top: 6 })
            .hitTestBehavior(HitTestMode.Block)
            .onClick(() => {
              this.toggleMessageExpanded(item.id);
            })
          Text('点击展开完整输出')
            .copyOption(CopyOptions.None)
            .fontSize(this.conversationFontSize(10))
            .fontColor(this.accentBorderColor(item.itemType ?? item.role))
            .margin({ top: 4 })
            .onClick(() => {
              this.toggleMessageExpanded(item.id);
            })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      } else {
        Text(this.collapsedMessagePreview(item))
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(this.conversationFontSize(12))
          .lineHeight(this.conversationLineHeight(19))
          .fontColor(this.messageContentColor(item.itemType ?? item.role))
          .wordBreak(WordBreak.BREAK_WORD)
          .margin({ top: 6 })
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .hitTestBehavior(HitTestMode.Block)
          .onClick(() => {
            this.toggleMessageExpanded(item.id);
          })
      }
    } else if (item.content.trim().length === 0) {
      Text(this.emptyMessageBodyText(item))
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(this.conversationFontSize(12))
        .lineHeight(this.conversationLineHeight(19))
        .fontColor(this.messageContentColor(item.itemType ?? item.role))
        .wordBreak(WordBreak.BREAK_WORD)
        .margin({ top: 6 })
    } else if (this.isMessageSelectableMode(item.id) && this.shouldShowMessageSelectableAction(item)) {
      Text(this.messageOriginalText(item.content))
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(this.conversationFontSize(12))
        .lineHeight(this.conversationLineHeight(19))
        .fontColor(this.messageContentColor(item.itemType ?? item.role))
        .width('100%')
        .wordBreak(WordBreak.BREAK_WORD)
        .padding({ left: 10, right: 10, top: 9, bottom: 9 })
        .margin({ top: 6 })
        .backgroundColor('#F8FAFC')
        .border({ width: 0.5, color: '#CBD5E1' })
        .borderRadius(8)
    } else if (this.isStreamingAssistantMessage(item)) {
      Text(item.content)
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(this.conversationFontSize(12))
        .lineHeight(this.conversationLineHeight(19))
        .fontColor(this.messageContentColor(item.itemType ?? item.role))
        .wordBreak(WordBreak.BREAK_WORD)
        .margin({ top: 6 })
    } else if (this.hasHtmlFileLinkContent(item.content)) {
      this.htmlFileMessageBody(item)
    } else if (!this.shouldRenderMarkdown(item.content)) {
      Text(item.content)
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(this.conversationFontSize(12))
        .lineHeight(this.conversationLineHeight(19))
        .fontColor(this.messageContentColor(item.itemType ?? item.role))
        .wordBreak(WordBreak.BREAK_WORD)
        .margin({ top: 6 })
    } else if (!this.hasRenderedOrCodeMarkdownSurface(item.content)) {
      this.plainMarkdownTextBody(item)
    } else if (this.shouldRenderInlineOnlyMarkdown(item.content)) {
      this.inlineMessageMarkdownBody(item)
    } else {
      this.markdownRenderedBody(item)
    }
  }

  @Builder
  private plainMarkdownTextBody(item: ChatMessage) {
    Text() {
      ForEach(this.plainMarkdownTextRuns(item.content, item.id), (run: MarkdownTextRun) => {
        Span(run.text)
          .fontColor(this.plainMarkdownRunColor(run, item.itemType ?? item.role))
          .fontSize(this.plainMarkdownRunFontSize(run))
          .fontWeight(this.plainMarkdownRunWeight(run))
      }, (run: MarkdownTextRun) => run.id)
    }
    .copyOption(CopyOptions.LocalDevice)
    .fontSize(this.conversationFontSize(12))
    .lineHeight(this.conversationLineHeight(19))
    .fontColor(this.messageContentColor(item.itemType ?? item.role))
    .width('100%')
    .wordBreak(WordBreak.BREAK_WORD)
    .margin({ top: 6 })
  }

  @Builder
  private inlineMessageMarkdownBody(item: ChatMessage) {
    this.inlineMarkdownLine(`${item.id}:inline`, item.content.trim(), this.messageContentColor(item.itemType ?? item.role), this.conversationFontSize(12), this.conversationLineHeight(19), undefined, 6, item.id)
  }

  @Builder
  private htmlFileMessageBody(item: ChatMessage) {
    Column() {
      Text() {
        ForEach(this.htmlTextRuns(item.content, `${item.id}:html-runs`), (run: HtmlTextRun) => {
          Span(run.text)
            .fontSize(this.conversationFontSize(12))
            .fontColor(run.isLink ? '#2563EB' : this.messageContentColor(item.itemType ?? item.role))
            .fontWeight(run.isLink ? FontWeight.Medium : FontWeight.Regular)
            .decoration(run.isLink ? { type: TextDecorationType.Underline, color: '#93C5FD' } : { type: TextDecorationType.None, color: 'transparent' })
        }, (run: HtmlTextRun) => run.id)
      }
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(this.conversationFontSize(12))
        .lineHeight(this.conversationLineHeight(19))
        .fontColor(this.messageContentColor(item.itemType ?? item.role))
        .wordBreak(WordBreak.BREAK_WORD)
        .margin({ top: 6 })
        .hitTestBehavior(HitTestMode.Block)
        .onClick(() => {
          this.openFirstHtmlFileLinkContent(item.content, item.id);
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private markdownRenderedBody(item: ChatMessage) {
    Column() {
      ForEach(this.markdownBlocks(item.content), (block: MarkdownBlock) => {
        this.markdownBlock(item.id, block)
      }, (block: MarkdownBlock) => block.id)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ top: 6 })
  }

  @Builder
  private markdownBlock(messageId: string, block: MarkdownBlock) {
    if (block.kind === 'heading') {
      Column() {
        this.inlineMarkdownContent(
          messageId,
          block.id,
          block.text,
          '#0F172A',
          this.markdownHeadingFontSize(block.level),
          this.markdownHeadingLineHeight(block.level),
          FontWeight.Medium
        )
      }
      .width('100%')
      .margin({ top: 6, bottom: 4 })
    } else if (block.kind === 'quote') {
      Row() {
        Column()
          .width(3)
          .height('100%')
          .backgroundColor('#CBD5E1')
          .borderRadius(2)
          .margin({ right: 9 })
        this.inlineMarkdownContent(messageId, block.id, block.text, '#475569')
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .padding({ top: 7, bottom: 7, right: 8 })
      .backgroundColor('#F8FAFC')
      .borderRadius(8)
      .margin({ top: 5, bottom: 5 })
    } else if (block.kind === 'list') {
      Column() {
        ForEach(block.text.split('\n'), (line: string, index: number) => {
          Row() {
            Text(this.markdownListMarker(line))
              .copyOption(CopyOptions.None)
              .fontSize(this.conversationFontSize(12))
              .fontColor('#64748B')
              .width(24)
            Column() {
              this.inlineMarkdownContent(messageId, `${block.id}-${index}`, this.markdownListText(line), '#27272A')
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
          .margin({ top: index === 0 ? 0 : 3 })
        })
      }
      .width('100%')
      .margin({ top: 4, bottom: 4 })
    } else if (block.kind === 'code') {
      this.codeBlock(block)
    } else if (block.kind === 'math') {
      this.mathBlock(block)
    } else if (block.kind === 'mermaid') {
      this.mermaidBlock(messageId, block)
    } else if (block.kind === 'table') {
      this.markdownTable(messageId, block)
    } else if (block.kind === 'divider') {
      Column()
        .width('100%')
        .height(1)
        .backgroundColor('#E4E4E7')
        .margin({ top: 8, bottom: 8 })
    } else {
      this.inlineMarkdownContent(messageId, block.id, block.text, '#27272A')
    }
  }

  @Builder
  private markdownTable(messageId: string, block: MarkdownBlock) {
    Column() {
      ForEach(block.rows, (row: string[], rowIndex: number) => {
        Row() {
          ForEach(row, (cell: string, cellIndex?: number) => {
            Column() {
              this.inlineMarkdownContent(
                messageId,
                `${block.id}:r${rowIndex}:c${cellIndex ?? 0}`,
                cell,
                rowIndex === 0 ? '#0F172A' : '#334155',
                this.conversationFontSize(10),
                this.conversationLineHeight(16),
                rowIndex === 0 ? FontWeight.Medium : FontWeight.Regular
              )
            }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              .padding({ left: 7, right: 7, top: 6, bottom: 6 })
          }, (cell: string, cellIndex?: number) => `${rowIndex}:${cellIndex ?? 0}`)
        }
        .width('100%')
        .backgroundColor(rowIndex === 0 ? '#F1F5F9' : '#FFFFFF')
        .border({ width: 0.5, color: '#E2E8F0' })
      })
    }
    .width('100%')
    .borderRadius(8)
    .margin({ top: 5, bottom: 5 })
  }

  @Builder
  private codeBlock(block: MarkdownBlock) {
    Column() {
      Row() {
        Text(block.language.length > 0 ? block.language : 'text')
          .copyOption(CopyOptions.None)
          .fontSize(9)
          .fontColor('#0369A1')
          .fontWeight(FontWeight.Medium)
          .padding({ left: 7, right: 7, top: 3, bottom: 3 })
          .backgroundColor('#E0F2FE')
          .borderRadius(6)
        Blank()
          .layoutWeight(1)
        this.iconCopyButton(() => {
          this.copyPlainText(block.text, '代码已复制');
        })
      }
      .width('100%')
      .margin({ bottom: 6 })

      Column() {
        this.highlightedCodeLines(block.text, block.language, `${block.id}:code`)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 10, right: 10, top: 9, bottom: 9 })
    .backgroundColor('#F8FAFC')
    .border({ width: 0.5, color: '#CBD5E1' })
    .borderRadius(8)
    .margin({ top: 5, bottom: 5 })
  }

  @Builder
  private highlightedCodeLines(text: string, language: string, baseId: string) {
    Text() {
      ForEach(this.codeBlockLines(text), (line: string, lineIndex: number) => {
        ForEach(this.codeLineTokens(line, language, `${baseId}:${lineIndex}`), (token: CodeToken) => {
          Span(token.text)
            .fontColor(this.codeTokenColor(token.kind))
            .fontWeight(this.codeTokenWeight(token.kind))
        }, (token: CodeToken) => token.id)
        if (lineIndex < this.codeBlockLines(text).length - 1) {
          Span('\n')
            .fontColor('#0F172A')
        }
      }, (line: string, lineIndex: number) => `${lineIndex}:${line}`)
    }
    .copyOption(CopyOptions.LocalDevice)
    .fontSize(this.conversationFontSize(11))
    .lineHeight(this.conversationLineHeight(18))
    .fontFamily('monospace')
    .width('100%')
  }

  @Builder
  private inlineMarkdownContent(messageId: string, blockId: string, text: string, color: string, fontSize?: number, lineHeight?: number, weight?: FontWeight) {
    Column() {
      ForEach(text.split('\n'), (line: string, lineIndex: number) => {
        if (line.length === 0) {
          Blank()
            .width('100%')
            .height(8)
        } else {
          this.inlineMarkdownLine(
            `${messageId}:${blockId}:${lineIndex}`,
            line,
            color,
            fontSize ?? this.conversationFontSize(12),
            lineHeight ?? this.conversationLineHeight(19),
            weight,
            lineIndex === 0 ? 0 : 2,
            messageId
          )
        }
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private inlineMathFlowSegment(segment: MathSegment, color: string, fontSize: number, lineHeight: number, weight?: FontWeight) {
    if (segment.kind === 'code') {
      Text(segment.text)
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(Math.max(fontSize - this.conversationFontSize(1), this.conversationFontSize(10)))
        .lineHeight(lineHeight)
        .fontFamily('monospace')
        .fontColor('#0F172A')
        .padding({ left: 4, right: 4, top: 1, bottom: 1 })
        .margin({ left: 2, right: 2, bottom: 2 })
        .backgroundColor('#F1F5F9')
        .border({ width: 0.5, color: '#E2E8F0' })
        .borderRadius(4)
    } else {
      Text(segment.text)
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(fontSize)
        .lineHeight(lineHeight)
        .fontColor(segment.kind === 'link' ? '#2563EB' : color)
        .fontWeight(segment.kind === 'strong' ? FontWeight.Medium : (weight ?? FontWeight.Regular))
        .margin({ bottom: 2 })
    }
  }

  @Builder
  private inlineMarkdownLine(baseId: string, text: string, color: string, fontSize: number, lineHeight: number, weight: FontWeight | undefined, topMargin: number, sourceMessageId?: string) {
    if (this.hasInlineMathText(text)) {
      Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
        ForEach(this.inlineMarkdownSegments(text, baseId), (segment: MathSegment) => {
          if (segment.kind === 'math') {
            this.inlineMathSegment(segment, fontSize, lineHeight)
          } else {
            this.inlineMathFlowSegment(segment, color, fontSize, lineHeight, weight)
          }
        }, (segment: MathSegment) => segment.id)
      }
      .width('100%')
      .margin({ top: topMargin })
    } else {
      this.inlineMarkdownTextLine(this.inlineMarkdownSegments(text, baseId), color, fontSize, lineHeight, weight, topMargin, sourceMessageId)
    }
  }

  @Builder
  private inlineMarkdownTextLine(segments: MathSegment[], color: string, fontSize: number, lineHeight: number, weight: FontWeight | undefined, topMargin: number, sourceMessageId?: string) {
    if (this.hasInlineLinkSegment(segments)) {
      Text() {
        ForEach(segments, (segment: MathSegment) => {
          if (segment.kind === 'code') {
            Span(this.inlineCodeSpanText(segment.text))
              .fontSize(Math.max(fontSize - this.conversationFontSize(1), this.conversationFontSize(10)))
              .fontColor('#0F172A')
              .fontWeight(FontWeight.Medium)
          } else {
            Span(segment.text)
              .fontSize(fontSize)
              .fontColor(segment.kind === 'link' ? '#2563EB' : color)
              .fontWeight(segment.kind === 'strong' || segment.kind === 'link' ? FontWeight.Medium : (weight ?? FontWeight.Regular))
          }
        }, (segment: MathSegment) => segment.id)
      }
      .copyOption(CopyOptions.LocalDevice)
      .fontSize(fontSize)
      .lineHeight(lineHeight)
      .width('100%')
      .wordBreak(WordBreak.BREAK_WORD)
      .margin({ top: topMargin })
      .onClick(() => {
        this.openFirstInlineLinkSegment(segments, sourceMessageId);
      })
    } else {
      Text() {
        ForEach(segments, (segment: MathSegment) => {
          if (segment.kind === 'code') {
            Span(this.inlineCodeSpanText(segment.text))
              .fontSize(Math.max(fontSize - this.conversationFontSize(1), this.conversationFontSize(10)))
              .fontColor('#0F172A')
              .fontWeight(FontWeight.Medium)
          } else {
            Span(segment.text)
              .fontSize(fontSize)
              .fontColor(color)
              .fontWeight(segment.kind === 'strong' ? FontWeight.Medium : (weight ?? FontWeight.Regular))
          }
        }, (segment: MathSegment) => segment.id)
      }
      .copyOption(CopyOptions.LocalDevice)
      .fontSize(fontSize)
      .lineHeight(lineHeight)
      .width('100%')
      .wordBreak(WordBreak.BREAK_WORD)
      .margin({ top: topMargin })
    }
  }

  private hasInlineMathSegment(segments: MathSegment[]): boolean {
    for (let index: number = 0; index < segments.length; index += 1) {
      if (segments[index].kind === 'math') {
        return true;
      }
    }
    return false;
  }

  private hasInlineMathText(text: string): boolean {
    return this.hasInlineMathSegment(this.inlineMarkdownSegments(text, 'inline-math-probe'));
  }

  private hasInlineLinkSegment(segments: MathSegment[]): boolean {
    for (let index: number = 0; index < segments.length; index += 1) {
      if (segments[index].kind === 'link') {
        return true;
      }
    }
    return false;
  }

  private hasHtmlFileLinkContent(content: string): boolean {
    return this.htmlFileLinkSegments(content, 'html-probe').length > 0;
  }

  private htmlFileLinkSegments(content: string, baseId: string): MathSegment[] {
    const sourceSegments: MathSegment[] = this.inlineMarkdownSegments(content, `${baseId}:source`);
    const result: MathSegment[] = [];
    for (let index: number = 0; index < sourceSegments.length; index += 1) {
      const segment: MathSegment = sourceSegments[index];
      if (segment.kind === 'link' && this.isHtmlFileTarget(segment.target)) {
        result.push(new MathSegment(`${baseId}:html:${result.length.toString()}`, 'link', segment.text, segment.rawText, segment.target));
      }
    }
    return result;
  }

  private htmlTextRuns(content: string, baseId: string): HtmlTextRun[] {
    const sourceSegments: MathSegment[] = this.inlineMarkdownSegments(content, `${baseId}:source`);
    const result: HtmlTextRun[] = [];
    let serial: number = 0;
    for (let index: number = 0; index < sourceSegments.length; index += 1) {
      const segment: MathSegment = sourceSegments[index];
      const isHtmlLink: boolean = segment.kind === 'link' && this.isHtmlFileTarget(segment.target);
      result.push(new HtmlTextRun(`${baseId}:run:${serial.toString()}`, segment.text, isHtmlLink));
      serial += 1;
    }
    if (result.length === 0) {
      result.push(new HtmlTextRun(`${baseId}:run:0`, content, false));
    }
    return result;
  }

  private openFirstHtmlFileLinkContent(content: string, sourceMessageId?: string): void {
    const segments: MathSegment[] = this.htmlFileLinkSegments(content, 'html-open');
    if (segments.length > 0) {
      this.openWebTarget(segments[0].target, segments[0].text, sourceMessageId);
    }
  }

  private firstInlineLinkSegment(segments: MathSegment[]): MathSegment | null {
    for (let index: number = 0; index < segments.length; index += 1) {
      if (segments[index].kind === 'link') {
        return segments[index];
      }
    }
    return null;
  }

  private openFirstInlineLinkSegment(segments: MathSegment[], sourceMessageId?: string): void {
    const linkSegment: MathSegment | null = this.firstInlineLinkSegment(segments);
    if (linkSegment !== null) {
      this.openWebTarget(linkSegment.target, linkSegment.text, sourceMessageId);
    }
  }

  private inlineCodeSpanText(text: string): string {
    return ` ${text} `;
  }

  @Builder
  private inlineMathSegment(segment: MathSegment, fontSize: number, lineHeight: number) {
    Row() {
      this.formulaInlineContent(segment.rawText, fontSize)
    }
    .padding({ left: 5, right: 5, top: 2, bottom: 2 })
    .margin({ right: 4, bottom: 2 })
    .backgroundColor('#F8FAFC')
    .border({ width: 0.5, color: '#CBD5E1' })
    .borderRadius(6)
  }

  @Builder
  private formulaInlineContent(source: string, fontSize: number) {
    Row() {
      this.formulaNode(this.parseFormula(source), Math.max(fontSize + this.conversationFontSize(1), this.conversationFontSize(13)), '#0F172A', false)
    }
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private formulaBlockContent(source: string) {
    Column() {
      ForEach(this.mathBlockLines(source), (line: string, lineIndex?: number) => {
        Row() {
          this.formulaNode(this.parseFormula(line), this.conversationFontSize(19), '#0F172A', true)
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .margin({ top: (lineIndex ?? 0) === 0 ? 0 : 6 })
      }, (line: string, lineIndex?: number) => `${lineIndex ?? 0}:${line}`)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private formulaNode(node: FormulaNode, fontSize: number, color: string, displayStyle: boolean = false) {
    if (node.kind === 'sequence') {
      Row() {
        ForEach(node.children, (child: FormulaNode, childIndex?: number) => {
          this.formulaNode(child, fontSize, color, displayStyle)
        }, (child: FormulaNode, childIndex?: number) => `${child.kind}:${childIndex ?? 0}:${child.text}`)
      }
      .alignItems(VerticalAlign.Center)
    } else if (node.kind === 'group' && node.children.length > 0) {
      Row() {
        Text(node.text.length > 0 ? node.text.charAt(0) : '(')
          .copyOption(CopyOptions.None)
          .fontSize(this.formulaGroupDelimiterFontSize(node, fontSize))
          .lineHeight(this.formulaGroupDelimiterFontSize(node, fontSize) + 6)
          .fontColor(color)
          .fontWeight(FontWeight.Medium)

        this.formulaNode(node.children[0], fontSize, color, displayStyle)

        Text(node.text.length > 1 ? node.text.charAt(1) : ')')
          .copyOption(CopyOptions.None)
          .fontSize(this.formulaGroupDelimiterFontSize(node, fontSize))
          .lineHeight(this.formulaGroupDelimiterFontSize(node, fontSize) + 6)
          .fontColor(color)
          .fontWeight(FontWeight.Medium)
      }
      .alignItems(VerticalAlign.Center)
    } else if (node.kind === 'fraction' && node.numerator !== null && node.denominator !== null) {
      Column() {
        Row() {
          this.formulaNode(node.numerator, Math.max(fontSize - 2, 11), color, displayStyle)
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .margin({ bottom: 2 })

        Column()
          .width('100%')
          .height(1)
          .backgroundColor(color)

        Row() {
          this.formulaNode(node.denominator, Math.max(fontSize - 2, 11), color, displayStyle)
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .margin({ top: 2 })
      }
      .width(this.formulaFractionWidth(node, fontSize))
      .alignItems(HorizontalAlign.Center)
      .padding({ left: 3, right: 3 })
    } else if (node.kind === 'sqrt' && node.radicand !== null) {
      Row() {
        Text('√')
          .copyOption(CopyOptions.None)
          .fontSize(fontSize + 2)
          .lineHeight(fontSize + 6)
          .fontColor(color)
          .fontWeight(FontWeight.Medium)

        Column() {
          Column()
            .width('100%')
            .height(1)
            .backgroundColor(color)
            .margin({ bottom: 1 })

          this.formulaNode(node.radicand, Math.max(fontSize - 1, 11), color, displayStyle)
        }
        .width(this.formulaRadicandWidth(node, fontSize))
        .padding({ left: 3, right: 3, top: 2 })
      }
      .alignItems(VerticalAlign.Bottom)
    } else if (node.kind === 'script' && node.base !== null) {
      if (displayStyle && this.isFormulaLimitOperatorNode(node.base)) {
        Column() {
          if (node.superscript !== null) {
            Row() {
              this.formulaNode(node.superscript, this.formulaLimitFontSize(fontSize), color, false)
            }
            .justifyContent(FlexAlign.Center)
            .margin({ bottom: 1 })
          }

          Row() {
            this.formulaNode(node.base, this.formulaLimitOperatorFontSize(fontSize), color, false)
          }
          .justifyContent(FlexAlign.Center)

          if (node.subscript !== null) {
            Row() {
              this.formulaNode(node.subscript, this.formulaLimitFontSize(fontSize), color, false)
            }
            .justifyContent(FlexAlign.Center)
            .margin({ top: 1 })
          }
        }
        .alignItems(HorizontalAlign.Center)
        .padding({ left: 2, right: 2 })
      } else {
        Row() {
          this.formulaNode(node.base, fontSize, color, displayStyle)

          Column() {
            if (node.superscript !== null) {
              this.formulaNode(node.superscript, Math.max(fontSize - 5, 9), color, false)
            }
            if (node.subscript !== null) {
              this.formulaNode(node.subscript, Math.max(fontSize - 5, 9), color, false)
            }
          }
          .alignItems(HorizontalAlign.Start)
        }
        .alignItems(VerticalAlign.Top)
      }
    } else if (node.kind === 'space') {
      Blank()
        .width(this.formulaSpacingWidth(node.text, fontSize))
        .height(1)
    } else {
      Text(node.text)
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(fontSize)
        .lineHeight(fontSize + 6)
        .fontColor(color)
        .fontStyle(this.formulaFontStyle(node))
        .fontWeight(FontWeight.Regular)
    }
  }

  @Builder
  private mathBlock(block: MarkdownBlock) {
    Column() {
      this.formulaBlockContent(block.rawText)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 10, right: 10, top: 9, bottom: 10 })
    .backgroundColor('#FDFEFF')
    .border({ width: 0.5, color: '#BFDBFE' })
    .borderRadius(8)
    .margin({ top: 5, bottom: 5 })
  }

  private formulaFractionWidth(node: FormulaNode, fontSize: number): number {
    if (node.numerator === null || node.denominator === null) {
      return Math.max(fontSize * 2, 26);
    }
    const numeratorWidth: number = this.formulaNodeApproxWidth(node.numerator, Math.max(fontSize - 2, 11));
    const denominatorWidth: number = this.formulaNodeApproxWidth(node.denominator, Math.max(fontSize - 2, 11));
    return Math.min(Math.max(Math.max(numeratorWidth, denominatorWidth) + 12, fontSize * 1.8), 360);
  }

  private formulaRadicandWidth(node: FormulaNode, fontSize: number): number {
    if (node.radicand === null) {
      return Math.max(fontSize * 2, 26);
    }
    return Math.min(Math.max(this.formulaNodeApproxWidth(node.radicand, Math.max(fontSize - 1, 11)) + 8, fontSize * 1.8), 340);
  }

  private formulaGroupDelimiterFontSize(node: FormulaNode, fontSize: number): number {
    if (node.children.length === 0) {
      return fontSize;
    }
    return this.formulaNeedsTallDelimiter(node.children[0]) ? fontSize + 4 : fontSize;
  }

  private formulaLimitFontSize(fontSize: number): number {
    return Math.max(fontSize - 6, 10);
  }

  private formulaLimitOperatorFontSize(fontSize: number): number {
    return fontSize + 3;
  }

  private formulaNodeApproxWidth(node: FormulaNode, fontSize: number): number {
    if (node.kind === 'sequence') {
      let width: number = 0;
      for (let i = 0; i < node.children.length; i++) {
        width += this.formulaNodeApproxWidth(node.children[i], fontSize);
      }
      return Math.max(width, fontSize);
    }
    if (node.kind === 'group' && node.children.length > 0) {
      return this.formulaNodeApproxWidth(node.children[0], fontSize) + fontSize;
    }
    if (node.kind === 'fraction' && node.numerator !== null && node.denominator !== null) {
      return this.formulaFractionWidth(node, fontSize);
    }
    if (node.kind === 'sqrt' && node.radicand !== null) {
      return this.formulaRadicandWidth(node, fontSize) + fontSize;
    }
    if (node.kind === 'script' && node.base !== null) {
      if (this.isFormulaLimitOperatorNode(node.base)) {
        const operatorWidth: number = this.formulaNodeApproxWidth(node.base, fontSize + 3);
        const supWidth: number = node.superscript === null ? 0 : this.formulaNodeApproxWidth(node.superscript, Math.max(fontSize - 6, 10));
        const subWidth: number = node.subscript === null ? 0 : this.formulaNodeApproxWidth(node.subscript, Math.max(fontSize - 6, 10));
        return Math.max(operatorWidth, Math.max(supWidth, subWidth)) + 4;
      }
      const baseWidth: number = this.formulaNodeApproxWidth(node.base, fontSize);
      const supWidth: number = node.superscript === null ? 0 : this.formulaNodeApproxWidth(node.superscript, Math.max(fontSize - 5, 9));
      const subWidth: number = node.subscript === null ? 0 : this.formulaNodeApproxWidth(node.subscript, Math.max(fontSize - 5, 9));
      return baseWidth + Math.max(supWidth, subWidth);
    }
    if (node.kind === 'space') {
      return this.formulaSpacingWidth(node.text, fontSize);
    }
    return this.formulaTextApproxWidth(node.text, fontSize);
  }

  private formulaNeedsTallDelimiter(node: FormulaNode): boolean {
    if (node.kind === 'fraction' || node.kind === 'sqrt') {
      return true;
    }
    if (node.kind === 'script' && node.base !== null && this.isFormulaLimitOperatorNode(node.base)) {
      return true;
    }
    if (node.kind === 'group' && node.children.length > 0) {
      return this.formulaNeedsTallDelimiter(node.children[0]);
    }
    if (node.kind === 'sequence') {
      for (let i = 0; i < node.children.length; i++) {
        if (this.formulaNeedsTallDelimiter(node.children[i])) {
          return true;
        }
      }
    }
    return false;
  }

  private isFormulaLimitOperatorNode(node: FormulaNode): boolean {
    return node.kind === 'operator' &&
      (node.text === '∑' ||
        node.text === '∏' ||
        node.text === '∫' ||
        node.text === '∮' ||
        node.text === 'lim' ||
        node.text === 'limsup' ||
        node.text === 'liminf' ||
        node.text === 'sup' ||
        node.text === 'inf' ||
        node.text === 'argmax' ||
        node.text === 'argmin');
  }

  private formulaSpacingWidth(command: string, fontSize: number): number {
    switch (command) {
      case 'qquad': return fontSize * 2;
      case 'quad': return fontSize;
      case ';': return fontSize * 0.35;
      case ':': return fontSize * 0.28;
      case ',': return fontSize * 0.18;
      default: return fontSize * 0.35;
    }
  }

  private formulaTextApproxWidth(text: string, fontSize: number): number {
    let width: number = 0;
    for (let i = 0; i < text.length; i++) {
      width += text[i] === ' ' ? fontSize * 0.35 : fontSize * 0.58;
    }
    return Math.max(width, fontSize * 0.6);
  }

  private formulaFontStyle(node: FormulaNode): FontStyle {
    return node.variant === 'italic' ? FontStyle.Italic : FontStyle.Normal;
  }

  @Builder
  private mermaidBlock(messageId: string, block: MarkdownBlock) {
    Column() {
      Row() {
        Text('Mermaid')
          .copyOption(CopyOptions.None)
          .fontSize(9)
          .fontColor('#2563EB')
          .padding({ left: 7, right: 7, top: 3, bottom: 3 })
          .backgroundColor('#EFF6FF')
          .borderRadius(6)

        Blank()
          .layoutWeight(1)

        this.mermaidZoomIconButton('out', this.isMermaidScaleAtMin(this.mermaidScaleKey(messageId, block)), () => {
          this.adjustMermaidScale(this.mermaidScaleKey(messageId, block), -1);
        })

        Blank()
          .width(4)

        this.mermaidZoomIconButton('in', this.isMermaidScaleAtMax(this.mermaidScaleKey(messageId, block)), () => {
          this.adjustMermaidScale(this.mermaidScaleKey(messageId, block), 1);
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({ bottom: 7 })

      MermaidWebDiagram({
        source: block.text,
        diagramHeight: this.mermaidDiagramHeight(block.text, this.mermaidScale(this.mermaidScaleKey(messageId, block))),
        fontScale: this.mermaidScale(this.mermaidScaleKey(messageId, block))
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 10, right: 10, top: 9, bottom: 10 })
    .backgroundColor('#F8FAFC')
    .border({ width: 0.5, color: '#BFDBFE' })
    .borderRadius(8)
    .margin({ top: 5, bottom: 5 })
  }

  @Builder
  private turnActivityLine() {
    Row() {
      this.turnActivityBlock()
      Blank()
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .margin({ bottom: 8 })
  }

  @Builder
  private turnActivityBlock() {
    Column() {
      Row() {
        Row() {
          Text(this.isTurnActivityCollapsed ? '\u203A' : '\u2304')
            .copyOption(CopyOptions.None)
            .fontSize(16)
            .fontColor(this.accentBorderColor('reasoning'))
        }
        .width(20)
        .height(20)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .backgroundColor(this.eventSoftBackground('reasoning'))
        .border({ width: 0.5, color: this.eventBorderColor('reasoning') })
          .borderRadius(6)
          .margin({ right: 8 })

        Text(this.messageIcon('reasoning'))
          .copyOption(CopyOptions.None)
          .fontSize(this.conversationFontSize(12))
          .fontColor(this.accentBorderColor('reasoning'))
          .fontWeight(FontWeight.Medium)
          .width(22)

        Text('思考')
          .copyOption(CopyOptions.None)
          .fontSize(this.conversationFontSize(12))
          .fontWeight(FontWeight.Medium)
          .fontColor(this.accentBorderColor('reasoning'))

        Text('刚刚')
          .copyOption(CopyOptions.None)
          .fontSize(10)
          .fontColor('#94A3B8')
          .margin({ left: 8 })

        Text('进行中')
          .copyOption(CopyOptions.None)
          .fontSize(10)
          .fontColor(this.statusColor('inProgress'))
          .padding({ left: 7, right: 7, top: 2, bottom: 2 })
          .backgroundColor(this.statusBgColor('inProgress'))
          .borderRadius(6)
          .margin({ left: 8 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .hitTestBehavior(HitTestMode.Block)
      .onClick(() => {
        this.toggleTurnActivityExpanded();
      })

      if (this.isTurnActivityCollapsed) {
        Text(this.thinkingStatusText())
          .copyOption(CopyOptions.None)
          .fontSize(this.conversationFontSize(11))
          .fontColor(this.accentBorderColor('reasoning'))
          .lineHeight(this.conversationLineHeight(17))
          .width('100%')
          .margin({ top: 6, left: 28 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .hitTestBehavior(HitTestMode.Block)
          .onClick(() => {
            this.toggleTurnActivityExpanded();
          })
      } else {
        Column() {
          Text(this.thinkingStatusText())
            .copyOption(CopyOptions.None)
            .fontSize(this.conversationFontSize(12))
            .fontColor(this.messageContentColor('reasoning'))
            .lineHeight(this.conversationLineHeight(19))
            .fontWeight(FontWeight.Medium)
            .margin({ top: 6 })

          ForEach(this.turnActivityDetailLines(), (line: string, index?: number) => {
            Text(line)
              .copyOption(CopyOptions.LocalDevice)
              .fontSize(this.conversationFontSize(12))
              .fontColor(this.messageContentColor('reasoning'))
              .lineHeight(this.conversationLineHeight(19))
              .wordBreak(WordBreak.BREAK_WORD)
              .margin({ top: index === 0 ? 6 : 4 })
          }, (line: string, index?: number) => `turn-activity:${index ?? 0}:${line}`)

          Text('收起思考内容')
            .copyOption(CopyOptions.None)
            .fontSize(this.conversationFontSize(10))
            .fontColor(this.accentBorderColor('reasoning'))
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .margin({ top: 6 })
            .backgroundColor(this.eventSoftBackground('reasoning'))
            .border({ width: 0.5, color: this.eventBorderColor('reasoning') })
            .borderRadius(6)
            .onClick(() => {
              this.toggleTurnActivityExpanded();
            })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 28 })
      }
    }
    .width('92%')
    .constraintSize({ maxWidth: '92%' })
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 10, right: 10, top: 9, bottom: 9 })
    .backgroundColor('#F8FAFC')
    .borderRadius(8)
  }

  @Builder
  private compactionNoticeLine(notice: CompactionNotice) {
    Row() {
      this.compactionNoticeBlock(notice)
      Blank()
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .margin({ bottom: 8 })
  }

  @Builder
  private compactionNoticeBlock(notice: CompactionNotice) {
    Column() {
      Row() {
        Row() {
          Text(this.isCompactionNoticeExpanded(notice.id) ? '\u2304' : '\u203A')
            .copyOption(CopyOptions.None)
            .fontSize(16)
            .fontColor(this.compactionNoticeColor(notice.status))
        }
        .width(20)
        .height(20)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .backgroundColor(this.compactionNoticeSoftBackground(notice.status))
        .border({ width: 0.5, color: this.compactionNoticeBorderColor(notice.status) })
        .borderRadius(6)
        .margin({ right: 8 })

        Text('上下文压缩')
          .copyOption(CopyOptions.None)
          .fontSize(this.conversationFontSize(12))
          .fontWeight(FontWeight.Medium)
          .fontColor(this.compactionNoticeColor(notice.status))

        Text(this.compactionNoticeStatusLabel(notice.status))
          .copyOption(CopyOptions.None)
          .fontSize(10)
          .fontColor(this.compactionNoticeColor(notice.status))
          .padding({ left: 7, right: 7, top: 2, bottom: 2 })
          .backgroundColor(this.compactionNoticeSoftBackground(notice.status))
          .borderRadius(6)
          .margin({ left: 8 })

        Blank()

        Text(notice.timestamp)
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(10)
          .fontColor('#94A3B8')
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .hitTestBehavior(HitTestMode.Block)
      .onClick(() => {
        this.toggleCompactionNoticeExpanded(notice.id);
      })

      Text(this.compactionNoticeSummary(notice))
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(this.conversationFontSize(11))
        .fontColor(this.compactionNoticeColor(notice.status))
        .lineHeight(this.conversationLineHeight(17))
        .width('100%')
        .margin({ top: 6, left: 28 })
        .maxLines(this.isCompactionNoticeExpanded(notice.id) ? 3 : 1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (this.isCompactionNoticeExpanded(notice.id)) {
        Column() {
          this.compactionMetricRow('压缩前', notice.oldTotalTokens > 0 ? `${this.formatTokenCount(notice.oldTotalTokens)} tokens` : '未知')
          this.compactionMetricRow('压缩后', notice.newTotalTokens > 0 ? `${this.formatTokenCount(notice.newTotalTokens)} tokens` : '未知')
          this.compactionMetricRow('释放', this.compactionSavedText(notice))
          if (notice.errorMessage.trim().length > 0) {
            Text(notice.errorMessage)
              .copyOption(CopyOptions.LocalDevice)
              .fontSize(this.conversationFontSize(10))
              .fontColor('#DC2626')
              .lineHeight(this.conversationLineHeight(16))
              .margin({ top: 6 })
          }
          if (notice.status === 'failed' || notice.status === 'timeout') {
            Text('重试压缩')
              .copyOption(CopyOptions.None)
              .fontSize(10)
              .fontColor('#4338CA')
              .fontWeight(FontWeight.Medium)
              .padding({ left: 8, right: 8, top: 5, bottom: 5 })
              .backgroundColor('#EEF2FF')
              .borderRadius(6)
              .margin({ top: 8 })
              .onClick(() => {
                this.retryCurrentCompaction(notice.threadId);
              })
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .margin({ top: 8, left: 28 })
      }
    }
    .width('92%')
    .constraintSize({ maxWidth: '92%' })
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 10, right: 10, top: 9, bottom: 9 })
    .backgroundColor('#F8FAFC')
    .borderRadius(8)
  }

  @Builder
  private compactionMetricRow(label: string, value: string) {
    Row() {
      Text(label)
        .copyOption(CopyOptions.None)
        .fontSize(10)
        .fontColor('#64748B')
        .width(56)

      Text(value)
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(this.conversationFontSize(10))
        .fontColor('#0F172A')
        .fontFamily('monospace')
    }
    .width('100%')
    .margin({ top: 3 })
  }

  @Builder
  private messageEventBlock(item: ChatMessage) {
    Column() {
      Row() {
        Row() {
          Text(this.isMessageCollapsed(item) ? '\u203A' : '\u2304')
            .copyOption(CopyOptions.None)
            .fontSize(16)
            .fontColor(this.accentBorderColor(item.itemType ?? item.role))
        }
        .width(20)
        .height(20)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .backgroundColor(this.eventSoftBackground(item.itemType ?? item.role))
        .border({ width: 0.5, color: this.eventBorderColor(item.itemType ?? item.role) })
        .borderRadius(6)
        .margin({ right: 8 })

        Text(this.messageIcon(item.itemType ?? item.role))
          .copyOption(CopyOptions.None)
          .fontSize(this.conversationFontSize(12))
          .fontColor(this.accentBorderColor(item.itemType ?? item.role))
          .fontWeight(FontWeight.Medium)
          .width(22)

        Text(this.operationLabel(item.itemType ?? item.role))
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(this.conversationFontSize(12))
          .fontWeight(FontWeight.Medium)
          .fontColor(this.accentBorderColor(item.itemType ?? item.role))

        Text(item.timestamp)
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(10)
          .fontColor('#94A3B8')
          .margin({ left: 8 })

        if (item.status && item.status !== 'completed') {
          Text(this.statusLabel(item.status))
            .fontSize(9)
            .fontColor(this.statusColor(item.status))
            .backgroundColor(this.statusBgColor(item.status))
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(6)
            .margin({ left: 8 })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .hitTestBehavior(HitTestMode.Block)
      .onClick(() => {
        this.toggleMessageExpanded(item.id);
      })

      if (this.isMessageCollapsed(item)) {
        Row() {
          Text(this.collapsedMessagePreview(item))
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(this.conversationFontSize(11))
            .fontColor(this.accentBorderColor(item.itemType ?? item.role))
            .lineHeight(this.conversationLineHeight(17))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
          .width('100%')
          .padding({ left: 46 })
          .margin({ top: 5 })
          .hitTestBehavior(HitTestMode.Block)
          .onClick(() => {
            this.toggleMessageExpanded(item.id);
          })
      } else {
        Column() {
          this.messageBody(item)
          if (this.isReasoningMessage(item)) {
            this.reasoningToggleText(item)
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 28 })
      }
    }
    .width('92%')
    .constraintSize({ maxWidth: '92%' })
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    .backgroundColor('#F8FAFC')
    .borderRadius(8)
  }

  @Builder
  private reasoningToggleText(item: ChatMessage) {
    Text(this.isMessageCollapsed(item) ? '展开思考内容' : '收起思考内容')
      .copyOption(CopyOptions.None)
      .fontSize(this.conversationFontSize(10))
      .fontColor(this.accentBorderColor(item.itemType ?? item.role))
      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
      .margin({ top: 6 })
      .backgroundColor(this.eventSoftBackground(item.itemType ?? item.role))
      .border({ width: 0.5, color: this.eventBorderColor(item.itemType ?? item.role) })
      .borderRadius(6)
      .onClick(() => {
        this.toggleMessageExpanded(item.id);
      })
  }

  @Builder
  private messageHeader(item: ChatMessage) {
    Row() {
      Text(this.displayBrandText(item.author))
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(this.conversationFontSize(12))
        .fontWeight(FontWeight.Medium)
        .fontColor(this.authorColor(item.itemType ?? item.role))

      Text(item.timestamp)
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(10)
        .fontColor('#A1A1AA')
        .margin({ left: 8 })
    }
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private messageHeaderRow(item: ChatMessage) {
    if (this.isUserMessage(item)) {
      this.messageHeader(item)
    } else {
      Row() {
        this.messageHeader(item)
      }
      .width('100%')
      .constraintSize({ maxWidth: '100%' })
      .alignItems(VerticalAlign.Center)
    }
  }

  @Builder
  private messageCard(item: ChatMessage) {
    Column() {
      this.messageHeaderRow(item)
      this.messageBody(item)
    }
    .alignItems(HorizontalAlign.Start)
    .constraintSize({ maxWidth: this.messageCardMaxWidth(item) })
    .padding({
      left: this.isUserMessage(item) ? 12 : 4,
      right: this.isUserMessage(item) ? 12 : 4,
      top: this.isUserMessage(item) ? 9 : 4,
      bottom: this.isUserMessage(item) ? 9 : 4
    })
    .backgroundColor(this.messageBackground(item.itemType ?? item.role))
    .border({ width: this.isUserMessage(item) ? 0.5 : 0, color: this.isUserMessage(item) ? '#BFDBFE' : 'transparent' })
    .borderRadius(this.isUserMessage(item) ? 10 : 0)
  }

  @Builder
  private messageActionRow(item: ChatMessage) {
    if (this.shouldShowMessageActions(item) && this.hoveredMessageId === item.id) {
      Row() {
        this.iconCopyButton(() => {
          this.copyMessage(item);
        })
        if (this.shouldShowMessageSelectableAction(item)) {
          Blank()
            .width(4)
          this.iconSelectTextButton(this.isMessageSelectableMode(item.id), () => {
            this.toggleMessageSelectableMode(item.id);
          })
        }
      }
      .height(26)
      .margin({
        top: 3,
        left: this.isUserMessage(item) ? 0 : 2,
        right: this.isUserMessage(item) ? 2 : 0
      })
    }
  }

  @Builder
  private messageCluster(item: ChatMessage) {
    Column() {
      this.messageCard(item)
      this.messageActionRow(item)
    }
    .alignItems(this.isUserMessage(item) ? HorizontalAlign.End : HorizontalAlign.Start)
  }

  @Builder
  private messageLine(item: ChatMessage) {
    Row() {
      if (this.isUserMessage(item)) {
        Blank()
          .layoutWeight(1)
        this.messageCluster(item)
      } else if (this.isCollapsibleMessage(item)) {
        this.messageEventBlock(item)
        Blank()
          .layoutWeight(1)
      } else {
        this.messageCluster(item)
        Blank()
          .layoutWeight(1)
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .margin({ bottom: this.isCollapsibleMessage(item) ? 6 : 10 })
    .onHover((isHover: boolean) => {
      if (!this.shouldShowMessageActions(item)) {
        return;
      }
      if (isHover) {
        this.hoveredMessageId = item.id;
        return;
      }
      if (this.hoveredMessageId === item.id) {
        this.hoveredMessageId = '';
      }
    })
  }

  private isUserMessage(item: ChatMessage): boolean {
    return item.role === 'user';
  }

  private mermaidDiagramHeight(source: string, scale?: number): number {
    const lineCount: number = source.replace(/\r\n/g, '\n').replace(/\r/g, '\n').split('\n').length;
    const baseHeight: number = Math.min(Math.max(220, lineCount * 28 + 120), 640);
    return Math.min(Math.max(220, Math.round(baseHeight * this.clampConversationFontScale(scale ?? 1))), 1152);
  }

  private shouldShowMessageActions(item: ChatMessage): boolean {
    const type: string = item.itemType ?? item.role;
    return item.content.trim().length > 0 &&
      item.role !== 'system' &&
      type !== 'system' &&
      !this.isIntermediateMessageType(type);
  }

  private shouldShowMessageSelectableAction(item: ChatMessage): boolean {
    return this.shouldShowMessageActions(item) && this.hasRenderedOrCodeMarkdownSurface(item.content);
  }

  private hasRenderedOrCodeMarkdownSurface(content: string): boolean {
    const text: string = content.trim();
    if (text.length === 0 || !this.shouldRenderMarkdown(text)) {
      return false;
    }
    if (this.hasInlineLinkSegment(this.inlineMarkdownSegments(text, 'inline-link-probe'))) {
      return true;
    }
    if (this.hasInlineMathText(text)) {
      return true;
    }
    const blocks: MarkdownBlock[] = this.markdownBlocks(text);
    for (let index: number = 0; index < blocks.length; index += 1) {
      const kind: string = blocks[index].kind;
      if (kind === 'code' || kind === 'math' || kind === 'mermaid' || kind === 'table') {
        return true;
      }
    }
    return false;
  }

  private plainMarkdownTextRuns(content: string, baseId: string): MarkdownTextRun[] {
    const blocks: MarkdownBlock[] = this.markdownBlocks(content);
    const runs: MarkdownTextRun[] = [];
    let serial: number = 0;
    for (let index: number = 0; index < blocks.length; index += 1) {
      if (index > 0) {
        serial = this.pushPlainMarkdownRun(runs, serial, '\n', 'newline');
      }
      serial = this.appendPlainMarkdownBlockRuns(runs, serial, blocks[index], `${baseId}:plain:${index}`);
    }
    if (runs.length === 0) {
      runs.push(new MarkdownTextRun(`${baseId}:plain:empty`, content.trim(), 'paragraph'));
    }
    return runs;
  }

  private appendPlainMarkdownBlockRuns(runs: MarkdownTextRun[], serial: number, block: MarkdownBlock, baseId: string): number {
    switch (block.kind) {
      case 'heading':
        return this.appendPlainMarkdownInlineRuns(runs, serial, block.text, 'heading', block.level, baseId);
      case 'quote':
        return this.appendPlainMarkdownQuoteRuns(runs, serial, block, baseId);
      case 'list':
        return this.appendPlainMarkdownListRuns(runs, serial, block, baseId);
      case 'divider':
        return this.pushPlainMarkdownRun(runs, serial, '────────────', 'divider');
      default:
        return this.appendPlainMarkdownInlineRuns(runs, serial, block.text, 'paragraph', 0, baseId);
    }
  }

  private appendPlainMarkdownQuoteRuns(runs: MarkdownTextRun[], serial: number, block: MarkdownBlock, baseId: string): number {
    const lines: string[] = block.text.split('\n');
    for (let index: number = 0; index < lines.length; index += 1) {
      if (index > 0) {
        serial = this.pushPlainMarkdownRun(runs, serial, '\n', 'newline');
      }
      serial = this.pushPlainMarkdownRun(runs, serial, '> ', 'quoteMarker');
      serial = this.appendPlainMarkdownInlineRuns(runs, serial, lines[index], 'quote', 0, `${baseId}:q${index}`);
    }
    return serial;
  }

  private appendPlainMarkdownListRuns(runs: MarkdownTextRun[], serial: number, block: MarkdownBlock, baseId: string): number {
    const lines: string[] = block.text.split('\n');
    for (let index: number = 0; index < lines.length; index += 1) {
      if (index > 0) {
        serial = this.pushPlainMarkdownRun(runs, serial, '\n', 'newline');
      }
      serial = this.pushPlainMarkdownRun(runs, serial, `${this.markdownListMarker(lines[index])} `, 'listMarker');
      serial = this.appendPlainMarkdownInlineRuns(runs, serial, this.markdownListText(lines[index]), 'list', 0, `${baseId}:li${index}`);
    }
    return serial;
  }

  private appendPlainMarkdownInlineRuns(runs: MarkdownTextRun[], serial: number, text: string, blockKind: string, level: number, baseId: string): number {
    const lines: string[] = text.split('\n');
    for (let lineIndex: number = 0; lineIndex < lines.length; lineIndex += 1) {
      if (lineIndex > 0) {
        serial = this.pushPlainMarkdownRun(runs, serial, '\n', 'newline');
      }
      const segments: MathSegment[] = this.inlineMarkdownSegments(lines[lineIndex], `${baseId}:line${lineIndex}`);
      for (let segmentIndex: number = 0; segmentIndex < segments.length; segmentIndex += 1) {
        const segment: MathSegment = segments[segmentIndex];
        const displayText: string = segment.kind === 'math' ? segment.rawText : segment.text;
        serial = this.pushPlainMarkdownRun(runs, serial, displayText, blockKind, segment.kind, level);
      }
    }
    return serial;
  }

  private pushPlainMarkdownRun(
    runs: MarkdownTextRun[],
    serial: number,
    text: string,
    blockKind: string,
    inlineKind?: string,
    level?: number
  ): number {
    if (text.length === 0) {
      return serial;
    }
    runs.push(new MarkdownTextRun(`plain-run-${serial}`, text, blockKind, inlineKind, level));
    return serial + 1;
  }

  private plainMarkdownRunColor(run: MarkdownTextRun, itemType?: string): string {
    if (run.inlineKind === 'link') {
      return '#2563EB';
    }
    if (run.inlineKind === 'code') {
      return '#0F172A';
    }
    if (run.blockKind === 'heading') {
      return '#0F172A';
    }
    if (run.blockKind === 'quote' || run.blockKind === 'quoteMarker') {
      return '#475569';
    }
    if (run.blockKind === 'listMarker') {
      return '#64748B';
    }
    if (run.blockKind === 'divider') {
      return '#94A3B8';
    }
    return this.messageContentColor(itemType);
  }

  private plainMarkdownRunFontSize(run: MarkdownTextRun): number {
    if (run.blockKind === 'heading') {
      return this.markdownHeadingFontSize(run.level);
    }
    return this.conversationFontSize(12);
  }

  private plainMarkdownRunWeight(run: MarkdownTextRun): FontWeight {
    if (run.blockKind === 'heading' || run.inlineKind === 'strong' || run.inlineKind === 'code' ||
      run.blockKind === 'listMarker' || run.blockKind === 'quoteMarker') {
      return FontWeight.Medium;
    }
    return FontWeight.Regular;
  }

  private shouldRenderMarkdown(content: string): boolean {
    const text: string = content.trim();
    if (text.length === 0) {
      return false;
    }
    return this.hasBlockMarkdownContent(text) || this.hasInlineMarkdownContent(text);
  }

  private shouldRenderInlineOnlyMarkdown(content: string): boolean {
    const text: string = content.trim();
    return text.length > 0 && !this.hasBlockMarkdownContent(text) && this.hasInlineMarkdownContent(text);
  }

  private hasBlockMarkdownContent(text: string): boolean {
    return text.indexOf('```') >= 0 ||
      text.indexOf('$$') >= 0 ||
      text.indexOf('\\[') >= 0 ||
      text.match(/(^|\n)#{1,6}\s+\S/) !== null ||
      text.match(/(^|\n)\s*>\s+\S/) !== null ||
      text.match(/(^|\n)\s*([-*+]|\d+\.)\s+\S/) !== null ||
      text.match(/\n\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?/) !== null ||
      text.match(/(^|\n)\s*(---|\*\*\*|___)\s*($|\n)/) !== null;
  }

  private hasInlineMarkdownContent(text: string): boolean {
    const dollarStart: number = this.findInlineDollarStart(text, 0);
    return text.indexOf('\\(') >= 0 ||
      (dollarStart >= 0 && this.findInlineDollarEnd(text, dollarStart + 1) >= 0) ||
      text.match(/\*\*[^*]+\*\*/) !== null ||
      text.match(/__[^_]+__/) !== null ||
      text.match(/`[^`]+`/) !== null ||
      text.match(/!\[[^\]]*\]\([^)]+\)/) !== null ||
      text.match(/\[[^\]]+\]\([^)]+\)/) !== null ||
      this.findInlineWebTarget(text, 0) !== null;
  }

  private messageCardMaxWidth(item: ChatMessage): string {
    if (this.isCollapsibleMessage(item)) {
      return '82%';
    }
    if (this.isUserMessage(item)) {
      return this.hasWideMarkdownContent(item.content) ? '82%' : '72%';
    }
    return this.hasWideMarkdownContent(item.content) ? '94%' : '90%';
  }

  private hasWideMarkdownContent(content: string): boolean {
    const text: string = content.trim();
    return text.indexOf('```') >= 0 ||
      text.indexOf('$$') >= 0 ||
      text.indexOf('\\[') >= 0 ||
      text.match(/\n\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?/) !== null ||
      text.length > 180;
  }

  private isCollapsibleMessage(item: ChatMessage): boolean {
    const type: string = item.itemType ?? item.role;
    return this.isIntermediateMessageType(type);
  }

  private isReasoningMessage(item: ChatMessage): boolean {
    const type: string = item.itemType ?? item.role;
    return type === 'reasoning';
  }

  private isMessageCollapsed(item: ChatMessage): boolean {
    return this.isCollapsibleMessage(item) && !this.isMessageExpanded(item.id);
  }

  private isMessageExpanded(messageId: string): boolean {
    return this.expandedIntermediateMessageIds.indexOf(messageId) >= 0;
  }

  private toggleMessageExpanded(messageId: string): void {
    if (this.isMessageExpanded(messageId)) {
      this.expandedIntermediateMessageIds = this.expandedIntermediateMessageIds.filter((id: string) => id !== messageId);
      return;
    }
    this.expandedIntermediateMessageIds = [...this.expandedIntermediateMessageIds, messageId];
  }

  private isMessageSelectableMode(messageId: string): boolean {
    return this.selectableMessageIds.indexOf(messageId) >= 0;
  }

  private toggleMessageSelectableMode(messageId: string): void {
    if (this.isMessageSelectableMode(messageId)) {
      this.selectableMessageIds = this.selectableMessageIds.filter((id: string) => id !== messageId);
      return;
    }
    this.selectableMessageIds = [...this.selectableMessageIds, messageId];
  }

  private markdownBlocks(content: string): MarkdownBlock[] {
    const lines: string[] = content.replace(/\r\n/g, '\n').replace(/\r/g, '\n').split('\n');
    const blocks: MarkdownBlock[] = [];
    let i = 0;
    let serial = 0;

    while (i < lines.length) {
      const line: string = lines[i];
      const trimmed: string = line.trim();
      if (trimmed.length === 0) {
        i++;
        continue;
      }

      if (trimmed.startsWith('```')) {
        const language: string = trimmed.substring(3).trim().toLowerCase();
        const body: string[] = [];
        i++;
        while (i < lines.length && !lines[i].trim().startsWith('```')) {
          body.push(lines[i]);
          i++;
        }
        if (i < lines.length) {
          i++;
        }
        const code: string = body.join('\n');
        const kind: string = this.isMermaidCodeBlock(language, code) ? 'mermaid' : 'code';
        const rawLanguage: string = kind === 'mermaid' ? (language.length > 0 ? language : 'mermaid') : language;
        blocks.push(new MarkdownBlock(
          `md-${serial++}`,
          kind,
          code,
          0,
          language,
          [],
          this.fencedCodeSource(rawLanguage, code)
        ));
        continue;
      }

      if (trimmed.startsWith('$$')) {
        const body: string[] = [];
        const firstBody: string = trimmed.substring(2);
        if (firstBody.endsWith('$$') && firstBody.length > 2) {
          body.push(firstBody.substring(0, firstBody.length - 2));
          i++;
        } else {
          if (firstBody.trim().length > 0) {
            body.push(firstBody);
          }
          i++;
          while (i < lines.length && !lines[i].trim().endsWith('$$')) {
            body.push(lines[i]);
            i++;
          }
          if (i < lines.length) {
            const lastLine: string = lines[i].trim();
            const lastBody: string = lastLine.substring(0, Math.max(lastLine.length - 2, 0));
            if (lastBody.trim().length > 0) {
              body.push(lastBody);
            }
            i++;
          }
        }
        const mathBody: string = body.join('\n');
        blocks.push(new MarkdownBlock(`md-${serial++}`, 'math', mathBody, 0, '', [], this.wrappedMathSource('$$', '$$', mathBody)));
        continue;
      }

      if (trimmed.startsWith('\\[')) {
        const body: string[] = [];
        const firstBody: string = trimmed.substring(2);
        if (firstBody.endsWith('\\]') && firstBody.length > 2) {
          body.push(firstBody.substring(0, firstBody.length - 2));
          i++;
        } else {
          if (firstBody.trim().length > 0) {
            body.push(firstBody);
          }
          i++;
          while (i < lines.length && !lines[i].trim().endsWith('\\]')) {
            body.push(lines[i]);
            i++;
          }
          if (i < lines.length) {
            const lastLine: string = lines[i].trim();
            const lastBody: string = lastLine.substring(0, Math.max(lastLine.length - 2, 0));
            if (lastBody.trim().length > 0) {
              body.push(lastBody);
            }
            i++;
          }
        }
        const mathBody: string = body.join('\n');
        blocks.push(new MarkdownBlock(`md-${serial++}`, 'math', mathBody, 0, '', [], this.wrappedMathSource('\\[', '\\]', mathBody)));
        continue;
      }

      const headingMatch: RegExpMatchArray | null = line.match(/^(#{1,6})\s+(.+)$/);
      if (headingMatch !== null) {
        blocks.push(new MarkdownBlock(`md-${serial++}`, 'heading', headingMatch[2], headingMatch[1].length));
        i++;
        continue;
      }

      if (this.isDividerLine(trimmed)) {
        blocks.push(new MarkdownBlock(`md-${serial++}`, 'divider', ''));
        i++;
        continue;
      }

      if (this.isTableStart(lines, i)) {
        const rows: string[][] = [];
        rows.push(this.parseTableRow(lines[i]));
        i += 2;
        while (i < lines.length && lines[i].indexOf('|') >= 0 && lines[i].trim().length > 0) {
          rows.push(this.parseTableRow(lines[i]));
          i++;
        }
        blocks.push(new MarkdownBlock(`md-${serial++}`, 'table', '', 0, '', rows));
        continue;
      }

      if (this.isQuoteLine(trimmed)) {
        const body: string[] = [];
        while (i < lines.length && this.isQuoteLine(lines[i].trim())) {
          body.push(lines[i].trim().replace(/^>\s?/, ''));
          i++;
        }
        blocks.push(new MarkdownBlock(`md-${serial++}`, 'quote', body.join('\n')));
        continue;
      }

      if (this.isListLine(trimmed)) {
        const body: string[] = [];
        while (i < lines.length && this.isListLine(lines[i].trim())) {
          body.push(lines[i].trim());
          i++;
        }
        blocks.push(new MarkdownBlock(`md-${serial++}`, 'list', body.join('\n')));
        continue;
      }

      const body: string[] = [];
      while (i < lines.length && lines[i].trim().length > 0 && !this.isMarkdownBoundary(lines, i)) {
        body.push(lines[i].trim());
        i++;
      }
      if (body.length === 0) {
        body.push(line);
        i++;
      }
      blocks.push(new MarkdownBlock(`md-${serial++}`, 'paragraph', body.join('\n')));
    }

    if (blocks.length === 0) {
      blocks.push(new MarkdownBlock('md-empty', 'paragraph', content));
    }
    return blocks;
  }

  private isMarkdownBoundary(lines: string[], index: number): boolean {
    const trimmed: string = lines[index].trim();
    return trimmed.startsWith('```') ||
      trimmed.startsWith('$$') ||
      trimmed.startsWith('\\[') ||
      trimmed.match(/^(#{1,6})\s+(.+)$/) !== null ||
      this.isDividerLine(trimmed) ||
      this.isQuoteLine(trimmed) ||
      this.isListLine(trimmed) ||
      this.isTableStart(lines, index);
  }

  private isDividerLine(trimmed: string): boolean {
    return trimmed === '---' || trimmed === '***' || trimmed === '___';
  }

  private isMermaidCodeBlock(language: string, code: string): boolean {
    const lang: string = language.trim().toLowerCase();
    if (lang === 'mermaid' || lang === 'mmd') {
      return true;
    }
    const firstMeaningfulLine: string = this.firstMeaningfulMermaidLine(code).toLowerCase();
    if (firstMeaningfulLine.length === 0) {
      return false;
    }
    const starters: string[] = [
      'flowchart ',
      'graph ',
      'sequencediagram',
      'classdiagram',
      'statediagram',
      'statediagram-v2',
      'erdiagram',
      'journey',
      'gantt',
      'pie',
      'mindmap',
      'timeline',
      'quadrantchart',
      'requirementdiagram',
      'gitgraph',
      'c4context',
      'c4container',
      'c4component',
      'c4dynamic',
      'zenuml',
      'sankey',
      'sankey-beta',
      'xychart-beta',
      'block-beta',
      'packet-beta',
      'architecture-beta',
      'kanban',
      'radar-beta',
      'treemap-beta'
    ];
    for (let index: number = 0; index < starters.length; index += 1) {
      if (firstMeaningfulLine.startsWith(starters[index])) {
        return true;
      }
    }
    return false;
  }

  private firstMeaningfulMermaidLine(code: string): string {
    const lines: string[] = code.replace(/\r\n/g, '\n').replace(/\r/g, '\n').split('\n');
    let skippingFrontmatter: boolean = false;
    for (let index: number = 0; index < lines.length; index += 1) {
      const line: string = lines[index].trim();
      if (line.length === 0 || line.startsWith('%%')) {
        continue;
      }
      if (line === '---') {
        skippingFrontmatter = !skippingFrontmatter;
        continue;
      }
      if (!skippingFrontmatter) {
        return line;
      }
    }
    return '';
  }

  private isQuoteLine(trimmed: string): boolean {
    return trimmed.startsWith('>');
  }

  private isListLine(trimmed: string): boolean {
    return trimmed.match(/^([-*+])\s+.+$/) !== null || trimmed.match(/^\d+\.\s+.+$/) !== null;
  }

  private isTableStart(lines: string[], index: number): boolean {
    if (index + 1 >= lines.length) {
      return false;
    }
    const current: string = lines[index].trim();
    const separator: string = lines[index + 1].trim();
    return current.indexOf('|') >= 0 && separator.match(/^\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?$/) !== null;
  }

  private parseTableRow(line: string): string[] {
    let text: string = line.trim();
    if (text.startsWith('|')) {
      text = text.substring(1);
    }
    if (text.endsWith('|')) {
      text = text.substring(0, text.length - 1);
    }
    return text.split('|').map((cell: string): string => cell.trim());
  }

  private codeBlockLines(text: string): string[] {
    const lines: string[] = text.replace(/\r\n/g, '\n').replace(/\r/g, '\n').replace(/\t/g, '    ').split('\n');
    return lines.length > 0 ? lines : [''];
  }

  private codeLineTokens(line: string, language: string, baseId: string): CodeToken[] {
    const tokens: CodeToken[] = [];
    const lang: string = this.normalizeCodeLanguage(language);
    let cursor: number = 0;
    let serial: number = 0;

    while (cursor < line.length) {
      const current: string = line[cursor];
      if (current === ' ') {
        let end: number = cursor + 1;
        while (end < line.length && line[end] === ' ') {
          end += 1;
        }
        tokens.push(new CodeToken(`${baseId}:${serial++}`, 'plain', line.substring(cursor, end)));
        cursor = end;
        continue;
      }

      if (this.isCodeLineCommentStart(line, cursor, lang)) {
        tokens.push(new CodeToken(`${baseId}:${serial++}`, 'comment', line.substring(cursor)));
        break;
      }

      if (line.startsWith('/*', cursor)) {
        const closing: number = line.indexOf('*/', cursor + 2);
        const end: number = closing >= 0 ? closing + 2 : line.length;
        tokens.push(new CodeToken(`${baseId}:${serial++}`, 'comment', line.substring(cursor, end)));
        cursor = end;
        continue;
      }

      if (current === '"' || current === '\'' || current === '`') {
        const end: number = this.findCodeStringEnd(line, cursor, current);
        tokens.push(new CodeToken(`${baseId}:${serial++}`, 'string', line.substring(cursor, end)));
        cursor = end;
        continue;
      }

      if (this.isCodeDigit(current)) {
        const end: number = this.findCodeNumberEnd(line, cursor);
        tokens.push(new CodeToken(`${baseId}:${serial++}`, 'number', line.substring(cursor, end)));
        cursor = end;
        continue;
      }

      if (this.isCodeIdentifierStart(current)) {
        const end: number = this.findCodeIdentifierEnd(line, cursor);
        const word: string = line.substring(cursor, end);
        tokens.push(new CodeToken(`${baseId}:${serial++}`, this.codeIdentifierKind(word, lang), word));
        cursor = end;
        continue;
      }

      if (this.isCodeOperator(current)) {
        let end: number = cursor + 1;
        while (end < line.length && this.isCodeOperator(line[end])) {
          end += 1;
        }
        tokens.push(new CodeToken(`${baseId}:${serial++}`, 'operator', line.substring(cursor, end)));
        cursor = end;
        continue;
      }

      tokens.push(new CodeToken(`${baseId}:${serial++}`, 'plain', current));
      cursor += 1;
    }

    if (tokens.length === 0) {
      tokens.push(new CodeToken(`${baseId}:empty`, 'plain', ' '));
    }
    return tokens;
  }

  private normalizeCodeLanguage(language: string): string {
    const lang: string = language.trim().toLowerCase();
    if (lang === 'c++' || lang === 'cpp' || lang === 'cc' || lang === 'cxx') {
      return 'cpp';
    }
    if (lang === 'ts' || lang === 'tsx' || lang === 'typescript') {
      return 'typescript';
    }
    if (lang === 'js' || lang === 'jsx' || lang === 'javascript') {
      return 'javascript';
    }
    if (lang === 'py' || lang === 'python3') {
      return 'python';
    }
    if (lang === 'sh' || lang === 'bash' || lang === 'zsh' || lang === 'powershell' || lang === 'ps1') {
      return 'shell';
    }
    return lang;
  }

  private isCodeLineCommentStart(line: string, index: number, lang: string): boolean {
    if (line.startsWith('//', index)) {
      return lang !== 'python' && lang !== 'shell';
    }
    if (line.startsWith('%%', index)) {
      return lang === 'mermaid';
    }
    if (line.startsWith('#', index)) {
      return lang === 'python' || lang === 'shell' || lang === 'ruby' || lang === 'toml' || lang === 'yaml';
    }
    if (line.startsWith('--', index)) {
      return lang === 'sql' || lang === 'lua';
    }
    return false;
  }

  private findCodeStringEnd(line: string, start: number, quote: string): number {
    let cursor: number = start + 1;
    while (cursor < line.length) {
      if (line[cursor] === '\\') {
        cursor += 2;
        continue;
      }
      if (line[cursor] === quote) {
        return cursor + 1;
      }
      cursor += 1;
    }
    return line.length;
  }

  private findCodeNumberEnd(line: string, start: number): number {
    let cursor: number = start + 1;
    while (cursor < line.length && /[A-Za-z0-9_.]/.test(line[cursor])) {
      cursor += 1;
    }
    return cursor;
  }

  private findCodeIdentifierEnd(line: string, start: number): number {
    let cursor: number = start + 1;
    while (cursor < line.length && this.isCodeIdentifierPart(line[cursor])) {
      cursor += 1;
    }
    return cursor;
  }

  private isCodeIdentifierStart(ch: string): boolean {
    return /[A-Za-z_$]/.test(ch);
  }

  private isCodeIdentifierPart(ch: string): boolean {
    return /[A-Za-z0-9_$]/.test(ch);
  }

  private isCodeDigit(ch: string): boolean {
    return /[0-9]/.test(ch);
  }

  private isCodeOperator(ch: string): boolean {
    return '+-*/%=!<>&|^~?:.'.indexOf(ch) >= 0;
  }

  private codeIdentifierKind(word: string, lang: string): string {
    if (word === 'true' || word === 'false' || word === 'null' || word === 'undefined' || word === 'None' ||
      word === 'nil' || word === 'nullptr') {
      return 'literal';
    }
    if (this.isCodeKeyword(word, lang)) {
      return 'keyword';
    }
    if (this.isCodeBuiltin(word, lang)) {
      return 'builtin';
    }
    return 'plain';
  }

  private isCodeKeyword(word: string, lang: string): boolean {
    const common: string = '|if|else|for|while|do|switch|case|break|continue|return|try|catch|finally|throw|new|class|struct|enum|interface|extends|implements|public|private|protected|static|const|let|var|void|async|await|import|export|from|as|in|of|';
    if (common.indexOf(`|${word}|`) >= 0) {
      return true;
    }
    if (lang === 'c' || lang === 'cpp') {
      return '|auto|char|double|float|int|long|short|signed|unsigned|sizeof|typedef|union|volatile|extern|register|inline|namespace|template|typename|using|virtual|override|include|define|'.indexOf(`|${word}|`) >= 0;
    }
    if (lang === 'python') {
      return '|def|lambda|yield|with|pass|elif|global|nonlocal|assert|del|is|not|and|or|except|raise|'.indexOf(`|${word}|`) >= 0;
    }
    if (lang === 'rust') {
      return '|fn|let|mut|impl|trait|pub|crate|mod|use|match|where|loop|move|ref|self|Self|super|unsafe|'.indexOf(`|${word}|`) >= 0;
    }
    if (lang === 'java' || lang === 'kotlin') {
      return '|abstract|boolean|byte|char|double|final|float|int|long|native|package|short|strictfp|super|synchronized|this|throws|transient|volatile|'.indexOf(`|${word}|`) >= 0;
    }
    if (lang === 'css') {
      return '|display|position|absolute|relative|fixed|flex|grid|block|inline|none|color|background|border|margin|padding|width|height|'.indexOf(`|${word}|`) >= 0;
    }
    if (lang === 'mermaid') {
      return '|graph|flowchart|sequenceDiagram|classDiagram|stateDiagram|stateDiagram-v2|erDiagram|journey|gantt|pie|mindmap|timeline|subgraph|end|participant|actor|as|title|section|TD|TB|BT|LR|RL|'.indexOf(`|${word}|`) >= 0;
    }
    return false;
  }

  private isCodeBuiltin(word: string, lang: string): boolean {
    const common: string = '|String|Number|Boolean|Array|Object|Map|Set|Promise|Error|Date|Math|JSON|console|print|printf|scanf|main|';
    if (common.indexOf(`|${word}|`) >= 0) {
      return true;
    }
    if (lang === 'python') {
      return '|str|int|float|bool|list|dict|set|tuple|len|range|open|enumerate|zip|sum|min|max|'.indexOf(`|${word}|`) >= 0;
    }
    if (lang === 'rust') {
      return '|String|Vec|Option|Result|Some|None|Ok|Err|println|format|'.indexOf(`|${word}|`) >= 0;
    }
    return false;
  }

  private codeTokenColor(kind: string): string {
    switch (kind) {
      case 'keyword': return '#7C3AED';
      case 'builtin': return '#0369A1';
      case 'string': return '#15803D';
      case 'number':
      case 'literal': return '#B45309';
      case 'comment': return '#64748B';
      case 'operator': return '#BE123C';
      default: return '#0F172A';
    }
  }

  private codeTokenWeight(kind: string): FontWeight {
    return kind === 'keyword' || kind === 'builtin' ? FontWeight.Medium : FontWeight.Regular;
  }

  private normalizeInlineMarkdownText(text: string): string {
    let result: string = text;
    result = result.replace(/!\[([^\]]*)\]\(([^)]+)\)/g, '图片: $1');
    result = result.replace(/\[([^\]]+)\]\(([^)]+)\)/g, '$1 ($2)');
    result = result.replace(/\*\*([^*]+)\*\*/g, '$1');
    result = result.replace(/__([^_]+)__/g, '$1');
    result = result.replace(/`([^`]+)`/g, '$1');
    return result;
  }

  private inlineMarkdownSegments(text: string, baseId: string): MathSegment[] {
    const segments: MathSegment[] = [];
    let cursor: number = 0;
    let serial: number = 0;

    while (cursor < text.length) {
      const dollarStart: number = this.findInlineDollarStart(text, cursor);
      const parenStart: number = text.indexOf('\\(', cursor);
      let start: number = -1;
      let kind: string = '';

      if (dollarStart >= 0 && (parenStart < 0 || dollarStart < parenStart)) {
        start = dollarStart;
        kind = 'dollar';
      } else if (parenStart >= 0) {
        start = parenStart;
        kind = 'paren';
      }

      if (start < 0) {
        serial = this.pushInlineMarkdownTextSegments(segments, text.substring(cursor), baseId, serial);
        break;
      }

      if (start > cursor) {
        serial = this.pushInlineMarkdownTextSegments(segments, text.substring(cursor, start), baseId, serial);
      }

      if (kind === 'dollar') {
        const end: number = this.findInlineDollarEnd(text, start + 1);
        if (end < 0) {
          serial = this.pushInlineMarkdownTextSegments(segments, text.substring(start), baseId, serial);
          break;
        }
        const expr: string = text.substring(start + 1, end);
        const raw: string = text.substring(start, end + 1);
        if (expr.indexOf('\n') >= 0 || expr.trim().length === 0) {
          serial = this.pushInlineMarkdownTextSegments(segments, raw, baseId, serial);
        } else {
          this.pushInlineMarkdownSegment(segments, new MathSegment(`${baseId}:math:${serial++}`, 'math', expr.trim(), raw));
        }
        cursor = end + 1;
        continue;
      }

      const parenEnd: number = text.indexOf('\\)', start + 2);
      if (parenEnd < 0) {
        serial = this.pushInlineMarkdownTextSegments(segments, text.substring(start), baseId, serial);
        break;
      }
      const expr: string = text.substring(start + 2, parenEnd);
      const raw: string = text.substring(start, parenEnd + 2);
      if (expr.indexOf('\n') >= 0 || expr.trim().length === 0) {
        serial = this.pushInlineMarkdownTextSegments(segments, raw, baseId, serial);
      } else {
        this.pushInlineMarkdownSegment(segments, new MathSegment(`${baseId}:math:${serial++}`, 'math', expr.trim(), raw));
      }
      cursor = parenEnd + 2;
    }

    if (segments.length === 0) {
      segments.push(new MathSegment(`${baseId}:text:0`, 'text', this.normalizeInlineMarkdownText(text)));
    }
    return segments;
  }

  private pushInlineMarkdownTextSegments(segments: MathSegment[], text: string, baseId: string, serial: number): number {
    let cursor: number = 0;
    while (cursor < text.length) {
      let next: number = text.length;
      let kind: string = '';
      const webTargetMatch: InlineWebTargetMatch | null = this.findInlineWebTarget(text, cursor);
      if (webTargetMatch !== null && webTargetMatch.start < next) {
        next = webTargetMatch.start;
        kind = 'web-target';
      }
      const codeStart: number = text.indexOf('`', cursor);
      if (codeStart >= 0 && codeStart < next) {
        next = codeStart;
        kind = 'code';
      }
      const strongStarStart: number = text.indexOf('**', cursor);
      if (strongStarStart >= 0 && strongStarStart < next) {
        next = strongStarStart;
        kind = 'strong-star';
      }
      const strongUnderlineStart: number = text.indexOf('__', cursor);
      if (strongUnderlineStart >= 0 && strongUnderlineStart < next) {
        next = strongUnderlineStart;
        kind = 'strong-underline';
      }
      const imageStart: number = text.indexOf('![', cursor);
      if (imageStart >= 0 && imageStart < next) {
        next = imageStart;
        kind = 'image';
      }
      const linkStart: number = text.indexOf('[', cursor);
      if (linkStart >= 0 && linkStart < next) {
        next = linkStart;
        kind = 'link';
      }

      if (next > cursor) {
        this.pushInlineMarkdownSegment(segments, new MathSegment(`${baseId}:text:${serial++}`, 'text', text.substring(cursor, next)));
      }
      if (kind.length === 0) {
        break;
      }

      if (kind === 'code') {
        const end: number = text.indexOf('`', next + 1);
        if (end > next + 1) {
          const codeText: string = text.substring(next + 1, end);
          if (this.isOpenableWebTarget(codeText)) {
            this.pushInlineMarkdownSegment(segments, new MathSegment(`${baseId}:link:${serial++}`, 'link', codeText, text.substring(next, end + 1), codeText));
          } else {
            this.pushInlineMarkdownSegment(segments, new MathSegment(`${baseId}:code:${serial++}`, 'code', codeText, text.substring(next, end + 1)));
          }
          cursor = end + 1;
          continue;
        }
      } else if (kind === 'web-target') {
        const match: InlineWebTargetMatch | null = this.findInlineWebTarget(text, next);
        if (match !== null && match.start === next && match.end > next) {
          const display: string = text.substring(match.start, match.end);
          this.pushInlineMarkdownSegment(segments, new MathSegment(`${baseId}:link:${serial++}`, 'link', display, display, match.target));
          cursor = match.end;
          continue;
        }
      } else if (kind === 'strong-star') {
        const end: number = text.indexOf('**', next + 2);
        if (end > next + 2) {
          this.pushInlineMarkdownSegment(segments, new MathSegment(`${baseId}:strong:${serial++}`, 'strong', text.substring(next + 2, end), text.substring(next, end + 2)));
          cursor = end + 2;
          continue;
        }
      } else if (kind === 'strong-underline') {
        const end: number = text.indexOf('__', next + 2);
        if (end > next + 2) {
          this.pushInlineMarkdownSegment(segments, new MathSegment(`${baseId}:strong:${serial++}`, 'strong', text.substring(next + 2, end), text.substring(next, end + 2)));
          cursor = end + 2;
          continue;
        }
      } else if (kind === 'image' || kind === 'link') {
        const parsedEnd: number = this.pushInlineMarkdownLinkSegment(segments, text, next, baseId, serial, kind === 'image');
        if (parsedEnd > next) {
          serial += 1;
          cursor = parsedEnd;
          continue;
        }
      }

      this.pushInlineMarkdownSegment(segments, new MathSegment(`${baseId}:text:${serial++}`, 'text', text[next]));
      cursor = next + 1;
    }
    return serial;
  }

  private pushInlineMarkdownLinkSegment(segments: MathSegment[], text: string, start: number, baseId: string, serial: number, image: boolean): number {
    const labelStart: number = image ? start + 2 : start + 1;
    const labelEnd: number = text.indexOf(']', labelStart);
    if (labelEnd <= labelStart || labelEnd + 1 >= text.length || text[labelEnd + 1] !== '(') {
      return -1;
    }
    const urlEnd: number = text.indexOf(')', labelEnd + 2);
    if (urlEnd <= labelEnd + 2) {
      return -1;
    }
    const label: string = text.substring(labelStart, labelEnd).trim();
    const url: string = text.substring(labelEnd + 2, urlEnd).trim();
    const target: string = this.cleanMarkdownLinkTarget(url);
    const display: string = image ? (label.length > 0 ? `图片: ${label}` : '图片') : (label.length > 0 ? label : url);
    this.pushInlineMarkdownSegment(segments, new MathSegment(`${baseId}:link:${serial}`, 'link', display, text.substring(start, urlEnd + 1), target));
    return urlEnd + 1;
  }

  private findInlineWebTarget(text: string, cursor: number): InlineWebTargetMatch | null {
    const httpMatch: InlineWebTargetMatch | null = this.findInlineHttpTarget(text, cursor);
    const localFileMatch: InlineWebTargetMatch | null = this.findInlineLocalWebFileTarget(text, cursor);
    if (httpMatch === null) {
      return localFileMatch;
    }
    if (localFileMatch === null) {
      return httpMatch;
    }
    return httpMatch.start <= localFileMatch.start ? httpMatch : localFileMatch;
  }

  private findInlineHttpTarget(text: string, cursor: number): InlineWebTargetMatch | null {
    const lower: string = text.toLowerCase();
    const httpIndex: number = lower.indexOf('http://', cursor);
    const httpsIndex: number = lower.indexOf('https://', cursor);
    let start: number = -1;
    if (httpIndex >= 0 && httpsIndex >= 0) {
      start = Math.min(httpIndex, httpsIndex);
    } else if (httpIndex >= 0) {
      start = httpIndex;
    } else if (httpsIndex >= 0) {
      start = httpsIndex;
    }
    if (start < 0) {
      return null;
    }
    let end: number = start;
    while (end < text.length && !this.isHttpTargetDelimiter(text[end])) {
      end += 1;
    }
    const trimmedEnd: number = this.trimAutoTargetEnd(text, start, end);
    if (trimmedEnd <= start) {
      return null;
    }
    const target: string = text.substring(start, trimmedEnd);
    return new InlineWebTargetMatch(start, trimmedEnd, target);
  }

  private findInlineLocalWebFileTarget(text: string, cursor: number): InlineWebTargetMatch | null {
    const lower: string = text.toLowerCase();
    let extensionIndex: number = this.nextOpenableFileExtensionIndex(lower, cursor);
    while (extensionIndex >= 0) {
      const extensionEnd: number = this.openableFileExtensionEnd(lower, extensionIndex);
      if (extensionEnd > extensionIndex) {
        let start: number = extensionIndex - 1;
        while (start >= 0 && !this.isLocalFileTargetDelimiter(text[start])) {
          start -= 1;
        }
        start += 1;
        let end: number = extensionEnd;
        if (end < text.length && (text[end] === '?' || text[end] === '#')) {
          end += 1;
          while (end < text.length && !this.isLocalFileTargetDelimiter(text[end])) {
            end += 1;
          }
        }
        end = this.trimAutoTargetEnd(text, start, end);
        if (start < end) {
          const rawTarget: string = text.substring(start, end);
          const target: string = this.normalizeInlineLocalWebFileTarget(rawTarget);
          if (this.isOpenableWebTarget(target)) {
            return new InlineWebTargetMatch(end - target.length, end, target);
          }
        }
      }
      extensionIndex = this.nextOpenableFileExtensionIndex(lower, extensionIndex + 1);
    }
    return null;
  }

  private nextOpenableFileExtensionIndex(lowerText: string, cursor: number): number {
    const extensions: string[] = ['.html', '.htm', '.markdown', '.md'];
    let result: number = -1;
    for (let index: number = 0; index < extensions.length; index += 1) {
      const next: number = lowerText.indexOf(extensions[index], cursor);
      if (next >= 0 && (result < 0 || next < result)) {
        result = next;
      }
    }
    return result;
  }

  private normalizeInlineLocalWebFileTarget(target: string): string {
    const cleanTarget: string = target.trim();
    if (this.isFileUri(cleanTarget) || this.isAbsoluteLocalPath(cleanTarget)) {
      return cleanTarget;
    }
    for (let index: number = 0; index < cleanTarget.length; index += 1) {
      if (!this.isAsciiLocalFileStart(cleanTarget[index])) {
        continue;
      }
      const candidate: string = cleanTarget.substring(index);
      if (this.isHtmlFileTarget(candidate) || this.isMarkdownFileTarget(candidate)) {
        return candidate;
      }
    }
    return cleanTarget;
  }

  private isAsciiLocalFileStart(ch: string): boolean {
    return (ch >= 'A' && ch <= 'Z') ||
      (ch >= 'a' && ch <= 'z') ||
      (ch >= '0' && ch <= '9') ||
      ch === '_' ||
      ch === '-' ||
      ch === '.';
  }

  private openableFileExtensionEnd(lowerText: string, extensionIndex: number): number {
    if (lowerText.substring(extensionIndex, extensionIndex + 5) === '.html') {
      return extensionIndex + 5;
    }
    if (lowerText.substring(extensionIndex, extensionIndex + 4) === '.htm') {
      const next: string = extensionIndex + 4 < lowerText.length ? lowerText[extensionIndex + 4] : '';
      if (next.length === 0 || next === '?' || next === '#' || this.isLocalFileTargetDelimiter(next)) {
        return extensionIndex + 4;
      }
    }
    if (lowerText.substring(extensionIndex, extensionIndex + 9) === '.markdown') {
      return extensionIndex + 9;
    }
    if (lowerText.substring(extensionIndex, extensionIndex + 3) === '.md') {
      const next: string = extensionIndex + 3 < lowerText.length ? lowerText[extensionIndex + 3] : '';
      if (next.length === 0 || next === '?' || next === '#' || this.isLocalFileTargetDelimiter(next)) {
        return extensionIndex + 3;
      }
    }
    return -1;
  }

  private isHttpTargetDelimiter(ch: string): boolean {
    return ch === ' ' || ch === '\n' || ch === '\r' || ch === '\t' ||
      ch === '<' || ch === '>' || ch === '"' || ch === '\'' || ch === '`';
  }

  private isLocalFileTargetDelimiter(ch: string): boolean {
    return this.isHttpTargetDelimiter(ch) ||
      ch === '[' || ch === ']' || ch === '(' || ch === ')' ||
      ch === '{' || ch === '}' || ch === ',' || ch === ';' || ch === '!' || ch === '?';
  }

  private trimAutoTargetEnd(text: string, start: number, end: number): number {
    let nextEnd: number = end;
    while (nextEnd > start) {
      const ch: string = text[nextEnd - 1];
      if (ch === '.' || ch === ',' || ch === ';' || ch === ':' || ch === '!' || ch === '?') {
        nextEnd -= 1;
        continue;
      }
      if ((ch === ')' || ch === ']') && this.hasUnbalancedClosingTargetChar(text.substring(start, nextEnd), ch)) {
        nextEnd -= 1;
        continue;
      }
      break;
    }
    return nextEnd;
  }

  private hasUnbalancedClosingTargetChar(value: string, closing: string): boolean {
    const opening: string = closing === ')' ? '(' : '[';
    let openCount: number = 0;
    let closeCount: number = 0;
    for (let index: number = 0; index < value.length; index += 1) {
      if (value[index] === opening) {
        openCount += 1;
      } else if (value[index] === closing) {
        closeCount += 1;
      }
    }
    return closeCount > openCount;
  }

  private cleanMarkdownLinkTarget(target: string): string {
    let result: string = target.trim();
    if (result.length >= 2 && result[0] === '<') {
      const closeIndex: number = result.indexOf('>');
      if (closeIndex > 0) {
        result = result.substring(1, closeIndex).trim();
      }
    }
    return result;
  }

  private pushInlineMarkdownSegment(segments: MathSegment[], segment: MathSegment): void {
    if (segment.text.length === 0) {
      return;
    }
    if (segment.kind === 'text' && segments.length > 0 && segments[segments.length - 1].kind === 'text') {
      const previous: MathSegment = segments[segments.length - 1];
      previous.text += segment.text;
      previous.rawText += segment.rawText;
      return;
    }
    segments.push(segment);
  }

  private findInlineDollarStart(text: string, cursor: number): number {
    for (let i = cursor; i < text.length; i++) {
      if (text[i] !== '$') {
        continue;
      }
      if (i > 0 && text[i - 1] === '\\') {
        continue;
      }
      if (i + 1 < text.length && text[i + 1] === '$') {
        continue;
      }
      return i;
    }
    return -1;
  }

  private findInlineDollarEnd(text: string, cursor: number): number {
    for (let i = cursor; i < text.length; i++) {
      if (text[i] !== '$') {
        continue;
      }
      if (i > 0 && text[i - 1] === '\\') {
        continue;
      }
      if (i + 1 < text.length && text[i + 1] === '$') {
        continue;
      }
      return i;
    }
    return -1;
  }

  private mathBlockLines(text: string): string[] {
    const normalized: string = this.normalizeFormulaSource(text).replace(/\\\\/g, '\n');
    const rawLines: string[] = normalized.replace(/\r\n/g, '\n').replace(/\r/g, '\n').split('\n');
    const lines: string[] = [];
    for (let i = 0; i < rawLines.length; i++) {
      const line: string = rawLines[i].replace(/&/g, ' ').trim();
      if (line.length > 0) {
        lines.push(line);
      }
    }
    if (lines.length > 0) {
      return lines;
    }
    const fallback: string = normalized.trim();
    return fallback.length > 0 ? [fallback] : ['0'];
  }

  private normalizeFormulaSource(text: string): string {
    let result: string = text.trim();
    if (result.startsWith('$$') && result.endsWith('$$') && result.length > 4) {
      result = result.substring(2, result.length - 2).trim();
    } else if (result.startsWith('\\[') && result.endsWith('\\]') && result.length > 4) {
      result = result.substring(2, result.length - 2).trim();
    } else if (result.startsWith('\\(') && result.endsWith('\\)') && result.length > 4) {
      result = result.substring(2, result.length - 2).trim();
    } else if (result.startsWith('$') && result.endsWith('$') && result.length > 2) {
      result = result.substring(1, result.length - 1).trim();
    }
    result = result.replace(/\\begin\{[^{}]+\}/g, '');
    result = result.replace(/\\end\{[^{}]+\}/g, '');
    result = result.replace(/\\left/g, '');
    result = result.replace(/\\right/g, '');
    result = result.replace(/\\,/g, ' ');
    result = result.replace(/\\;/g, ' ');
    result = result.replace(/\\:/g, ' ');
    result = result.replace(/\\!/g, '');
    return result.trim();
  }

  private parseFormula(text: string): FormulaNode {
    const parsed: FormulaParseResult = this.parseFormulaSequence(this.normalizeFormulaSource(text), 0, '');
    return parsed.node;
  }

  private parseFormulaSequence(source: string, index: number, stopChar: string): FormulaParseResult {
    const children: FormulaNode[] = [];
    let cursor: number = index;

    while (cursor < source.length) {
      if (stopChar.length > 0 && source[cursor] === stopChar) {
        cursor += 1;
        break;
      }
      if (source[cursor] === '}') {
        break;
      }
      if (source[cursor] === ' ' || source[cursor] === '\t') {
        this.pushFormulaChild(children, new FormulaNode('text', ' '));
        cursor += 1;
        continue;
      }
      if (source[cursor] === '/') {
        const numeratorIndex: number = this.findFormulaFractionNumeratorIndex(children);
        if (numeratorIndex >= 0) {
          const denominatorCursor: number = this.skipFormulaWhitespace(source, cursor + 1);
          const denominator: FormulaParseResult = this.parseFormulaOperand(source, denominatorCursor);
          if (!(denominator.node.kind === 'text' && denominator.node.text.length === 0 && denominator.nextIndex === denominatorCursor)) {
            const numeratorNodes: FormulaNode[] = children.splice(numeratorIndex, children.length - numeratorIndex);
            const fraction: FormulaNode = new FormulaNode('fraction');
            fraction.numerator = numeratorNodes[0];
            fraction.denominator = denominator.node;
            this.pushFormulaChild(children, fraction);
            cursor = denominator.nextIndex;
            continue;
          }
        }
      }
      const operand: FormulaParseResult = this.parseFormulaOperand(source, cursor);
      this.pushFormulaChild(children, operand.node);
      cursor = operand.nextIndex;
    }

    if (children.length === 0) {
      return new FormulaParseResult(new FormulaNode('text', ''), cursor);
    }
    if (children.length === 1) {
      return new FormulaParseResult(children[0], cursor);
    }
    return new FormulaParseResult(new FormulaNode('sequence', '', children), cursor);
  }

  private parseFormulaOperand(source: string, index: number): FormulaParseResult {
    const atom: FormulaParseResult = this.parseFormulaAtom(source, index);
    let node: FormulaNode = atom.node;
    let cursor: number = atom.nextIndex;
    let superscript: FormulaNode | null = null;
    let subscript: FormulaNode | null = null;

    while (cursor < source.length && (source[cursor] === '^' || source[cursor] === '_')) {
      const operator: string = source[cursor];
      const operand: FormulaParseResult = this.parseFormulaScriptOperand(source, cursor + 1);
      cursor = operand.nextIndex;
      if (operator === '^') {
        superscript = operand.node;
      } else {
        subscript = operand.node;
      }
    }

    if (superscript !== null || subscript !== null) {
      const scriptNode: FormulaNode = new FormulaNode('script');
      scriptNode.base = node;
      scriptNode.superscript = superscript;
      scriptNode.subscript = subscript;
      node = scriptNode;
    }

    return new FormulaParseResult(node, cursor);
  }

  private parseFormulaScriptOperand(source: string, index: number): FormulaParseResult {
    if (index >= source.length) {
      return new FormulaParseResult(new FormulaNode('text', ''), index);
    }
    if (source[index] === '{') {
      return this.parseFormulaSequence(source, index + 1, '}');
    }
    return this.parseFormulaAtom(source, index);
  }

  private parseFormulaAtom(source: string, index: number): FormulaParseResult {
    if (index >= source.length) {
      return new FormulaParseResult(new FormulaNode('text', ''), index);
    }

    const current: string = source[index];
    if (current === '{') {
      return this.parseFormulaSequence(source, index + 1, '}');
    }
    if (current === '(') {
      return this.parseFormulaDelimitedGroup(source, index, ')', '()');
    }
    if (current === '[') {
      return this.parseFormulaDelimitedGroup(source, index, ']', '[]');
    }

    if (current === '\\') {
      if (index + 1 >= source.length) {
        return new FormulaParseResult(new FormulaNode('text', '\\'), index + 1);
      }

      if (source[index + 1] === '\\') {
        return new FormulaParseResult(new FormulaNode('text', ' '), index + 2);
      }

      let cursor: number = index + 1;
      while (cursor < source.length && this.isFormulaLetter(source[cursor])) {
        cursor += 1;
      }

      if (cursor === index + 1) {
        return new FormulaParseResult(new FormulaNode('text', source[index + 1]), index + 2);
      }

      const command: string = source.substring(index + 1, cursor);
      if (command === 'frac' || command === 'dfrac' || command === 'tfrac') {
        const numerator: FormulaParseResult = this.parseFormulaScriptOperand(source, cursor);
        const denominator: FormulaParseResult = this.parseFormulaScriptOperand(source, numerator.nextIndex);
        const fraction: FormulaNode = new FormulaNode('fraction');
        fraction.numerator = numerator.node;
        fraction.denominator = denominator.node;
        return new FormulaParseResult(fraction, denominator.nextIndex);
      }

      if (command === 'sqrt') {
        let nextIndex: number = cursor;
        if (nextIndex < source.length && source[nextIndex] === '[') {
          nextIndex += 1;
          while (nextIndex < source.length && source[nextIndex] !== ']') {
            nextIndex += 1;
          }
          if (nextIndex < source.length) {
            nextIndex += 1;
          }
        }
        const radicand: FormulaParseResult = this.parseFormulaScriptOperand(source, nextIndex);
        const sqrtNode: FormulaNode = new FormulaNode('sqrt');
        sqrtNode.radicand = radicand.node;
        return new FormulaParseResult(sqrtNode, radicand.nextIndex);
      }

      if (command === 'operatorname' && cursor < source.length && source[cursor] === '*') {
        cursor += 1;
      }

      if (command === 'text' || command === 'mathrm' || command === 'operatorname' || command === 'mathbf' ||
        command === 'mathit' || command === 'mathbb' || command === 'mathcal' || command === 'mathsf' || command === 'mathtt') {
        return this.parseFormulaTextGroup(source, cursor, command === 'mathit' ? 'italic' : 'roman');
      }

      if (command === 'displaystyle' || command === 'textstyle' || command === 'limits' || command === 'nolimits') {
        return new FormulaParseResult(new FormulaNode('text', ''), cursor);
      }

      if (this.isFormulaSpacingCommand(command)) {
        return new FormulaParseResult(new FormulaNode('space', command), cursor);
      }

      const mapped: string = this.formulaCommandText(command);
      if (mapped.length > 0) {
        return new FormulaParseResult(
          new FormulaNode(this.isFormulaOperatorCommand(command) ? 'operator' : 'text', mapped, [], this.isFormulaOperatorCommand(command) ? 'roman' : 'italic'),
          cursor
        );
      }

      return new FormulaParseResult(new FormulaNode('text', command), cursor);
    }

    if (this.isFormulaLetter(current)) {
      let cursor: number = index + 1;
      while (cursor < source.length && this.isFormulaLetter(source[cursor])) {
        cursor += 1;
      }
      return new FormulaParseResult(new FormulaNode('text', source.substring(index, cursor), [], 'italic'), cursor);
    }

    if (this.isFormulaDigit(current)) {
      let cursor: number = index + 1;
      while (cursor < source.length && this.isFormulaDigit(source[cursor])) {
        cursor += 1;
      }
      return new FormulaParseResult(new FormulaNode('number', source.substring(index, cursor), [], 'roman'), cursor);
    }

    return new FormulaParseResult(
      new FormulaNode(this.isFormulaOperatorChar(current) || this.isFormulaPunctuationChar(current) ? 'operator' : 'text', current, [], 'roman'),
      index + 1
    );
  }

  private pushFormulaChild(children: FormulaNode[], node: FormulaNode): void {
    if (node.kind === 'text' && node.text.length === 0) {
      return;
    }
    if (children.length > 0 && children[children.length - 1].kind === node.kind && children[children.length - 1].variant === node.variant &&
      (node.kind === 'text' || node.kind === 'number' || node.kind === 'operator')) {
      children[children.length - 1].text += node.text;
      return;
    }
    children.push(node);
  }

  private parseFormulaTextGroup(source: string, index: number, variant: string): FormulaParseResult {
    if (index >= source.length || source[index] !== '{') {
      return this.parseFormulaScriptOperand(source, index);
    }
    let cursor: number = index + 1;
    let depth: number = 1;
    let result: string = '';
    while (cursor < source.length && depth > 0) {
      if (source[cursor] === '{') {
        depth += 1;
        result += source[cursor];
        cursor += 1;
        continue;
      }
      if (source[cursor] === '}') {
        depth -= 1;
        if (depth === 0) {
          cursor += 1;
          break;
        }
        result += source[cursor];
        cursor += 1;
        continue;
      }
      result += source[cursor];
      cursor += 1;
    }
    return new FormulaParseResult(new FormulaNode('text', result, [], variant), cursor);
  }

  private parseFormulaDelimitedGroup(source: string, index: number, closingChar: string, delimiter: string): FormulaParseResult {
    const inner: FormulaParseResult = this.parseFormulaSequence(source, index + 1, closingChar);
    return new FormulaParseResult(new FormulaNode('group', delimiter, [inner.node]), inner.nextIndex);
  }

  private skipFormulaWhitespace(source: string, index: number): number {
    let cursor: number = index;
    while (cursor < source.length && (source[cursor] === ' ' || source[cursor] === '\t')) {
      cursor += 1;
    }
    return cursor;
  }

  private findFormulaFractionNumeratorIndex(children: FormulaNode[]): number {
    let index: number = children.length - 1;
    while (index >= 0 && this.isFormulaSpaceNode(children[index])) {
      index -= 1;
    }
    if (index < 0) {
      return -1;
    }
    return this.isFormulaFractionCandidate(children[index]) ? index : -1;
  }

  private isFormulaSpaceNode(node: FormulaNode): boolean {
    return node.kind === 'text' && node.text === ' ';
  }

  private isFormulaFractionCandidate(node: FormulaNode): boolean {
    if (node.kind === 'text' || node.kind === 'number' || node.kind === 'sequence' || node.kind === 'group' ||
      node.kind === 'fraction' || node.kind === 'sqrt' || node.kind === 'script') {
      return true;
    }
    if (node.kind === 'operator') {
      return node.text.length > 1 || '+-=<>*/'.indexOf(node.text) < 0;
    }
    return false;
  }

  private isFormulaLetter(ch: string): boolean {
    return /[A-Za-z]/.test(ch);
  }

  private isFormulaDigit(ch: string): boolean {
    return /[0-9]/.test(ch);
  }

  private isFormulaOperatorChar(ch: string): boolean {
    return '+-=<>*/'.indexOf(ch) >= 0;
  }

  private isFormulaPunctuationChar(ch: string): boolean {
    return '()[]{}|,.;:!'.indexOf(ch) >= 0;
  }

  private isFormulaSpacingCommand(command: string): boolean {
    return command === 'quad' || command === 'qquad';
  }

  private isFormulaOperatorCommand(command: string): boolean {
    return command === 'sum' ||
      command === 'prod' ||
      command === 'int' ||
      command === 'oint' ||
      command === 'times' ||
      command === 'cdot' ||
      command === 'pm' ||
      command === 'mp' ||
      command === 'leq' ||
      command === 'le' ||
      command === 'geq' ||
      command === 'ge' ||
      command === 'neq' ||
      command === 'approx' ||
      command === 'mid' ||
      command === 'cap' ||
      command === 'cup' ||
      command === 'in' ||
      command === 'notin' ||
      command === 'to' ||
      command === 'rightarrow' ||
      command === 'leftarrow' ||
      command === 'mapsto' ||
      command === 'sin' ||
      command === 'cos' ||
      command === 'tan' ||
      command === 'log' ||
      command === 'ln' ||
      command === 'lim' ||
      command === 'limsup' ||
      command === 'liminf' ||
      command === 'sup' ||
      command === 'inf' ||
      command === 'argmax' ||
      command === 'argmin' ||
      command === 'max' ||
      command === 'min' ||
      command === 'exp';
  }

  private formulaCommandText(command: string): string {
    switch (command) {
      case 'alpha': return 'α';
      case 'beta': return 'β';
      case 'gamma': return 'γ';
      case 'delta': return 'δ';
      case 'epsilon':
      case 'varepsilon': return 'ε';
      case 'theta':
      case 'vartheta': return 'θ';
      case 'lambda': return 'λ';
      case 'mu': return 'μ';
      case 'pi': return 'π';
      case 'sigma': return 'σ';
      case 'phi':
      case 'varphi': return 'φ';
      case 'omega': return 'ω';
      case 'Gamma': return 'Γ';
      case 'Delta': return 'Δ';
      case 'Theta': return 'Θ';
      case 'Lambda': return 'Λ';
      case 'Pi': return 'Π';
      case 'Sigma': return 'Σ';
      case 'Phi': return 'Φ';
      case 'Omega': return 'Ω';
      case 'sum': return '∑';
      case 'prod': return '∏';
      case 'int': return '∫';
      case 'oint': return '∮';
      case 'infty': return '∞';
      case 'times': return '×';
      case 'cdot': return '·';
      case 'pm': return '±';
      case 'mp': return '∓';
      case 'neq': return '≠';
      case 'approx': return '≈';
      case 'mid': return '|';
      case 'cap': return '∩';
      case 'cup': return '∪';
      case 'in': return '∈';
      case 'notin': return '∉';
      case 'le':
      case 'leq': return '≤';
      case 'ge':
      case 'geq': return '≥';
      case 'to':
      case 'rightarrow': return '→';
      case 'leftarrow': return '←';
      case 'mapsto': return '↦';
      case 'cdots': return '⋯';
      case 'ldots': return '…';
      case 'sin':
      case 'cos':
      case 'tan':
      case 'log':
      case 'ln':
      case 'lim':
      case 'limsup':
      case 'liminf':
      case 'sup':
      case 'inf':
      case 'argmax':
      case 'argmin':
      case 'max':
      case 'min':
      case 'exp': return command;
      default: return '';
    }
  }

  private renderInlineMath(text: string): string {
    let result: string = '';
    let cursor: number = 0;
    while (cursor < text.length) {
      const start: number = this.findInlineDollarStart(text, cursor);
      if (start < 0) {
        result += text.substring(cursor);
        break;
      }
      const end: number = this.findInlineDollarEnd(text, start + 1);
      if (end < 0) {
        result += text.substring(cursor);
        break;
      }
      const expr: string = text.substring(start + 1, end);
      if (expr.indexOf('\n') >= 0 || expr.trim().length === 0) {
        result += text.substring(cursor, end + 1);
      } else {
        result += text.substring(cursor, start) + this.renderMathText(expr);
      }
      cursor = end + 1;
    }
    return result;
  }

  private renderInlineParenMath(text: string): string {
    let result: string = '';
    let cursor: number = 0;
    while (cursor < text.length) {
      const start: number = text.indexOf('\\(', cursor);
      if (start < 0) {
        result += text.substring(cursor);
        break;
      }
      const end: number = text.indexOf('\\)', start + 2);
      if (end < 0) {
        result += text.substring(cursor);
        break;
      }
      const expr: string = text.substring(start + 2, end);
      if (expr.indexOf('\n') >= 0 || expr.trim().length === 0) {
        result += text.substring(cursor, end + 2);
      } else {
        result += text.substring(cursor, start) + this.renderMathText(expr);
      }
      cursor = end + 2;
    }
    return result;
  }

  private renderMathText(text: string): string {
    let result: string = text.trim();
    let previous: string = '';
    while (previous !== result) {
      previous = result;
      result = result.replace(/\\begin\{[^{}]+\}/g, '');
      result = result.replace(/\\end\{[^{}]+\}/g, '');
      result = result.replace(/\\operatorname\{([^{}]+)\}/g, '$1');
      result = result.replace(/\\mathrm\{([^{}]+)\}/g, '$1');
      result = result.replace(/\\text\{([^{}]+)\}/g, '$1');
      result = result.replace(/\\left/g, '');
      result = result.replace(/\\right/g, '');
      result = result.replace(/\\frac\{([^{}]+)\}\{([^{}]+)\}/g, '($1)/($2)');
      result = result.replace(/\\sqrt\{([^{}]+)\}/g, '√($1)');
    }
    result = result.replace(/\\\\/g, '\n');
    result = result.replace(/\s*&\s*/g, '  ');
    result = result.replace(/\\qquad/g, '    ');
    result = result.replace(/\\quad/g, '  ');
    result = result.replace(/\\,/g, ' ');
    result = result.replace(/\\;/g, ' ');
    result = result.replace(/\\:/g, ' ');
    result = result.replace(/\\!/g, '');
    result = result.replace(/\\sum/g, 'Σ');
    result = result.replace(/\\int/g, '∫');
    result = result.replace(/\\prod/g, 'Π');
    result = result.replace(/\\to/g, '→');
    result = result.replace(/\\mapsto/g, '↦');
    result = result.replace(/\\cdots/g, '⋯');
    result = result.replace(/\\ldots/g, '…');
    result = result.replace(/\\times/g, '×');
    result = result.replace(/\\cdot/g, '·');
    result = result.replace(/\\leq?/g, '≤');
    result = result.replace(/\\geq?/g, '≥');
    result = result.replace(/\\neq/g, '≠');
    result = result.replace(/\\approx/g, '≈');
    result = result.replace(/\\rightarrow/g, '→');
    result = result.replace(/\\leftarrow/g, '←');
    result = result.replace(/\\alpha/g, 'α');
    result = result.replace(/\\beta/g, 'β');
    result = result.replace(/\\gamma/g, 'γ');
    result = result.replace(/\\delta/g, 'δ');
    result = result.replace(/\\lambda/g, 'λ');
    result = result.replace(/\\mu/g, 'μ');
    result = result.replace(/\\pi/g, 'π');
    result = result.replace(/\\sigma/g, 'σ');
    result = result.replace(/\\theta/g, 'θ');
    result = result.replace(/\\infty/g, '∞');
    result = result.replace(/\^\{([^{}]+)\}/g, (_match: string, expr: string): string => this.renderMathSuperscript(expr));
    result = result.replace(/\^([A-Za-z0-9+\-=()])/g, (_match: string, expr: string): string => this.renderMathSuperscript(expr));
    result = result.replace(/_\{([^{}]+)\}/g, (_match: string, expr: string): string => this.renderMathSubscript(expr));
    result = result.replace(/_([A-Za-z0-9+\-=()])/g, (_match: string, expr: string): string => this.renderMathSubscript(expr));
    result = result.replace(/[ \t]+\n/g, '\n');
    result = result.replace(/\n[ \t]+/g, '\n');
    return result;
  }

  private renderMathSuperscript(text: string): string {
    const map: Record<string, string> = {
      '0': '⁰',
      '1': '¹',
      '2': '²',
      '3': '³',
      '4': '⁴',
      '5': '⁵',
      '6': '⁶',
      '7': '⁷',
      '8': '⁸',
      '9': '⁹',
      '+': '⁺',
      '-': '⁻',
      '=': '⁼',
      '(': '⁽',
      ')': '⁾',
      'n': 'ⁿ',
      'i': 'ⁱ'
    };
    let result: string = '';
    const source: string = text.trim();
    for (let i = 0; i < source.length; i++) {
      const mapped: string | undefined = map[source[i]];
      if (mapped === undefined) {
        return `^(${source})`;
      }
      result += mapped;
    }
    return result;
  }

  private renderMathSubscript(text: string): string {
    const map: Record<string, string> = {
      '0': '₀',
      '1': '₁',
      '2': '₂',
      '3': '₃',
      '4': '₄',
      '5': '₅',
      '6': '₆',
      '7': '₇',
      '8': '₈',
      '9': '₉',
      '+': '₊',
      '-': '₋',
      '=': '₌',
      '(': '₍',
      ')': '₎',
      'a': 'ₐ',
      'e': 'ₑ',
      'h': 'ₕ',
      'i': 'ᵢ',
      'j': 'ⱼ',
      'k': 'ₖ',
      'l': 'ₗ',
      'm': 'ₘ',
      'n': 'ₙ',
      'o': 'ₒ',
      'p': 'ₚ',
      'r': 'ᵣ',
      's': 'ₛ',
      't': 'ₜ',
      'u': 'ᵤ',
      'v': 'ᵥ',
      'x': 'ₓ'
    };
    let result: string = '';
    const source: string = text.trim();
    for (let i = 0; i < source.length; i++) {
      const mapped: string | undefined = map[source[i]];
      if (mapped === undefined) {
        return `_(${source})`;
      }
      result += mapped;
    }
    return result;
  }

  private mathDisplayLines(text: string): string[] {
    const lines: string[] = this.renderMathText(text)
      .split('\n')
      .map((line: string): string => line.trim())
      .filter((line: string): boolean => line.length > 0);
    if (lines.length > 0) {
      return lines;
    }
    const fallback: string = this.renderMathText(text).trim();
    return fallback.length > 0 ? [fallback] : ['0'];
  }

  private fencedCodeSource(language: string, code: string): string {
    const info: string = language.trim();
    if (info.length > 0) {
      return `\`\`\`${info}\n${code}\n\`\`\``;
    }
    return `\`\`\`\n${code}\n\`\`\``;
  }

  private wrappedMathSource(opening: string, closing: string, body: string): string {
    if (body.indexOf('\n') >= 0) {
      return `${opening}\n${body}\n${closing}`;
    }
    return `${opening}${body}${closing}`;
  }

  private markdownHeadingFontSize(level: number): number {
    if (level <= 1) {
      return this.conversationFontSize(18);
    }
    if (level === 2) {
      return this.conversationFontSize(16);
    }
    if (level === 3) {
      return this.conversationFontSize(14);
    }
    return this.conversationFontSize(13);
  }

  private markdownHeadingLineHeight(level: number): number {
    if (level <= 1) {
      return this.conversationLineHeight(26);
    }
    if (level === 2) {
      return this.conversationLineHeight(24);
    }
    return this.conversationLineHeight(21);
  }

  private markdownListMarker(line: string): string {
    const ordered: RegExpMatchArray | null = line.match(/^(\d+)\.\s+.+$/);
    if (ordered !== null) {
      return `${ordered[1]}.`;
    }
    return '•';
  }

  private markdownListText(line: string): string {
    return line.replace(/^([-*+])\s+/, '').replace(/^\d+\.\s+/, '');
  }

  private messageIcon(itemType?: string): string {
    switch (itemType) {
      case 'reasoning':
        return '🧠';
      case 'command':
        return '⚡';
      case 'tool':
        return '🔧';
      case 'file':
        return '📄';
      case 'search':
        return '🔍';
      case 'plan':
        return '📋';
      case 'image':
        return '🖼️';
      case 'hook':
        return '🪝';
      case 'review':
        return '👁️';
      default:
        return '';
    }
  }

  private eventSoftBackground(role: string): string {
    switch (role) {
      case 'reasoning': return '#FFFBEB';
      case 'command': return '#ECFDF5';
      case 'tool': return '#EFF6FF';
      case 'file': return '#F5F3FF';
      case 'search': return '#F0FDFA';
      case 'plan': return '#FFF7ED';
      case 'image': return '#FDF2F8';
      case 'hook': return '#FEFCE8';
      case 'review': return '#FEF9C3';
      default: return '#F8FAFC';
    }
  }

  private eventBorderColor(role: string): string {
    switch (role) {
      case 'reasoning': return '#FDE68A';
      case 'command': return '#A7F3D0';
      case 'tool': return '#BFDBFE';
      case 'file': return '#DDD6FE';
      case 'search': return '#99F6E4';
      case 'plan': return '#FED7AA';
      case 'image': return '#FBCFE8';
      case 'hook': return '#FDE68A';
      case 'review': return '#FACC15';
      default: return '#E2E8F0';
    }
  }

  private emptyMessageBodyText(item: ChatMessage): string {
    const type: string = item.itemType ?? item.role;
    if (type === 'reasoning') {
      return item.status === 'inProgress' ? '等待可展示的思考内容。' : '本次没有返回可展示的思考内容。';
    }
    if (item.status === 'inProgress') {
      return this.thinkingStatusText();
    }
    return '没有可展示的输出。';
  }

  private collapsedMessagePreview(item: ChatMessage): string {
    const text: string = item.content.replace(/\s+/g, ' ').trim();
    if (this.isReasoningMessage(item)) {
      if (text.length > 0) {
        return text;
      }
      return item.status === 'inProgress' ? this.thinkingStatusPhraseText() : '点击展开查看思考内容。';
    }
    if (text.length > 0) {
      return text;
    }
    return this.emptyMessageBodyText(item);
  }

  private compactionNoticeStatusLabel(status: string): string {
    switch (status) {
      case 'starting':
        return '启动中';
      case 'running':
        return '压缩中';
      case 'completed':
        return '已完成';
      case 'failed':
        return '失败';
      case 'timeout':
        return '超时';
      default:
        return status;
    }
  }

  private compactionNoticeColor(status: string): string {
    switch (status) {
      case 'failed':
      case 'timeout':
        return '#DC2626';
      case 'starting':
      case 'running':
        return '#2563EB';
      case 'completed':
        return '#4338CA';
      default:
        return '#64748B';
    }
  }

  private compactionNoticeSoftBackground(status: string): string {
    switch (status) {
      case 'failed':
      case 'timeout':
        return '#FEF2F2';
      case 'starting':
      case 'running':
        return '#EFF6FF';
      case 'completed':
        return '#EEF2FF';
      default:
        return '#F8FAFC';
    }
  }

  private compactionNoticeBorderColor(status: string): string {
    switch (status) {
      case 'failed':
      case 'timeout':
        return '#FECACA';
      case 'starting':
      case 'running':
        return '#BFDBFE';
      case 'completed':
        return '#C7D2FE';
      default:
        return '#CBD5E1';
    }
  }

  private compactionNoticeSummary(notice: CompactionNotice): string {
    if (notice.status === 'starting' || notice.status === 'running') {
      if (notice.savedTokens > 0) {
        return `已释放 ${this.formatTokenCount(notice.savedTokens)} tokens，正在同步最终结果。`;
      }
      return '正在压缩当前线程上下文。';
    }
    if (notice.errorMessage.trim().length > 0) {
      return notice.errorMessage.trim();
    }
    if (notice.savedTokens > 0) {
      return `释放 ${this.formatTokenCount(notice.savedTokens)} tokens。`;
    }
    return '压缩完成，token 用量暂无明显变化。';
  }

  private compactionSavedText(notice: CompactionNotice): string {
    if (notice.savedTokens > 0) {
      return `${this.formatTokenCount(notice.savedTokens)} tokens`;
    }
    if (notice.status === 'starting' || notice.status === 'running') {
      return '计算中';
    }
    return '0 tokens';
  }

  private statusLabel(status: string): string {
    switch (status) {
      case 'inProgress':
        return '进行中';
      case 'failed':
        return '失败';
      case 'declined':
        return '已拒绝';
      default:
        return status;
    }
  }

  private statusColor(status: string): string {
    switch (status) {
      case 'inProgress':
        return '#0369A1';
      case 'failed':
        return '#DC2626';
      case 'declined':
        return '#D97706';
      default:
        return '#71717A';
    }
  }

  private statusBgColor(status: string): string {
    switch (status) {
      case 'inProgress':
        return '#E0F2FE';
      case 'failed':
        return '#FEE2E2';
      case 'declined':
        return '#FEF3C7';
      default:
        return '#F4F4F5';
    }
  }

  private messageContentColor(itemType?: string): string {
    switch (itemType) {
      case 'reasoning':
        return '#71717A';
      case 'command':
      case 'tool':
        return '#1E40AF';
      default:
        return '#27272A';
    }
  }

  @Builder
  private diffRow(line: CodeDiffLine) {
    Row() {
      Text(line.lineNumber)
        .copyOption(CopyOptions.LocalDevice)
        .width(28)
        .fontSize(10)
        .fontColor('#A1A1AA')
        .fontFamily('monospace')

      Text(line.sign)
        .copyOption(CopyOptions.LocalDevice)
        .width(12)
        .fontSize(11)
        .fontColor(this.diffColor(line.kind))
        .fontFamily('monospace')

      Text(line.content)
        .copyOption(CopyOptions.LocalDevice)
        .layoutWeight(1)
        .fontSize(10)
        .fontColor(this.diffColor(line.kind))
        .fontFamily('monospace')
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 7, bottom: 7 })
    .backgroundColor(this.diffBackground(line.kind))
    .borderRadius(8)
  }

  @Builder
  private diffFileRow(file: CodeDiffFile) {
    Row() {
      Column() {
        Text(file.label)
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(11)
          .fontWeight(this.isDiffFileSelected(file) ? FontWeight.Medium : FontWeight.Regular)
          .fontColor('#18181B')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(file.path)
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(9)
          .fontColor('#A1A1AA')
          .margin({ top: 4 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text(file.diffStat)
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(10)
        .fontColor(this.isDiffFileSelected(file) ? '#2563EB' : '#16A34A')
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    .backgroundColor(this.isDiffFileSelected(file) ? '#F4F4F5' : '#FFFFFF')
    .borderRadius(8)
    .onClick(() => {
      this.selectDiffFile(file.path);
    })
  }


  @Builder
  private approvalCard(approval: CodexApprovalRequest) {
    Column() {
      Row() {
        this.panelTitle(approval.title, 'app-server 正在等待前端响应')

        Blank()
          .layoutWeight(1)

        this.chip('需要确认', '#FEF3C7', '#92400E')
      }
      .width('100%')

      Text(approval.detail)
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(this.conversationFontSize(12))
        .fontColor('#27272A')
        .lineHeight(this.conversationLineHeight(19))
        .margin({ top: 10 })

      Row() {
        Button('允许')
          .height(34)
          .fontSize(12)
          .backgroundColor('#27272A')
          .fontColor('#FFFFFF')
          .borderRadius(8)
          .onClick(() => {
            void this.approvePending();
          })

        Button('拒绝')
          .height(34)
          .margin({ left: 8 })
          .fontSize(12)
          .backgroundColor('#FAFAFA')
          .fontColor('#27272A')
          .borderRadius(8)
          .border({ width: 0.5, color: '#E4E4E7' })
          .onClick(() => {
            void this.declinePending();
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .margin({ top: 12 })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(14)
    .backgroundColor('#FFFBEB')
    .borderRadius(10)
    .margin({ top: 10 })
  }

  @Builder
  private requestUserInputCard(request: CodexRequestUserInput) {
    Column() {
      Row() {
        this.panelTitle(request.title, '继续执行当前计划前，需要你补充信息')

        Blank()
          .layoutWeight(1)

        this.chip('Plan', '#FFF7ED', '#C2410C')
      }
      .width('100%')

      if (request.detail.trim().length > 0) {
        Text(request.detail)
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(this.conversationFontSize(12))
          .fontColor('#27272A')
          .lineHeight(this.conversationLineHeight(19))
          .margin({ top: 10 })
      }

      Column() {
        ForEach(request.questions, (question: CodexRequestUserInputQuestion) => {
          Column() {
            Text(question.header)
              .fontSize(this.conversationFontSize(11))
              .fontWeight(FontWeight.Medium)
              .fontColor('#18181B')

            Text(question.question)
              .fontSize(this.conversationFontSize(11))
              .fontColor('#71717A')
              .lineHeight(this.conversationLineHeight(18))
              .margin({ top: 4 })

            if (question.options.length > 0) {
              Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
                ForEach(question.options, (option: CodexRequestUserInputOption) => {
                  Column() {
                    this.optionChip(
                      new SelectorOption(option.label, option.label),
                      this.requestUserInputAnswer(question.id) === option.label,
                      () => {
                        this.setRequestUserInputAnswer(question.id, option.label);
                      }
                    )
                    if (option.description.trim().length > 0) {
                      Text(option.description)
                        .fontSize(this.conversationFontSize(10))
                        .fontColor('#A1A1AA')
                        .lineHeight(this.conversationLineHeight(16))
                    }
                  }
                  .alignItems(HorizontalAlign.Start)
                  .margin({ right: 8, bottom: 8 })
                }, (option: CodexRequestUserInputOption) => `${question.id}:${option.label}`)
              }
              .width('100%')
              .margin({ top: 8 })
            }

            if (question.isOther || question.options.length === 0) {
              TextInput({
                text: this.requestUserInputAnswer(question.id),
                placeholder: question.isSecret ? '输入不会展示在会话流里的私密内容' : '输入你的回答'
              })
                .width('100%')
                .height(40)
                .margin({ top: 8 })
                .fontSize(this.conversationFontSize(11))
                .backgroundColor('#FAFAFA')
                .borderRadius(8)
                .border({ width: 0.5, color: '#E4E4E7' })
                .padding({ left: 12, right: 12 })
                .onChange((value: string) => {
                  this.setRequestUserInputAnswer(question.id, value);
                })
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .margin({ top: 12 })
        }, (question: CodexRequestUserInputQuestion) => question.id)
      }
      .width('100%')

      Row() {
        Button('继续')
          .height(34)
          .fontSize(12)
          .backgroundColor('#27272A')
          .fontColor('#FFFFFF')
          .borderRadius(8)
          .onClick(() => {
            void this.submitRequestUserInput();
          })

        Button('取消')
          .height(34)
          .margin({ left: 8 })
          .fontSize(12)
          .backgroundColor('#FAFAFA')
          .fontColor('#27272A')
          .borderRadius(8)
          .border({ width: 0.5, color: '#E4E4E7' })
          .onClick(() => {
            void this.declineRequestUserInput();
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .margin({ top: 14 })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(14)
    .backgroundColor('#FFFBEB')
    .borderRadius(10)
    .margin({ top: 10 })
  }

  @Builder
  private leftPanel() {
    Column() {
      // Header
      Text('ArkPilot')
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#18181B')
        .width('100%')
        .onClick(() => { this.showAboutDialog = true; })

      Divider()
        .width('100%')
        .color('#D4D4D8')
        .strokeWidth(0.5)
        .margin({ top: 12, bottom: 4 })

      // Title row with + button
      Row() {
        Text('项目')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor('#18181B')

        Blank()
          .layoutWeight(1)

        Text('+')
          .fontSize(18)
          .fontColor('#71717A')
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .onClick(() => {
            this.openCreateProjectDialog();
          })
      }
      .width('100%')
      .padding({ left: 4, right: 4, top: 8, bottom: 8 })

      // Scrollable project list — takes all remaining space
      List({ scroller: this.leftScrollController }) {
        if (this.projects.length === 0) {
          ListItem() {
            Text('暂无项目，点击右上角 + 创建')
              .fontSize(10)
              .fontColor('#D4D4D8')
              .margin({ top: 4 })
          }
        } else {
          ForEach(this.projects, (proj: ProjectRecord) => {
            ListItem() {
              this.projectGroup(proj)
            }
            .hitTestBehavior(HitTestMode.Transparent)
          }, (proj: ProjectRecord) => `${proj.id}_${proj.expanded.toString()}`)
        }
      }
      .listDirection(Axis.Vertical)
      .scrollBar(BarState.Auto)
      .layoutWeight(1)
      .width('100%')
      .edgeEffect(EdgeEffect.Spring)

      // Settings button — always at bottom
      Button() {
        Row() {
          Text('⚙')
            .fontSize(14)
            .fontColor('#71717A')

          Text('设置')
            .fontSize(12)
            .fontColor('#71717A')
            .margin({ left: 6 })
        }
      }
      .height(38)
      .width('100%')
      .margin({ top: 8 })
      .backgroundColor('#FFFFFF')
      .borderRadius(16)
      .border({ width: 0.5, color: '#E4E4E7' })
      .onClick(() => {
        router.pushUrl({ url: 'pages/SettingsPage' });
      })

    }
    .height('100%')
    .width(this.leftPanelWidth)
    .padding(12)
    .backgroundColor('#FAFAFA')
    .border({ width: 0.5, color: '#E4E4E7' })
    .borderRadius(20)
    .onClick(() => {
      this.showProjectMenuId = '';
      this.showSessionMenuId = '';
    })
  }

  @Builder
  private chatCenterView() {
    Column() {
      Column() {
        Row() {
          Button() {
            Stack() {
              Column()
                .width(16)
                .height(12)
                .borderRadius(3)
                .border({ width: 1.5, color: '#71717A' })
                .backgroundColor(this.showLeftDrawer ? '#F4F4F5' : '#FFFFFF')
              Column()
                .width(1.5)
                .height(8)
                .backgroundColor('#71717A')
                .position({ x: 4, y: 2 })
            }
            .width(16)
            .height(12)
          }
          .type(ButtonType.Normal)
          .width(32)
          .height(28)
          .backgroundColor('#FAFAFA')
          .borderRadius(8)
          .border({ width: 0.5, color: '#E4E4E7' })
          .onClick(() => {
            this.toggleLeftDrawer();
          })

          Blank()
            .width(6)

          Column() {
            Text(this.currentWorkspaceTitle)
              .copyOption(CopyOptions.LocalDevice)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor('#18181B')

            Text(this.currentWorkspaceDescription)
              .copyOption(CopyOptions.LocalDevice)
              .fontSize(10)
              .fontColor('#A1A1AA')
              .margin({ top: 4 })
          }
          .alignItems(HorizontalAlign.Start)

          Blank()
            .layoutWeight(1)

          if (!this.isPhoneBreakpoint()) {
            Row() {
              Text(this.currentCollaborationModeLabel())
                .copyOption(CopyOptions.None)
                .fontSize(10)
                .fontColor('#C2410C')
                .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                .backgroundColor('#FFF7ED')
                .borderRadius(6)
              Blank()
                .width(6)
              Text(this.currentModelLabel())
                .copyOption(CopyOptions.None)
                .fontSize(10)
                .fontColor('#2563EB')
                .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                .backgroundColor('#EFF6FF')
                .borderRadius(6)
              Blank()
                .width(6)
              Text(this.currentEffortLabel())
                .copyOption(CopyOptions.None)
                .fontSize(10)
                .fontColor('#71717A')
                .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                .backgroundColor('#F4F4F5')
                .borderRadius(6)
              Blank()
                .width(6)
            }
            .alignItems(VerticalAlign.Center)
          }

          this.conversationZoomControl()

          Blank()
            .width(6)

          Button() {
            Stack() {
              Column()
                .width(16)
                .height(12)
                .borderRadius(3)
                .border({ width: 1.5, color: '#71717A' })
                .backgroundColor(this.showRightDrawer ? '#F4F4F5' : '#FFFFFF')
              Column()
                .width(1.5)
                .height(8)
                .backgroundColor('#71717A')
                .position({ x: 10.5, y: 2 })
            }
            .width(16)
            .height(12)
          }
          .type(ButtonType.Normal)
          .width(32)
          .height(28)
          .backgroundColor('#FAFAFA')
          .borderRadius(8)
          .border({ width: 0.5, color: '#E4E4E7' })
          .onClick(() => {
            this.toggleRightDrawer();
          })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        if (this.isPhoneBreakpoint()) {
          Row() {
            Text(this.currentCollaborationModeLabel())
              .copyOption(CopyOptions.None)
              .fontSize(10)
              .fontColor('#C2410C')
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .backgroundColor('#FFF7ED')
              .borderRadius(6)
            Blank()
              .width(6)
            Text(this.currentModelLabel())
              .copyOption(CopyOptions.None)
              .fontSize(10)
              .fontColor('#2563EB')
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .backgroundColor('#EFF6FF')
              .borderRadius(6)
            Blank()
              .width(6)
            Text(this.currentEffortLabel())
              .copyOption(CopyOptions.None)
              .fontSize(10)
              .fontColor('#71717A')
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .backgroundColor('#F4F4F5')
              .borderRadius(6)
          }
          .width('100%')
          .margin({ top: 8 })
        }
      }
      .width('100%')

      if (!this.isPhoneBreakpoint() && this.pendingApproval !== null) {
        this.approvalCard(this.pendingApproval!)
      }

      if (!this.isPhoneBreakpoint() && this.pendingRequestUserInput !== null) {
        this.requestUserInputCard(this.pendingRequestUserInput!)
      }

      Column() {
        Scroll(this.messageScroller) {
          Column() {
            ForEach(this.visibleMessages(), (item: ChatMessage) => {
              this.messageLine(item)
            }, (item: ChatMessage) => this.messageRenderKey(item))
            ForEach(this.activeCompactionNotices(), (notice: CompactionNotice) => {
              this.compactionNoticeLine(notice)
            }, (notice: CompactionNotice) => this.compactionNoticeRenderKey(notice))
            if (this.shouldShowTurnActivityLine()) {
              this.turnActivityLine()
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .layoutWeight(1)
        .margin({ top: 10 })
        .scrollBar(this.mouseNearRightEdge ? BarState.On : BarState.Auto)
        .onWillScroll((xOffset: number, yOffset: number, scrollState: ScrollState, scrollSource: ScrollSource) => {
          return this.handleMessageWillScroll(xOffset, yOffset, scrollState, scrollSource);
        })
        .onDidScroll((xOffset: number, yOffset: number, scrollState: ScrollState) => {
          this.handleMessageDidScroll(xOffset, yOffset, scrollState);
        })
        .onScrollEdge((side: Edge) => {
          this.handleMessageScrollEdge(side);
        })
        .onScrollStop(() => {
          this.handleMessageScrollStop();
        })
        .onReachEnd(() => {
          this.resumeMessageAutoFollow();
        })
        .onAxisEvent((event: AxisEvent) => {
          this.handleConversationAxisZoom(event);
        })
      }
      .layoutWeight(1)
      .width('100%')
      .onAreaChange((_old: Area, newArea: Area) => {
        this.chatAreaWidth = newArea.width as number;
      })
      .onTouch((event: TouchEvent) => {
        if (event.touches.length > 0) {
          const touch: TouchObject = event.touches[0];
          const near: boolean = this.chatAreaWidth - touch.windowX < 20;
          if (near !== this.mouseNearRightEdge) {
            this.mouseNearRightEdge = near;
          }
        }
      })
      .onHover((isHover: boolean) => {
        if (!isHover) {
          this.mouseNearRightEdge = false;
        }
      })

      Column() {
          Row() {
            Row() {
              Text('模式')
                .copyOption(CopyOptions.None)
                .fontSize(10)
                .fontColor('#64748B')
              Text(this.currentCollaborationModeLabel())
                .copyOption(CopyOptions.None)
                .fontSize(10)
                .fontWeight(FontWeight.Medium)
                .fontColor('#0F172A')
                .margin({ left: 6 })
              Text('▾')
                .copyOption(CopyOptions.None)
                .fontSize(10)
                .fontColor('#94A3B8')
                .margin({ left: 6 })
            }
            .padding({ left: 12, right: 12, top: 7, bottom: 7 })
            .backgroundColor(this.showCollaborationModeOptions ? '#EEF6FF' : '#FFFFFF')
            .border({ width: 0.5, color: this.showCollaborationModeOptions ? '#93C5FD' : '#E2E8F0' })
            .borderRadius(12)
            .scale({ x: this.showCollaborationModeOptions ? 1.02 : 1, y: this.showCollaborationModeOptions ? 1.02 : 1 })
            .animation({ duration: this.motionFastDuration, curve: Curve.FastOutSlowIn })
            .onClick(() => {
              this.runFastMotion(() => {
                this.showCollaborationModeOptions = !this.showCollaborationModeOptions;
                if (this.showCollaborationModeOptions) {
                  this.showEffortOptions = false;
                }
              });
            })

            Blank()
              .width(8)
            Row() {
              Text('推理')
                .copyOption(CopyOptions.None)
                .fontSize(10)
                .fontColor('#64748B')

              Text(this.currentEffortLabel())
                .copyOption(CopyOptions.None)
                .fontSize(10)
                .fontColor('#0F172A')
                .margin({ left: 6 })

              Text('▾')
                .copyOption(CopyOptions.None)
                .fontSize(10)
                .fontColor('#94A3B8')
                .margin({ left: 6 })
            }
            .padding({ left: 12, right: 12, top: 7, bottom: 7 })
            .backgroundColor(this.showEffortOptions ? '#EEF6FF' : '#FFFFFF')
            .border({ width: 0.5, color: this.showEffortOptions ? '#93C5FD' : '#E2E8F0' })
            .borderRadius(12)
            .scale({ x: this.showEffortOptions ? 1.02 : 1, y: this.showEffortOptions ? 1.02 : 1 })
            .animation({ duration: this.motionFastDuration, curve: Curve.FastOutSlowIn })
            .onClick(() => {
              this.runFastMotion(() => {
                this.showEffortOptions = !this.showEffortOptions;
                if (this.showEffortOptions) {
                  this.showCollaborationModeOptions = false;
                }
              });
            })
          }
          .width('100%')
          .margin({ top: 0 })
          .transition(TransitionEffect.OPACITY.animation({ duration: this.motionFastDuration, curve: Curve.FastOutSlowIn }))

          if (this.showCollaborationModeOptions) {
            Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
              ForEach(this.collaborationModes, (item: CollaborationModeOption) => {
                this.optionChip(
                  new SelectorOption(item.name, item.name),
                  this.selectedCollaborationModeName === item.name,
                  () => {
                    this.chooseCollaborationMode(item);
                  }
                )
              }, (item: CollaborationModeOption) => item.name)
            }
            .width('100%')
            .margin({ top: 8 })
            .transition(TransitionEffect.OPACITY.animation({ duration: this.motionFastDuration, curve: Curve.FastOutSlowIn }))
          }

          if (this.showEffortOptions) {
            Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
              ForEach(this.effortOptions, (item: SelectorOption, index: number) => {
                this.optionChip(item, this.selectedEffortIndex === index, () => {
                  this.runFastMotion(() => {
                    this.selectedEffortIndex = index;
                    this.showEffortOptions = false;
                  });
                })
              })
            }
            .width('100%')
            .margin({ top: 8 })
            .transition(TransitionEffect.OPACITY.animation({ duration: this.motionFastDuration, curve: Curve.FastOutSlowIn }))
          }

        Row() {
          TextArea({ text: this.draft, placeholder: this.dynamicInputPlaceholder() })
            .layoutWeight(1)
            .constraintSize({ minHeight: 42, maxHeight: 136 })
            .minLines(1)
            .maxLines(5, { overflowMode: MaxLinesMode.SCROLL })
            .fontSize(this.conversationFontSize(13))
            .lineHeight(this.conversationLineHeight(20))
            .fontColor('#0F172A')
            .wordBreak(WordBreak.BREAK_WORD)
            .placeholderColor('#94A3B8')
            .backgroundColor('#FFFFFF')
            .borderRadius(14)
            .border({ width: 0.5, color: '#D7DEE8' })
            .padding({ left: 14, right: 14 })
            .enterKeyType(EnterKeyType.Send)
            .onChange((value: string) => {
              this.draft = value;
            })
            .onSubmit((_enterKey: EnterKeyType) => {
              this.sendMessage();
            })
            .onKeyEvent((event: KeyEvent) => {
              if (this.handleConversationKeyEvent(event)) {
                return true;
              }
              if (event.type === KeyType.Down && event.keyCode === 27 && this.isRunning) {
                this.stopTurn();
                return true;
              }
              return false;
            })

          Button() {
            Text(this.isRunning ? '■' : '发送')
              .fontSize(this.isRunning ? 14 : 12)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFFFFF')
              .copyOption(CopyOptions.None)
          }
            .width(66)
            .height(42)
            .margin({ left: 9 })
            .backgroundColor(this.isRunning ? '#27272A' : '#111827')
            .borderRadius(14)
            .shadow({ radius: 12, color: this.isRunning ? '#22DC2626' : '#24111827', offsetY: 4 })
            .opacity(1)
            .onClick(() => {
              if (this.isRunning) {
                this.stopTurn();
              } else {
                this.sendMessage();
              }
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Bottom)
        .margin({ top: 8 })

        Row() {
          Text(this.connectionText)
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(10)
            .fontColor('#64748B')
            .fontWeight(FontWeight.Medium)

          Text(this.workspaceRoot.trim().length > 0 ? this.workspaceRoot : '默认 cwd')
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(10)
            .fontColor('#94A3B8')
            .margin({ left: 10 })
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .margin({ top: 9 })
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 12, bottom: 10 })
      .margin({ top: 10 })
      .backgroundColor('#FAFAFA')
      .border({ width: 0.5, color: '#E4E4E7' })
      .borderRadius(18)
      .shadow({ radius: 18, color: '#120F172A', offsetY: 6 })
    }
    .height('100%')
    .width('100%')
    .focusable(true)
    .onKeyEvent((event: KeyEvent) => {
      return this.handleConversationKeyEvent(event);
    })
  }

  @Builder
  private centerPanel() {
    Column() {
      if (this.workspaces.length === 0) {
        Row() {
          Button() {
          Stack() {
            Column()
              .width(16)
              .height(12)
              .borderRadius(3)
              .border({ width: 1.5, color: '#71717A' })
              .backgroundColor(this.showLeftDrawer ? '#F4F4F5' : '#FFFFFF')
            Column()
              .width(1.5)
              .height(8)
              .backgroundColor('#71717A')
              .position({ x: 4, y: 2 })
          }
          .width(16)
          .height(12)
        }
        .type(ButtonType.Normal)
        .width(32)
        .height(28)
        .backgroundColor('#FAFAFA')
        .borderRadius(8)
        .border({ width: 0.5, color: '#E4E4E7' })
        .onClick(() => {
          this.toggleLeftDrawer();
        })
          Blank()
            .layoutWeight(1)
          Button() {
            Stack() {
              Column()
                .width(16)
                .height(12)
                .borderRadius(3)
                .border({ width: 1.5, color: '#71717A' })
                .backgroundColor(this.showRightDrawer ? '#F4F4F5' : '#FFFFFF')
              Column()
                .width(1.5)
                .height(8)
                .backgroundColor('#71717A')
                .position({ x: 10.5, y: 2 })
            }
            .width(16)
            .height(12)
          }
          .type(ButtonType.Normal)
          .width(32)
          .height(28)
          .backgroundColor('#FAFAFA')
          .borderRadius(8)
          .border({ width: 0.5, color: '#E4E4E7' })
          .onClick(() => {
            this.toggleRightDrawer();
          })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Column() {
          if (this.projects.length === 0) {
            Text('当前暂无项目')
              .copyOption(CopyOptions.LocalDevice)
              .fontSize(16)
              .fontColor('#A1A1AA')
            Text('请新建项目')
              .copyOption(CopyOptions.LocalDevice)
              .fontSize(12)
              .fontColor('#D4D4D8')
              .margin({ top: 8 })
          } else {
            Text('当前暂无会话')
              .copyOption(CopyOptions.LocalDevice)
              .fontSize(16)
              .fontColor('#A1A1AA')
            Text('请在项目中新建会话')
              .copyOption(CopyOptions.LocalDevice)
              .fontSize(12)
              .fontColor('#D4D4D8')
              .margin({ top: 8 })
          }
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        this.chatCenterView()
      }
    }
    .height('100%')
    .layoutWeight(1)
    .padding(12)
    .backgroundColor('#FAFAFA')
    .border({ width: 0.5, color: '#E4E4E7' })
    .borderRadius(12)
  }

  @Builder
  private chatContextPanel() {
    Column() {
      Row() {
        this.panelTitle('统一 diff', 'turn/diff/updated 会实时刷新这里')

        Blank()
          .layoutWeight(1)

        Text(this.diffFiles.length > 0 ? this.currentDiffFileStat() : this.diffStat)
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(10)
          .fontColor('#16A34A')
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor('#F0FDF4')
          .borderRadius(6)
      }
      .width('100%')

      Text(this.changedFiles)
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(11)
        .fontColor('#71717A')
        .margin({ top: 8 })
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (this.diffFiles.length > 0) {
        Text('\u53d8\u66f4\u6587\u4ef6')
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(10)
          .fontColor('#A1A1AA')
          .margin({ top: 10 })

        List({ space: 6 }) {
          ForEach(this.diffFiles, (file: CodeDiffFile) => {
            ListItem() {
              this.diffFileRow(file)
            }
          }, (file: CodeDiffFile) => file.path)
        }
        .width('100%')
        .height(Math.min(150, this.diffFiles.length * 54))
        .margin({ top: 8 })
        .scrollBar(BarState.Off)

        Row() {
          Text('\u5f53\u524d')
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(10)
            .fontColor('#A1A1AA')

          Text(this.currentDiffFilePath())
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(10)
            .fontColor('#27272A')
            .layoutWeight(1)
            .margin({ left: 8 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(this.currentDiffFileStat())
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(10)
            .fontColor('#1D4ED8')
        }
        .width('100%')
        .margin({ top: 10 })
      }

      List({ space: 6 }) {
        ForEach(this.codeLines, (item: CodeDiffLine) => {
          ListItem() {
            this.diffRow(item)
          }
        }, (item: CodeDiffLine) => item.id)
      }
      .layoutWeight(1)
      .width('100%')
      .margin({ top: 10 })
      .scrollBar(BarState.Off)
    }
    .height('100%')
    .width('100%')
  }

  @Builder
  private rightPanelTabButton(label: string, tab: RightPanelTab) {
    Text(label)
      .copyOption(CopyOptions.None)
      .fontSize(11)
      .fontWeight(this.rightPanelTab === tab ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(this.rightPanelTab === tab ? '#FFFFFF' : '#64748B')
      .textAlign(TextAlign.Center)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .backgroundColor(this.rightPanelTab === tab ? '#27272A' : 'transparent')
      .borderRadius(7)
      .onClick(() => {
        this.selectRightPanelTab(tab);
      })
  }

  @Builder
  private rightPanelTabs() {
    Row() {
      this.rightPanelTabButton('Diff', 'diff')
      this.rightPanelTabButton('浏览器', 'browser')
    }
    .padding(2)
    .backgroundColor('#EEF2F7')
    .borderRadius(9)
  }

  @Builder
  private browserPreviewToolbar() {
    Row() {
      Column() {
        Text(this.browserPreviewTitleText())
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor('#18181B')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(this.browserPreviewSubtitleText())
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(9)
          .fontColor('#94A3B8')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 3 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text('↻')
        .copyOption(CopyOptions.None)
        .fontSize(13)
        .fontColor(this.hasBrowserPreview() ? '#475569' : '#CBD5E1')
        .textAlign(TextAlign.Center)
        .width(28)
        .height(28)
        .backgroundColor('#FFFFFF')
        .border({ width: 0.5, color: '#E2E8F0' })
        .borderRadius(7)
        .margin({ left: 8 })
        .onClick(() => {
          this.refreshBrowserPreview();
        })

      Text('↗')
        .copyOption(CopyOptions.None)
        .fontSize(13)
        .fontColor(this.hasBrowserPreview() ? '#475569' : '#CBD5E1')
        .textAlign(TextAlign.Center)
        .width(28)
        .height(28)
        .backgroundColor('#FFFFFF')
        .border({ width: 0.5, color: '#E2E8F0' })
        .borderRadius(7)
        .margin({ left: 6 })
        .onClick(() => {
          if (this.hasBrowserPreview()) {
            this.openHtmlPreviewTarget(this.browserPreviewSrc, this.browserPreviewTitleText());
          }
        })

      Text('×')
        .copyOption(CopyOptions.None)
        .fontSize(15)
        .fontColor('#475569')
        .textAlign(TextAlign.Center)
        .width(28)
        .height(28)
        .backgroundColor('#FFFFFF')
        .border({ width: 0.5, color: '#E2E8F0' })
        .borderRadius(7)
        .margin({ left: 6 })
        .onClick(() => {
          this.closeBrowserPreview();
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: 10, right: 10, top: 9, bottom: 9 })
    .backgroundColor('#F8FAFC')
    .border({ width: 0.5, color: '#E2E8F0' })
    .borderRadius(10)
  }

  @Builder
  private browserPreviewPanel() {
    Column() {
      this.browserPreviewToolbar()

      if (!this.hasBrowserPreview()) {
        Column() {
          Text('点击对话中的 HTML 文件后会在这里打开')
            .copyOption(CopyOptions.None)
            .fontSize(12)
            .fontColor('#64748B')
            .lineHeight(18)
            .textAlign(TextAlign.Center)
            .padding({ left: 18, right: 18 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        Stack() {
          Web({ src: this.browserPreviewSrc, controller: this.browserPreviewController })
            .javaScriptAccess(true)
            .domStorageAccess(true)
            .fileAccess(true)
            .onlineImageAccess(true)
            .imageAccess(true)
            .darkMode(WebDarkMode.Off)
            .forceDarkAccess(false)
            .zoomAccess(true)
            .textZoomRatio(100)
            .onPageBegin(() => {
              this.browserPreviewError = '';
            })
            .onErrorReceive((event) => {
              if (event !== undefined && event.error !== undefined && event.request !== undefined && event.request.isMainFrame()) {
                this.browserPreviewError = event.error.getErrorInfo();
              }
            })
            .width('100%')
            .height('100%')

          if (this.browserPreviewError.length > 0) {
            Column() {
              Text('网页加载失败')
                .copyOption(CopyOptions.None)
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor('#B91C1C')

              Text(this.browserPreviewError)
                .copyOption(CopyOptions.LocalDevice)
                .fontSize(11)
                .fontColor('#7F1D1D')
                .lineHeight(17)
                .margin({ top: 7 })
            }
            .width('88%')
            .padding(12)
            .backgroundColor('#FEF2F2')
            .border({ width: 0.5, color: '#FECACA' })
            .borderRadius(8)
          }
        }
        .width('100%')
        .layoutWeight(1)
        .margin({ top: 8 })
        .backgroundColor('#FFFFFF')
        .border({ width: 0.5, color: '#E2E8F0' })
        .borderRadius(10)
      }
    }
    .height('100%')
    .width('100%')
  }

  @Builder
  private rightPanel() {
    Column() {
      if (this.hasBrowserPreview()) {
        Row() {
          this.rightPanelTabs()
          Blank()
            .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .margin({ bottom: 10 })
      }

      Column() {
        if (this.hasBrowserPreview() && this.rightPanelTab === 'browser') {
          this.browserPreviewPanel()
        } else {
          this.chatContextPanel()
        }
      }
      .layoutWeight(1)
      .width('100%')

      this.tokenUsageCard()
    }
    .height('100%')
    .width(this.rightPanelWidth)
    .padding(12)
    .backgroundColor('#FAFAFA')
    .border({ width: 0.5, color: '#E4E4E7' })
    .borderRadius(20)
  }

  @Builder
  private phoneWorkspace() {
    Column() {
      this.centerPanel()
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private tabletWorkspace() {
    Row() {
      if (this.showLeftDrawer) {
        Row() {
          this.leftPanel()

          Column() {
            Column()
              .width(2)
              .height('60%')
              .backgroundColor('#CBD5E1')
              .borderRadius(1)
          }
          .width(8)
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor('#F4F4F5')
          .borderRadius(4)
          .hitTestBehavior(HitTestMode.Block)
          .gesture(
            PanGesture({ direction: PanDirection.Horizontal })
              .onActionStart(() => {
                this.dragStartLeftW = this.leftPanelWidth;
                this.dragStartRightW = this.rightPanelWidth;
                this.leftHiding = false;
              })
              .onActionUpdate((event: GestureEvent) => {
                if (this.leftHiding) return;
                const newLeft = this.dragStartLeftW + event.offsetX;
                if (newLeft <= this.leftDrawerMinWidth - 20) {
                  this.leftHiding = true;
                  this.runPanelMotion(() => {
                    this.showLeftDrawer = false;
                  });
                  setTimeout(() => {
                    this.leftPanelWidth = 280;
                  }, 350);
                } else if (newLeft >= this.leftDrawerMinWidth) {
                  this.leftPanelWidth = newLeft;
                }
              })
          )
        }
        .height('100%')
        .transition(TransitionEffect.move(TransitionEdge.START).animation({ duration: this.motionPanelDuration, curve: Curve.FastOutSlowIn }))
      }
      this.centerPanel()
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private desktopWorkspace() {
    Row() {
      if (this.showLeftDrawer) {
        Row() {
          this.leftPanel()

          Column() {
            Column()
              .width(2)
              .height('60%')
              .backgroundColor('#CBD5E1')
              .borderRadius(1)
          }
          .width(8)
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor('#F4F4F5')
          .borderRadius(4)
          .hitTestBehavior(HitTestMode.Block)
          .gesture(
            PanGesture({ direction: PanDirection.Horizontal })
              .onActionStart(() => {
                this.dragStartLeftW = this.leftPanelWidth;
                this.dragStartRightW = this.rightPanelWidth;
                this.leftHiding = false;
              })
              .onActionUpdate((event: GestureEvent) => {
                if (this.leftHiding) return;
                const newLeft = this.dragStartLeftW + event.offsetX;
                if (newLeft <= this.leftDrawerMinWidth - 20) {
                  this.leftHiding = true;
                  this.runPanelMotion(() => {
                    this.showLeftDrawer = false;
                  });
                  setTimeout(() => {
                    this.leftPanelWidth = 280;
                  }, 350);
                } else if (newLeft >= this.leftDrawerMinWidth) {
                  this.leftPanelWidth = newLeft;
                }
              })
          )
        }
        .height('100%')
        .transition(TransitionEffect.move(TransitionEdge.START).animation({ duration: this.motionPanelDuration, curve: Curve.FastOutSlowIn }))
      }

      this.centerPanel()

      if (this.showRightDrawer) {
        Row() {
          Column() {
            Column()
              .width(2)
              .height('60%')
              .backgroundColor('#CBD5E1')
              .borderRadius(1)
          }
          .width(8)
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor('#F4F4F5')
          .borderRadius(4)
          .hitTestBehavior(HitTestMode.Block)
          .gesture(
            PanGesture({ direction: PanDirection.Horizontal })
              .onActionStart(() => {
                this.dragStartLeftW = this.leftPanelWidth;
                this.dragStartRightW = this.rightPanelWidth;
                this.rightHiding = false;
              })
              .onActionUpdate((event: GestureEvent) => {
                if (this.rightHiding) return;
                const newRight = this.dragStartRightW - event.offsetX;
                if (newRight <= this.rightDrawerMinWidth - 20) {
                  this.rightHiding = true;
                  this.runPanelMotion(() => {
                    this.showRightDrawer = false;
                  });
                  setTimeout(() => {
                    this.rightPanelWidth = 360;
                  }, 350);
                } else if (newRight >= this.rightDrawerMinWidth) {
                  this.rightPanelWidth = newRight;
                }
              })
          )

          Column() {
            this.rightPanel()
          }
          .height('100%')
        }
        .transition(TransitionEffect.move(TransitionEdge.END).animation({ duration: this.motionPanelDuration, curve: Curve.FastOutSlowIn }))
      }
    }
    .width('100%')
    .height('100%')
  }

  // ── 上下文助手（Rust 侧预计算 blendedTotal / contextRemainingPercent，前端仅展示）──

  private formatTokenCount(count: number): string {
    if (count !== count) return '0';
    if (count <= 0) return '0';
    if (count < 1000) return count.toString();
    if (count < 1000000) return (count / 1000).toFixed(1).replace(/\.0$/, '') + 'k';
    return (count / 1000000).toFixed(1).replace(/\.0$/, '') + 'M';
  }

  private blendedTotal(): number {
    if (this.tokenUsage === null || this.tokenUsage === undefined) return 0;
    const v = this.tokenUsage.total.blendedTotal;
    if (typeof v !== 'number' || v !== v) return 0;
    return v < 0 ? 0 : v;
  }

  private contextWindow(): number {
    if (this.tokenUsage !== null && this.tokenUsage !== undefined) {
      const v = this.tokenUsage.modelContextWindow;
      if (typeof v === 'number' && v === v && v > 0) {
        return v;
      }
    }
    const provider = providerCatalogService.activeProvider();
    if (provider !== null && provider.contextWindow > 0) {
      return provider.contextWindow;
    }
    return 0;
  }

  private contextRemainingPct(): number {
    if (this.tokenUsage === null || this.tokenUsage === undefined) return -1;
    const v = this.tokenUsage.contextRemainingPercent;
    if (typeof v !== 'number' || v !== v) return -1;
    return v;
  }

  private usedPct(): number {
    const rem = this.contextRemainingPct();
    if (rem < 0) return -1;
    return (100 - rem);
  }

  private contextBarWidth(): string {
    const pct = this.usedPct();
    if (pct < 0) return '0%';
    const clamped: number = pct > 100 ? 100 : (pct < 0 ? 0 : pct);
    return clamped.toString() + '%';
  }

  private contextBarColor(): ResourceColor {
    const pct = this.usedPct();
    if (pct < 0) return '#3B82F6';
    if (pct >= 90) return '#EF4444';
    if (pct >= 70) return '#F59E0B';
    return '#3B82F6';
  }

  // total.total_tokens — 和 Rust 计算 remaining% 用的是同一个字段
  private totalTokensUsed(): number {
    if (this.tokenUsage === null || this.tokenUsage === undefined) return 0;
    const v = this.tokenUsage.total.totalTokens;
    if (typeof v !== 'number' || v !== v) return 0;
    return v < 0 ? 0 : v;
  }

  private contextText(): string {
    const used = this.totalTokensUsed();
    const win = this.contextWindow();
    const rem = this.contextRemainingPct();
    let suffix: string = '';
    if (win > 0 && rem >= 0) {
      suffix = rem <= 0 ? ' (压缩中...)' : ' (' + rem.toString() + '% 剩余)';
    }
    if (win <= 0) return this.formatTokenCount(used) + suffix;
    return this.formatTokenCount(used) + ' / ' + this.formatTokenCount(win) + suffix;
  }

  private safePct(part: number, whole: number): string {
    if (whole <= 0 || part <= 0 || whole !== whole || part !== part) return '0%';
    const v = (part / whole) * 100;
    if (v !== v || v < 0) return '0%';
    return (v > 100 ? 100 : v).toFixed(0) + '%';
  }

  private tokenMiniText(): string {
    const total = this.totalTokensUsed();
    const win = this.contextWindow();
    const pct = this.contextRemainingPct();
    let suffix: string = '';
    if (win > 0 && pct >= 0) {
      suffix = pct <= 0 ? ' · 压缩中...' : ' · 剩余 ' + pct.toString() + '%';
    }
    return '总 ' + this.formatTokenCount(total) + suffix;
  }

  private readonly TREND_CHART_H: number = 52;

  private trendChartWidth(): number {
    return this.rightPanelWidth - 48;
  }

  private tokenTrendLinePath(data: DailyTokenSnapshot[], maxVal: number, w: number, h: number): string {
    if (data.length === 0 || maxVal <= 0) return '';
    const points: string[] = [];
    const padY = 4;
    const stepX = w / Math.max(data.length - 1, 1);
    for (let i = 0; i < data.length; i++) {
      const x = i * stepX;
      const y = h - (data[i].totalTokens / maxVal) * (h - padY * 2) - padY;
      if (i === 0) {
        points.push(`M ${x} ${y}`);
      } else {
        points.push(`L ${x} ${y}`);
      }
    }
    return points.join(' ');
  }

  private getTrendData(): DailyTokenSnapshot[] {
    if (this.tokenAggregate === null) return [];
    const days = this.tokenTrendRange === 1 ? 7 : 30;
    const len = this.tokenAggregate.daily.length;
    const start = Math.max(len - days, 0);
    return this.tokenAggregate.daily.slice(start, len);
  }

  private getTrendTokenPath(): string {
    const data = this.getTrendData();
    const maxVal = data.reduce((max: number, d: DailyTokenSnapshot) => Math.max(max, d.totalTokens), 0);
    return this.tokenTrendLinePath(data, maxVal, this.trendChartWidth(), this.TREND_CHART_H);
  }

  private getTrendAreaPath(): string {
    const data = this.getTrendData();
    const maxVal = data.reduce((max: number, d: DailyTokenSnapshot) => Math.max(max, d.totalTokens), 0);
    if (data.length === 0 || maxVal <= 0) return '';
    const w = this.trendChartWidth();
    const h = this.TREND_CHART_H;
    const padY = 4;
    const stepX = w / Math.max(data.length - 1, 1);
    let path = `M 0 ${h}`;
    for (let i = 0; i < data.length; i++) {
      const x = i * stepX;
      const y = h - (data[i].totalTokens / maxVal) * (h - padY * 2) - padY;
      path += ` L ${x} ${y}`;
    }
    path += ` L ${w} ${h} Z`;
    return path;
  }

  private getTrendSumTokens(): number {
    return this.getTrendData().reduce((s: number, d: DailyTokenSnapshot): number => s + d.totalTokens, 0);
  }

  private getTrendSumRequests(): number {
    return this.getTrendData().reduce((s: number, d: DailyTokenSnapshot): number => s + d.requestCount, 0);
  }

  private getTrendFirstDate(): string {
    const data = this.getTrendData();
    return data.length > 0 ? data[0].date.substring(5) : '';
  }

  private getTrendLastDate(): string {
    const data = this.getTrendData();
    return data.length > 0 ? data[data.length - 1].date.substring(5) : '';
  }

  @Builder trendLegendDot(color: string) {
    Circle({ width: 6, height: 6 }).fill(color)
  }

  @Builder tokenUsageCard() {
    Column() {
      // 箭头指示器（展开时显示，可拖拽调整高度）
      if (this.tokenCardExpanded) {
        Row() {
          Text('▼')
            .fontSize(10)
            .fontColor('#A1A1AA')
        }
        .width('100%')
        .height(16)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .backgroundColor('#FFFFFF')
        .borderRadius({ topLeft: 10, topRight: 10 })
        .border({ width: 0.5, color: '#E4E4E7' })
        .margin({ bottom: -1 })
        .hitTestBehavior(HitTestMode.Block)
        .gesture(
          TapGesture()
            .onAction(() => {
              this.runMotion(() => {
                this.tokenCardExpanded = false;
              });
            })
        )
        .gesture(
          PanGesture({ direction: PanDirection.Vertical })
            .onActionStart(() => {
              this.tokenCardDragStartY = 0;
              this.tokenCardDragStartH = this.tokenCardHeight;
            })
          .onActionUpdate((event: GestureEvent) => {
            const newH = this.tokenCardDragStartH - event.offsetY;
            if (newH >= 120 && newH <= 600) {
              this.tokenCardHeight = newH;
            }
          })
      )
      }

      // 卡片内容
      Column() {
        if (!this.tokenCardExpanded) {
          // 收起状态：只显示摘要
          Row() {
            Text(this.tokenMiniText())
              .fontSize(11)
              .fontColor('#71717A')
              .maxLines(1)
            Blank()
            Text('▲')
              .fontSize(10)
              .fontColor('#A1A1AA')
          }
          .width('100%')
          .padding({ top: 8, bottom: 8, left: 12, right: 12 })
          .borderRadius({ topLeft: 10, topRight: 10 })
          .backgroundColor('#FAFAFA')
          .border({ width: 0.5, color: '#E4E4E7' })
          .hitTestBehavior(HitTestMode.Block)
          .gesture(
            TapGesture()
              .onAction(() => {
                this.runMotion(() => {
                  this.tokenCardExpanded = true;
                });
              })
          )
        } else {
          // 展开状态：固定高度 + 滚动
          Scroll() {
            Column() {
              // 上下文窗口占用（置顶，最重要）
              Column() {
                Row() {
                  Text('上下文窗口')
                    .fontSize(12)
                    .fontColor('#18181B')
                    .fontWeight(FontWeight.Medium)
                  Blank()
                  Text(this.contextText())
                    .fontSize(12)
                    .fontColor('#18181B')
                    .fontWeight(FontWeight.Medium)
                  if (this.contextRemainingPct() <= 70 && this.contextRemainingPct() >= 0) {
                    Text(this.compacting ? '压缩中...' : (this.compactError.length > 0 ? this.compactError : '压缩'))
                      .fontSize(10)
                      .fontColor(this.compactError.length > 0 ? '#EF4444' : '#27272A')
                      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                      .border({ width: 1, color: this.compactError.length > 0 ? '#EF4444' : '#E4E4E7' })
                      .borderRadius(6)
                      .backgroundColor(this.compactError.length > 0 ? '#FEF2F2' : '#FAFAFA')
                      .margin({ left: 6 })
                      .onClick(() => {
                        this.retryCurrentCompaction(this.backendActiveThreadId);
                      })
                  }
                }
                .width('100%')

                if (this.contextRemainingPct() >= 0) {
                  Progress({ value: this.contextRemainingPct(), total: 100, type: ProgressType.Linear })
                    .width('100%')
                    .height(8)
                    .style({ strokeWidth: 8, enableSmoothEffect: true })
                    .color(this.contextBarColor())
                    .margin({ top: 6 })
                }
              }
              .width('100%')
              .padding({ top: 8, bottom: 10 })

              // 标题行
              Row() {
                Text('Token 用量')
                  .fontSize(13)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#18181B')
                Blank()
                Text(this.providerName)
                  .fontSize(11)
                  .fontColor('#A1A1AA')
              }
              .width('100%')
              .padding({ bottom: 2 })

          // 标签页 — 分段式选择器
          Row() {
            Text('当前轮')
              .fontSize(12)
              .fontColor(this.tokenTab === 0 ? '#FFFFFF' : '#71717A')
              .fontWeight(this.tokenTab === 0 ? FontWeight.Medium : FontWeight.Normal)
              .padding({ left: 14, right: 14, top: 5, bottom: 5 })
              .borderRadius(6)
              .backgroundColor(this.tokenTab === 0 ? '#27272A' : 'transparent')
              .onClick(() => { this.tokenTab = 0; })
            Text('趋势')
              .fontSize(12)
              .fontColor(this.tokenTab === 1 ? '#FFFFFF' : '#71717A')
              .fontWeight(this.tokenTab === 1 ? FontWeight.Medium : FontWeight.Normal)
              .padding({ left: 14, right: 14, top: 5, bottom: 5 })
              .borderRadius(6)
              .backgroundColor(this.tokenTab === 1 ? '#27272A' : 'transparent')
              .onClick(() => { this.tokenTab = 1; })
          }
          .margin({ top: 10 })
          .padding(2)
          .borderRadius(8)
          .backgroundColor('#F4F4F5')
          .width('100%')

          // 当前轮 tab
          if (this.tokenTab === 0) {
            Column() {
              if (this.tokenUsage === null) {
                Text('等待数据...')
                  .fontSize(11)
                  .fontColor('#A1A1AA')
                  .margin({ top: 12 })
              } else {
                // 细分数字
                Column() {
                  Row() {
                    Circle({ width: 6, height: 6 }).fill('#3B82F6')
                    Text('输入').fontSize(11).fontColor('#A1A1AA').margin({ left: 6 })
                    Blank()
                    Text(this.formatTokenCount(this.tokenUsage!.last.inputTokens)).fontSize(11).fontColor('#18181B').fontWeight(FontWeight.Medium)
                  }.width('100%').padding({ top: 6 })
                  Row() {
                    Circle({ width: 6, height: 6 }).fill('#A1A1AA')
                    Text('缓存').fontSize(11).fontColor('#A1A1AA').margin({ left: 6 })
                    Blank()
                    Text(this.formatTokenCount(this.tokenUsage!.last.cachedInputTokens)).fontSize(11).fontColor('#18181B').fontWeight(FontWeight.Medium)
                  }.width('100%').padding({ top: 6 })
                  Row() {
                    Circle({ width: 6, height: 6 }).fill('#22C55E')
                    Text('输出').fontSize(11).fontColor('#A1A1AA').margin({ left: 6 })
                    Blank()
                    Text(this.formatTokenCount(this.tokenUsage!.last.outputTokens)).fontSize(11).fontColor('#18181B').fontWeight(FontWeight.Medium)
                  }.width('100%').padding({ top: 6 })
                  Row() {
                    Circle({ width: 6, height: 6 }).fill('#A855F7')
                    Text('推理').fontSize(11).fontColor('#A1A1AA').margin({ left: 6 })
                    Blank()
                    Text(this.formatTokenCount(this.tokenUsage!.last.reasoningOutputTokens)).fontSize(11).fontColor('#18181B').fontWeight(FontWeight.Medium)
                  }.width('100%').padding({ top: 6 })
                }
                .margin({ top: 4 })
              }
            }
            .margin({ top: 8 })
            .width('100%')
          }

          // 趋势 tab
          if (this.tokenTab === 1) {
            Column() {
              if (this.tokenAggregate === null) {
                Text('加载中...')
                  .fontSize(11)
                  .fontColor('#A1A1AA')
                  .margin({ top: 12 })
              } else {
                // 范围切换按钮
                Row() {
                  Text('今日')
                    .fontSize(11)
                    .fontColor(this.tokenTrendRange === 0 ? '#FFFFFF' : '#71717A')
                    .fontWeight(this.tokenTrendRange === 0 ? FontWeight.Medium : FontWeight.Normal)
                    .padding({ left: 12, right: 12, top: 4, bottom: 4 })
                    .borderRadius(6)
                    .backgroundColor(this.tokenTrendRange === 0 ? '#27272A' : 'transparent')
                    .onClick(() => { this.tokenTrendRange = 0; })
                  Text('近7天')
                    .fontSize(11)
                    .fontColor(this.tokenTrendRange === 1 ? '#FFFFFF' : '#71717A')
                    .fontWeight(this.tokenTrendRange === 1 ? FontWeight.Medium : FontWeight.Normal)
                    .padding({ left: 12, right: 12, top: 4, bottom: 4 })
                    .borderRadius(6)
                    .backgroundColor(this.tokenTrendRange === 1 ? '#27272A' : 'transparent')
                    .onClick(() => { this.tokenTrendRange = 1; })
                  Text('近30天')
                    .fontSize(11)
                    .fontColor(this.tokenTrendRange === 2 ? '#FFFFFF' : '#71717A')
                    .fontWeight(this.tokenTrendRange === 2 ? FontWeight.Medium : FontWeight.Normal)
                    .padding({ left: 12, right: 12, top: 4, bottom: 4 })
                    .borderRadius(6)
                    .backgroundColor(this.tokenTrendRange === 2 ? '#27272A' : 'transparent')
                    .onClick(() => { this.tokenTrendRange = 2; })
                }
                .margin({ top: 8 })
                .padding(2)
                .borderRadius(7)
                .backgroundColor('#F4F4F5')
                .width('100%')

                // 今日视图：水平堆叠条 + 卡片
                if (this.tokenTrendRange === 0) {
                  Column() {
                    // 总量摘要
                    Row() {
                      Text(this.formatTokenCount(this.tokenAggregate!.today.totalTokens))
                        .fontSize(20)
                        .fontWeight(FontWeight.Medium)
                        .fontColor('#18181B')
                      Text(' tokens')
                        .fontSize(11)
                        .fontColor('#A1A1AA')
                        .margin({ left: 2 })
                      Blank()
                      Text(`${this.tokenAggregate!.today.requestCount} 次请求`)
                        .fontSize(11)
                        .fontColor('#A1A1AA')
                    }
                    .width('100%')
                    .margin({ top: 10 })
                    .alignItems(VerticalAlign.Bottom)

                    // 水平堆叠条
                    if (this.tokenAggregate!.today.totalTokens > 0) {
                      Row() {
                        if (this.tokenAggregate!.today.inputTokens > 0) {
                          Row()
                            .layoutWeight(this.tokenAggregate!.today.inputTokens)
                            .height(8)
                            .backgroundColor('#3B82F6')
                        }
                        if (this.tokenAggregate!.today.cachedInputTokens > 0) {
                          Row()
                            .layoutWeight(this.tokenAggregate!.today.cachedInputTokens)
                            .height(8)
                            .backgroundColor('#A1A1AA')
                        }
                        if (this.tokenAggregate!.today.outputTokens > 0) {
                          Row()
                            .layoutWeight(this.tokenAggregate!.today.outputTokens)
                            .height(8)
                            .backgroundColor('#22C55E')
                        }
                        if (this.tokenAggregate!.today.reasoningOutputTokens > 0) {
                          Row()
                            .layoutWeight(this.tokenAggregate!.today.reasoningOutputTokens)
                            .height(8)
                            .backgroundColor('#A855F7')
                        }
                      }
                      .width('100%')
                      .height(8)
                      .borderRadius(4)
                      .clip(true)
                      .margin({ top: 10 })
                    }

                    // 分类明细卡片
                    Column() {
                      Row() {
                        this.trendLegendDot('#3B82F6')
                        Text('输入').fontSize(11).fontColor('#71717A').margin({ left: 6 })
                        Blank()
                        Text(this.formatTokenCount(this.tokenAggregate!.today.inputTokens)).fontSize(11).fontColor('#18181B').fontWeight(FontWeight.Medium)
                      }.width('100%').padding({ top: 8, bottom: 8 })

                      Row().width('100%').height(0.5).backgroundColor('#F4F4F5')

                      Row() {
                        this.trendLegendDot('#A1A1AA')
                        Text('缓存').fontSize(11).fontColor('#71717A').margin({ left: 6 })
                        Blank()
                        Text(this.formatTokenCount(this.tokenAggregate!.today.cachedInputTokens)).fontSize(11).fontColor('#18181B').fontWeight(FontWeight.Medium)
                      }.width('100%').padding({ top: 8, bottom: 8 })

                      Row().width('100%').height(0.5).backgroundColor('#F4F4F5')

                      Row() {
                        this.trendLegendDot('#22C55E')
                        Text('输出').fontSize(11).fontColor('#71717A').margin({ left: 6 })
                        Blank()
                        Text(this.formatTokenCount(this.tokenAggregate!.today.outputTokens)).fontSize(11).fontColor('#18181B').fontWeight(FontWeight.Medium)
                      }.width('100%').padding({ top: 8, bottom: 8 })

                      Row().width('100%').height(0.5).backgroundColor('#F4F4F5')

                      Row() {
                        this.trendLegendDot('#A855F7')
                        Text('推理').fontSize(11).fontColor('#71717A').margin({ left: 6 })
                        Blank()
                        Text(this.formatTokenCount(this.tokenAggregate!.today.reasoningOutputTokens)).fontSize(11).fontColor('#18181B').fontWeight(FontWeight.Medium)
                      }.width('100%').padding({ top: 8, bottom: 8 })
                    }
                    .width('100%')
                    .margin({ top: 12 })
                    .padding(10)
                    .backgroundColor('#FAFAFA')
                    .borderRadius(8)
                  }
                }

                // 近7天/近30天视图：面积图
                if (this.tokenTrendRange === 1 || this.tokenTrendRange === 2) {
                  Column() {
                    // 总量摘要
                    Row() {
                      Text(this.formatTokenCount(this.getTrendSumTokens()))
                        .fontSize(20)
                        .fontWeight(FontWeight.Medium)
                        .fontColor('#18181B')
                      Text(' tokens')
                        .fontSize(11)
                        .fontColor('#A1A1AA')
                        .margin({ left: 2 })
                      Blank()
                      Text(`${this.getTrendSumRequests()} 次请求`)
                        .fontSize(11)
                        .fontColor('#A1A1AA')
                    }
                    .width('100%')
                    .margin({ top: 10 })
                    .alignItems(VerticalAlign.Bottom)

                    // 面积图
                    Stack({ alignContent: Alignment.BottomStart }) {
                      // 网格线
                      Column() {
                        Row().width('100%').height(0.5).backgroundColor('#F4F4F5')
                        Row().width('100%').height(0.5).backgroundColor('#F4F4F5').margin({ top: 24 })
                        Row().width('100%').height(0.5).backgroundColor('#F4F4F5').margin({ top: 24 })
                      }
                      .width('100%')
                      .height(52)
                      .padding({ left: 2, right: 2 })

                      // 面积填充
                      Shape() {
                        Path()
                          .commands(this.getTrendAreaPath())
                          .fill('#1A3B82F6')
                          .stroke('none')
                      }
                      .width('100%')
                      .height(52)

                      // 折线
                      Shape() {
                        Path()
                          .commands(this.getTrendTokenPath())
                          .stroke('#3B82F6')
                          .strokeWidth(2)
                          .fill('none')
                      }
                      .width('100%')
                      .height(52)
                    }
                    .width('100%')
                    .height(52)
                    .margin({ top: 12 })

                    // X轴日期
                    Row() {
                      Text(this.getTrendFirstDate()).fontSize(9).fontColor('#A1A1AA')
                      Blank()
                      Text(this.getTrendLastDate()).fontSize(9).fontColor('#A1A1AA')
                    }
                    .width('100%')
                    .margin({ top: 4 })

                    // 每日明细列表
                    Column() {
                      ForEach(this.getTrendData().slice(-7).reverse(), (item: DailyTokenSnapshot) => {
                        Row() {
                          Text(item.date.substring(5))
                            .fontSize(11)
                            .fontColor('#71717A')
                            .width(40)
                          Blank()
                          Text(this.formatTokenCount(item.totalTokens))
                            .fontSize(11)
                            .fontColor('#18181B')
                            .fontWeight(FontWeight.Medium)
                          Text(`  ${item.requestCount}次`)
                            .fontSize(10)
                            .fontColor('#A1A1AA')
                        }
                        .width('100%')
                        .padding({ top: 7, bottom: 7 })
                      })
                    }
                    .width('100%')
                    .margin({ top: 12 })
                    .padding(10)
                    .backgroundColor('#FAFAFA')
                    .borderRadius(8)
                  }
                }
              }
            }
            .margin({ top: 8 })
            .width('100%')
          }
            }
          }
          .scrollable(ScrollDirection.Vertical)
          .height(this.tokenCardHeight)
          .align(Alignment.TopStart)
        }
      }
      .padding(this.tokenCardExpanded ? 12 : 0)
      .width('100%')
      .backgroundColor('#FFFFFF')
      .borderRadius({ bottomLeft: 10, bottomRight: 10 })
      .border({ width: 0.5, color: '#E4E4E7' })
      .shadow(this.tokenCardExpanded ? { radius: 12, color: '#0A000000', offsetY: 4 } : undefined)
      .animation({ duration: this.motionNormalDuration, curve: Curve.FastOutSlowIn })
    }
    .width('100%')
    .alignItems(HorizontalAlign.End)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {}
        .width('100%')
        .height('100%')
        .backgroundColor('#EEF2F7')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      Stack({ alignContent: Alignment.BottomEnd }) {
        Column() {
          if (this.currentBreakpoint === 'lg') {
            this.desktopWorkspace()
          } else if (this.currentBreakpoint === 'md') {
            this.tabletWorkspace()
          } else {
            this.phoneWorkspace()
          }
        }
        .width('100%')
        .height('100%')
        .padding(10)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        if (this.isPhoneBreakpoint() && this.showLeftDrawer) {
          Stack({ alignContent: Alignment.TopStart }) {
            Row() {
              this.leftPanel()
            }
            .height('100%')
          }
          .width('100%')
          .height('100%')
          .padding({ top: 12, bottom: 12, left: 12, right: 48 })
          .backgroundColor('#66000000')
          .transition(TransitionEffect.OPACITY.animation({ duration: this.motionPanelDuration, curve: Curve.FastOutSlowIn }))
          .onClick(() => {
            this.showLeftDrawer = false;
          })
        }

        if (this.currentBreakpoint !== 'lg' && this.showRightDrawer) {
          Stack({ alignContent: Alignment.BottomEnd }) {
            Column() {
              this.rightPanel()
            }
            .width(this.rightPanelWidth)
            .height(this.isPhoneBreakpoint() ? '88%' : (this.currentBreakpoint === 'md' ? '78%' : '88%'))
            .padding(4)
          }
          .width('100%')
          .height('100%')
          .padding(this.isPhoneBreakpoint()
            ? { left: 28, right: 8, top: 16, bottom: 8 }
            : { left: 24, right: 12, top: 24, bottom: 12 })
          .backgroundColor('#66000000')
          .transition(TransitionEffect.OPACITY.animation({ duration: this.motionPanelDuration, curve: Curve.FastOutSlowIn }))
          .onClick(() => {
            this.showRightDrawer = false;
          })
        }

        if (this.isPhoneBreakpoint() && (this.pendingApproval !== null || this.pendingRequestUserInput !== null)) {
          Column() {
            Blank()
              .layoutWeight(1)
            Column() {
              if (this.pendingApproval !== null) {
                this.approvalCard(this.pendingApproval!)
              }
              if (this.pendingRequestUserInput !== null) {
                this.requestUserInputCard(this.pendingRequestUserInput!)
              }
            }
            .width('100%')
            .padding({ left: 12, right: 12, bottom: 12 })
          }
          .width('100%')
          .height('100%')
          .backgroundColor('#4D000000')
          .transition(TransitionEffect.OPACITY.animation({ duration: this.motionNormalDuration, curve: Curve.FastOutSlowIn }))
          .onClick(() => {
            // tap backdrop to dismiss — do nothing, user must approve/deny
          })
        }

        if (this.showAboutDialog) {
          Stack() {
            Column()
              .width('100%')
              .height('100%')
              .backgroundColor('#0F172A')
              .opacity(0.4)
              .onClick(() => { this.showAboutDialog = false; })

            Column() {
              Row() {
                Text('关于我们')
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#18181B')

                Blank()
                  .layoutWeight(1)

                Text('✕')
                  .fontSize(16)
                  .fontColor('#94A3B8')
                  .onClick(() => { this.showAboutDialog = false; })
              }
              .width('100%')

              Image($r('app.media.splash_bg'))
                .width('100%')
                .margin({ top: 12 })
                .borderRadius(12)
                .objectFit(ImageFit.Contain)
            }
            .width(this.isPhoneBreakpoint() ? '98%' : '1280px')
            .constraintSize({ minHeight: this.isPhoneBreakpoint() ? '80vh' : '80vh' })
            .padding(20)
            .backgroundColor('#FFFFFF')
            .borderRadius(16)
            .shadow({ radius: 24, color: '#33000000', offsetX: 0, offsetY: 8 })
          }
          .width('100%')
          .height('100%')
          .transition(TransitionEffect.OPACITY.animation({ duration: 250, curve: Curve.FastOutSlowIn }))
        }
      }
      .width('100%')
      .height('100%')

      if (this.showProjectMenuId.length > 0 || this.showSessionMenuId.length > 0) {
        this.topLevelFloatingMenus()
      }
    }
    .width('100%')
    .height('100%')
    .onClick(() => {
      this.showProjectMenuId = '';
      this.showSessionMenuId = '';
    })
  }
}

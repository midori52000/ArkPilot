import router from '@ohos.router';
import { ProviderPreset, BUILTIN_PROVIDER_PRESETS } from '../apim/ApiTypes';
import { ApiWireFormat, ProviderCategory, ProviderRecord } from '../backend/ConsoleModels';
import { configManagerFacade } from '../backend/CodexBackend';

type ToastTone = 'info' | 'success' | 'warning' | 'error';
type AddProviderMode = 'claude' | 'unified';

class UiToastItem {
  id: number;
  tone: ToastTone;
  message: string;

  constructor(id: number, tone: ToastTone, message: string) {
    this.id = id;
    this.tone = tone;
    this.message = message;
  }
}

@Entry
@Component
struct AddProviderPage {
  @State private sparkSeed: number = 0;
  @State private toasts: UiToastItem[] = [];
  @State private toastIdSeed: number = 1;
  @State private activeMode: AddProviderMode = 'claude';
  @State private selectedPresetId: string = 'anthropic-official';
  @State private providerName: string = 'Claude Official';
  @State private providerNote: string = '';
  @State private websiteUrl: string = 'https://console.anthropic.com';
  @State private apiKey: string = '';
  @State private baseUrl: string = 'https://api.anthropic.com/v1';
  @State private wireApi: ApiWireFormat = 'anthropic';
  @State private requestFullUrl: boolean = false;
  @State private advancedExpanded: boolean = false;
  @State private writeGeneralConfig: boolean = true;
  @State private configJson: string = '{\n  "env": {},\n  "autoUpdatesChannel": "latest"\n}';
  @State private aliasEnabled: boolean = false;
  @State private teammatesEnabled: boolean = false;
  @State private toolSearchEnabled: boolean = true;
  @State private intenseThinkingEnabled: boolean = false;
  @State private autoUpdateDisabled: boolean = false;
  @State private modelTestSingleConfig: boolean = false;
  @State private billingSingleConfig: boolean = false;

  aboutToAppear(): void {
    this.applyPreset(this.selectedPresetId, false);
  }

  private triggerFeedback(message: string, tone: ToastTone = 'info'): void {
    this.sparkSeed += 1;
    this.showToast(message, tone);
  }

  private showToast(message: string, tone: ToastTone = 'info', duration: number = 1800): void {
    const toastId = this.toastIdSeed;
    this.toastIdSeed += 1;
    this.toasts = [...this.toasts, new UiToastItem(toastId, tone, message)];
    setTimeout(() => {
      this.dismissToast(toastId);
    }, duration);
  }

  private dismissToast(toastId: number): void {
    this.toasts = this.toasts.filter((toast: UiToastItem) => toast.id !== toastId);
  }

  private notePending(action: string): void {
    this.triggerFeedback(`${action}暂未接入后端，当前仅前端模拟。`, 'warning');
  }

  private toneBackground(tone: ToastTone): string {
    switch (tone) {
      case 'success':
        return '#DCFCE7';
      case 'warning':
        return '#FEF3C7';
      case 'error':
        return '#FEE2E2';
      default:
        return '#E0F2FE';
    }
  }

  private toneColor(tone: ToastTone): string {
    switch (tone) {
      case 'success':
        return '#166534';
      case 'warning':
        return '#92400E';
      case 'error':
        return '#B91C1C';
      default:
        return '#0C4A6E';
    }
  }

  private categoryLabel(category: ProviderCategory): string {
    switch (category) {
      case 'official':
        return '官方';
      case 'third_party':
        return '第三方';
      case 'cloud_provider':
        return '云服务商';
      case 'aggregator':
        return '聚合';
      case 'custom':
        return '自定义';
      default:
        return category;
    }
  }

  private modeLabel(mode: AddProviderMode): string {
    return mode === 'claude' ? 'Claude 供应商' : '统一供应商';
  }

  private presetAccent(presetId: string): string {
    const preset = this.findPreset(presetId);
    if (preset !== null && preset.iconColor.trim().length > 0) {
      return preset.iconColor;
    }
    return '#8B5CF6';
  }

  private presetIconText(): string {
    if (this.selectedPresetId === 'custom') {
      return 'P';
    }
    const preset = this.findPreset(this.selectedPresetId);
    if (preset === null) {
      return 'P';
    }
    const name = preset.name.trim();
    if (name.length > 0) {
      return name.substring(0, 1).toUpperCase();
    }
    return 'P';
  }

  private selectedPreset(): ProviderPreset | null {
    return this.findPreset(this.selectedPresetId);
  }

  private selectedPresetCategoryLabel(): string {
    const preset = this.selectedPreset();
    if (preset === null) {
      return '';
    }
    return this.categoryLabel(preset.category);
  }

  private selectedPresetWireApiLabel(): string {
    const preset = this.selectedPreset();
    if (preset === null) {
      return '';
    }
    return preset.wireApi;
  }

  private findPreset(presetId: string): ProviderPreset | null {
    for (let index = 0; index < BUILTIN_PROVIDER_PRESETS.length; index += 1) {
      if (BUILTIN_PROVIDER_PRESETS[index].id === presetId) {
        return BUILTIN_PROVIDER_PRESETS[index];
      }
    }
    return null;
  }

  private visiblePresets(): ProviderPreset[] {
    const result: ProviderPreset[] = [];
    for (let index = 0; index < BUILTIN_PROVIDER_PRESETS.length; index += 1) {
      const preset = BUILTIN_PROVIDER_PRESETS[index];
      if (this.activeMode === 'claude') {
        if (preset.wireApi === 'anthropic' || preset.name.indexOf('Claude') >= 0 || preset.defaultModel.indexOf('claude') >= 0) {
          result.push(preset);
        }
      } else {
        result.push(preset);
      }
    }
    return result;
  }

  private applyPreset(presetId: string, withToast: boolean = true): void {
    this.selectedPresetId = presetId;
    if (presetId === 'custom') {
      this.providerName = '';
      this.providerNote = '';
      this.websiteUrl = '';
      this.apiKey = '';
      this.baseUrl = '';
      this.wireApi = this.activeMode === 'claude' ? 'anthropic' : 'responses';
      if (withToast) {
        this.triggerFeedback('已切换到自定义配置。', 'info');
      }
      return;
    }

    const preset = this.findPreset(presetId);
    if (preset === null) {
      return;
    }

    this.providerName = preset.name;
    this.providerNote = preset.description;
    this.websiteUrl = preset.websiteUrl;
    this.baseUrl = preset.baseUrl;
    this.wireApi = preset.wireApi;
    if (withToast) {
      this.triggerFeedback(`已载入 ${preset.name} 预设。`, 'success');
    }
  }

  private switchMode(mode: AddProviderMode): void {
    this.activeMode = mode;
    this.selectedPresetId = 'custom';
    this.applyPreset(mode === 'claude' ? 'anthropic-official' : 'custom', false);
    this.triggerFeedback(`已切换到${this.modeLabel(mode)}视图。`, 'info');
  }

  private submitAddProvider(): void {
    if (this.providerName.trim().length === 0) {
      this.triggerFeedback('请先填写供应商名称。', 'error');
      return;
    }
    if (this.apiKey.trim().length === 0) {
      this.triggerFeedback('请先填写 API Key。', 'error');
      return;
    }
    if (this.baseUrl.trim().length === 0) {
      this.triggerFeedback('请先填写请求地址。', 'error');
      return;
    }

    // 从预设获取 model / icon / category
    let model = 'gpt-5.1';
    let icon = '';
    let iconColor = '#8B5CF6';
    let category: ProviderCategory = 'custom';
    if (this.selectedPresetId !== 'custom') {
      const preset = this.selectedPreset();
      if (preset !== null) {
        model = preset.defaultModel;
        icon = preset.icon;
        iconColor = preset.iconColor.length > 0 ? preset.iconColor : '#8B5CF6';
        category = preset.category;
      }
    }

    const provider = new ProviderRecord(
      `provider-${Date.now()}-${Math.floor(Math.random() * 1000)}`,
      this.providerName.trim(),
      'codex',
      'exclusive',
      this.baseUrl.trim(),
      this.apiKey.trim(),
      model,
      false,
      'dirty',
      '',
      'apiKey',
      [],
      this.wireApi,
      category,
      this.providerNote.trim(),
      this.websiteUrl.trim(),
      icon,
      iconColor,
      [],
      'unknown',
      0,
      0,
      null,
      Date.now()
    );

    const result = configManagerFacade.saveProvider(provider);
    if (!result.ok || result.error !== null) {
      const message = result.error !== null ? result.error.message : '保存 Provider 失败。';
      this.triggerFeedback(message, 'error');
      return;
    }
    this.triggerFeedback(`已成功添加供应商 "${provider.name}"`, 'success');
    router.back();
  }

  @Builder
  private backdropLayer() {
    Stack() {
      Column()
        .width(320)
        .height(320)
        .backgroundColor('#D7E8FF')
        .opacity(0.34)
        .borderRadius(180)
        .position({ x: -72, y: -36 })

      Column()
        .width(240)
        .height(240)
        .backgroundColor('#FFF3D6')
        .opacity(0.28)
        .borderRadius(160)
        .position({ x: 760, y: 116 })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private particleCluster() {
    Row() {
      ForEach([0, 1, 2, 3, 4], (index: number) => {
        Column()
          .width(index % 2 === 0 ? 8 : 5)
          .height(index % 2 === 0 ? 8 : 5)
          .backgroundColor(index % 3 === 0 ? '#60A5FA' : (index % 3 === 1 ? '#34D399' : '#FBBF24'))
          .borderRadius(12)
          .opacity((this.sparkSeed + index) % 2 === 0 ? 0.95 : 0.35)
          .scale({ x: (this.sparkSeed + index) % 2 === 0 ? 1.18 : 0.82, y: (this.sparkSeed + index) % 2 === 0 ? 1.18 : 0.82 })
          .margin({ left: index === 0 ? 0 : 8, top: index % 2 === 0 ? 0 : 10 })
          .animation({ duration: 220, curve: Curve.EaseOut })
      })
    }
  }

  @Builder
  private topBar() {
    Row() {
      Button() {
        Row() {
          Text('←')
            .fontSize(16)
            .fontColor('#0F172A')
          Text('返回')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor('#0F172A')
            .margin({ left: 8 })
        }
      }
      .height(42)
      .padding({ left: 14, right: 14 })
      .backgroundColor('#FFFFFF')
      .borderRadius(18)
      .border({ width: 1, color: '#D8E1EE' })
      .onClick(() => { router.back(); })

      Column() {
        Text('添加新供应商')
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor('#0F172A')
        Text('独立添加页 · 预设先选 · 前端模拟提交')
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(11)
          .fontColor('#64748B')
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 18 })

      Blank()
        .layoutWeight(1)

      this.particleCluster()
    }
    .width('100%')
    .padding({ left: 28, right: 28, top: 24, bottom: 16 })
  }

  @Builder
  private modeChip(label: string, mode: AddProviderMode) {
    Button(label)
      .height(40)
      .layoutWeight(1)
      .fontSize(12)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.activeMode === mode ? '#FFFFFF' : '#94A3B8')
      .backgroundColor(this.activeMode === mode ? '#2284F6' : '#F4F6FB')
      .borderRadius(12)
      .onClick(() => { this.switchMode(mode); })
  }

  @Builder
  private formLabel(label: string) {
    Text(label)
      .copyOption(CopyOptions.LocalDevice)
      .fontSize(11)
      .fontWeight(FontWeight.Medium)
      .fontColor('#0F172A')
      .margin({ top: 16 })
  }

  @Builder
  private inputField(text: string, placeholder: string, key: string, onChange: (value: string) => void) {
    TextInput({ text: text, placeholder: placeholder })
      .width('100%')
      .height(42)
      .backgroundColor('#FFFFFF')
      .border({ width: 1, color: '#DEE6F2' })
      .borderRadius(14)
      .padding({ left: 14, right: 14 })
      .margin({ top: 8 })
      .onChange(onChange)
  }

  @Builder
  private chip(label: string, background: string, color: string) {
    Text(label)
      .copyOption(CopyOptions.LocalDevice)
      .fontSize(10)
      .fontColor(color)
      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
      .backgroundColor(background)
      .borderRadius(10)
  }

  @Builder
  private presetChip(label: string, selected: boolean, key: string, onClick: () => void) {
    Button(label)
      .height(36)
      .fontSize(11)
      .fontWeight(selected ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(selected ? '#FFFFFF' : '#64748B')
      .backgroundColor(selected ? '#2284F6' : '#F5F7FB')
      .borderRadius(12)
      .border({ width: selected ? 0 : 1, color: '#E1E7F0' })
      .padding({ left: 14, right: 14 })
      .margin({ right: 10, bottom: 10 })
      .onClick(onClick)
  }

  @Builder
  private toggleChip(label: string, enabled: boolean, key: string, onClick: () => void) {
    Row() {
      Text(enabled ? '☑' : '☐')
        .fontSize(13)
        .fontColor(enabled ? '#D946EF' : '#94A3B8')
      Text(label)
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(11)
        .fontColor('#64748B')
        .margin({ left: 6 })
    }
    .padding({ left: 4, right: 10, top: 4, bottom: 4 })
    .onClick(onClick)
  }

  @Builder
  private ghostSwitch(enabled: boolean, key: string, onClick: () => void) {
    Row() {
      Row() {
        Column()
          .width(18)
          .height(18)
          .backgroundColor('#FFFFFF')
          .borderRadius(9)
          .margin({ left: enabled ? 18 : 2 })
          .animation({ duration: 140, curve: Curve.EaseOut })
      }
      .width(40)
      .height(22)
      .backgroundColor(enabled ? '#D946EF' : '#E5E7EB')
      .borderRadius(11)
    }
    .onClick(onClick)
  }

  @Builder
  private sectionCard(title: string, subtitle: string) {
    Column() {
      Text(title)
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor('#0F172A')
      Text(subtitle)
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(11)
        .fontColor('#64748B')
        .lineHeight(18)
        .margin({ top: 4 })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  private presetSection() {
    Column() {
      this.sectionCard('预设供应商', '先选预设，再补齐名称、API Key 和请求地址。')

      Row() {
        this.presetChip('自定义配置', this.selectedPresetId === 'custom', 'preset-custom', () => { this.applyPreset('custom'); })
        ForEach(this.visiblePresets(), (preset: ProviderPreset) => {
          this.presetChip(preset.name, this.selectedPresetId === preset.id, `preset-${preset.id}`, () => { this.applyPreset(preset.id); })
        }, (preset: ProviderPreset) => preset.id)
      }
      .width('100%')
      .margin({ top: 14 })
      
      Row() {
        Text('💡')
          .fontSize(11)
        Text('自定义配置需手动填写所有必要字段')
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(10)
          .fontColor('#64748B')
          .margin({ left: 6 })
      }
      .margin({ top: 4 })
    }
    .width('100%')
    .padding(18)
    .backgroundColor('#FFFFFF')
    .border({ width: 1, color: '#E2EAF3' })
    .borderRadius(24)
  }

  @Builder
  private previewBadge() {
    Column() {
      Stack({ alignContent: Alignment.Center }) {
        Column()
          .width(78)
          .height(78)
          .backgroundColor('#FFFFFF')
          .border({ width: 1, color: '#E3E8F2' })
          .borderRadius(22)

        Text(this.presetIconText())
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.presetAccent(this.selectedPresetId))
      }

      if (this.selectedPresetId !== 'custom' && this.selectedPreset() !== null) {
        Row() {
          this.chip(this.selectedPresetCategoryLabel(), '#EEF4FF', '#3563C8')
          this.chip(this.selectedPresetWireApiLabel(), '#F8FAFC', '#64748B')
        }
        .margin({ top: 10 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .margin({ top: 14, bottom: 8 })
  }

  @Builder
  private requestHint() {
    Row() {
      Text('💡')
        .fontSize(11)
      Text('填写兼容 Claude API 的服务端点地址，不要以斜杠结尾')
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(10)
        .fontColor('#D97706')
        .margin({ left: 6 })
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .backgroundColor('#FFF9E9')
    .border({ width: 1, color: '#FACC15' })
    .borderRadius(14)
    .margin({ top: 10 })
  }

  @Builder
  private advancedSection() {
    Column() {
      Row() {
        Text(this.advancedExpanded ? '⌄' : '›')
          .fontSize(14)
          .fontColor('#334155')
        Text('高级选项')
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor('#0F172A')
          .margin({ left: 8 })
      }
      .width('100%')
      .onClick(() => { this.advancedExpanded = !this.advancedExpanded; })

      Text('包含 API 格式、认证字段、模型映射等配置。大多数场景下保持默认即可。')
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(11)
        .fontColor('#94A3B8')
        .lineHeight(18)
        .margin({ top: 8 })

      if (this.advancedExpanded) {
        Column() {
          this.formLabel('Wire API')
          Row() {
            this.presetChip('responses', this.wireApi === 'responses', 'wire-responses', () => { this.wireApi = 'responses'; })
            this.presetChip('chat', this.wireApi === 'chat', 'wire-chat', () => { this.wireApi = 'chat'; })
            this.presetChip('anthropic', this.wireApi === 'anthropic', 'wire-anthropic', () => { this.wireApi = 'anthropic'; })
          }
          .width('100%')
        }
        .width('100%')
      }
    }
    .width('100%')
    .margin({ top: 18 })
  }

  @Builder
  private configSection() {
    Column() {
      Row() {
        Text('配置 JSON')
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor('#0F172A')
        Blank()
          .layoutWeight(1)
        Row() {
          Text(this.writeGeneralConfig ? '☑' : '☐')
            .fontSize(13)
            .fontColor('#D946EF')
          Text('写入通用配置')
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(11)
            .fontColor('#64748B')
            .margin({ left: 6 })
        }
        .onClick(() => { this.writeGeneralConfig = !this.writeGeneralConfig; })
      }
      .width('100%')

      Row() {
        this.toggleChip('隐藏 AI 署名', this.aliasEnabled, 'toggle-alias', () => { this.aliasEnabled = !this.aliasEnabled; })
        this.toggleChip('Teammates 模式', this.teammatesEnabled, 'toggle-teammates', () => { this.teammatesEnabled = !this.teammatesEnabled; })
        this.toggleChip('启用 Tool Search', this.toolSearchEnabled, 'toggle-tool-search', () => { this.toolSearchEnabled = !this.toolSearchEnabled; })
        this.toggleChip('最大强度思考', this.intenseThinkingEnabled, 'toggle-intense', () => { this.intenseThinkingEnabled = !this.intenseThinkingEnabled; })
        this.toggleChip('禁用自动升级', this.autoUpdateDisabled, 'toggle-updates', () => { this.autoUpdateDisabled = !this.autoUpdateDisabled; })
      }
      .width('100%')
            .margin({ top: 10 })

      TextArea({ text: this.configJson, placeholder: '{\n  "env": {}\n}' })
        .width('100%')
        .height(180)
        .margin({ top: 10 })
        .padding(12)
        .backgroundColor('#F7FAFF')
        .border({ width: 1, color: '#D9E3F2' })
        .borderRadius(14)
        .fontFamily('monospace')
        .fontSize(11)
        .onChange((value: string) => { this.configJson = value; })
    }
    .width('100%')
    .margin({ top: 18 })
  }

  @Builder
  private collapseCard(title: string, enabled: boolean, key: string, onClick: () => void) {
    Row() {
      Row() {
        Text('◌')
          .fontSize(15)
          .fontColor('#64748B')
        Text(title)
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor('#0F172A')
          .margin({ left: 10 })
      }

      Blank()
        .layoutWeight(1)

      Text('使用单独配置')
        .copyOption(CopyOptions.LocalDevice)
        .fontSize(11)
        .fontColor('#64748B')
        .margin({ right: 10 })

      this.ghostSwitch(enabled, key, onClick)

      Text('›')
        .fontSize(16)
        .fontColor('#94A3B8')
        .margin({ left: 14 })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 18, bottom: 18 })
    .backgroundColor('#FFFFFF')
    .border({ width: 1, color: '#E2EAF3' })
    .borderRadius(18)
    .margin({ top: 14 })
  }

  @Builder
  private contentPanel() {
    Column() {
      Row() {
        this.modeChip('Claude 供应商', 'claude')
        this.modeChip('统一供应商', 'unified')
      }
      .width('100%')
      .padding({ left: 4, right: 4, top: 4, bottom: 4 })
      .backgroundColor('#F5F7FB')
      .borderRadius(16)

      this.presetSection()

      this.previewBadge()

      Row() {
        Column() {
          this.formLabel('供应商名称')
          this.inputField(this.providerName, '例如：Claude 官方', 'provider-name', (value: string) => { this.providerName = value; })
        }
        .layoutWeight(1)

        Column() {
          this.formLabel('备注')
          this.inputField(this.providerNote, '例如：公司专用账号', 'provider-note', (value: string) => { this.providerNote = value; })
        }
        .layoutWeight(1)
        .margin({ left: 14 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      this.formLabel('官网链接')
      this.inputField(this.websiteUrl, 'https://example.com（可选）', 'website-url', (value: string) => { this.websiteUrl = value; })

      this.formLabel('API Key')
      this.inputField(this.apiKey, '只需要填这里，下方配置会自动填充', 'api-key', (value: string) => { this.apiKey = value; })

      Row() {
        Text('请求地址')
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor('#0F172A')
        Row() {
          Text('完整 URL')
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(10)
            .fontColor('#64748B')
            .margin({ right: 8 })
          this.ghostSwitch(this.requestFullUrl, 'request-full-url', () => { this.requestFullUrl = !this.requestFullUrl; })
        }
        .margin({ left: 14 })
        Blank()
          .layoutWeight(1)
        Row() {
          Text('⚡')
            .fontSize(11)
            .fontColor('#64748B')
          Text('管理与测速')
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(10)
            .fontColor('#64748B')
            .margin({ left: 6 })
        }
      }
      .width('100%')
      .margin({ top: 16 })

      this.inputField(this.baseUrl, 'https://your-api-endpoint.com', 'base-url', (value: string) => { this.baseUrl = value; })
      this.requestHint()
      this.advancedSection()
      this.configSection()

      Row() {
        Text('✎')
          .fontSize(12)
          .fontColor('#64748B')
        Text('格式化')
          .copyOption(CopyOptions.LocalDevice)
          .fontSize(11)
          .fontColor('#64748B')
          .margin({ left: 8 })
      }
      .margin({ top: 18 })
      .onClick(() => { this.notePending('JSON 格式化'); })

      this.collapseCard('模型测试配置', this.modelTestSingleConfig, 'model-test-switch', () => {
        this.modelTestSingleConfig = !this.modelTestSingleConfig;
        this.notePending('模型测试配置');
      })

      this.collapseCard('计费配置', this.billingSingleConfig, 'billing-switch', () => {
        this.billingSingleConfig = !this.billingSingleConfig;
        this.notePending('计费配置');
      })
    }
    .width('100%')
    .padding(18)
    .backgroundColor('#FFFFFF')
    .border({ width: 1, color: '#E2EAF3' })
    .borderRadius(24)
  }

  @Builder
  private bottomBar() {
    Row() {
      Blank()
        .layoutWeight(1)

      Button('取消')
        .height(40)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor('#64748B')
        .backgroundColor('#FFFFFF')
        .borderRadius(14)
        .border({ width: 1, color: '#D5E0ED' })
        .padding({ left: 18, right: 18 })
        .onClick(() => { router.back(); })

      Button('+ 添加')
        .height(40)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor('#FFFFFF')
        .backgroundColor('#2284F6')
        .borderRadius(14)
        .padding({ left: 20, right: 20 })
        .margin({ left: 12 })
        .onClick(() => { this.submitAddProvider(); })
    }
    .width('100%')
    .padding({ left: 24, right: 24, top: 14, bottom: 18 })
    .backgroundColor('#FFFFFF')
    .border({ width: 1, color: '#E3EAF4' })
    .borderRadius(22)
    .margin({ top: 16 })
  }

  @Builder
  private toastHost() {
    Column() {
      ForEach(this.toasts, (toast: UiToastItem) => {
        Row() {
          Column()
            .width(8)
            .height(8)
            .backgroundColor(this.toneColor(toast.tone))
            .borderRadius(8)

          Text(toast.message)
            .copyOption(CopyOptions.LocalDevice)
            .fontSize(11)
            .fontColor('#0F172A')
            .margin({ left: 10 })
            .layoutWeight(1)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width(360)
        .padding({ left: 14, right: 14, top: 12, bottom: 12 })
        .backgroundColor(this.toneBackground(toast.tone))
        .border({ width: 1, color: '#FFFFFF' })
        .borderRadius(18)
        .margin({ top: 10 })
      }, (toast: UiToastItem) => `${toast.id}`)
    }
    .alignItems(HorizontalAlign.End)
    .position({ x: 700, y: 28 })
  }

  build() {
    Stack() {
      this.backdropLayer()

      Column() {
        this.topBar()

        Scroll() {
          Column() {
            this.contentPanel()
            this.bottomBar()
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 28, right: 28, bottom: 24 })
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')

      this.toastHost()
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#E9EEF6')
  }
}

import { apiManagementVM, ApiManagementState } from '../apim/ApiManagementViewModel';
import { ProviderRecord, ProviderPreset, EndpointSpeedResult, BUILTIN_PROVIDER_PRESETS } from '../apim/ApiTypes';

@Component
export struct ApiManagementPage {
  @State private vm: ApiManagementState = apiManagementVM.state;
  @State private activeSubTab: string = 'providers';
  @State private filterCategory: string = 'all';
  @State private editorExpanded: boolean = false;
  @State private showSpeedResults: boolean = false;
  @State private showDiscoveredModels: boolean = false;
  @State private showUsageResult: boolean = false;
  @State private exportJson: string = '';
  @State private importJson: string = '';
  @State private showExportDialog: boolean = false;
  @State private showImportDialog: boolean = false;

  aboutToAppear(): void {
    apiManagementVM.loadProviders();
  }

  private categoryLabel(category: string): string {
    switch (category) {
      case 'official': return '官方';
      case 'third_party': return '第三方';
      case 'cloud_provider': return '云服务商';
      case 'aggregator': return '聚合服务';
      case 'custom': return '自定义';
      default: return category;
    }
  }

  private wireApiLabel(wireApi: string): string {
    switch (wireApi) {
      case 'responses': return 'Responses';
      case 'chat': return 'Chat';
      case 'anthropic': return 'Anthropic';
      default: return wireApi;
    }
  }

  private healthColor(status: string): string {
    switch (status) {
      case 'healthy': return '#166534';
      case 'degraded': return '#C2410C';
      case 'unhealthy': return '#B91C1C';
      default: return '#64748B';
    }
  }

  private firstN(items: string[], n: number): string[] {
    const result: string[] = [];
    const max = items.length < n ? items.length : n;
    for (let i = 0; i < max; i++) {
      result.push(items[i]);
    }
    return result;
  }

  private healthBg(status: string): string {
    switch (status) {
      case 'healthy': return '#DCFCE7';
      case 'degraded': return '#FFF7ED';
      case 'unhealthy': return '#FEE2E2';
      default: return '#F8FAFC';
    }
  }

  @Builder
  private chip(label: string, background: string, color: string) {
    Text(label)
      .fontSize(10)
      .fontColor(color)
      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
      .backgroundColor(background)
      .borderRadius(8)
  }

  @Builder
  private sectionTitle(title: string, subtitle: string) {
    Column() {
      Text(title)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor('#0F172A')
      Text(subtitle)
        .fontSize(10)
        .fontColor('#94A3B8')
        .margin({ top: 2 })
    }
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private subTabChip(label: string, tab: string) {
    Text(label)
      .fontSize(11)
      .fontWeight(this.activeSubTab === tab ? FontWeight.Medium : FontWeight.Regular)
      .fontColor(this.activeSubTab === tab ? '#1D4ED8' : '#64748B')
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .backgroundColor(this.activeSubTab === tab ? '#EEF4FF' : '#F8FAFC')
      .border({ width: 1, color: this.activeSubTab === tab ? '#BFDBFE' : '#E5E7EB' })
      .borderRadius(10)
      .margin({ right: 6 })
      .onClick(() => { this.activeSubTab = tab; })
  }

  // ── Preset list panel ──

  @Builder
  private presetsPanel() {
    Column() {
      this.sectionTitle('Provider 预设库', '选择一个预设作为起点，填入 API Key 即可快速添加')

      Row() {
        this.filterChip('全部', 'all')
        this.filterChip('官方', 'official')
        this.filterChip('第三方', 'third_party')
        this.filterChip('云服务商', 'cloud_provider')
        this.filterChip('聚合', 'aggregator')
      }
      .width('100%')
      .margin({ top: 10 })

      List({ space: 0 }) {
        ForEach(
          this.filteredPresets(),
          (preset: ProviderPreset) => {
            ListItem() {
              this.presetRow(preset)
            }
          },
          (preset: ProviderPreset) => preset.id
        )
      }
      .layoutWeight(1)
      .width('100%')
      .margin({ top: 8 })
      .scrollBar(BarState.Off)
    }
    .height('100%')
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  private filteredPresets(): ProviderPreset[] {
    if (this.filterCategory === 'all') return BUILTIN_PROVIDER_PRESETS;
    const result: ProviderPreset[] = [];
    const presets = BUILTIN_PROVIDER_PRESETS;
    for (let i = 0; i < presets.length; i++) {
      if (presets[i].category === this.filterCategory) {
        result.push(presets[i]);
      }
    }
    return result;
  }

  @Builder
  private filterChip(label: string, category: string) {
    Text(label)
      .fontSize(10)
      .fontColor(this.filterCategory === category ? '#1D4ED8' : '#64748B')
      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
      .backgroundColor(this.filterCategory === category ? '#EEF4FF' : '#F8FAFC')
      .border({ width: 1, color: this.filterCategory === category ? '#BFDBFE' : '#E5E7EB' })
      .borderRadius(8)
      .margin({ right: 6 })
      .onClick(() => { this.filterCategory = category; })
  }

  @Builder
  private presetRow(preset: ProviderPreset) {
    Column() {
      Row() {
        Column() {
          Text(preset.name)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor('#0F172A')

          Text(preset.description)
            .fontSize(10)
            .fontColor('#64748B')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 2 })

          Row() {
            this.chip(this.categoryLabel(preset.category), '#EEF4FF', '#1D4ED8')
            this.chip(this.wireApiLabel(preset.wireApi), '#F8FAFC', '#64748B')
          }
          .width('100%')
          .margin({ top: 6 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')

      Row() {
        Button('使用此预设')
          .height(28)
          .fontSize(11)
          .backgroundColor('#111827')
          .fontColor('#FFFFFF')
          .borderRadius(12)
          .onClick(() => {
            this.vm.selectedPresetId = preset.id;
            this.vm.showAddFromPreset = true;
          })
      }
      .width('100%')
      .margin({ top: 8 })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(12)
    .backgroundColor('#FFFFFF')
    .border({ width: 1, color: '#E5E7EB' })
    .borderRadius(14)
    .margin({ bottom: 8 })
  }

  // ── Provider list panel ──

  @Builder
  private providersPanel() {
    Column() {
      Row() {
        Text('Provider 管理')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor('#0F172A')
        Text(`  ${this.vm.providers.length} 个`)
          .fontSize(12)
          .fontColor('#64748B')
          .margin({ left: 6 })
        Blank().layoutWeight(1)
        this.chip(apiManagementVM.activeProviderName, '#DCFCE7', '#166534')
      }
      .width('100%')

      Row() {
        Button('从预设添加')
          .height(30)
          .fontSize(11)
          .backgroundColor('#111827')
          .fontColor('#FFFFFF')
          .borderRadius(12)
          .onClick(() => {
            apiManagementVM.startNewFromPreset();
          })

        Button('自定义')
          .height(30)
          .fontSize(11)
          .margin({ left: 8 })
          .backgroundColor('#FFFFFF')
          .fontColor('#334155')
          .borderRadius(12)
          .border({ width: 1, color: '#CBD5E1' })
          .onClick(() => {
            apiManagementVM.startEditing(null);
            this.editorExpanded = true;
          })

        Button('导出')
          .height(30)
          .fontSize(11)
          .margin({ left: 8 })
          .backgroundColor('#FFFFFF')
          .fontColor('#334155')
          .borderRadius(12)
          .border({ width: 1, color: '#CBD5E1' })
          .onClick(() => {
            this.exportJson = apiManagementVM.exportProviders();
            this.showExportDialog = true;
          })

        Button('导入')
          .height(30)
          .fontSize(11)
          .margin({ left: 8 })
          .backgroundColor('#FFFFFF')
          .fontColor('#334155')
          .borderRadius(12)
          .border({ width: 1, color: '#CBD5E1' })
          .onClick(() => {
            this.showImportDialog = true;
          })
      }
      .width('100%')
      .margin({ top: 10 })

      if (this.vm.providers.length === 0) {
        Column() {
          Text('暂无 Provider')
            .fontSize(13)
            .fontColor('#334155')
            .fontWeight(FontWeight.Medium)
          Text('从预设库快速添加，或创建自定义 Provider')
            .fontSize(11)
            .fontColor('#64748B')
            .lineHeight(18)
            .margin({ top: 6 })
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding(16)
        .margin({ top: 12 })
        .backgroundColor('#F8FAFC')
        .border({ width: 1, color: '#E2E8F0' })
        .borderRadius(14)
        .layoutWeight(1)
      } else {
        List({ space: 0 }) {
          ForEach(this.vm.providers, (provider: ProviderRecord) => {
            ListItem() {
              this.providerCard(provider)
            }
          }, (provider: ProviderRecord) => provider.id)
        }
        .layoutWeight(1)
        .width('100%')
        .margin({ top: 10 })
        .scrollBar(BarState.Off)
      }
    }
    .height('100%')
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private providerCard(provider: ProviderRecord) {
    Column() {
      Row() {
        Column() {
          Row() {
            Text(provider.name.length > 0 ? provider.name : '未命名')
              .fontSize(12)
              .fontWeight(provider.isActive ? FontWeight.Bold : FontWeight.Medium)
              .fontColor('#0F172A')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            if (provider.isActive) {
              this.chip('ACTIVE', '#DCFCE7', '#166534')
            }
          }

          Text(`${provider.baseUrl.length > 0 ? provider.baseUrl : '未设置 URL'} · ${provider.model.length > 0 ? provider.model : '未设置模型'}`)
            .fontSize(10)
            .fontColor('#64748B')
            .margin({ top: 3 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Row() {
            this.chip(this.categoryLabel(provider.category), '#EEF4FF', '#1D4ED8')
            this.chip(this.wireApiLabel(provider.wireApi), '#F8FAFC', '#64748B')
            this.chip(provider.healthStatus, this.healthBg(provider.healthStatus), this.healthColor(provider.healthStatus))
            this.chip(provider.syncStatus, '#F8FAFC', '#64748B')
          }
          .width('100%')
          .margin({ top: 6 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')

      Row() {
        Button('编辑')
          .height(26)
          .fontSize(10)
          .backgroundColor('#FFFFFF')
          .fontColor('#334155')
          .borderRadius(10)
          .border({ width: 1, color: '#CBD5E1' })
          .onClick(() => {
            apiManagementVM.startEditing(provider);
            this.editorExpanded = true;
            this.activeSubTab = 'providers';
          })

        Button(provider.isActive ? '已启用' : '激活')
          .height(26)
          .fontSize(10)
          .margin({ left: 6 })
          .backgroundColor(provider.isActive ? '#DBEAFE' : '#111827')
          .fontColor(provider.isActive ? '#1D4ED8' : '#FFFFFF')
          .borderRadius(10)
          .onClick(() => {
            if (!provider.isActive) {
              apiManagementVM.activateProvider(provider.id);
            }
          })

        Button('验证')
          .height(26)
          .fontSize(10)
          .margin({ left: 6 })
          .backgroundColor('#FFFFFF')
          .fontColor('#334155')
          .borderRadius(10)
          .border({ width: 1, color: '#CBD5E1' })
          .onClick(() => {
            apiManagementVM.validateProvider(provider);
          })

        Button('删除')
          .height(26)
          .fontSize(10)
          .margin({ left: 6 })
          .backgroundColor('#FFFFFF')
          .fontColor('#B91C1C')
          .borderRadius(10)
          .border({ width: 1, color: '#FECACA' })
          .onClick(() => {
            apiManagementVM.deleteProvider(provider.id);
          })
      }
      .width('100%')
      .margin({ top: 8 })

      Row() {
        Button('测速')
          .height(24)
          .fontSize(10)
          .backgroundColor('#FFFFFF')
          .fontColor('#64748B')
          .borderRadius(8)
          .border({ width: 1, color: '#E5E7EB' })
          .onClick(() => {
            apiManagementVM.testSpeed(provider, false);
            this.showSpeedResults = true;
          })

        Button('模型发现')
          .height(24)
          .fontSize(10)
          .margin({ left: 4 })
          .backgroundColor('#FFFFFF')
          .fontColor('#64748B')
          .borderRadius(8)
          .border({ width: 1, color: '#E5E7EB' })
          .onClick(() => {
            apiManagementVM.discoverModels(provider);
            this.showDiscoveredModels = true;
          })

        Button('用量')
          .height(24)
          .fontSize(10)
          .margin({ left: 4 })
          .backgroundColor('#FFFFFF')
          .fontColor('#64748B')
          .borderRadius(8)
          .border({ width: 1, color: '#E5E7EB' })
          .onClick(() => {
            apiManagementVM.queryUsage(provider);
            this.showUsageResult = true;
          })
      }
      .width('100%')
      .margin({ top: 6 })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(12)
    .backgroundColor(provider.isActive ? '#F0FDF4' : '#FFFFFF')
    .border({ width: 1, color: provider.isActive ? '#BBF7D0' : '#E5E7EB' })
    .borderRadius(14)
    .margin({ bottom: 8 })
  }

  // ── Editor panel ──

  @Builder
  private editorPanel() {
    Column() {
      if (this.vm.editingProvider !== null) {
        this.sectionTitle(
          '编辑 Provider',
          '修改后点击保存'
        )

        TextInput({ text: this.vm.editingProvider.name, placeholder: 'Provider 名称' })
          .width('100%').height(36).margin({ top: 8 }).fontSize(11)
          .backgroundColor('#FFFFFF').borderRadius(10)
          .padding({ left: 10, right: 10 })
          .onChange((value: string) => { if (this.vm.editingProvider !== null) { this.vm.editingProvider.name = value; } })

        TextInput({ text: this.vm.editingProvider.baseUrl, placeholder: 'https://api.openai.com/v1' })
          .width('100%').height(36).margin({ top: 8 }).fontSize(11)
          .backgroundColor('#FFFFFF').borderRadius(10)
          .padding({ left: 10, right: 10 })
          .onChange((value: string) => { if (this.vm.editingProvider !== null) { this.vm.editingProvider.baseUrl = value; } })

        TextInput({ text: this.vm.editingProvider.apiKey, placeholder: 'sk-...' })
          .width('100%').height(36).margin({ top: 8 }).fontSize(11)
          .backgroundColor('#FFFFFF').borderRadius(10)
          .padding({ left: 10, right: 10 })
          .onChange((value: string) => { if (this.vm.editingProvider !== null) { this.vm.editingProvider.apiKey = value; } })

        TextInput({ text: this.vm.editingProvider.model, placeholder: '模型 ID（如 gpt-5.1）' })
          .width('100%').height(36).margin({ top: 8 }).fontSize(11)
          .backgroundColor('#FFFFFF').borderRadius(10)
          .padding({ left: 10, right: 10 })
          .onChange((value: string) => { if (this.vm.editingProvider !== null) { this.vm.editingProvider.model = value; } })

        Text('API 格式')
          .fontSize(10).fontColor('#64748B').margin({ top: 10 })
        Row() {
          this.optionChip('Responses', this.vm.editingProvider.wireApi === 'responses', () => { if (this.vm.editingProvider !== null) { this.vm.editingProvider.wireApi = 'responses'; } })
          this.optionChip('Chat', this.vm.editingProvider.wireApi === 'chat', () => { if (this.vm.editingProvider !== null) { this.vm.editingProvider.wireApi = 'chat'; } })
          this.optionChip('Anthropic', this.vm.editingProvider.wireApi === 'anthropic', () => { if (this.vm.editingProvider !== null) { this.vm.editingProvider.wireApi = 'anthropic'; } })
        }

        Text('分类')
          .fontSize(10).fontColor('#64748B').margin({ top: 8 })
        Row() {
          this.optionChip('官方', this.vm.editingProvider.category === 'official', () => { if (this.vm.editingProvider !== null) { this.vm.editingProvider.category = 'official'; } })
          this.optionChip('第三方', this.vm.editingProvider.category === 'third_party', () => { if (this.vm.editingProvider !== null) { this.vm.editingProvider.category = 'third_party'; } })
          this.optionChip('聚合', this.vm.editingProvider.category === 'aggregator', () => { if (this.vm.editingProvider !== null) { this.vm.editingProvider.category = 'aggregator'; } })
          this.optionChip('自定义', this.vm.editingProvider.category === 'custom', () => { if (this.vm.editingProvider !== null) { this.vm.editingProvider.category = 'custom'; } })
        }

        TextInput({ text: this.vm.editingProvider.description, placeholder: '描述/备注' })
          .width('100%').height(36).margin({ top: 8 }).fontSize(11)
          .backgroundColor('#FFFFFF').borderRadius(10)
          .padding({ left: 10, right: 10 })
          .onChange((value: string) => { if (this.vm.editingProvider !== null) { this.vm.editingProvider.description = value; } })

        TextInput({ text: this.vm.editingProvider.websiteUrl, placeholder: '获取 API Key 的网址' })
          .width('100%').height(36).margin({ top: 8 }).fontSize(11)
          .backgroundColor('#FFFFFF').borderRadius(10)
          .padding({ left: 10, right: 10 })
          .onChange((value: string) => { if (this.vm.editingProvider !== null) { this.vm.editingProvider.websiteUrl = value; } })

        Row() {
          Button('保存')
            .height(32).fontSize(11)
            .backgroundColor('#111827').fontColor('#FFFFFF').borderRadius(12)
            .onClick(() => {
              apiManagementVM.saveEditing();
              this.editorExpanded = false;
            })

          Button('取消')
            .height(32).fontSize(11).margin({ left: 8 })
            .backgroundColor('#FFFFFF').fontColor('#334155').borderRadius(12)
            .border({ width: 1, color: '#CBD5E1' })
            .onClick(() => {
              apiManagementVM.cancelEditing();
              this.editorExpanded = false;
            })
        }
        .width('100%').margin({ top: 12 })
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(12)
    .backgroundColor('#F8FAFC')
    .border({ width: 1, color: '#E2E8F0' })
    .borderRadius(14)
  }

  @Builder
  private optionChip(label: string, selected: boolean, onClick: () => void) {
    Text(label)
      .fontSize(10)
      .fontColor(selected ? '#1D4ED8' : '#64748B')
      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
      .backgroundColor(selected ? '#EEF4FF' : '#F8FAFC')
      .border({ width: 1, color: selected ? '#BFDBFE' : '#E5E7EB' })
      .borderRadius(8)
      .margin({ right: 6 })
      .onClick(onClick)
  }

  // ── Dialogs ──

  @Builder
  private addPresetDialog() {
    if (this.vm.showAddFromPreset) {
      Column() {
        Text('从预设创建 Provider')
          .fontSize(14).fontWeight(FontWeight.Medium).fontColor('#0F172A')

        Text('请在下方填入 API Key，其他字段将自动从预设填充。')
          .fontSize(11).fontColor('#64748B').lineHeight(16).margin({ top: 6 })

        TextInput({ text: this.vm.newApiKey, placeholder: '输入你的 API Key' })
          .width('100%').height(38).margin({ top: 12 }).fontSize(12)
          .backgroundColor('#FFFFFF').borderRadius(12)
          .padding({ left: 12, right: 12 })
          .onChange((value: string) => { this.vm.newApiKey = value; })

        Row() {
          Button('确认添加')
            .height(32).fontSize(12).backgroundColor('#111827').fontColor('#FFFFFF').borderRadius(12)
            .onClick(() => { apiManagementVM.confirmAddFromPreset(); })

          Button('取消')
            .height(32).fontSize(12).margin({ left: 8 })
            .backgroundColor('#FFFFFF').fontColor('#334155').borderRadius(12)
            .border({ width: 1, color: '#CBD5E1' })
            .onClick(() => { apiManagementVM.cancelAddFromPreset(); })
        }
        .width('100%').margin({ top: 14 })
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding(16)
      .backgroundColor('#FFFFFF')
      .border({ width: 1, color: '#E2E8F0' })
      .borderRadius(16)
      .margin({ top: 8 })
    }
  }

  @Builder
  private validationResultPanel() {
    if (this.vm.validationResult !== null) {
      Column() {
        Text(this.vm.validationResult.success ? '验证通过' : '验证失败')
          .fontSize(13).fontWeight(FontWeight.Medium)
          .fontColor(this.vm.validationResult.success ? '#166534' : '#B91C1C')

        Text(`延迟: ${this.vm.validationResult.latencyMs}ms · HTTP ${this.vm.validationResult.statusCode}`)
          .fontSize(11).fontColor('#64748B').margin({ top: 4 })

        if (this.vm.validationResult.accountInfo.length > 0) {
          Text(this.vm.validationResult.accountInfo)
            .fontSize(11).fontColor('#334155').margin({ top: 4 })
        }
        if (this.vm.validationResult.errorMessage.length > 0) {
          Text(this.vm.validationResult.errorMessage)
            .fontSize(11).fontColor('#B91C1C').margin({ top: 4 })
        }

        Button('关闭')
          .height(28).fontSize(11).margin({ top: 8 })
          .backgroundColor('#FFFFFF').fontColor('#64748B').borderRadius(10)
          .border({ width: 1, color: '#E5E7EB' })
          .onClick(() => { this.vm.validationResult = null; })
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding(12)
      .backgroundColor(this.vm.validationResult.success ? '#F0FDF4' : '#FEF2F2')
      .border({ width: 1, color: this.vm.validationResult.success ? '#BBF7D0' : '#FECACA' })
      .borderRadius(14)
      .margin({ top: 8 })
    }
  }

  @Builder
  private speedResultsPanel() {
    if (this.showSpeedResults && this.vm.speedResults.length > 0) {
      Column() {
        Row() {
          Text('端点测速结果')
            .fontSize(13).fontWeight(FontWeight.Medium).fontColor('#0F172A')
          Blank().layoutWeight(1)
          Button('关闭')
            .height(24).fontSize(10).backgroundColor('#FFFFFF').fontColor('#64748B').borderRadius(8)
            .border({ width: 1, color: '#E5E7EB' })
            .onClick(() => { this.showSpeedResults = false; })
        }
        .width('100%')

        List({ space: 0 }) {
          ForEach(this.vm.speedResults, (r: EndpointSpeedResult) => {
            ListItem() {
              Row() {
                Text(r.endpointUrl)
                  .fontSize(10).fontColor('#334155').maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
                Text(r.success ? `${r.latencyMs}ms` : 'FAIL')
                  .fontSize(10).fontColor(r.success ? '#166534' : '#B91C1C')
                this.chip(r.success ? 'OK' : `ERR`,
                  r.success ? '#DCFCE7' : '#FEE2E2',
                  r.success ? '#166534' : '#B91C1C')
              }
              .width('100%')
              .padding({ top: 6, bottom: 6 })
            }
          }, (r: EndpointSpeedResult) => r.endpointUrl)
        }
        .width('100%')
        .margin({ top: 8 })
        .height(150)
        .scrollBar(BarState.Off)
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding(12)
      .backgroundColor('#FFFFFF')
      .border({ width: 1, color: '#E5E7EB' })
      .borderRadius(14)
      .margin({ top: 8 })
    }
  }

  @Builder
  private discoveredModelsPanel() {
    if (this.showDiscoveredModels && this.vm.discoveredModels.length > 0) {
      Column() {
        Row() {
          Text(`发现 ${this.vm.discoveredModels.length} 个模型`)
            .fontSize(13).fontWeight(FontWeight.Medium).fontColor('#0F172A')
          Blank().layoutWeight(1)
          Button('关闭')
            .height(24).fontSize(10).backgroundColor('#FFFFFF').fontColor('#64748B').borderRadius(8)
            .border({ width: 1, color: '#E5E7EB' })
            .onClick(() => { this.showDiscoveredModels = false; })
        }
        .width('100%')

        List({ space: 0 }) {
          ForEach(this.firstN(this.vm.discoveredModels, 30), (model: string) => {
            ListItem() {
              Text(model)
                .fontSize(10).fontColor('#334155')
                .padding({ top: 4, bottom: 4 })
            }
          }, (model: string) => model)
        }
        .width('100%')
        .margin({ top: 6 })
        .height(180)
        .scrollBar(BarState.Off)
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding(12)
      .backgroundColor('#FFFFFF')
      .border({ width: 1, color: '#E5E7EB' })
      .borderRadius(14)
      .margin({ top: 8 })
    }
  }

  @Builder
  private usageResultPanel() {
    if (this.showUsageResult && this.vm.usageResult !== null) {
      Column() {
        Row() {
          Text('用量查询')
            .fontSize(13).fontWeight(FontWeight.Medium).fontColor('#0F172A')
          Blank().layoutWeight(1)
          Button('关闭')
            .height(24).fontSize(10).backgroundColor('#FFFFFF').fontColor('#64748B').borderRadius(8)
            .border({ width: 1, color: '#E5E7EB' })
            .onClick(() => { this.showUsageResult = false; })
        }
        .width('100%')

        if (this.vm.usageResult.success) {
          Text(`计划: ${this.vm.usageResult.planName}`).fontSize(11).fontColor('#334155').margin({ top: 8 })
          Text(`已用: ${this.vm.usageResult.usedAmount.toFixed(2)} / 总额: ${this.vm.usageResult.totalAmount.toFixed(2)} ${this.vm.usageResult.unit}`)
            .fontSize(11).fontColor('#334155').margin({ top: 4 })
          Text(`剩余: ${this.vm.usageResult.remainingAmount.toFixed(2)} ${this.vm.usageResult.unit}`)
            .fontSize(11).fontWeight(FontWeight.Medium).fontColor('#166534').margin({ top: 4 })
        } else {
          Text(this.vm.usageResult.errorMessage).fontSize(11).fontColor('#B91C1C').margin({ top: 8 })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding(12)
      .backgroundColor('#FFFFFF')
      .border({ width: 1, color: '#E5E7EB' })
      .borderRadius(14)
      .margin({ top: 8 })
    }
  }

  @Builder
  private exportDialog() {
    if (this.showExportDialog) {
      Column() {
        Row() {
          Text('导出 Provider 配置').fontSize(14).fontWeight(FontWeight.Medium).fontColor('#0F172A')
          Blank().layoutWeight(1)
          Button('关闭')
            .height(26).fontSize(10).backgroundColor('#FFFFFF').fontColor('#64748B').borderRadius(8)
            .border({ width: 1, color: '#E5E7EB' })
            .onClick(() => { this.showExportDialog = false; })
        }
        .width('100%')

        TextArea({ text: this.exportJson })
          .width('100%').height(200).margin({ top: 8 }).fontSize(10)
          .backgroundColor('#F8FAFC').borderRadius(10)
          .fontFamily('monospace')

        Text('已自动保护隐私数据。')
          .fontSize(10).fontColor('#94A3B8').margin({ top: 6 })
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding(14)
      .backgroundColor('#FFFFFF')
      .border({ width: 1, color: '#E2E8F0' })
      .borderRadius(16)
    }
  }

  @Builder
  private importDialog() {
    if (this.showImportDialog) {
      Column() {
        Row() {
          Text('导入 Provider 配置').fontSize(14).fontWeight(FontWeight.Medium).fontColor('#0F172A')
          Blank().layoutWeight(1)
          Button('关闭')
            .height(26).fontSize(10).backgroundColor('#FFFFFF').fontColor('#64748B').borderRadius(8)
            .border({ width: 1, color: '#E5E7EB' })
            .onClick(() => { this.showImportDialog = false; })
        }
        .width('100%')

        TextArea({ text: this.importJson, placeholder: '粘贴 JSON 配置...' })
          .width('100%').height(160).margin({ top: 8 }).fontSize(10)
          .backgroundColor('#FFFFFF').borderRadius(10)
          .border({ width: 1, color: '#E2E8F0' })
          .onChange((value: string) => { this.importJson = value; })

        Row() {
          Button('导入')
            .height(30).fontSize(11).backgroundColor('#111827').fontColor('#FFFFFF').borderRadius(12)
            .onClick(() => {
              if (this.importJson.trim().length > 0) {
                apiManagementVM.importProviders(this.importJson);
                this.showImportDialog = false;
                this.importJson = '';
              }
            })

          Button('取消')
            .height(30).fontSize(11).margin({ left: 8 })
            .backgroundColor('#FFFFFF').fontColor('#64748B').borderRadius(12)
            .border({ width: 1, color: '#CBD5E1' })
            .onClick(() => {
              this.showImportDialog = false;
              this.importJson = '';
            })
        }
        .width('100%').margin({ top: 10 })
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding(14)
      .backgroundColor('#FFFFFF')
      .border({ width: 1, color: '#E2E8F0' })
      .borderRadius(16)
    }
  }

  build() {
    Column() {
      if (this.vm.statusText.trim().length > 0) {
        Text(this.vm.statusText)
          .fontSize(11).fontColor('#334155').lineHeight(18).margin({ top: 4, bottom: 4 })
      }
      if (this.vm.errorText.trim().length > 0) {
        Text(this.vm.errorText)
          .fontSize(11).fontColor('#B91C1C').lineHeight(18).margin({ top: 4, bottom: 4 })
      }

      if (this.vm.validating) {
        Text('正在验证 API Key...')
          .fontSize(11).fontColor('#1D4ED8').margin({ bottom: 4 })
      }
      if (this.vm.speedTesting) {
        Text('正在进行端点测速...')
          .fontSize(11).fontColor('#1D4ED8').margin({ bottom: 4 })
      }
      if (this.vm.discoveringModels) {
        Text('正在获取模型列表...')
          .fontSize(11).fontColor('#1D4ED8').margin({ bottom: 4 })
      }

      this.addPresetDialog()
      this.validationResultPanel()
      this.speedResultsPanel()
      this.discoveredModelsPanel()
      this.usageResultPanel()
      this.exportDialog()
      this.importDialog()

      Row() {
        this.subTabChip('Provider 列表', 'providers')
        this.subTabChip('预设库', 'presets')
      }
      .width('100%')
      .margin({ top: 8 })

      if (this.activeSubTab === 'presets') {
        this.presetsPanel()
      } else {
        Column() {
          this.providersPanel()
          if (this.editorExpanded) {
            Column() {
              this.editorPanel()
            }
            .margin({ top: 10 })
          }
        }
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

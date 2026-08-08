import { BaiduMapView } from '../components/BaiduMapView';
import { SplashAdView } from '../components/SplashAdView';
import { NanjingTerritoryStore, TerritoryInfo } from '../model/TerritoryModel';
import { MapAgentBridge } from '../agent/MapAgentBridge';
import { MapAgentService } from '../agent/MapAgentService';
import { AgentProcessStep } from '../agent/MapAgentModels';
import { AuthSession, AuthSessionStore } from '../model/AuthSessionModel';
import { BackendApiService, AuthSessionDto } from '../service/BackendApiService';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { abilityAccessCtrl, common } from '@kit.AbilityKit';
import { speechRecognizer } from '@kit.CoreSpeechKit';
import { promptAction } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

const VOICE_LOG_DOMAIN: number = 0x0000;
const VOICE_LOG_TAG: string = 'MyDomaiVoice';
const VOICE_SESSION_ID: string = 'mydomai_voice_map';

enum AppTab {
  MAP = 0,
  TERRITORY = 1,
  RANKING = 2,
  TASK = 3,
  PROFILE = 4
}

@Entry
@Component
struct Index {
  @State activeTab: number = AppTab.MAP
  @State isRunning: boolean = false
  @State runSeconds: number = 0
  @State runDistance: number = 0
  @State totalDistance: number = 126.8
  @State territoryArea: number = NanjingTerritoryStore.getTotalArea()
  @State conqueredCount: number = 18
  @State runCount: number = 42
  @State experience: number = 680
  @State territoryNotice: string = ''
  @State rankingRegion: number = 2
  @State selectedTerritoryId: number = -1
  @State selectedRunPhoto: string = ''
  @State shareCaption: string = '今晚完成了一次 10 公里夜跑，顺便收下新的领地。'
  @State shareMessage: string = ''
  @State hasPublishedShare: boolean = false
  @State runDistanceText: string = '0.00'
  @State showSplashAd: boolean = true
  @State isListeningVoice: boolean = false
  @State voiceText: string = ''
  @State voiceHint: string = '按住说话：跑步指令或地图规划'
  @State isAgentThinking: boolean = false
  @State showAgentPanel: boolean = false
  @State agentSteps: Array<AgentProcessStep> = []
  @State showPrivacyPolicy: boolean = false
  @State showAboutApp: boolean = false
  @State isLoggedIn: boolean = false
  @State sessionUserId: string = ''
  @State sessionDisplayName: string = ''
  @State sessionDiamonds: number = 100
  @State sessionToken: string = ''
  @State authMode: string = 'login'
  @State authUsername: string = ''
  @State authPassword: string = ''
  @State authDisplayName: string = ''
  @State authMessage: string = ''
  @State authBusy: boolean = false

  private runTimer: number = -1
  private runTimerController: TextTimerController = new TextTimerController()
  private runTimerStarted: boolean = false
  private asrEngine: speechRecognizer.SpeechRecognitionEngine | null = null
  private hasMicrophonePermission: boolean = false
  private agentStepSeq: number = 1
  private tabItems: string[] = ['地图', '领地', '排行', '分享', '我的']
  private tabIcons: string[] = ['⌖', '◇', '♛', '□', '○']
  private rankNames: string[] = ['Mika', 'Alex', 'Tom', 'Luna', 'Noah']
  private rankAreas: string[] = ['42.83 km²', '31.56 km²', '6.72 km²', '5.98 km²', '5.21 km²']
  private territories: Array<TerritoryInfo> = NanjingTerritoryStore.getAll()

  aboutToAppear(): void {
    void this.restoreAuthSession()
  }

  aboutToDisappear(): void {
    this.stopRunTimer()
    this.runTimerController.pause()
    this.stopVoiceRecognition(true)
  }

  private async restoreAuthSession(): Promise<void> {
    try {
      const context = getContext(this) as common.UIAbilityContext
      const local = await AuthSessionStore.load(context)
      if (local === null) {
        this.clearSessionState()
        return
      }
      const remote = await BackendApiService.me(local.token)
      if (remote === null) {
        await AuthSessionStore.clear(context)
        this.clearSessionState()
        this.authMessage = '登录已失效，请重新登录'
        return
      }
      await this.applyAuthSession(remote)
    } catch (e) {
      hilog.warn(VOICE_LOG_DOMAIN, VOICE_LOG_TAG, 'restoreAuthSession failed %{public}s', JSON.stringify(e))
    }
  }

  private clearSessionState(): void {
    this.isLoggedIn = false
    this.sessionUserId = ''
    this.sessionDisplayName = ''
    this.sessionDiamonds = 100
    this.sessionToken = ''
  }

  private async applyAuthSession(session: AuthSessionDto): Promise<void> {
    const context = getContext(this) as common.UIAbilityContext
    const saved: AuthSession = {
      userId: session.userId,
      displayName: session.displayName,
      diamonds: session.diamonds,
      token: session.token,
      expiresAt: session.expiresAt
    }
    await AuthSessionStore.save(context, saved)
    this.isLoggedIn = true
    this.sessionUserId = session.userId
    this.sessionDisplayName = session.displayName
    this.sessionDiamonds = session.diamonds
    this.sessionToken = session.token
    this.authMessage = ''
    this.authPassword = ''
  }

  private async submitAuth(): Promise<void> {
    if (this.authBusy) {
      return
    }
    const username = this.authUsername.trim().toLowerCase()
    const password = this.authPassword
    if (username.length < 3) {
      this.authMessage = '用户名至少 3 位'
      return
    }
    if (password.length < 6) {
      this.authMessage = '密码至少 6 位'
      return
    }
    this.authBusy = true
    this.authMessage = this.authMode === 'register' ? '注册中…' : '登录中…'
    try {
      let session: AuthSessionDto | null = null
      if (this.authMode === 'register') {
        const display = this.authDisplayName.trim().length > 0 ? this.authDisplayName.trim() : username
        session = await BackendApiService.register(username, password, display)
      } else {
        session = await BackendApiService.login(username, password)
      }
      if (session === null) {
        this.authMessage = this.authMode === 'register' ? '注册失败（用户名可能已存在）' : '登录失败（用户名或密码错误）'
        return
      }
      await this.applyAuthSession(session)
      this.authMessage = this.authMode === 'register' ? '注册成功' : '登录成功'
      promptAction.showToast({ message: this.authMessage, duration: 2000 })
    } finally {
      this.authBusy = false
    }
  }

  private async logoutAuth(): Promise<void> {
    const token = this.sessionToken
    try {
      if (token.length > 0) {
        await BackendApiService.logout(token)
      }
    } catch (e) {
      // ignore network errors on logout
    }
    try {
      const context = getContext(this) as common.UIAbilityContext
      await AuthSessionStore.clear(context)
    } catch (e) {
      // ignore
    }
    this.clearSessionState()
    this.authMessage = '已退出登录'
    promptAction.showToast({ message: '已退出登录', duration: 2000 })
  }

  private startSimulatedRun(): void {
    this.stopRunTimer()
    this.runTimerController.pause()
    this.isRunning = true
    this.runSeconds = 0
    this.runDistance = 0
    this.runDistanceText = '0.00'
    this.territoryNotice = ''
    this.runTimerStarted = false
    this.runTimerController.reset()
    setTimeout(() => {
      if (this.isRunning) {
        this.runTimerController.start()
      }
    }, 50)
  }

  private stopRunTimer(): void {
    if (this.runTimer >= 0) {
      clearInterval(this.runTimer)
      this.runTimer = -1
    }
    this.runTimerController.pause()
  }

  private syncRunProgress(elapsedMs: number): void {
    const seconds = Math.floor(elapsedMs / 1000)
    if (seconds === this.runSeconds) {
      return
    }
    this.runSeconds = seconds
    this.runDistance = Number((seconds * 0.0023).toFixed(4))
    this.runDistanceText = this.runDistance.toFixed(2)
    if (!this.runTimerStarted) {
      this.runTimerStarted = true
      // #region agent log
      console.info(`[RunTimer] started elapsedMs=${elapsedMs}`)
      // #endregion
    }
  }

  private finishSimulatedRun(): void {
    this.stopRunTimer()
    this.isRunning = false
    const distance = Math.max(1.06, this.runDistance)
    const claimedArea = Math.max(0.18, Number((distance * 0.18).toFixed(2)))
    this.runDistance = distance
    this.totalDistance = Number((this.totalDistance + distance).toFixed(1))
    this.territoryArea = Number((this.territoryArea + claimedArea).toFixed(2))
    this.runCount += 1
    this.experience += 1250
    this.territoryNotice = `闭环完成，新增 ${claimedArea.toFixed(2)} km² 领地 · +1,250 XP`
  }

  private reclaimTerritory(): void {
    this.conqueredCount += 1
    this.territoryArea = Number((this.territoryArea + 0.12).toFixed(2))
    this.territoryNotice = '夺回成功 · 江南区防线已恢复'
  }

  private formatRunTime(): string {
    const hours = Math.floor(this.runSeconds / 3600)
    const minutes = Math.floor((this.runSeconds % 3600) / 60)
    const seconds = this.runSeconds % 60
    const pad2 = (value: number): string => {
      return value < 10 ? `0${value}` : `${value}`
    }
    if (hours > 0) {
      return `${pad2(hours)}:${pad2(minutes)}:${pad2(seconds)}`
    }
    return `${pad2(minutes)}:${pad2(seconds)}`
  }

  private openTerritoryOnMap(id: number): void {
    this.selectedTerritoryId = id
    this.activeTab = AppTab.MAP
  }

  private async pickRunPhoto(): Promise<void> {
    try {
      const picker = new photoAccessHelper.PhotoViewPicker()
      const options = new photoAccessHelper.PhotoSelectOptions()
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE
      options.maxSelectNumber = 1
      const result = await picker.select(options)
      if (result.photoUris.length > 0) {
        this.selectedRunPhoto = result.photoUris[0]
        this.shareMessage = '照片已添加，可以发布跑步记录了'
      }
    } catch (error) {
      this.shareMessage = '没有选择照片'
      console.error(`Pick running photo failed: ${JSON.stringify(error)}`)
    }
  }

  private publishRunShare(): void {
    if (this.selectedRunPhoto.length === 0) {
      this.shareMessage = '请先添加一张跑步照片'
      return
    }
    this.hasPublishedShare = true
    this.shareMessage = '跑步记录已发布到我的分享'
  }

  private async ensureMicrophonePermission(): Promise<boolean> {
    if (this.hasMicrophonePermission) {
      return true
    }
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      const permissionManager = abilityAccessCtrl.createAtManager()
      const result = await permissionManager.requestPermissionsFromUser(context, ['ohos.permission.MICROPHONE'])
      this.hasMicrophonePermission = result.authResults.every((status: number) => status === 0)
      if (!this.hasMicrophonePermission) {
        this.voiceHint = '需要麦克风权限才能语音识别'
        promptAction.showToast({ message: '请授权麦克风权限' })
      }
      return this.hasMicrophonePermission
    } catch (error) {
      this.voiceHint = '麦克风权限申请失败'
      console.error(`Request microphone permission failed: ${JSON.stringify(error)}`)
      return false
    }
  }

  private handleVoiceCommand(text: string): void {
    const normalized = text.replace(/\s+/g, '')
    if (normalized.includes('开始跑步') || normalized.includes('开始跑') ||
      (normalized.includes('出发') && !normalized.includes('资源') && !normalized.includes('区域'))) {
      if (!this.isRunning) {
        this.startSimulatedRun()
        this.voiceHint = '已识别：开始跑步'
        promptAction.showToast({ message: '语音指令：开始跑步' })
      }
      return
    }
    if (normalized.includes('完成圈地') || normalized.includes('结束跑步') || normalized.includes('停止跑步')) {
      if (this.isRunning) {
        this.finishSimulatedRun()
        this.voiceHint = '已识别：结束跑步'
        promptAction.showToast({ message: '语音指令：结束跑步' })
      }
      return
    }
    void this.runMapAgent(text)
  }

  private resetAgentProcess(): void {
    this.agentStepSeq = 1
    this.agentSteps = []
    this.showAgentPanel = true
  }

  private appendAgentStep(title: string, detail: string, status: string): void {
    // 同标题从 running → 最终态：原地更新，避免刷成两条重复步骤
    if (this.agentSteps.length > 0) {
      const last = this.agentSteps[this.agentSteps.length - 1]
      if (last.title === title && last.status === 'running' && status !== 'running') {
        const next: Array<AgentProcessStep> = []
        for (let i = 0; i < this.agentSteps.length; i++) {
          if (i === this.agentSteps.length - 1) {
            const updated: AgentProcessStep = {
              id: last.id,
              title: title,
              detail: detail,
              status: status
            }
            next.push(updated)
          } else {
            next.push(this.agentSteps[i])
          }
        }
        this.agentSteps = next
        this.showAgentPanel = true
        this.voiceHint = title
        return
      }
    }
    const next: Array<AgentProcessStep> = []
    for (let i = 0; i < this.agentSteps.length; i++) {
      const step = this.agentSteps[i]
      // 上一步若仍在执行，先标记为完成 ✅
      if (step.status === 'running') {
        const doneStep: AgentProcessStep = {
          id: step.id,
          title: step.title,
          detail: step.detail,
          status: 'done'
        }
        next.push(doneStep)
      } else {
        next.push(step)
      }
    }
    const created: AgentProcessStep = {
      id: this.agentStepSeq++,
      title: title,
      detail: detail,
      status: status
    }
    next.push(created)
    this.agentSteps = next
    this.showAgentPanel = true
    this.voiceHint = title
  }

  /** 将仍处于 running 的步骤全部收尾为 ✅ */
  private finalizeAgentSteps(): void {
    const next: Array<AgentProcessStep> = []
    let changed = false
    for (let i = 0; i < this.agentSteps.length; i++) {
      const step = this.agentSteps[i]
      if (step.status === 'running') {
        const doneStep: AgentProcessStep = {
          id: step.id,
          title: step.title,
          detail: step.detail,
          status: 'done'
        }
        next.push(doneStep)
        changed = true
      } else {
        next.push(step)
      }
    }
    if (changed) {
      this.agentSteps = next
    }
  }

  private agentStatusMark(status: string): string {
    if (status === 'running') {
      return '…'
    }
    if (status === 'done') {
      return '✅'
    }
    if (status === 'warn') {
      return '⚠️'
    }
    if (status === 'error') {
      return '❌'
    }
    return '·'
  }

  private agentStatusColor(status: string): string {
    if (status === 'running') {
      return '#D97706'
    }
    if (status === 'done') {
      return '#2DAB55'
    }
    if (status === 'warn') {
      return '#F59E0B'
    }
    if (status === 'error') {
      return '#EF5B5B'
    }
    return '#7A887F'
  }

  private closeAgentPanel(): void {
    if (this.isAgentThinking) {
      return
    }
    this.showAgentPanel = false
  }

  private async runMapAgent(userText: string): Promise<void> {
    if (this.isAgentThinking) {
      return
    }
    const context = MapAgentBridge.getContext()
    if (context === null) {
      this.resetAgentProcess()
      this.appendAgentStep('地图未就绪', '请稍后再试语音规划', 'error')
      this.voiceHint = '地图未就绪，请稍后再试'
      promptAction.showToast({ message: '地图未就绪' })
      return
    }
    this.isAgentThinking = true
    this.resetAgentProcess()
    this.appendAgentStep('开始执行', '语音指令已提交给地图 Agent', 'running')
    await new Promise<void>((resolve: () => void) => {
      setTimeout(() => {
        resolve()
      }, 800)
    })
    this.appendAgentStep('开始执行', '语音指令已提交给地图 Agent', 'done')
    try {
      hilog.info(VOICE_LOG_DOMAIN, VOICE_LOG_TAG, '[V] agent request text=%{public}s', userText)
      const plan = await MapAgentService.planFromVoice(
        userText,
        context,
        (title: string, detail: string, status: string): void => {
          this.appendAgentStep(title, detail, status)
        }
      )
      if (plan.action === 'none') {
        this.voiceHint = plan.reply
        promptAction.showToast({ message: plan.reply })
        return
      }
      // 仅在分析完成后绘制内置默认可探索区域 JSON（不用模型几何）
      this.appendAgentStep('绘制默认领地', '加载内置可探索区域 JSON', 'running')
      await new Promise<void>((resolve: () => void) => {
        setTimeout(() => {
          resolve()
        }, 900)
      })
      const applied = await MapAgentBridge.applyDefaultTerritory(plan.reply)
      if (applied) {
        this.appendAgentStep('绘制默认领地', '可探索区域已上图', 'done')
        await new Promise<void>((resolve: () => void) => {
          setTimeout(() => {
            resolve()
          }, 700)
        })
        this.appendAgentStep('执行完成', plan.reply, 'done')
        this.voiceHint = plan.reply
        promptAction.showToast({ message: '已显示默认可探索区域' })
      } else {
        this.appendAgentStep('绘制失败', '默认领地 JSON 未能上图', 'error')
        this.voiceHint = '默认领地显示失败'
        promptAction.showToast({ message: '默认领地显示失败' })
      }
    } catch (error) {
      this.appendAgentStep('执行失败', 'Agent 调用异常', 'error')
      this.voiceHint = 'Agent 调用失败'
      hilog.error(VOICE_LOG_DOMAIN, VOICE_LOG_TAG, '[V] agent failed %{public}s', JSON.stringify(error))
      promptAction.showToast({ message: 'Agent 调用失败' })
    } finally {
      this.finalizeAgentSteps()
      this.isAgentThinking = false
    }
  }

  private async startVoiceRecognition(): Promise<void> {
    if (!canIUse('SystemCapability.AI.SpeechRecognizer')) {
      this.voiceHint = '当前设备不支持语音识别'
      promptAction.showToast({ message: '设备不支持语音识别' })
      return
    }
    if (this.isListeningVoice) {
      return
    }
    const granted = await this.ensureMicrophonePermission()
    if (!granted) {
      return
    }
    try {
      this.stopVoiceRecognition(true)
      this.voiceText = ''
      this.voiceHint = '正在聆听...'
      this.isListeningVoice = true
      this.asrEngine = await speechRecognizer.createEngine({
        language: 'zh-CN',
        online: 1
      })
      const that = this
      this.asrEngine.setListener({
        onStart: (_sessionId: string, _eventMessage: string) => {
          that.voiceHint = '请说话...'
          // #region agent log
          hilog.info(VOICE_LOG_DOMAIN, VOICE_LOG_TAG, '[V] asr onStart')
          // #endregion
        },
        onEvent: (_sessionId: string, _eventCode: number, _eventMessage: string) => {
        },
        onResult: (_sessionId: string, result: speechRecognizer.SpeechRecognitionResult) => {
          that.voiceText = result.result
          // #region agent log
          hilog.info(VOICE_LOG_DOMAIN, VOICE_LOG_TAG, '[V] asr result last=%{public}s text=%{public}s',
            `${result.isLast}`, result.result)
          // #endregion
          if (result.isLast) {
            that.handleVoiceCommand(result.result)
            that.isListeningVoice = false
            that.releaseAsrEngine()
          }
        },
        onComplete: (_sessionId: string, _eventMessage: string) => {
          that.isListeningVoice = false
          if (that.voiceText.length === 0) {
            that.voiceHint = '未识别到内容，请再试一次'
          }
          that.releaseAsrEngine()
        },
        onError: (_sessionId: string, errorCode: number, errorMessage: string) => {
          that.isListeningVoice = false
          that.voiceHint = `识别失败(${errorCode})`
          that.releaseAsrEngine()
          // #region agent log
          hilog.error(VOICE_LOG_DOMAIN, VOICE_LOG_TAG, '[V] asr error %{public}d %{public}s', errorCode, errorMessage)
          // #endregion
        }
      })
      const recognizerParams: speechRecognizer.StartParams = {
        sessionId: VOICE_SESSION_ID,
        audioInfo: {
          audioType: 'pcm',
          sampleRate: 16000,
          soundChannel: 1,
          sampleBit: 16
        },
        extraParams: {
          'recognitionMode': 0,
          'vadBegin': 2000,
          'vadEnd': 3000,
          'maxAudioDuration': 20000
        } as Record<string, Object>
      }
      this.asrEngine.startListening(recognizerParams)
    } catch (error) {
      this.isListeningVoice = false
      this.voiceHint = '语音识别启动失败'
      console.error(`Start voice recognition failed: ${JSON.stringify(error)}`)
    }
  }

  private releaseAsrEngine(): void {
    if (this.asrEngine === null) {
      return
    }
    try {
      this.asrEngine.shutdown()
    } catch (_error) {
    }
    this.asrEngine = null
  }

  private finishVoiceRecognition(): void {
    if (this.asrEngine !== null) {
      try {
        this.asrEngine.finish(VOICE_SESSION_ID)
      } catch (_error) {
      }
    }
    if (this.voiceText.length === 0) {
      this.voiceHint = '识别完成，可再次按住说话'
    }
  }

  private stopVoiceRecognition(force: boolean = false): void {
    if (this.asrEngine !== null) {
      try {
        this.asrEngine.finish(VOICE_SESSION_ID)
      } catch (_error) {
      }
      if (force) {
        try {
          this.asrEngine.cancel(VOICE_SESSION_ID)
        } catch (_error) {
        }
        this.releaseAsrEngine()
      }
    }
    this.isListeningVoice = false
    if (this.voiceText.length === 0 && (this.voiceHint === '正在聆听...' || this.voiceHint === '请说话...')) {
      this.voiceHint = '按住说话：跑步指令或地图规划'
    }
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        this.pageContent()
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#F4F7F5')

      if (!this.showSplashAd) {
        this.bottomBar()
      }

      if (this.showSplashAd) {
        SplashAdView({ visible: $showSplashAd })
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  pageContent() {
    if (this.activeTab === AppTab.MAP) {
      this.mapPage()
    } else if (this.activeTab === AppTab.TERRITORY) {
      this.territoryPage()
    } else if (this.activeTab === AppTab.TASK) {
      this.sharePage()
    } else if (this.activeTab === AppTab.RANKING) {
      this.rankingPage()
    } else {
      this.profilePage()
    }
  }

  @Builder
  mapPage() {
    Stack({ alignContent: Alignment.Top }) {
      this.mapBackground()
      Column() {
        if (this.isRunning) {
          this.runningStats()
        } else {
          Blank().layoutWeight(1)
          if (this.showAgentPanel) {
            this.agentProcessPanel()
          }
          this.voiceControlBar()
          this.startRunButton()
        }
      }
      .width('100%')
      .height('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 92 })
      .hitTestBehavior(HitTestMode.Transparent)

      if (this.isRunning) {
        Column() {
          this.runMapBadge()
          Blank().layoutWeight(1)
          this.finishRunCard()
        }
        .width('100%')
        .height('100%')
        .padding({ left: 16, right: 16, top: 150, bottom: 92 })
        .hitTestBehavior(HitTestMode.Transparent)
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  mapBackground() {
    BaiduMapView({
      focusTerritoryId: this.selectedTerritoryId,
      sessionUserId: this.sessionUserId,
      sessionDisplayName: this.sessionDisplayName,
      sessionDiamonds: this.sessionDiamonds
    })
    .width('100%')
    .height('100%')
  }

  @Builder
  agentProcessPanel() {
    Column() {
      Row() {
        Column() {
          Text(this.isAgentThinking ? 'Agent 执行中' : 'Agent 执行过程')
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1E2D25')
          Text(this.isAgentThinking ? '正在规划地图轨迹…' : '可查看本次规划步骤')
            .fontSize(11)
            .fontColor('#7A887F')
            .margin({ top: 2 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        if (!this.isAgentThinking) {
          Text('关闭')
            .fontSize(12)
            .fontColor('#2DAB55')
            .padding({ left: 10, right: 4, top: 6, bottom: 6 })
            .onClick(() => {
              this.closeAgentPanel()
            })
        } else {
          Text('●')
            .fontSize(12)
            .fontColor('#D97706')
            .padding({ right: 4 })
        }
      }
      .width('100%')
      .padding({ left: 14, right: 10, top: 10, bottom: 6 })

      Scroll() {
        Column() {
          ForEach(this.agentSteps, (step: AgentProcessStep) => {
            Row() {
              Text(this.agentStatusMark(step.status))
                .width(22)
                .fontSize(step.status === 'done' || step.status === 'warn' || step.status === 'error' ? 13 : 12)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.agentStatusColor(step.status))
                .textAlign(TextAlign.Center)
              Column() {
                Text(step.title)
                  .fontSize(12)
                  .fontWeight(FontWeight.Medium)
                  .fontColor('#1E2D25')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                if (step.detail.length > 0) {
                  Text(step.detail)
                    .fontSize(11)
                    .fontColor('#7A887F')
                    .margin({ top: 2 })
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
              .margin({ left: 8 })
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
            .padding({ left: 14, right: 14, top: 6, bottom: 6 })
          }, (step: AgentProcessStep) => `${step.id}`)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .constraintSize({ maxHeight: 168 })
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
      .padding({ bottom: 8 })
    }
    .width('92%')
    .backgroundColor('#FFFFFFF5')
    .borderRadius(18)
    .border({ width: 1, color: this.isAgentThinking ? '#F59E0B55' : '#D7E1DC' })
    .shadow({ radius: 12, color: '#00000018', offsetX: 0, offsetY: 3 })
    .margin({ bottom: 10 })
    .hitTestBehavior(HitTestMode.Default)
  }

  @Builder
  voiceControlBar() {
    Column() {
      Row() {
        Column() {
          Text(this.isListeningVoice ? '正在聆听' : (this.isAgentThinking ? 'Agent 规划中' : '语音助手'))
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1E2D25')
          Text(this.voiceText.length > 0 ? this.voiceText : this.voiceHint)
            .fontSize(11)
            .fontColor(this.isListeningVoice || this.isAgentThinking ? '#2DAB55' : '#7A887F')
            .margin({ top: 4 })
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Column() {
          Text(this.isListeningVoice ? '●' : (this.isAgentThinking ? '…' : '🎤'))
            .fontSize(this.isListeningVoice || this.isAgentThinking ? 16 : 20)
            .fontColor(this.isListeningVoice ? '#EF5B5B' : (this.isAgentThinking ? '#D97706' : '#1E2D25'))
        }
        .width(48)
        .height(48)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.isListeningVoice ? '#FEE2E2' : (this.isAgentThinking ? '#FEF3C7' : '#F4F7F4'))
        .borderRadius(24)
        .border({
          width: this.isListeningVoice || this.isAgentThinking ? 2 : 1,
          color: this.isListeningVoice ? '#EF5B5B' : (this.isAgentThinking ? '#F59E0B' : '#D7E1DC')
        })
        .hitTestBehavior(HitTestMode.Default)
        .onTouch((event: TouchEvent) => {
          if (this.isAgentThinking) {
            return
          }
          if (event.type === TouchType.Down) {
            this.startVoiceRecognition()
          } else if (event.type === TouchType.Up) {
            this.finishVoiceRecognition()
          } else if (event.type === TouchType.Cancel) {
            this.stopVoiceRecognition(true)
          }
        })
      }
      .width('100%')
      .padding({ left: 14, right: 12, top: 10, bottom: 10 })
    }
    .width('86%')
    .backgroundColor('#FFFFFFF0')
    .borderRadius(18)
    .shadow({ radius: 10, color: '#00000018', offsetX: 0, offsetY: 2 })
    .margin({ bottom: 12 })
    .hitTestBehavior(HitTestMode.Default)
  }

  @Builder
  startRunButton() {
    Button('⌁  开始跑步')
      .fontSize(17)
      .fontWeight(FontWeight.Bold)
      .fontColor('#16231D')
      .backgroundColor('#FFD52C')
      .height(52)
      .width('58%')
      .borderRadius(26)
      .shadow({ radius: 12, color: '#A9971F55', offsetX: 0, offsetY: 5 })
      .onClick(() => {
        this.startSimulatedRun()
      })
      .margin({ bottom: 8 })
  }

  @Builder
  runningStats() {
    Row() {
      this.statCell(this.runDistanceText, '公里')
      Row().width(1).height(32).backgroundColor('#D7E1DC')
      this.runTimeStatCell()
      Row().width(1).height(32).backgroundColor('#D7E1DC')
      this.statCell(`${Math.round(this.runDistance * 68)}`, '消耗')
    }
    .width('100%')
    .height(70)
    .margin({ top: 14 })
    .backgroundColor('#FFFFFFEE')
    .borderRadius(16)
    .justifyContent(FlexAlign.SpaceEvenly)
  }

  @Builder
  runTimeStatCell() {
    Column() {
      TextTimer({ isCountDown: false, controller: this.runTimerController })
        .format('HH:mm:ss')
        .fontSize(19)
        .fontColor('#1E2824')
        .fontWeight(FontWeight.Medium)
        .onTimer((_utc: number, elapsedTime: number) => {
          this.syncRunProgress(elapsedTime)
        })
      Text('时间').fontSize(11).fontColor('#87938E').margin({ top: 4 })
    }
  }

  @Builder
  statCell(value: string, label: string) {
    Column() {
      Text(value).fontSize(19).fontColor('#1E2824').fontWeight(FontWeight.Medium)
      Text(label).fontSize(11).fontColor('#87938E').margin({ top: 4 })
    }
  }

  @Builder
  runMapBadge() {
    Text('●  正在记录轨迹')
      .fontSize(13)
      .fontColor('#FFFFFF')
      .padding({ left: 14, right: 14, top: 9, bottom: 9 })
      .backgroundColor('#35AF5B')
      .borderRadius(18)
      .margin({ top: 16 })
  }

  @Builder
  finishRunCard() {
    Column() {
      Text('跑步圈地预览').fontSize(16).fontWeight(FontWeight.Bold).fontColor('#1C2923')
      Row() {
        Column() { Text('可占领土地').fontSize(12).fontColor('#7E8B84'); Text(`${Math.max(0.18, this.runDistance * 0.18).toFixed(2)} km²`).fontSize(19).fontWeight(FontWeight.Bold).margin({ top: 4 }) }.alignItems(HorizontalAlign.Start)
        Blank().layoutWeight(1)
        Column() { Text('预计经验').fontSize(12).fontColor('#7E8B84'); Text('+1,250 XP').fontSize(17).fontColor('#E6A719').fontWeight(FontWeight.Bold).margin({ top: 4 }) }.alignItems(HorizontalAlign.End)
      }.width('100%').margin({ top: 16 })
      Text('路线形成闭环后，区域会染成你的颜色').fontSize(11).fontColor('#718079').margin({ top: 12 })
      Button('完成圈地').width('100%').height(44).backgroundColor('#37B75B').fontColor('#FFFFFF').fontSize(15).margin({ top: 14 }).onClick(() => { this.finishSimulatedRun() })
    }
    .width('100%')
    .padding(18)
    .backgroundColor('#FFFFFFF2')
    .borderRadius(18)
  }

  @Builder
  territoryPage() {
    Column() {
      this.simpleHeader('我的领地', `${this.territories.length} 块领地 · ${this.territoryArea.toFixed(2)} km²`)
      if (this.territoryNotice.length > 0) {
        Text(this.territoryNotice).fontSize(12).fontColor('#2D9850').padding({ left: 14, right: 14, top: 10, bottom: 10 }).backgroundColor('#E7F6EA').borderRadius(12).margin({ left: 16, right: 16, bottom: 10 })
      }
      Scroll() {
        Column() {
          ForEach(this.territories, (territory: TerritoryInfo) => {
            this.territoryCard(territory)
          })
          Row() {
            Column() { Text('⚔').fontSize(22).fontColor('#E09120') }.width(44).height(44).justifyContent(FlexAlign.Center).backgroundColor('#FFF5DA').borderRadius(14)
            Column() { Text('江南区正在被挑战').fontSize(14).fontWeight(FontWeight.Bold).fontColor('#29352F'); Text('有跑者进入你的领地 · 立即夺回').fontSize(11).fontColor('#7B877F').margin({ top: 4 }) }.alignItems(HorizontalAlign.Start).margin({ left: 10 })
            Blank()
            Button('夺回').fontSize(11).fontColor('#FFFFFF').backgroundColor('#E79B27').height(32).width(52).borderRadius(16).onClick(() => { this.reclaimTerritory() })
          }.width('100%').padding(12).backgroundColor('#FFFFFF').borderRadius(16).margin({ bottom: 12 })
          Button('⌁  开始跑步扩张').width('100%').height(48).backgroundColor('#FFD52C').fontColor('#1E2A22').fontWeight(FontWeight.Bold).margin({ top: 8, bottom: 110 }).onClick(() => { this.activeTab = AppTab.MAP; this.startSimulatedRun() })
        }.width('100%').padding({ left: 16, right: 16 })
      }.layoutWeight(1)
    }.width('100%').height('100%').padding({ top: 18 })
  }

  @Builder
  territoryCard(territory: TerritoryInfo) {
    Row() {
      Column() { Text('⌂').fontSize(26).fontColor(territory.borderColor) }.width(68).height(82).justifyContent(FlexAlign.Center).backgroundColor(territory.fillColor).borderRadius(16)
      Column() {
        Row() { Text(territory.name).fontSize(17).fontWeight(FontWeight.Bold).fontColor('#1F2C25'); Text(territory.level).fontSize(11).fontColor(territory.borderColor).margin({ left: 8 }) }.width('100%')
        Text(`${territory.areaKm2.toFixed(2)} km²`).fontSize(14).fontColor('#52605A').margin({ top: 8 })
        Text(territory.income).fontSize(12).fontColor('#35A757').margin({ top: 5 })
      }.alignItems(HorizontalAlign.Start).margin({ left: 14 })
      Blank()
      Text('›').fontSize(26).fontColor('#A5B0AA')
    }
    .width('100%').padding(14).backgroundColor('#FFFFFF').borderRadius(16).margin({ bottom: 12 })
    .onClick(() => {
      this.openTerritoryOnMap(territory.id)
    })
  }

  @Builder
  rankingPage() {
    Column() {
      this.simpleHeader('排行榜', '和附近跑者争夺城市版图')
      Row() {
        ForEach(['全球', '国家', '城市', '附近'], (label: string, index: number) => {
          Text(label).fontSize(12).fontColor(this.rankingRegion === index ? '#FFFFFF' : '#4D6256').width('25%').height(34).textAlign(TextAlign.Center).padding({ top: 9, bottom: 9 }).backgroundColor(this.rankingRegion === index ? '#35A95B' : '#EDF4EF').borderRadius(17).onClick(() => { this.rankingRegion = index })
        })
      }.width('100%').padding({ left: 16, right: 16 })
      Row() {
        Column() { Text('我的排名').fontSize(11).fontColor('#6E7D74'); Text('#128').fontSize(24).fontWeight(FontWeight.Bold).fontColor('#1F3027').margin({ top: 5 }) }.alignItems(HorizontalAlign.Start)
        Blank()
        Column() { Text('领地面积').fontSize(11).fontColor('#6E7D74'); Text(`${this.territoryArea.toFixed(2)} km²`).fontSize(17).fontWeight(FontWeight.Bold).fontColor('#2B9850').margin({ top: 7 }) }.alignItems(HorizontalAlign.End)
      }.width('100%').padding(18).backgroundColor('#FFFFFF').borderRadius(16).margin({ top: 16, left: 16, right: 16 })
      Column() {
        ForEach(this.rankNames, (name: string, index: number) => {
          Row() {
            Text(`${index + 1}`).fontSize(16).fontWeight(FontWeight.Bold).fontColor(index === 0 ? '#D69D18' : '#708078').width(30).textAlign(TextAlign.Center)
            Column() { Text(name).fontSize(15).fontWeight(FontWeight.Bold).fontColor('#26332C'); Text(index === 2 ? '我 · 领地成长中' : '城市跑者').fontSize(11).fontColor('#849088').margin({ top: 4 }) }.alignItems(HorizontalAlign.Start).margin({ left: 8 })
            Blank()
            Text(this.rankAreas[index]).fontSize(14).fontWeight(FontWeight.Bold).fontColor(index === 2 ? '#2F9D52' : '#33413A')
          }.width('100%').padding({ top: 14, bottom: 14 }).border({ width: { bottom: 1 }, color: '#ECF1ED' })
        })
      }.width('100%').padding({ left: 18, right: 18 }).backgroundColor('#FFFFFF').borderRadius(16).margin({ top: 12, left: 16, right: 16 })
      Blank().layoutWeight(1)
    }.width('100%').height('100%').padding({ top: 18, bottom: 80 })
  }

  @Builder
  sharePage() {
    Column() {
      this.simpleHeader('跑步分享', '记录今天的路线和心情')
      Scroll() {
        Column() {
          Column() {
            Row() {
              Text('分享你的跑步瞬间').fontSize(16).fontWeight(FontWeight.Bold).fontColor('#213028')
              Blank()
              Text('照片 + 跑步数据').fontSize(10).fontColor('#8A968E')
            }.width('100%')
            if (this.selectedRunPhoto.length > 0) {
              Image(this.selectedRunPhoto).width('100%').height(190).objectFit(ImageFit.Cover).borderRadius(14).margin({ top: 14 })
            } else {
              Column() {
                Text('＋').fontSize(34).fontColor('#35A95B')
                Text('添加跑步照片').fontSize(13).fontColor('#4B6B58').margin({ top: 6 })
                Text('从相册选择今天的跑步记录').fontSize(11).fontColor('#8A968E').margin({ top: 4 })
              }.width('100%').height(190).justifyContent(FlexAlign.Center).backgroundColor('#EDF7EF').borderRadius(14).margin({ top: 14 }).onClick(() => { this.pickRunPhoto() })
            }
            Button(this.selectedRunPhoto.length > 0 ? '更换照片' : '从相册选择').width('100%').height(38).fontSize(12).fontColor('#2A8F4B').backgroundColor('#EAF5EC').borderRadius(19).margin({ top: 10 }).onClick(() => { this.pickRunPhoto() })
            TextInput({ text: this.shareCaption, placeholder: '写下这次跑步的心情...' }).width('100%').height(58).fontSize(13).fontColor('#26332C').backgroundColor('#F7F9F7').borderRadius(12).margin({ top: 12 }).onChange((value: string) => { this.shareCaption = value })
            Row() {
              this.shareDataCell(`${this.runDistance > 0 ? this.runDistance.toFixed(2) : '10.00'}`, '公里')
              this.shareDataCell(this.runSeconds > 0 ? this.formatRunTime() : '01:02:18', '时间')
              this.shareDataCell(this.territoryArea.toFixed(2), '领地 km²')
            }.width('100%').justifyContent(FlexAlign.SpaceAround).padding({ top: 12, bottom: 12 }).margin({ top: 12 }).backgroundColor('#F9FBF9').borderRadius(12)
            if (this.shareMessage.length > 0) {
              Text(this.shareMessage).fontSize(11).fontColor('#319550').margin({ top: 10 })
            }
            Button('发布跑步记录').width('100%').height(44).fontSize(14).fontWeight(FontWeight.Bold).fontColor('#FFFFFF').backgroundColor('#35A95B').borderRadius(22).margin({ top: 12 }).onClick(() => { this.publishRunShare() })
          }.width('100%').padding(16).backgroundColor('#FFFFFF').borderRadius(18).margin({ bottom: 14 })
          if (this.hasPublishedShare) {
            Column() {
              Row() { Text('我的最新分享').fontSize(15).fontWeight(FontWeight.Bold).fontColor('#24332B'); Blank(); Text('刚刚').fontSize(11).fontColor('#8A968E') }.width('100%')
              Image(this.selectedRunPhoto).width('100%').height(160).objectFit(ImageFit.Cover).borderRadius(14).margin({ top: 12 })
              Text(this.shareCaption).fontSize(13).fontColor('#34423A').margin({ top: 10 })
              Row() { Text('⌁ 10.00 km').fontSize(11).fontColor('#2F9851'); Text('· 领地 +0.42 km²').fontSize(11).fontColor('#75837A').margin({ left: 8 }); Blank(); Text('♡ 0').fontSize(12).fontColor('#8A968E') }.width('100%').margin({ top: 10 })
            }.width('100%').padding(16).backgroundColor('#FFFFFF').borderRadius(18).margin({ bottom: 110 })
          } else {
            Text('发布后，你的跑步照片和路线摘要会出现在这里').fontSize(11).fontColor('#8A968E').margin({ top: 8, bottom: 110 })
          }
        }.width('100%').padding({ left: 16, right: 16 })
      }.layoutWeight(1)
    }.width('100%').height('100%').padding({ top: 18, bottom: 80 })
  }

  @Builder
  shareDataCell(value: string, label: string) {
    Column() {
      Text(value).fontSize(15).fontWeight(FontWeight.Bold).fontColor('#26352C')
      Text(label).fontSize(10).fontColor('#849088').margin({ top: 4 })
    }
  }

  @Builder
  listPage(title: string, names: string[], values: string[]) {
    Column() {
      this.simpleHeader(title, 'KYRO NEXT')
      Column() {
        ForEach(names, (name: string, index: number) => {
          Row() {
            Column() { Text(index === 0 ? '✦' : index === 1 ? '◉' : '◇').fontSize(20).fontColor(index === 0 ? '#F2B52A' : '#35AE61') }.width(44).height(44).justifyContent(FlexAlign.Center).backgroundColor('#F1F6F2').borderRadius(14)
            Text(name).fontSize(15).fontColor('#28332E').margin({ left: 14 })
            Blank()
            Text(values[index]).fontSize(15).fontWeight(FontWeight.Bold).fontColor('#2E9A50')
          }.width('100%').padding(14).backgroundColor('#FFFFFF').borderRadius(15).margin({ bottom: 10 })
        })
      }.width('100%').padding(16)
      Blank().layoutWeight(1)
    }.width('100%').height('100%').padding({ top: 18, bottom: 80 })
  }

  @Builder
  profilePage() {
    Stack({ alignContent: Alignment.Center }) {
      Column() {
        this.simpleHeader('我的', this.isLoggedIn ? '已登录' : '登录后同步领地与调试身份')
        Column() {
          if (this.isLoggedIn) {
            this.profileLoggedInCard()
          } else {
            this.profileAuthCard()
          }

          if (this.isLoggedIn) {
            GridRow({ columns: 2 }) {
              GridCol() {
                this.profileMetric('累计跑步', `${this.totalDistance.toFixed(1)} km`, '#2C9550')
              }
              GridCol() {
                this.profileMetric('已占领领地', `${this.territoryArea.toFixed(2)} km²`, '#2C9550')
              }
              GridCol() {
                this.profileMetric('夺取数量', `${this.conqueredCount} 次`, '#E39A1F')
              }
              GridCol() {
                this.profileMetric('跑步次数', `${this.runCount} 次`, '#536D9D')
              }
            }.width('100%').margin({ top: 12 })
          }

          Column() {
            Row() {
              Column() {
                Text('隐私政策').fontSize(15).fontWeight(FontWeight.Medium).fontColor('#28332E')
                Text('了解我们如何收集与保护你的信息').fontSize(11).fontColor('#8A968E').margin({ top: 4 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Text('›').fontSize(22).fontColor('#A0ABA4')
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 16, bottom: 16 })
            .border({ width: { bottom: 1 }, color: '#EEF2ED' })
            .onClick(() => {
              this.showPrivacyPolicy = true
            })
            Row() {
              Column() {
                Text('关于 App').fontSize(15).fontWeight(FontWeight.Medium).fontColor('#28332E')
                Text('版本、功能介绍与联系方式').fontSize(11).fontColor('#8A968E').margin({ top: 4 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Text('›').fontSize(22).fontColor('#A0ABA4')
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 16, bottom: 16 })
            .onClick(() => {
              this.showAboutApp = true
            })
          }
          .width('100%')
          .margin({ top: 8 })
          .backgroundColor('#FFFFFF')
          .borderRadius(16)
          .padding({ left: 4, right: 4 })
        }.width('100%').padding(16)
        Blank().layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .padding({ top: 18, bottom: 80 })

      if (this.showPrivacyPolicy) {
        this.privacyPolicyDialog()
      }
      if (this.showAboutApp) {
        this.aboutAppDialog()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  profileLoggedInCard() {
    Column() {
      Row() {
        Column() {
          Text(this.sessionDisplayName.length > 0
            ? this.sessionDisplayName.substring(0, 1).toUpperCase()
            : 'U')
            .fontSize(27)
            .fontColor('#FFFFFF')
        }
        .width(58)
        .height(58)
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#35A95B')
        .borderRadius(29)
        Column() {
          Text(this.sessionDisplayName).fontSize(21).fontWeight(FontWeight.Bold).fontColor('#1E2D25')
          Text(`@${this.sessionUserId}`).fontSize(13).fontColor('#77837D').margin({ top: 5 })
          Text(`钻石 ${this.sessionDiamonds}💎`).fontSize(12).fontColor('#B88417').margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 14 })
        Blank()
      }
      .width('100%')
      Text('该账号即地图调试 / 圈地同步使用的当前用户')
        .fontSize(11)
        .fontColor('#7A887F')
        .width('100%')
        .margin({ top: 12 })
      Button('退出登录')
        .width('100%')
        .height(40)
        .fontSize(14)
        .fontColor('#B91C1C')
        .backgroundColor('#FEE2E2')
        .borderRadius(12)
        .margin({ top: 14 })
        .onClick(() => {
          void this.logoutAuth()
        })
    }
    .width('100%')
    .padding(18)
    .backgroundColor('#FFFFFF')
    .borderRadius(18)
  }

  @Builder
  profileAuthCard() {
    Column() {
      Row() {
        Button('登录')
          .layoutWeight(1)
          .height(34)
          .fontSize(13)
          .fontColor(this.authMode === 'login' ? '#FFFFFF' : '#166534')
          .backgroundColor(this.authMode === 'login' ? '#35A95B' : '#EAF5EC')
          .borderRadius(10)
          .onClick(() => {
            this.authMode = 'login'
            this.authMessage = ''
          })
        Button('注册')
          .layoutWeight(1)
          .height(34)
          .fontSize(13)
          .fontColor(this.authMode === 'register' ? '#FFFFFF' : '#1D4ED8')
          .backgroundColor(this.authMode === 'register' ? '#3B82F6' : '#EEF5FF')
          .borderRadius(10)
          .margin({ left: 8 })
          .onClick(() => {
            this.authMode = 'register'
            this.authMessage = ''
          })
      }.width('100%')

      Text('用户名')
        .fontSize(12)
        .fontColor('#4B5563')
        .width('100%')
        .margin({ top: 14 })
      TextInput({ text: this.authUsername, placeholder: '3-32 位字母数字或下划线' })
        .height(40)
        .fontSize(14)
        .backgroundColor('#F4F7F4')
        .borderRadius(10)
        .margin({ top: 6 })
        .onChange((value: string) => {
          this.authUsername = value
        })

      if (this.authMode === 'register') {
        Text('昵称（可选）')
          .fontSize(12)
          .fontColor('#4B5563')
          .width('100%')
          .margin({ top: 10 })
        TextInput({ text: this.authDisplayName, placeholder: '显示名称' })
          .height(40)
          .fontSize(14)
          .backgroundColor('#F4F7F4')
          .borderRadius(10)
          .margin({ top: 6 })
          .onChange((value: string) => {
            this.authDisplayName = value
          })
      }

      Text('密码')
        .fontSize(12)
        .fontColor('#4B5563')
        .width('100%')
        .margin({ top: 10 })
      TextInput({ text: this.authPassword, placeholder: '至少 6 位' })
        .height(40)
        .fontSize(14)
        .backgroundColor('#F4F7F4')
        .borderRadius(10)
        .margin({ top: 6 })
        .type(InputType.Password)
        .onChange((value: string) => {
          this.authPassword = value
        })

      if (this.authMessage.length > 0) {
        Text(this.authMessage)
          .fontSize(12)
          .fontColor('#B45309')
          .width('100%')
          .margin({ top: 10 })
      }

      Button(this.authBusy ? '请稍候…' : (this.authMode === 'register' ? '注册并登录' : '登录'))
        .width('100%')
        .height(42)
        .fontSize(15)
        .fontColor('#FFFFFF')
        .backgroundColor(this.authMode === 'register' ? '#3B82F6' : '#35A95B')
        .borderRadius(12)
        .margin({ top: 14 })
        .enabled(!this.authBusy)
        .onClick(() => {
          void this.submitAuth()
        })
    }
    .width('100%')
    .padding(18)
    .backgroundColor('#FFFFFF')
    .borderRadius(18)
  }

  private privacyPolicyBody(): string {
    return [
      '生效日期：2026年7月31日',
      '更新日期：2026年7月31日',
      '',
      '欢迎使用「我的领地 / MyDomai」。我们重视你的隐私，并按照本政策说明如何收集、使用与保护相关信息。',
      '',
      '一、我们收集的信息',
      '1. 位置信息：用于在地图上展示你的跑步轨迹、生成闭环领地，以及判断与资源、陷阱的相对位置。仅在你授权定位权限后采集。',
      '2. 麦克风信息：仅在你使用语音识别功能时，用于识别跑步指令或地图规划语音，不会在后台持续录音。',
      '3. 相册/图片：仅在你主动选择图片时（如分享跑步照片、闭环广告图片），用于本地展示与相关功能。',
      '4. 设备与日志信息：可能包括设备型号、系统版本、崩溃日志，用于保障服务稳定与排查问题。',
      '',
      '二、信息如何使用',
      '1. 提供地图、圈地、资源与陷阱等核心玩法；',
      '2. 完成语音指令与地图 Agent 规划；',
      '3. 改进产品体验、排查故障与保障安全；',
      '4. 未经你的同意，我们不会将个人信息出售给第三方。',
      '',
      '三、信息存储与保护',
      '位置轨迹、领地数据与广告图片等主要保存在本机；涉及云端大模型请求时，仅会发送完成任务所需的最小上下文（如位置摘要、资源摘要），不上传无关相册内容。我们采取合理安全措施防止未经授权的访问。',
      '',
      '四、你的权利',
      '你可以在系统设置中撤回定位、麦克风、相册等权限；撤回后相关功能将不可用。你也可以删除本机保存的领地与物品数据。',
      '',
      '五、未成年人保护',
      '若你为未成年人，请在监护人指导下使用本应用，并确认监护人同意本政策。',
      '',
      '六、政策更新',
      '我们可能适时更新本政策，更新后将在应用内公示。继续使用即表示你了解更新后的内容。',
      '',
      '七、联系我们',
      '如对本政策有疑问，可通过应用内「关于 App」中的联系方式与我们沟通。'
    ].join('\n')
  }

  private aboutAppBody(): string {
    return [
      '我的领地（MyDomai）',
      '版本：1.0.0',
      '包名：com.example.mydomain',
      '',
      '产品简介',
      'MyDomai 是一款结合真实地图的跑步圈地游戏。你可以通过跑步轨迹围合闭环，占领领地；在领地内放置资源与陷阱；也可以通过语音与地图 Agent 规划可探索区域。',
      '',
      '主要功能',
      '· 地图定位与跑步轨迹绘制',
      '· 闭环领地生成、编辑与占领',
      '· 资源投放、陷阱互动与钻石结算',
      '· 语音指令（开始/结束跑步）与地图 Agent 规划',
      '· 闭环广告（图片 + 口号）展示',
      '· 领地分享与个人数据概览',
      '',
      '开发说明',
      '本应用基于 HarmonyOS 构建，地图能力由百度地图 SDK 提供。调试面板中的摇杆、双用户等功能用于开发与演示，正式体验以实际跑步与地图互动为准。',
      '',
      '开源与第三方',
      '· 百度地图 HarmonyOS SDK',
      '· 系统语音识别能力（设备支持时）',
      '· DeepSeek 大模型接口（用于地图 Agent，需网络）',
      '',
      '联系与反馈',
      '邮箱：support@mydomai.example',
      '反馈建议：欢迎在「分享」页记录跑步故事，或通过应用商店评价告诉我们你的想法。',
      '',
      '版权信息',
      '© 2026 MyDomai. All rights reserved.',
      '应用内品牌 Logo 预设仅为风格化演示素材，不代表官方授权商标使用。'
    ].join('\n')
  }

  @Builder
  privacyPolicyDialog() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#00000055')
        .onClick(() => {
          this.showPrivacyPolicy = false
        })
      Column() {
        Row() {
          Text('隐私政策').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#1E2D25')
          Blank()
          Text('✕').fontSize(16).fontColor('#8A9790').onClick(() => {
            this.showPrivacyPolicy = false
          })
        }.width('100%')
        Scroll() {
          Text(this.privacyPolicyBody())
            .fontSize(13)
            .fontColor('#3F4A44')
            .lineHeight(22)
            .width('100%')
        }
        .width('100%')
        .layoutWeight(1)
        .margin({ top: 12 })
        .scrollBar(BarState.Auto)
        Button('我知道了')
          .width('100%')
          .height(42)
          .fontSize(14)
          .fontColor('#FFFFFF')
          .backgroundColor('#37B75B')
          .margin({ top: 14 })
          .onClick(() => {
            this.showPrivacyPolicy = false
          })
      }
      .width('88%')
      .height('72%')
      .padding(18)
      .backgroundColor('#FFFFFFFA')
      .borderRadius(16)
      .shadow({ radius: 12, color: '#00000022', offsetX: 0, offsetY: 2 })
      .hitTestBehavior(HitTestMode.Default)
    }
    .width('100%')
    .height('100%')
    .zIndex(300)
  }

  @Builder
  aboutAppDialog() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#00000055')
        .onClick(() => {
          this.showAboutApp = false
        })
      Column() {
        Row() {
          Text('关于 App').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#1E2D25')
          Blank()
          Text('✕').fontSize(16).fontColor('#8A9790').onClick(() => {
            this.showAboutApp = false
          })
        }.width('100%')
        Scroll() {
          Text(this.aboutAppBody())
            .fontSize(13)
            .fontColor('#3F4A44')
            .lineHeight(22)
            .width('100%')
        }
        .width('100%')
        .layoutWeight(1)
        .margin({ top: 12 })
        .scrollBar(BarState.Auto)
        Button('我知道了')
          .width('100%')
          .height(42)
          .fontSize(14)
          .fontColor('#FFFFFF')
          .backgroundColor('#37B75B')
          .margin({ top: 14 })
          .onClick(() => {
            this.showAboutApp = false
          })
      }
      .width('88%')
      .height('72%')
      .padding(18)
      .backgroundColor('#FFFFFFFA')
      .borderRadius(16)
      .shadow({ radius: 12, color: '#00000022', offsetX: 0, offsetY: 2 })
      .hitTestBehavior(HitTestMode.Default)
    }
    .width('100%')
    .height('100%')
    .zIndex(300)
  }

  @Builder
  profileRow(label: string, value: string) {
    Row() {
      Text(label).fontSize(15).fontColor('#53605A')
      Blank()
      Text(value).fontSize(15).fontWeight(FontWeight.Medium).fontColor('#28332E')
    }
    .width('100%')
    .padding({ left: 6, right: 6, top: 18, bottom: 18 })
    .border({ width: { bottom: 1 }, color: '#E5ECE8' })
  }

  @Builder
  profileMetric(label: string, value: string, color: string) { Column() { Text(value).fontSize(18).fontWeight(FontWeight.Bold).fontColor(color); Text(label).fontSize(11).fontColor('#7B887F').margin({ top: 5 }) }.width('100%').padding({ top: 14, bottom: 14 }).backgroundColor('#FFFFFF').borderRadius(14) }

  @Builder
  simpleHeader(title: string, subtitle: string) { Row() { Column() { Text(title).fontSize(26).fontWeight(FontWeight.Bold).fontColor('#18231E'); Text(subtitle).fontSize(12).fontColor('#819089').margin({ top: 5 }) }.alignItems(HorizontalAlign.Start); Blank(); Text('⋯').fontSize(28).fontColor('#4B5952') }.width('100%').padding({ left: 20, right: 20, bottom: 18 }) }

  @Builder
  bottomBar() {
    Row() {
      ForEach(this.tabItems, (label: string, index: number) => {
        Column() {
          Text(this.tabIcons[index]).fontSize(22).fontColor(this.activeTab === index ? '#35A956' : '#7F8B85')
          Text(label).fontSize(10).fontColor(this.activeTab === index ? '#249647' : '#7F8B85').margin({ top: 3 })
        }.width('20%').height(58).justifyContent(FlexAlign.Center).onClick(() => { this.activeTab = index })
      })
    }
    .width('100%').height(74).padding({ top: 6, bottom: 10 }).backgroundColor('#FFFFFFF5').border({ width: { top: 1 }, color: '#E1EAE4' })
  }
}

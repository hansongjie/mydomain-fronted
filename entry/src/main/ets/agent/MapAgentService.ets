import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DeepSeekConfig } from '../config/DeepSeekConfig';
import {
  AgentMapContext,
  AgentPlanResult,
  AgentPoiPoint,
  AgentProgressReporter,
  AgentResourceCluster,
  AgentResourcePoint,
  AgentTrapPoint
} from './MapAgentModels';
import { RoadNetworkService } from './RoadNetworkService';
import { RoadSegment } from './RoadNetworkModels';

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'MyDomaiAgent';
const MAX_PROMPT_RESOURCES: number = 60;
const MAX_PROMPT_TRAPS: number = 40;
const MAX_PROMPT_POIS: number = 40;
const CLUSTER_RADIUS_M: number = 380;
/** 主步骤展示时长，避免瞬间刷完 */
const STEP_PACE_MS: number = 900;
/** 子清单（最近资源/陷阱等）稍短一点 */
const SUB_STEP_PACE_MS: number = 700;

interface ChatMessage {
  role: string;
  content: string;
}

interface JsonObjectFormat {
  type: string;
}

interface ThinkingOption {
  type: string;
}

interface ChatCompletionRequest {
  model: string;
  messages: Array<ChatMessage>;
  temperature: number;
  response_format: JsonObjectFormat;
  thinking: ThinkingOption;
}

export interface AgentConnectivityResult {
  ok: boolean;
  message: string;
  latencyMs: number;
}

export class MapAgentService {
  private static lastConnectivityOkAtMs: number = 0;
  private static lastConnectivityMessage: string = '';

  /** Sort resources/traps/pois, attach distances, and build density clusters for the LLM. */
  static enrichContext(context: AgentMapContext): AgentMapContext {
    const resources: Array<AgentResourcePoint> = [];
    let worldCount = 0;
    let territoryCount = 0;
    for (let i = 0; i < context.resources.length; i++) {
      const item = context.resources[i];
      const distance = MapAgentService.distanceMeters(
        context.userLat, context.userLng, item.lat, item.lng);
      const scope = item.scope.length > 0 ? item.scope :
        (item.loopId === 0 ? 'world' : 'territory');
      if (scope === 'world') {
        worldCount++;
      } else {
        territoryCount++;
      }
      const enriched: AgentResourcePoint = {
        id: item.id,
        typeId: item.typeId,
        name: item.name,
        icon: item.icon,
        lat: item.lat,
        lng: item.lng,
        scope: scope,
        loopId: item.loopId,
        distanceMeters: Math.round(distance)
      };
      resources.push(enriched);
    }
    resources.sort((a: AgentResourcePoint, b: AgentResourcePoint) => {
      return a.distanceMeters - b.distanceMeters;
    });

    const traps: Array<AgentTrapPoint> = [];
    for (let i = 0; i < context.traps.length; i++) {
      const item = context.traps[i];
      const distance = MapAgentService.distanceMeters(
        context.userLat, context.userLng, item.lat, item.lng);
      const trap: AgentTrapPoint = {
        id: item.id,
        lat: item.lat,
        lng: item.lng,
        ownerId: item.ownerId,
        diamondCost: item.diamondCost,
        distanceMeters: Math.round(distance),
        loopId: item.loopId
      };
      traps.push(trap);
    }
    traps.sort((a: AgentTrapPoint, b: AgentTrapPoint) => {
      return a.distanceMeters - b.distanceMeters;
    });

    const pois: Array<AgentPoiPoint> = [];
    for (let i = 0; i < context.pois.length; i++) {
      const item = context.pois[i];
      const distance = MapAgentService.distanceMeters(
        context.userLat, context.userLng, item.lat, item.lng);
      const poi: AgentPoiPoint = {
        id: item.id,
        name: item.name,
        kind: item.kind,
        lat: item.lat,
        lng: item.lng,
        distanceMeters: Math.round(distance)
      };
      pois.push(poi);
    }
    pois.sort((a: AgentPoiPoint, b: AgentPoiPoint) => {
      return a.distanceMeters - b.distanceMeters;
    });

    const clusters = MapAgentService.buildClusters(resources, context.userLat, context.userLng);
    return {
      userLat: context.userLat,
      userLng: context.userLng,
      resources: resources,
      traps: traps,
      pois: pois,
      clusters: clusters,
      loops: context.loops,
      worldResourceCount: worldCount,
      territoryItemCount: territoryCount,
      trapCount: traps.length,
      poiCount: pois.length,
      roadPromptText: context.roadPromptText,
      roadCount: context.roadCount
    };
  }

  static async testConnectivity(force: boolean = false): Promise<AgentConnectivityResult> {
    const now = Date.now();
    if (!force && MapAgentService.lastConnectivityOkAtMs > 0 &&
      now - MapAgentService.lastConnectivityOkAtMs < 120000) {
      return {
        ok: true,
        message: `${MapAgentService.lastConnectivityMessage}（缓存）`,
        latencyMs: 0
      };
    }
    const started = now;
    const messages: Array<ChatMessage> = [
      { role: 'system', content: 'Reply with JSON only.' },
      { role: 'user', content: '{"ping":true} 请原样返回 {"ok":true,"echo":"mydomai"}' }
    ];
    const responseFormat: JsonObjectFormat = { type: 'json_object' };
    const thinkingOption: ThinkingOption = { type: 'disabled' };
    const requestBody: ChatCompletionRequest = {
      model: DeepSeekConfig.MODEL,
      messages: messages,
      temperature: 0,
      response_format: responseFormat,
      thinking: thinkingOption
    };
    const request = http.createHttp();
    try {
      const response = await request.request(`${DeepSeekConfig.BASE_URL}${DeepSeekConfig.CHAT_PATH}`, {
        method: http.RequestMethod.POST,
        header: MapAgentService.buildAuthHeaders(),
        extraData: JSON.stringify(requestBody),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 15000
      });
      const latencyMs = Date.now() - started;
      if (response.responseCode < 200 || response.responseCode >= 300) {
        return {
          ok: false,
          message: `HTTP ${response.responseCode}`,
          latencyMs: latencyMs
        };
      }
      const raw = `${response.result}`;
      const ok = raw.indexOf('ok') >= 0 || raw.indexOf('mydomai') >= 0 || raw.length > 20;
      const message = ok ? `DeepSeek 已连通 · ${DeepSeekConfig.MODEL}` : '响应异常';
      if (ok) {
        MapAgentService.lastConnectivityOkAtMs = Date.now();
        MapAgentService.lastConnectivityMessage = message;
      }
      return {
        ok: ok,
        message: message,
        latencyMs: latencyMs
      };
    } catch (error) {
      return {
        ok: false,
        message: `网络异常 ${JSON.stringify(error)}`,
        latencyMs: Date.now() - started
      };
    } finally {
      request.destroy();
    }
  }

  private static sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(() => {
        resolve();
      }, ms);
    });
  }

  /** 先展示 running，停顿后再以最终状态收尾，便于看清每一步 */
  private static async pacedReport(
    onProgress: AgentProgressReporter | undefined,
    title: string,
    detail: string,
    finalStatus: string,
    paceMs: number = STEP_PACE_MS
  ): Promise<void> {
    if (onProgress !== undefined) {
      await Promise.resolve(onProgress(title, detail, 'running'));
    }
    await MapAgentService.sleep(paceMs);
    if (onProgress !== undefined && finalStatus !== 'running') {
      await Promise.resolve(onProgress(title, detail, finalStatus));
    }
  }

  /**
   * Step-by-step: perceive env → roads → DeepSeek analysis → return Chinese reply.
   * Final drawing of built-in territory JSON is done by the UI layer, not here.
   */
  static async planFromVoice(
    userText: string,
    rawContext: AgentMapContext,
    onProgress?: AgentProgressReporter
  ): Promise<AgentPlanResult> {
    const report = async (title: string, detail: string, status: string): Promise<void> => {
      await MapAgentService.pacedReport(onProgress, title, detail, status, STEP_PACE_MS);
    };
    const reportSub = async (title: string, detail: string, status: string): Promise<void> => {
      await MapAgentService.pacedReport(onProgress, title, detail, status, SUB_STEP_PACE_MS);
    };

    const trimmed = userText.trim();
    if (trimmed.length === 0) {
      await report('识别为空', '没有识别到有效语音内容', 'error');
      return MapAgentService.emptyPlan('没有识别到有效语音内容');
    }

    await report('理解需求', `「${trimmed}」`, 'done');

    let context = MapAgentService.enrichContext(rawContext);
    await report('感知地图资源',
      `共 ${context.resources.length} 个 · 世界 ${context.worldResourceCount} · 领地物品 ${context.territoryItemCount}`,
      'done');
    await MapAgentService.reportResourceSnapshot(context, reportSub);

    await report('感知陷阱',
      context.trapCount > 0
        ? `附近陷阱 ${context.trapCount} 个（按距离排序）`
        : '地图上暂无已放置陷阱',
      context.trapCount > 0 ? 'done' : 'warn');
    await MapAgentService.reportTrapSnapshot(context, reportSub);

    await report('感知 POI / 领地',
      `闭环 ${context.loops.length} · POI ${context.poiCount}`,
      'done');
    await MapAgentService.reportPoiSnapshot(context, reportSub);

    await report('加载道路网络', '从 OpenStreetMap 拉取安德门附近可跑步道路', 'running');
    const roads: Array<RoadSegment> =
      await RoadNetworkService.fetchWalkableRoads(context.userLat, context.userLng, 700);
    context = {
      userLat: context.userLat,
      userLng: context.userLng,
      resources: context.resources,
      traps: context.traps,
      pois: context.pois,
      clusters: context.clusters,
      loops: context.loops,
      worldResourceCount: context.worldResourceCount,
      territoryItemCount: context.territoryItemCount,
      trapCount: context.trapCount,
      poiCount: context.poiCount,
      roadPromptText: RoadNetworkService.formatRoadsForPrompt(roads),
      roadCount: roads.length
    };
    if (roads.length === 0) {
      await report('道路数据不足', '未获取到可跑步道路，仍继续分析（最终仍画默认领地）', 'warn');
    } else {
      await report('道路已就绪', `可跑步道路 ${roads.length} 条 · 供模型理解通行约束`, 'done');
    }

    let reply = '';
    let source = 'local';
    try {
      // 网络请求本身耗时；此处只短暂停顿让 UI 先进入「调用中」
      if (onProgress !== undefined) {
        await Promise.resolve(onProgress('调用 DeepSeek',
          `模型 ${DeepSeekConfig.MODEL} · 分析资源/道路/POI/陷阱`, 'running'));
      }
      await MapAgentService.sleep(500);
      const remote = await MapAgentService.callDeepSeek(trimmed, context, onProgress);
      if (remote !== null && remote.reply.trim().length > 0) {
        reply = remote.reply.trim();
        source = 'deepseek';
        await report('模型分析完成', reply, 'done');
      } else {
        reply = MapAgentService.synthesizeLocalReply(trimmed, context);
        source = 'local';
        await report('本地分析兜底', reply, 'warn');
      }
    } catch (error) {
      const errText = MapAgentService.stringifyError(error);
      hilog.error(LOG_DOMAIN, LOG_TAG, '[Agent] deepseek failed %{public}s', errText);
      await report('DeepSeek 失败', errText, 'warn');
      reply = MapAgentService.synthesizeLocalReply(trimmed, context);
      source = 'local';
      await report('本地分析兜底', reply, 'warn');
    }

    await report('准备默认领地', '分析完成，下一步绘制内置可探索区域 JSON', 'done');
    return {
      reply: reply,
      action: 'show_default',
      routeName: '可探索区域',
      points: [],
      source: source
    };
  }

  private static stringifyError(error: Object | string | number | boolean | null | undefined): string {
    if (error === null || error === undefined) {
      return '未知错误';
    }
    if (typeof error === 'string') {
      return error;
    }
    try {
      const record = error as Record<string, Object>;
      const code = record['code'];
      const message = record['message'];
      if (code !== undefined || message !== undefined) {
        return `code=${code ?? '-'} message=${message ?? '-'}`;
      }
      return JSON.stringify(error);
    } catch (_e) {
      return `${error}`;
    }
  }

  private static async reportResourceSnapshot(
    context: AgentMapContext,
    report: (title: string, detail: string, status: string) => Promise<void>
  ): Promise<void> {
    if (context.resources.length === 0) {
      await report('资源清单', '地图上暂无已放置资源', 'warn');
      return;
    }
    const previewCount = Math.min(5, context.resources.length);
    const parts: Array<string> = [];
    for (let i = 0; i < previewCount; i++) {
      const r = context.resources[i];
      parts.push(`${r.icon}${r.name}@${r.lat.toFixed(5)},${r.lng.toFixed(5)}(${r.distanceMeters}m)`);
    }
    const more = context.resources.length > previewCount
      ? ` …等共 ${context.resources.length} 个`
      : '';
    await report('最近资源', `${parts.join(' · ')}${more}`, 'done');

    if (context.clusters.length > 0) {
      const top = context.clusters[0];
      await report('资源热点',
        `${top.label} · ${top.count} 个资源 · 距你 ${top.distanceMeters}m @${top.centerLat.toFixed(5)},${top.centerLng.toFixed(5)}`,
        'done');
    }
  }

  private static async reportTrapSnapshot(
    context: AgentMapContext,
    report: (title: string, detail: string, status: string) => Promise<void>
  ): Promise<void> {
    if (context.traps.length === 0) {
      return;
    }
    const previewCount = Math.min(4, context.traps.length);
    const parts: Array<string> = [];
    for (let i = 0; i < previewCount; i++) {
      const t = context.traps[i];
      parts.push(`#${t.id} owner=${t.ownerId} cost=${t.diamondCost}💎 ${t.distanceMeters}m`);
    }
    const more = context.traps.length > previewCount ? ` …等共 ${context.traps.length} 个` : '';
    await report('附近陷阱', `${parts.join(' · ')}${more}`, 'done');
  }

  private static async reportPoiSnapshot(
    context: AgentMapContext,
    report: (title: string, detail: string, status: string) => Promise<void>
  ): Promise<void> {
    if (context.pois.length === 0 && context.loops.length === 0) {
      await report('POI 清单', '附近暂无闭环/地标 POI', 'warn');
      return;
    }
    if (context.pois.length > 0) {
      const previewCount = Math.min(4, context.pois.length);
      const parts: Array<string> = [];
      for (let i = 0; i < previewCount; i++) {
        const p = context.pois[i];
        parts.push(`${p.name}(${p.kind}) ${p.distanceMeters}m`);
      }
      const more = context.pois.length > previewCount ? ` …等共 ${context.pois.length} 个` : '';
      await report('附近 POI', `${parts.join(' · ')}${more}`, 'done');
    }
    if (context.loops.length > 0) {
      const previewCount = Math.min(3, context.loops.length);
      const parts: Array<string> = [];
      for (let i = 0; i < previewCount; i++) {
        const loop = context.loops[i];
        parts.push(`${loop.name}#${loop.id}@${loop.ownerId}`);
      }
      await report('现有闭环', `${parts.join(' · ')}`, 'done');
    }
  }

  private static synthesizeLocalReply(userText: string, context: AgentMapContext): string {
    const hot = context.clusters.length > 0
      ? `资源热点「${context.clusters[0].label}」约 ${context.clusters[0].distanceMeters}m`
      : `已放置资源 ${context.resources.length} 个`;
    const road = context.roadCount > 0 ? `可跑步道路 ${context.roadCount} 条` : '道路数据暂缺';
    const trap = `陷阱 ${context.trapCount} 个`;
    const poi = `POI ${context.poiCount} 个`;
    return `根据「${userText}」，已分析周边：${hot}；${road}；${trap}；${poi}。将为你标出默认可探索区域。`;
  }

  private static buildAuthHeaders(): Record<string, string> {
    const headers: Record<string, string> = {};
    headers['Content-Type'] = 'application/json';
    headers['Authorization'] = `Bearer ${DeepSeekConfig.API_KEY}`;
    return headers;
  }

  private static async callDeepSeek(
    userText: string,
    context: AgentMapContext,
    report?: AgentProgressReporter
  ): Promise<AgentPlanResult | null> {
    const systemPrompt = MapAgentService.buildSystemPrompt();
    const userPrompt = MapAgentService.buildUserPrompt(userText, context);
    const messages: Array<ChatMessage> = [
      { role: 'system', content: systemPrompt },
      { role: 'user', content: userPrompt }
    ];

    const responseFormat: JsonObjectFormat = { type: 'json_object' };
    const thinkingOption: ThinkingOption = { type: 'disabled' };
    const requestBody: ChatCompletionRequest = {
      model: DeepSeekConfig.MODEL,
      messages: messages,
      temperature: 0.3,
      response_format: responseFormat,
      thinking: thinkingOption
    };
    const body = JSON.stringify(requestBody);

    if (report !== undefined) {
      await Promise.resolve(report('等待 DeepSeek 响应',
        `POST ${DeepSeekConfig.CHAT_PATH} · 资源/道路/POI/陷阱已附带 · 完成后才画默认领地`,
        'running'));
      await MapAgentService.sleep(400);
    }

    const request = http.createHttp();
    try {
      const response = await request.request(`${DeepSeekConfig.BASE_URL}${DeepSeekConfig.CHAT_PATH}`, {
        method: http.RequestMethod.POST,
        header: MapAgentService.buildAuthHeaders(),
        extraData: body,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: DeepSeekConfig.TIMEOUT_MS,
        readTimeout: DeepSeekConfig.TIMEOUT_MS
      });

      if (response.responseCode < 200 || response.responseCode >= 300) {
        const errBody = `${response.result}`;
        hilog.error(LOG_DOMAIN, LOG_TAG, '[Agent] http %{public}d %{public}s',
          response.responseCode, errBody);
        await MapAgentService.pacedReport(report, '接口返回错误', `HTTP ${response.responseCode}`, 'error');
        return null;
      }

      const raw = `${response.result}`;
      hilog.info(LOG_DOMAIN, LOG_TAG, '[Agent] deepseek ok bytes=%{public}d', raw.length);
      await MapAgentService.pacedReport(report, '收到响应', `HTTP 200 · ${raw.length} 字节`, 'done', SUB_STEP_PACE_MS);
      await MapAgentService.pacedReport(report, '解析回复', '提取中文分析结论', 'running', 500);
      const parsed = MapAgentService.parseModelResponse(raw);
      if (parsed === null) {
        await MapAgentService.pacedReport(report, '解析失败', '响应里没有可用的 reply', 'error');
      } else {
        await MapAgentService.pacedReport(report, '解析完成', '已得到模型分析说明', 'done', SUB_STEP_PACE_MS);
      }
      return parsed;
    } catch (error) {
      const errText = MapAgentService.stringifyError(error);
      hilog.error(LOG_DOMAIN, LOG_TAG, '[Agent] http throw %{public}s', errText);
      await MapAgentService.pacedReport(report, '请求异常', errText, 'error');
      return null;
    } finally {
      request.destroy();
    }
  }

  private static buildSystemPrompt(): string {
    return [
      '你是跑步圈地游戏 MyDomai 的地图 Agent，场景在南京安德门地铁站附近。',
      '你会收到真实环境数据：已放置资源、陷阱、POI/闭环、可跑步道路。',
      '任务：结合用户语音意图，逐步分析这些外界信息，用中文给出简洁结论。',
      '硬性约束：',
      '1) 只输出一个 JSON，不要 Markdown',
      '2) 客户端最终会固定绘制内置「可探索区域」领地，不要尝试生成几何 points',
      '3) reply 需点名资源热点、道路通行、陷阱风险、POI/领地，并回应用户意图',
      '4) action 固定为 show_default',
      '输出格式：',
      '{"reply":"中文说明","action":"show_default","routeName":"可探索区域","summary":{"resources":0,"roads":0,"traps":0,"pois":0}}'
    ].join('\n');
  }

  private static buildUserPrompt(userText: string, context: AgentMapContext): string {
    const lines: Array<string> = [];
    lines.push(`用户语音：${userText}`);
    lines.push(`用户当前位置（百度坐标）：lat=${context.userLat.toFixed(6)} lng=${context.userLng.toFixed(6)}`);
    lines.push(`区域提示：南京安德门地铁站附近`);
    lines.push(`【可跑步道路】条数=${context.roadCount}`);
    lines.push(context.roadPromptText.length > 0 ? context.roadPromptText : '(无道路数据)');
    lines.push(`【已放置资源统计】总数=${context.resources.length} 世界资源=${context.worldResourceCount} 领地物品=${context.territoryItemCount}`);

    if (context.clusters.length > 0) {
      lines.push('【资源热点聚类】（按密度优先）');
      const maxClusters = Math.min(5, context.clusters.length);
      for (let i = 0; i < maxClusters; i++) {
        const c = context.clusters[i];
        lines.push(
          `${i + 1}. ${c.label} count=${c.count} center_lat=${c.centerLat.toFixed(6)} center_lng=${c.centerLng.toFixed(6)} dist=${c.distanceMeters}m ids=[${c.resourceIds.join(',')}]`
        );
      }
    }

    lines.push(`【已放置资源清单】共 ${context.resources.length} 个（按距用户由近到远，最多 ${MAX_PROMPT_RESOURCES} 条）：`);
    if (context.resources.length === 0) {
      lines.push('(空)');
    } else {
      const max = Math.min(MAX_PROMPT_RESOURCES, context.resources.length);
      for (let i = 0; i < max; i++) {
        const r = context.resources[i];
        lines.push(
          `#${i + 1} id=${r.id} ${r.icon}${r.name}(${r.typeId}) lat=${r.lat.toFixed(6)} lng=${r.lng.toFixed(6)} dist=${r.distanceMeters}m scope=${r.scope} loopId=${r.loopId}`
        );
      }
    }

    lines.push(`【陷阱】共 ${context.traps.length} 个（最多 ${MAX_PROMPT_TRAPS} 条）：`);
    if (context.traps.length === 0) {
      lines.push('(空)');
    } else {
      const max = Math.min(MAX_PROMPT_TRAPS, context.traps.length);
      for (let i = 0; i < max; i++) {
        const t = context.traps[i];
        lines.push(
          `#${i + 1} id=${t.id} owner=${t.ownerId} cost=${t.diamondCost} lat=${t.lat.toFixed(6)} lng=${t.lng.toFixed(6)} dist=${t.distanceMeters}m loopId=${t.loopId}`
        );
      }
    }

    lines.push(`【POI】共 ${context.pois.length} 个（最多 ${MAX_PROMPT_POIS} 条）：`);
    if (context.pois.length === 0) {
      lines.push('(空)');
    } else {
      const max = Math.min(MAX_PROMPT_POIS, context.pois.length);
      for (let i = 0; i < max; i++) {
        const p = context.pois[i];
        lines.push(
          `#${i + 1} ${p.name} kind=${p.kind} lat=${p.lat.toFixed(6)} lng=${p.lng.toFixed(6)} dist=${p.distanceMeters}m`
        );
      }
    }

    if (context.loops.length > 0) {
      lines.push(`【现有闭环】共 ${context.loops.length} 个：`);
      for (let i = 0; i < context.loops.length; i++) {
        const loop = context.loops[i];
        lines.push(
          `闭环 ${loop.name}#${loop.id} owner=${loop.ownerId} center_lat=${loop.centerLat.toFixed(6)} center_lng=${loop.centerLng.toFixed(6)} verts=${loop.pointCount}`
        );
      }
    } else {
      lines.push('【现有闭环】无');
    }

    lines.push('请结合以上环境信息分析用户意图，输出 JSON；客户端会在分析后绘制默认可探索区域，无需返回 points。');
    return lines.join('\n');
  }

  private static parseModelResponse(raw: string): AgentPlanResult | null {
    try {
      const root = JSON.parse(raw) as Record<string, Object>;
      const choices = root['choices'] as Array<Record<string, Object>> | undefined;
      if (choices === undefined || choices.length === 0) {
        return null;
      }
      const message = choices[0]['message'] as Record<string, Object> | undefined;
      if (message === undefined) {
        return null;
      }
      let content = `${message['content'] ?? ''}`;
      content = content.replace(/```json/g, '').replace(/```/g, '').trim();
      const start = content.indexOf('{');
      const end = content.lastIndexOf('}');
      if (start < 0 || end <= start) {
        return null;
      }
      const jsonText = content.substring(start, end + 1);
      const plan = JSON.parse(jsonText) as Record<string, Object>;
      const reply = `${plan['reply'] ?? ''}`.trim();
      if (reply.length === 0) {
        return null;
      }
      const routeName = `${plan['routeName'] ?? '可探索区域'}`;
      return {
        reply: reply,
        action: 'show_default',
        routeName: routeName,
        points: [],
        source: 'deepseek'
      };
    } catch (error) {
      hilog.error(LOG_DOMAIN, LOG_TAG, '[Agent] parse failed %{public}s', JSON.stringify(error));
      return null;
    }
  }

  private static emptyPlan(reply: string): AgentPlanResult {
    return {
      reply: reply,
      action: 'none',
      routeName: '',
      points: [],
      source: 'none'
    };
  }

  private static buildClusters(
    resources: Array<AgentResourcePoint>,
    userLat: number,
    userLng: number
  ): Array<AgentResourceCluster> {
    const clusters: Array<AgentResourceCluster> = [];
    const used: Array<boolean> = [];
    for (let i = 0; i < resources.length; i++) {
      used.push(false);
    }
    for (let i = 0; i < resources.length; i++) {
      if (used[i]) {
        continue;
      }
      const seed = resources[i];
      const members: Array<AgentResourcePoint> = [seed];
      used[i] = true;
      for (let j = i + 1; j < resources.length; j++) {
        if (used[j]) {
          continue;
        }
        const d = MapAgentService.distanceMeters(seed.lat, seed.lng, resources[j].lat, resources[j].lng);
        if (d <= CLUSTER_RADIUS_M) {
          members.push(resources[j]);
          used[j] = true;
        }
      }
      let sumLat = 0;
      let sumLng = 0;
      const ids: Array<number> = [];
      for (let k = 0; k < members.length; k++) {
        sumLat += members[k].lat;
        sumLng += members[k].lng;
        ids.push(members[k].id);
      }
      const centerLat = sumLat / members.length;
      const centerLng = sumLng / members.length;
      const label = MapAgentService.topResourceLabel(members);
      const cluster: AgentResourceCluster = {
        centerLat: centerLat,
        centerLng: centerLng,
        count: members.length,
        resourceIds: ids,
        label: label,
        distanceMeters: Math.round(MapAgentService.distanceMeters(userLat, userLng, centerLat, centerLng))
      };
      clusters.push(cluster);
    }
    clusters.sort((a: AgentResourceCluster, b: AgentResourceCluster) => {
      if (b.count !== a.count) {
        return b.count - a.count;
      }
      return a.distanceMeters - b.distanceMeters;
    });
    return clusters;
  }

  private static topResourceLabel(members: Array<AgentResourcePoint>): string {
    let bestName = members.length > 0 ? members[0].name : '资源群';
    let best = 0;
    for (let i = 0; i < members.length; i++) {
      let count = 0;
      for (let j = 0; j < members.length; j++) {
        if (members[j].name === members[i].name) {
          count++;
        }
      }
      if (count > best) {
        best = count;
        bestName = members[i].name;
      }
    }
    return `${bestName}热点(${members.length})`;
  }

  private static distanceMeters(lat1: number, lng1: number, lat2: number, lng2: number): number {
    const toRad = Math.PI / 180;
    const dLat = (lat2 - lat1) * toRad;
    const dLng = (lng2 - lng1) * toRad;
    const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
      Math.cos(lat1 * toRad) * Math.cos(lat2 * toRad) * Math.sin(dLng / 2) * Math.sin(dLng / 2);
    return 6371000 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  }
}

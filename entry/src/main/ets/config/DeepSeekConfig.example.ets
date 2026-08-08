/**
 * DeepSeek OpenAI-compatible API config.
 * Copy to DeepSeekConfig.ets and fill in your key:
 *   cp entry/src/main/ets/config/DeepSeekConfig.example.ets \
 *      entry/src/main/ets/config/DeepSeekConfig.ets
 */
export class DeepSeekConfig {
  static readonly BASE_URL: string = 'https://api.deepseek.com';
  static readonly CHAT_PATH: string = '/chat/completions';
  static readonly API_KEY: string = 'YOUR_DEEPSEEK_API_KEY';
  static readonly MODEL_FLASH: string = 'deepseek-v4-flash';
  static readonly MODEL_PRO: string = 'deepseek-v4-pro';
  /** Default model for map voice agent */
  static readonly MODEL: string = DeepSeekConfig.MODEL_FLASH;
  static readonly TIMEOUT_MS: number = 45000;
}

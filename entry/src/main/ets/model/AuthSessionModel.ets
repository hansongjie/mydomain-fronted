import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const AUTH_STORE_NAME: string = 'auth_session';

export interface AuthSession {
  userId: string;
  displayName: string;
  diamonds: number;
  token: string;
  expiresAt: string;
}

/** 本地登录会话：供「我的」与地图调试身份共用 */
export class AuthSessionStore {
  private static cached: AuthSession | null = null;

  static getCached(): AuthSession | null {
    return AuthSessionStore.cached;
  }

  static isLoggedIn(): boolean {
    const s = AuthSessionStore.cached;
    return s !== null && s.userId.length > 0 && s.token.length > 0;
  }

  static async load(context: common.UIAbilityContext): Promise<AuthSession | null> {
    try {
      const store = await preferences.getPreferences(context, { name: AUTH_STORE_NAME });
      const userId = String(await store.get('userId', ''));
      const token = String(await store.get('token', ''));
      if (userId.length === 0 || token.length === 0) {
        AuthSessionStore.cached = null;
        return null;
      }
      const session: AuthSession = {
        userId: userId,
        displayName: String(await store.get('displayName', userId)),
        diamonds: Number(await store.get('diamonds', 100)),
        token: token,
        expiresAt: String(await store.get('expiresAt', ''))
      };
      AuthSessionStore.cached = session;
      return session;
    } catch (e) {
      AuthSessionStore.cached = null;
      return null;
    }
  }

  static async save(context: common.UIAbilityContext, session: AuthSession): Promise<void> {
    AuthSessionStore.cached = session;
    const store = await preferences.getPreferences(context, { name: AUTH_STORE_NAME });
    await store.put('userId', session.userId);
    await store.put('displayName', session.displayName);
    await store.put('diamonds', session.diamonds);
    await store.put('token', session.token);
    await store.put('expiresAt', session.expiresAt);
    await store.flush();
  }

  static async clear(context: common.UIAbilityContext): Promise<void> {
    AuthSessionStore.cached = null;
    const store = await preferences.getPreferences(context, { name: AUTH_STORE_NAME });
    await store.clear();
    await store.flush();
  }

  static updateDiamonds(diamonds: number): void {
    if (AuthSessionStore.cached === null) {
      return;
    }
    AuthSessionStore.cached.diamonds = Math.max(0, diamonds);
  }
}

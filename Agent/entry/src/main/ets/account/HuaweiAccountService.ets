import { loginComponentManager } from '@kit.AccountKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { HuaweiAccountSession } from './AccountModels';

const ACCOUNT_SERVICE_DOMAIN = 0x0ff3;
const ACCOUNT_SERVICE_TAG = 'HuaweiAccountService';
const ACCOUNT_PREFS_NAME = 'arkpilot_account';
const ACCOUNT_SESSION_KEY = 'session';
const APPSTORAGE_LOGGED_IN_KEY = 'arkPilotLoggedIn';

export class HuaweiAccountService {
  loginController: loginComponentManager.LoginWithHuaweiIDButtonController = new loginComponentManager.LoginWithHuaweiIDButtonController();
  lastErrorCode: number = 0;
  isLoggedIn: boolean = false;
  private prefs: preferences.Preferences | null = null;
  private session: HuaweiAccountSession | null = null;
  private initialized: boolean = false;
  private onLoginStateChange: () => void = () => {};

  init(context: common.Context): void {
    if (this.initialized) {
      this.restoreSession();
      return;
    }
    this.initialized = true;
    try {
      this.prefs = preferences.getPreferencesSync(context, { name: ACCOUNT_PREFS_NAME });
    } catch (err) {
      this.prefs = null;
      hilog.error(ACCOUNT_SERVICE_DOMAIN, ACCOUNT_SERVICE_TAG, 'init preferences failed: %{public}s', `${err}`);
    }
    this.restoreSession();
    this.registerLoginCallback();
  }

  ensureInit(context: common.Context): void {
    this.init(context);
  }

  setOnLoginStateChange(callback: () => void): void {
    this.onLoginStateChange = callback;
  }

  getSession(): HuaweiAccountSession | null {
    return this.session;
  }

  maskedUnionID(): string {
    if (this.session === null) {
      return '';
    }
    return this.maskId(this.session.unionID);
  }

  private maskId(id: string): string {
    if (id.length === 0) {
      return '';
    }
    if (id.length <= 4) {
      return '****';
    }
    return `****${id.substring(id.length - 4)}`;
  }

  private registerLoginCallback(): void {
    this.loginController.onClickLoginWithHuaweiIDButton((err: BusinessError, credential: loginComponentManager.HuaweiIDCredential) => {
      if (err !== null && err !== undefined) {
        this.lastErrorCode = err.code;
        this.isLoggedIn = false;
        AppStorage.setOrCreate<boolean>(APPSTORAGE_LOGGED_IN_KEY, false);
        this.notifyLoginStateChanged();
        return;
      }
      this.handleLoginSuccess(credential);
    });
  }

  private handleLoginSuccess(credential: loginComponentManager.HuaweiIDCredential): void {
    const session: HuaweiAccountSession = new HuaweiAccountSession(
      credential.unionID,
      credential.openID,
      credential.authorizationCode,
      credential.idToken ?? '',
      Date.now()
    );
    this.session = session;
    this.isLoggedIn = true;
    this.lastErrorCode = 0;
    this.saveSession(session);
    AppStorage.setOrCreate<boolean>(APPSTORAGE_LOGGED_IN_KEY, true);
    this.notifyLoginStateChanged();
  }

  private saveSession(session: HuaweiAccountSession): void {
    if (this.prefs === null) {
      return;
    }
    try {
      this.prefs.putSync(ACCOUNT_SESSION_KEY, session.toJson());
      void this.prefs.flush();
    } catch (err) {
      hilog.error(ACCOUNT_SERVICE_DOMAIN, ACCOUNT_SERVICE_TAG, 'save session failed: %{public}s', `${err}`);
    }
  }

  private restoreSession(): void {
    if (this.prefs === null) {
      this.isLoggedIn = false;
      this.session = null;
      AppStorage.setOrCreate<boolean>(APPSTORAGE_LOGGED_IN_KEY, false);
      return;
    }
    try {
      const raw: preferences.ValueType = this.prefs.getSync(ACCOUNT_SESSION_KEY, '');
      if (typeof raw === 'string' && raw.length > 0) {
        const restored: HuaweiAccountSession | null = HuaweiAccountSession.fromJson(raw);
        if (restored !== null) {
          this.session = restored;
          this.isLoggedIn = true;
          AppStorage.setOrCreate<boolean>(APPSTORAGE_LOGGED_IN_KEY, true);
          return;
        }
      }
      this.isLoggedIn = false;
      this.session = null;
      AppStorage.setOrCreate<boolean>(APPSTORAGE_LOGGED_IN_KEY, false);
    } catch (err) {
      this.isLoggedIn = false;
      this.session = null;
      AppStorage.setOrCreate<boolean>(APPSTORAGE_LOGGED_IN_KEY, false);
      hilog.error(ACCOUNT_SERVICE_DOMAIN, ACCOUNT_SERVICE_TAG, 'restore session failed: %{public}s', `${err}`);
    }
  }

  logout(): void {
    this.session = null;
    this.isLoggedIn = false;
    this.lastErrorCode = 0;
    if (this.prefs !== null) {
      try {
        this.prefs.deleteSync(ACCOUNT_SESSION_KEY);
        void this.prefs.flush();
      } catch (err) {
        hilog.error(ACCOUNT_SERVICE_DOMAIN, ACCOUNT_SERVICE_TAG, 'logout clear failed: %{public}s', `${err}`);
      }
    }
    AppStorage.setOrCreate<boolean>(APPSTORAGE_LOGGED_IN_KEY, false);
    this.notifyLoginStateChanged();
  }

  private notifyLoginStateChanged(): void {
    this.onLoginStateChange();
  }
}

export const huaweiAccountService: HuaweiAccountService = new HuaweiAccountService();

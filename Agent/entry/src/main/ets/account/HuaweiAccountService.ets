import { loginComponentManager } from '@kit.AccountKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { HuaweiAccountSession, maskAccountId } from './AccountModels';

const ACCOUNT_SERVICE_DOMAIN = 0x0ff3;
const ACCOUNT_SERVICE_TAG = 'HuaweiAccountService';
const ACCOUNT_PREFS_NAME = 'arkpilot_account';
const ACCOUNT_SESSION_KEY = 'session';
const ACCOUNT_LAST_OPENID_KEY = 'lastOpenId';
const APPSTORAGE_LOGGED_IN_KEY = 'arkPilotLoggedIn';

export class HuaweiAccountService {
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
    return maskAccountId(this.session.unionID);
  }

  applyCredential(credential: loginComponentManager.HuaweiIDCredential): void {
    this.applyCredentialFields(
      credential.openID,
      credential.unionID,
      credential.authorizationCode,
      credential.idToken ?? ''
    );
  }

  applyCredentialFields(openID: string, unionID: string, authorizationCode: string, idToken: string): void {
    const session: HuaweiAccountSession = new HuaweiAccountSession(
      unionID,
      openID,
      authorizationCode,
      idToken,
      Date.now()
    );
    this.session = session;
    this.isLoggedIn = true;
    this.lastErrorCode = 0;
    this.saveSession(session);
    this.saveLastAccount(openID);
    AppStorage.setOrCreate<boolean>(APPSTORAGE_LOGGED_IN_KEY, true);
    this.notifyLoginStateChanged();
  }

  recordLoginError(code: number): void {
    this.lastErrorCode = code;
    this.isLoggedIn = false;
    AppStorage.setOrCreate<boolean>(APPSTORAGE_LOGGED_IN_KEY, false);
  }

  lastAccountMasked(): string {
    if (this.prefs === null) {
      return '';
    }
    try {
      const raw: preferences.ValueType = this.prefs.getSync(ACCOUNT_LAST_OPENID_KEY, '');
      if (typeof raw === 'string' && raw.length > 0) {
        return maskAccountId(raw);
      }
    } catch (err) {
      hilog.error(ACCOUNT_SERVICE_DOMAIN, ACCOUNT_SERVICE_TAG, 'read last account failed: %{public}s', `${err}`);
    }
    return '';
  }

  clearLastAccount(): void {
    if (this.prefs === null) {
      return;
    }
    try {
      this.prefs.deleteSync(ACCOUNT_LAST_OPENID_KEY);
      void this.prefs.flush();
    } catch (err) {
      hilog.error(ACCOUNT_SERVICE_DOMAIN, ACCOUNT_SERVICE_TAG, 'clear last account failed: %{public}s', `${err}`);
    }
  }

  private saveLastAccount(openID: string): void {
    if (this.prefs === null) {
      return;
    }
    try {
      this.prefs.putSync(ACCOUNT_LAST_OPENID_KEY, openID);
      void this.prefs.flush();
    } catch (err) {
      hilog.error(ACCOUNT_SERVICE_DOMAIN, ACCOUNT_SERVICE_TAG, 'save last account failed: %{public}s', `${err}`);
    }
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

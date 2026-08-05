import { authentication, loginComponentManager } from '@kit.AccountKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import util from '@ohos.util';
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

  maskedUnionID(): string {
    if (this.session === null) {
      return '';
    }
    return maskAccountId(this.session.unionID);
  }

  applyCredential(credential: loginComponentManager.HuaweiIDCredential): void {
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
    this.saveLastAccount(credential.openID);
    AppStorage.setOrCreate<boolean>(APPSTORAGE_LOGGED_IN_KEY, true);
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

  async logout(context?: common.Context): Promise<void> {
    this.session = null;
    this.isLoggedIn = false;
    this.lastErrorCode = 0;
    if (this.prefs !== null) {
      try {
        this.prefs.deleteSync(ACCOUNT_SESSION_KEY);
        this.prefs.deleteSync(ACCOUNT_LAST_OPENID_KEY);
        void this.prefs.flush();
      } catch (err) {
        hilog.error(ACCOUNT_SERVICE_DOMAIN, ACCOUNT_SERVICE_TAG, 'logout clear failed: %{public}s', `${err}`);
      }
    }
    AppStorage.setOrCreate<boolean>(APPSTORAGE_LOGGED_IN_KEY, false);
    if (context !== undefined) {
      await this.cancelAuthorization(context);
    }
  }

  /**
   * Cancels the app's authorization for the current HUAWEI ID account.
   * After cancellation, the next login will show the authorization UI again,
   * allowing the user to switch to another HUAWEI ID account.
   * @returns true if the cancellation succeeded; false otherwise.
   */
  async cancelAuthorization(context: common.Context): Promise<boolean> {
    try {
      const provider = new authentication.HuaweiIDProvider();
      const request = provider.createCancelAuthorizationRequest();
      request.state = util.generateRandomUUID();
      const controller = new authentication.AuthenticationController(context);
      const response = await controller.executeRequest(request);
      const cancelResponse = response as authentication.CancelAuthorizationResponse;
      const responseState: string = cancelResponse.state ?? '';
      if (responseState.length > 0 && responseState !== request.state) {
        hilog.error(ACCOUNT_SERVICE_DOMAIN, ACCOUNT_SERVICE_TAG, '%{public}s', 'cancel authorization state mismatch');
        return false;
      }
      hilog.info(ACCOUNT_SERVICE_DOMAIN, ACCOUNT_SERVICE_TAG, '%{public}s', 'cancel authorization succeeded');
      return true;
    } catch (err) {
      const bizErr = err as BusinessError;
      hilog.error(ACCOUNT_SERVICE_DOMAIN, ACCOUNT_SERVICE_TAG, 'cancel authorization failed: %{public}s, code=%{public}d', `${bizErr}`, bizErr.code);
      return false;
    }
  }
}

export const huaweiAccountService: HuaweiAccountService = new HuaweiAccountService();

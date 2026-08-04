import { describe, it, expect } from '@ohos/hypium';
import {
  ACCOUNT_ERROR_AGREEMENT_NOT_ACCEPTED,
  ACCOUNT_ERROR_APP_NOT_AUTHORIZED,
  ACCOUNT_ERROR_INTERNAL,
  ACCOUNT_ERROR_NETWORK,
  ACCOUNT_ERROR_NOT_LOGGED_IN,
  ACCOUNT_ERROR_PACKAGE_FINGERPRINT,
  ACCOUNT_ERROR_SCOPE_OR_PERMISSION,
  ACCOUNT_ERROR_USER_CANCELED,
  HuaweiAccountSession,
  accountErrorMessage,
  maskAccountId
} from '../../src/main/ets/account/AccountModels';

export default function accountUnitTest() {
  describe('accountUnitTest', () => {
    it('maskAccountId_empty', 0, () => {
      expect(maskAccountId('')).assertEqual('');
    });

    it('maskAccountId_short', 0, () => {
      expect(maskAccountId('ab')).assertEqual('****');
    });

    it('maskAccountId_fourChars', 0, () => {
      expect(maskAccountId('1234')).assertEqual('****');
    });

    it('maskAccountId_normal', 0, () => {
      expect(maskAccountId('0123456789')).assertEqual('****6789');
    });

    it('maskAccountId_exactlyFive', 0, () => {
      expect(maskAccountId('12345')).assertEqual('****2345');
    });

    it('accountErrorMessage_notLoggedIn', 0, () => {
      const message: string = accountErrorMessage(ACCOUNT_ERROR_NOT_LOGGED_IN);
      expect(message.length).assertLarger(0);
      expect(message).assertContain('华为账号');
    });

    it('accountErrorMessage_appNotAuthorized', 0, () => {
      const message: string = accountErrorMessage(ACCOUNT_ERROR_APP_NOT_AUTHORIZED);
      expect(message.length).assertLarger(0);
      expect(message).assertContain('AppGallery Connect');
    });

    it('accountErrorMessage_fingerprint', 0, () => {
      const message: string = accountErrorMessage(ACCOUNT_ERROR_PACKAGE_FINGERPRINT);
      expect(message.length).assertLarger(0);
      expect(message).assertContain('签名');
    });

    it('accountErrorMessage_userCanceled', 0, () => {
      const message: string = accountErrorMessage(ACCOUNT_ERROR_USER_CANCELED);
      expect(message).assertContain('取消');
    });

    it('accountErrorMessage_scope', 0, () => {
      const message: string = accountErrorMessage(ACCOUNT_ERROR_SCOPE_OR_PERMISSION);
      expect(message.length).assertLarger(0);
      expect(message).assertContain('权限');
    });

    it('accountErrorMessage_agreement', 0, () => {
      const message: string = accountErrorMessage(ACCOUNT_ERROR_AGREEMENT_NOT_ACCEPTED);
      expect(message.length).assertLarger(0);
      expect(message).assertContain('协议');
    });

    it('accountErrorMessage_network', 0, () => {
      const message: string = accountErrorMessage(ACCOUNT_ERROR_NETWORK);
      expect(message.length).assertLarger(0);
      expect(message).assertContain('网络');
    });

    it('accountErrorMessage_internal', 0, () => {
      const message: string = accountErrorMessage(ACCOUNT_ERROR_INTERNAL);
      expect(message.length).assertLarger(0);
      expect(message).assertContain('错误');
    });

    it('accountErrorMessage_unknownCode', 0, () => {
      const message: string = accountErrorMessage(999999);
      expect(message).assertContain('999999');
    });

    it('session_roundtrip', 0, () => {
      const session: HuaweiAccountSession = new HuaweiAccountSession(
        'union-1',
        'open-1',
        'code-1',
        'id-token-1',
        1234567890
      );
      const json: string = session.toJson();
      const restored: HuaweiAccountSession | null = HuaweiAccountSession.fromJson(json);
      expect(restored).not().assertEqual(null);
      if (restored !== null) {
        expect(restored.unionID).assertEqual('union-1');
        expect(restored.openID).assertEqual('open-1');
        expect(restored.authorizationCode).assertEqual('code-1');
        expect(restored.idToken).assertEqual('id-token-1');
        expect(restored.loginAt).assertEqual(1234567890);
      }
    });

    it('session_fromJson_missingOpenId', 0, () => {
      const raw: string = '{"unionID":"u1","authorizationCode":"c1","loginAt":"123"}';
      const restored: HuaweiAccountSession | null = HuaweiAccountSession.fromJson(raw);
      expect(restored).assertEqual(null);
    });

    it('session_fromJson_corrupted', 0, () => {
      const restored: HuaweiAccountSession | null = HuaweiAccountSession.fromJson('{not-json');
      expect(restored).assertEqual(null);
    });

    it('session_fromJson_empty', 0, () => {
      const restored: HuaweiAccountSession | null = HuaweiAccountSession.fromJson('');
      expect(restored).assertEqual(null);
    });
  });
}

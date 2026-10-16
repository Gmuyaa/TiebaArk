/**
 * 账号凭据的安全存储。
 *
 * 保存凭据字节及已由服务端资料确认的稳定 UID；后者只用于定位账号快照。
 * 它不认识贴吧协议，不做登录判断，也不持有登录态（那是 `AuthSession` 的事）。
 *
 * 为什么用 Asset Store Kit（`@kit.AssetStoreKit`）而不是 `preferences`：
 * BDUSS 等价于账号密码，`DeviceIdentity` 用的 `preferences` 是明文，不适合放凭据。
 * asset 是系统级凭据存储，且**不需要额外声明权限**——
 * 只有 `Tag.IS_PERSISTENT`（要求 `ohos.permission.STORE_PERSISTENT_DATA`）才需要，
 * 本实现刻意不设它，因此 `module.json5` 保持只声明 INTERNET 不变。
 *
 * 错误处理沿用项目风格（见 `net/HttpClient.ets`）：**不抛异常**，失败返回结果对象。
 * 存储不可用不应让应用不可用——最坏情况是"本次运行有效，重启要重新登录"。
 */

import { asset } from '@kit.AssetStoreKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { decodeUtf8, encodeUtf8 } from '../utils/TextCodec';
import { AuthAlias, CredentialBundle, isAssetMissing } from './AuthModel';

/** 一次存储读写的结果。`ok=false` 时 `message` 是给日志/提示的原因（不含凭据内容） */
export class StoreResult {
  ok: boolean = false;
  message: string = '';

  static success(): StoreResult {
    const r: StoreResult = new StoreResult();
    r.ok = true;
    return r;
  }

  static failure(message: string): StoreResult {
    const r: StoreResult = new StoreResult();
    r.ok = false;
    r.message = message;
    return r;
  }
}

/** asset 的"不存在"错误码判据在 AuthModel（可被用例锁住） */

/**
 * 从 catch 到的值里取业务错误码。
 * ArkTS 不允许随意断言联合类型，这里逐层判断后取值，取不到返回 0。
 */
function errorCodeOf(err: Object): number {
  const maybe: BusinessError = err as BusinessError;
  return maybe.code === undefined ? 0 : maybe.code;
}

/** 从 asset 的 Value（boolean|number|Uint8Array 联合）里安全取出字节 */
function bytesOf(value: asset.Value | undefined): Uint8Array {
  if (value instanceof Uint8Array) {
    return value;
  }
  return new Uint8Array(0);
}

export class AuthStore {
  private static credentialWrite: Promise<StoreResult> = Promise.resolve(StoreResult.success());
  private static enqueue(write: () => Promise<StoreResult>): Promise<StoreResult> {
    const next: Promise<StoreResult> = AuthStore.credentialWrite.then(write, write);
    AuthStore.credentialWrite = next;
    return next;
  }
  private static readonly FORUM_UID: string = 'forum_snapshot_uid';
  private static forumUidWrite: Promise<void> = Promise.resolve();

  static async loadForumUid(): Promise<number> {
    const value: number = Number(await AuthStore.getOne(AuthStore.FORUM_UID));
    return Number.isSafeInteger(value) && value > 0 ? value : 0;
  }

  static async saveForumUid(uid: number): Promise<void> {
    if (Number.isSafeInteger(uid) && uid > 0) {
      AuthStore.forumUidWrite = AuthStore.forumUidWrite.then(async (): Promise<void> => {
        await AuthStore.putOne(AuthStore.FORUM_UID, String(uid));
      });
      await AuthStore.forumUidWrite;
    }
  }

  /** 单条凭据的写入属性 */
  private static addMap(alias: string, secret: string): asset.AssetMap {
    const map: asset.AssetMap = new Map<asset.Tag, asset.Value>();
    map.set(asset.Tag.ALIAS, encodeUtf8(alias));
    map.set(asset.Tag.SECRET, encodeUtf8(secret));
    // 开机首次解锁后可读：够用，且不放宽到"开机即可读"
    map.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
    return map;
  }

  /** 按别名写入一条凭据。已存在时先删再写（asset.add 对已存在别名会报错） */
  private static async putOne(alias: string, secret: string): Promise<StoreResult> {
    if (secret.length === 0) {
      return AuthStore.removeOne(alias);
    }
    try {
      await AuthStore.removeOne(alias);
      await asset.add(AuthStore.addMap(alias, secret));
      return StoreResult.success();
    } catch (err) {
      const e: Error = err as Error;
      return StoreResult.failure(`写入凭据失败：${e.message}`);
    }
  }

  /** 按别名读取一条凭据；读不到返回空串（不是错误） */
  private static async getOne(alias: string): Promise<string> {
    try {
      const query: asset.AssetMap = new Map<asset.Tag, asset.Value>();
      query.set(asset.Tag.ALIAS, encodeUtf8(alias));
      query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
      const found: asset.AssetMap[] = await asset.query(query);
      if (found.length === 0) {
        return '';
      }
      return decodeUtf8(bytesOf(found[0].get(asset.Tag.SECRET)));
    } catch (err) {
      // 读失败与"没有这条"对调用方是同一件事：都当作未登录，不阻断浏览
      return '';
    }
  }

  private static async removeOne(alias: string): Promise<StoreResult> {
    try {
      const query: asset.AssetMap = new Map<asset.Tag, asset.Value>();
      query.set(asset.Tag.ALIAS, encodeUtf8(alias));
      await asset.remove(query);
      return StoreResult.success();
    } catch (err) {
      const e: Error = err as Error;
      if (isAssetMissing(errorCodeOf(e))) {
        return StoreResult.success();
      }
      return StoreResult.failure(`清除凭据失败：${e.message}`);
    }
  }

  /**
   * 保存整份凭据。三个字段分别存：
   * 空字段会被删除，因此"登录时没有 stoken"不会留下上一次的旧值。
   */
  static save(bundle: CredentialBundle): Promise<StoreResult> {
    const snapshot: CredentialBundle = new CredentialBundle();
    snapshot.bduss = bundle.bduss; snapshot.stoken = bundle.stoken; snapshot.tbs = bundle.tbs;
    return AuthStore.enqueue((): Promise<StoreResult> => AuthStore.saveNow(snapshot));
  }
  private static async saveNow(bundle: CredentialBundle): Promise<StoreResult> {
    await AuthStore.forumUidWrite;
    await AuthStore.removeOne(AuthStore.FORUM_UID);
    const bduss: StoreResult = await AuthStore.putOne(AuthAlias.BDUSS, bundle.bduss);
    if (!bduss.ok) {
      return bduss;
    }
    const stoken: StoreResult = await AuthStore.putOne(AuthAlias.STOKEN, bundle.stoken);
    if (!stoken.ok) {
      return stoken;
    }
    return AuthStore.putOne(AuthAlias.TBS, bundle.tbs);
  }

  /** 读取整份凭据。任何一条读不到都按空串处理，由上层判断是否算"已登录" */
  static async load(): Promise<CredentialBundle> {
    const bundle: CredentialBundle = new CredentialBundle();
    await AuthStore.enqueue(async (): Promise<StoreResult> => {
      bundle.bduss = await AuthStore.getOne(AuthAlias.BDUSS);
      bundle.stoken = await AuthStore.getOne(AuthAlias.STOKEN);
      bundle.tbs = await AuthStore.getOne(AuthAlias.TBS);
      return StoreResult.success();
    });
    return bundle;
  }

  /** 只更新 tbs（登录后刷新 tbs 时用，不动 BDUSS） */
  static saveTbs(tbs: string, bduss: string, stoken: string): Promise<StoreResult> {
    return AuthStore.enqueue(async (): Promise<StoreResult> => {
      const storedBduss: string = await AuthStore.getOne(AuthAlias.BDUSS);
      const storedStoken: string = await AuthStore.getOne(AuthAlias.STOKEN);
      if (storedBduss !== bduss || storedStoken !== stoken || bduss.length === 0) {
        return StoreResult.failure('账号已变化，未保存旧 tbs');
      }
      return AuthStore.putOne(AuthAlias.TBS, tbs);
    });
  }

  /** 清除全部账号凭据。**不动 DeviceIdentity**：设备身份与账号身份分离 */
  static clear(): Promise<StoreResult> {
    return AuthStore.enqueue((): Promise<StoreResult> => AuthStore.clearNow());
  }
  private static async clearNow(): Promise<StoreResult> {
    await AuthStore.forumUidWrite;
    await AuthStore.removeOne(AuthStore.FORUM_UID);
    const bduss: StoreResult = await AuthStore.removeOne(AuthAlias.BDUSS);
    const stoken: StoreResult = await AuthStore.removeOne(AuthAlias.STOKEN);
    const tbs: StoreResult = await AuthStore.removeOne(AuthAlias.TBS);
    if (!bduss.ok) {
      return bduss;
    }
    if (!stoken.ok) {
      return stoken;
    }
    return tbs;
  }
}

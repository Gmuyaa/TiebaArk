

import { asset } from '@kit.AssetStoreKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { decodeUtf8, encodeUtf8 } from '../utils/TextCodec';
import { AuthAlias, CredentialBundle, isAssetMissing } from './AuthModel';

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

function errorCodeOf(err: Object): number {
  const maybe: BusinessError = err as BusinessError;
  return maybe.code === undefined ? 0 : maybe.code;
}

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

  private static addMap(alias: string, secret: string): asset.AssetMap {
    const map: asset.AssetMap = new Map<asset.Tag, asset.Value>();
    map.set(asset.Tag.ALIAS, encodeUtf8(alias));
    map.set(asset.Tag.SECRET, encodeUtf8(secret));

    map.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
    return map;
  }

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

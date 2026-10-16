
export class AppPermission {
  name: string = '';
  label: string = '';
  declared: boolean = false;
  state: number = -2;
}

const PRIVACY_NAMES: string[] = ['ohos.permission.INTERNET', 'ohos.permission.CAMERA',
  'ohos.permission.MICROPHONE', 'ohos.permission.LOCATION', 'ohos.permission.READ_IMAGEVIDEO'];

export function permissionLabel(name: string): string {
  if (name === 'ohos.permission.INTERNET') { return '联网'; }
  if (name === 'ohos.permission.GET_NETWORK_INFO') { return '网络连接信息'; }
  if (name === 'ohos.permission.CAMERA') { return '相机'; }
  if (name === 'ohos.permission.MICROPHONE') { return '麦克风'; }
  if (name === 'ohos.permission.LOCATION') { return '精确位置'; }
  if (name === 'ohos.permission.READ_IMAGEVIDEO') { return '读取图片与视频'; }
  return name;
}

export function permissionStateLabel(item: AppPermission): string {
  if (!item.declared) { return '未声明'; }
  if (item.state === 0) { return '已授权'; }
  if (item.state === -1) { return '未授权'; }
  return '授权状态未确认';
}

export function appPermissionItems(names: string[], states: number[]): AppPermission[] {
  const items: AppPermission[] = [];
  const seen: Set<string> = new Set<string>();
  for (let i = 0; i < names.length; i++) {
    const name: string = names[i];
    if (name.length === 0) { throw new Error('系统权限名称缺失'); }
    if (seen.has(name)) { continue; }
    const item: AppPermission = new AppPermission(); item.name = name; item.label = permissionLabel(name); item.declared = true;
    item.state = i < states.length && (states[i] === 0 || states[i] === -1) ? states[i] : -2;
    items.push(item); seen.add(name);
  }
  for (const name of PRIVACY_NAMES) {
    if (seen.has(name)) { continue; }
    const item: AppPermission = new AppPermission(); item.name = name; item.label = permissionLabel(name);
    items.push(item);
  }
  return items;
}

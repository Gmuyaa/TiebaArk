
import { common } from '@kit.AbilityKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { systemShare } from '@kit.ShareKit';

export async function shareWebPage(context: common.UIAbilityContext, title: string, url: string): Promise<void> {
  const record: systemShare.SharedRecord = {
    utd: uniformTypeDescriptor.UniformDataType.HYPERLINK,
    content: url,
    title: title
  };
  const data: systemShare.SharedData = new systemShare.SharedData(record);
  const controller: systemShare.ShareController = new systemShare.ShareController(data);
  await controller.show(context, {});
}

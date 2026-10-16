import { display } from '@kit.ArkUI';
import { connection } from '@kit.NetworkKit';
import { data, radio } from '@kit.TelephonyKit';
import { VideoFeedEnvironment } from '../model/VideoFeed';

/** 不读设备标识/账号。读取失败时网络未知；不伪报 Wi-Fi 或蜂窝代际。 */
export async function readVideoEnvironment(): Promise<VideoFeedEnvironment> {
  const environment: VideoFeedEnvironment = new VideoFeedEnvironment();
  const screen = display.getDefaultDisplaySync();
  environment.width = screen.width; environment.height = screen.height; environment.density = screen.densityPixels;
  try {
    const net = await connection.getDefaultNet();
    if (net.netId === 0) { environment.newNetType = 0; return environment; }
    const capabilities = await connection.getNetCapabilities(net);
    if (capabilities.bearerTypes.indexOf(connection.NetBearType.BEARER_WIFI) >= 0) { environment.newNetType = 1; }
    else if (capabilities.bearerTypes.indexOf(connection.NetBearType.BEARER_CELLULAR) >= 0) {
      const slot: number = await data.getDefaultCellularDataSlotId();
      const tech = await radio.getRadioTech(slot); const type: radio.RadioTechnology = tech.psRadioTech;
      if (type === radio.RadioTechnology.RADIO_TECHNOLOGY_GSM || type === radio.RadioTechnology.RADIO_TECHNOLOGY_1XRTT) { environment.newNetType = 2; }
      else if (type === radio.RadioTechnology.RADIO_TECHNOLOGY_WCDMA || type === radio.RadioTechnology.RADIO_TECHNOLOGY_HSPA ||
        type === radio.RadioTechnology.RADIO_TECHNOLOGY_HSPAP || type === radio.RadioTechnology.RADIO_TECHNOLOGY_TD_SCDMA ||
        type === radio.RadioTechnology.RADIO_TECHNOLOGY_EVDO || type === radio.RadioTechnology.RADIO_TECHNOLOGY_EHRPD) { environment.newNetType = 3; }
      else if (type === radio.RadioTechnology.RADIO_TECHNOLOGY_LTE || type === radio.RadioTechnology.RADIO_TECHNOLOGY_LTE_CA) { environment.newNetType = 4; }
      else if (type === radio.RadioTechnology.RADIO_TECHNOLOGY_NR) { environment.newNetType = 5; }
    }
  } catch (err) { environment.newNetType = -1; }
  return environment;
}

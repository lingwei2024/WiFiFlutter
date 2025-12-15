import wifiManager from '@ohos.wifi';
import wifiHotspot from '@ohos.wifiHotspot';
import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
} from '@ohos/flutter_ohos';

/** WifiIotPlugin **/
export default class WifiIotPlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;

  constructor() {
  }

  getUniqueClassName(): string {
    return "WifiIotPlugin"
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), "wifi_iot");
    this.channel.setMethodCallHandler(this)
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    if (this.channel != null) {
      this.channel.setMethodCallHandler(null)
    }
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    try {
      switch (call.method) {
        case 'getPlatformVersion':
          result.success('HarmonyOS');
          break;
        case 'isEnabled':
          const isEnabled = await this.isEnabled();
          result.success(isEnabled);
          break;

        case 'setEnabled':
          const setEnabledResult = await this.setEnabled(call.arguments);
          result.success(setEnabledResult);
          break;
        default:
          result.notImplemented();
      }
    } catch (error) {
      console.error(`Method ${call.method} failed:`, JSON.stringify(error));
    }
  }

  /**
   * 检查WiFi是否启用
   */
  async isEnabled(): Promise<boolean> {
    try {
      const isActive = await wifiManager.isWifiActive();
      return isActive;
    } catch (error) {
      console.error('isEnabled error:', JSON.stringify(error));
      return false;
    }
  }

  /**
   * 启用或禁用WiFi
   */
  async setEnabled(state: boolean, shouldOpenSettings: boolean = false): Promise<boolean> {
    try {
      if (state) {
        await wifiManager.enableWifi();
      } else {
        await wifiManager.disableWifi();
      }
      return true;
    } catch (error) {
      console.error('setEnabled error:', JSON.stringify(error));
      return false;
    }
  }

}
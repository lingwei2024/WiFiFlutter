import {
  Any,
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
} from '@ohos/flutter_ohos';

import wifiManager from '@ohos.wifiManager';
import { Callback } from '@kit.BasicServicesKit';

interface ConnectResult {
  success: boolean;
  errorCode: number;
  errorMessage: string | null;
  errorDetails: string | null;
}

interface WifiNetwork {
  ssid: string;
  bssid: string;
  capabilities: string;
  frequency: number;
  level: number;
  timestamp: number;
}

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

  async onMethodCall(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      console.log(".............................收到指令:" + call.method);
      switch (call.method) {
        case 'getPlatformVersion':
          result.success('HarmonyOS');
          break;

        case 'isEnabled':
          const isEnabled = await wifiManager.isWifiActive();
          result.success(isEnabled);
          break;

        case 'setEnabled':
          const setEnabledResult = await this.setEnabled(call);
          result.success(setEnabledResult);
          break;

        case 'connect':
          this.connect(call, (success) => {
            result.success(success);
          });
          break;
        case 'connectWithResult':
          this.connectWithResult(call, result);
          break;
        case 'isConnected':
          const isConnected = await this.isConnected();
          result.success(isConnected);
          break;

        case 'disconnect':
          const disconnectResult = await this.disconnect();
          result.success(disconnectResult);
          break;

        case 'getSSID':
          const ssid = await this.getSSID();
          result.success(ssid);
          break;

        case 'getBSSID':
          const bssid = await this.getBSSID();
          result.success(bssid);
          break;

        case 'getIP':
          const ip = await this.getIP();
          result.success(ip);
          break;

        case 'getCurrentSignalStrength':
          const signal = await this.getCurrentSignalStrength();
          result.success(signal);
          break;

        case 'getFrequency':
          const frequency = await this.getFrequency();
          result.success(frequency);
          break;

        case 'forceWifiUsage':
          const forceWifiResult = await this.forceWifiUsage(call);
          result.success(forceWifiResult);
          break;

        case 'scanWifiNetworks':
          const networks = await this.scanWifiNetworks();
          result.success(networks);
          break;

        case 'loadWifiList':
          const wifiList = await this.loadWifiList();
          result.success(wifiList);
          break;

        case 'removeWifiNetwork':
          const removeResult = await this.removeWifiNetwork(call);
          result.success(removeResult);
          break;

        case 'isRegisteredWifiNetwork':
          const isRegistered = await this.isRegisteredWifiNetwork(call);
          result.success(isRegistered);
          break;

        case 'registerWifiNetwork':
          const registerResult = await this.registerWifiNetwork(call);
          result.success(registerResult);
          break;

        // WiFi AP 相关方法
        case 'isWiFiAPEnabled':
          const apEnabled = await this.isWiFiAPEnabled();
          result.success(apEnabled);
          break;

        case 'setWiFiAPEnabled':
          const setAPResult = await this.setWiFiAPEnabled(call.args);
          result.success(setAPResult);
          break;

        case 'getWiFiAPSSID':
          const apSsid = await this.getWiFiAPSSID();
          result.success(apSsid);
          break;

        case 'getWiFiAPPreSharedKey':
          const apPassword = await this.getWiFiAPPreSharedKey();
          result.success(apPassword);
          break;

        case 'getClientList':
          const clients = await this.getClientList(call.args);
          result.success(clients);
          break;

        default:
          result.notImplemented();
      }
    } catch (error) {
      console.error(`Method ${call.method} failed:`, JSON.stringify(error));
      result.error(
        'ERROR',
        error.message || 'Unknown error',
        error
      );
    }
  }

  private async setEnabled(call: MethodCall): Promise<boolean> {
    try {
      const state = call.argument('state') as boolean;
      const shouldOpenSettings = call.argument('shouldOpenSettings') as boolean;
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

  private async connect(call: MethodCall, callBack:Callback<boolean>) {
    try {
      const ssid = call.argument('ssid') as string;
      const bssid = call.argument('bssid') as string | undefined;
      const password = call.argument('password') as string | undefined;
      const security = call.argument('security') as string;
      const isHidden = call.argument('is_hidden') as boolean || false;
      console.log(".............................. 连接网络：" + ssid + "bssid:" + bssid + "password:" + password + "security:" + security + "is_hidden" + isHidden);
      // 验证SSID
      if (!ssid || ssid.length === 0) {
        callBack(false)
      }
      // 映射安全类型
      const securityType = this.mapSecurityType(security);
      const wifiConfig: wifiManager.WifiDeviceConfig = {
        ssid: ssid,
        preSharedKey: password ?? '',
        securityType: securityType
      };
      console.log(".................................. 11111 " + JSON.stringify(wifiConfig))
      wifiManager.addCandidateConfig(wifiConfig).then(result => {
        console.log('addCandidateConfig:' + result)
        wifiManager.connectToCandidateConfig(result);
        callBack(true)
      }).catch((err: number) => {
        console.error("connectToCandidateConfig failed:" + err);
        callBack(false)
      });
    } catch (error) {
      console.error('connect error:', JSON.stringify(error));
      callBack(false)
    }
  }

  private async connectWithResult(call: MethodCall, result:MethodResult) {
    try {
      this.connect(call, (success) => {
        if (success) {
          result.success({
            success: true,
            errorCode: 0, // SUCCESS
            errorMessage: null,
            errorDetails: null
          });
        } else {
          result.success({
            success: false,
            errorCode: 8, // CONNECTION_TIMEOUT
            errorMessage: 'Connection failed',
            errorDetails: null
          });
        }
      });
    } catch (error) {
      console.error('connectWithResult error:', JSON.stringify(error));
      result.success({
        success: false,
        errorCode: 1, // CONNECTION_TIMEOUT
        errorMessage: error.message,
        errorDetails: JSON.stringify(error)
      });
    }
  }

  private async isConnected(): Promise<boolean> {
    try {
      const wifiInfo = await wifiManager.getLinkedInfo();
      return wifiInfo !== null && wifiInfo.connState === wifiManager.ConnState.CONNECTED;
    } catch (error) {
      console.error('isConnected error:', JSON.stringify(error));
      return false;
    }
  }

  private async disconnect(): Promise<boolean> {
    try {
      wifiManager.disconnect();
      return true;
    } catch (error) {
      console.error('disconnect error:', JSON.stringify(error));
      return false;
    }
  }

  private async getSSID(): Promise<string | null> {
    try {
      const wifiInfo = await wifiManager.getLinkedInfo();
      return wifiInfo?.ssid || null;
    } catch (error) {
      console.error('getSSID error:', JSON.stringify(error));
      return null;
    }
  }

  private async getBSSID(): Promise<string | null> {
    try {
      const wifiInfo = await wifiManager.getLinkedInfo();
      return wifiInfo?.bssid || null;
    } catch (error) {
      console.error('getBSSID error:', JSON.stringify(error));
      return null;
    }
  }

  private async getIP(): Promise<string | null> {
    try {
      const ipInfo = wifiManager.getIpInfo();
      return ipInfo?.ipAddress?.toString() || null;
    } catch (error) {
      console.error('getIP error:', JSON.stringify(error));
      return null;
    }
  }

  private async getCurrentSignalStrength(): Promise<number | null> {
    try {
      const wifiInfo = await wifiManager.getLinkedInfo();
      return wifiInfo?.rssi || null;
    } catch (error) {
      console.error('getCurrentSignalStrength error:', JSON.stringify(error));
      return null;
    }
  }

  private async getFrequency(): Promise<number | null> {
    try {
      const wifiInfo = await wifiManager.getLinkedInfo();
      return wifiInfo?.frequency || null;
    } catch (error) {
      console.error('getFrequency error:', JSON.stringify(error));
      return null;
    }
  }


  private async forceWifiUsage(call: MethodCall): Promise<boolean> {
    // HarmonyOS中网络路由由系统管理
    // 这里可以记录使用偏好或进行提示
    const useWifi = call.argument('useWifi') as boolean;
    console.log('forceWifiUsage:', useWifi);
    return true;
  }

  private async scanWifiNetworks(): Promise<WifiNetwork[]> {
    try {
      await wifiManager.startScan();
      const scanResults = await wifiManager.getScanInfoList();
      const networks: WifiNetwork[] = [];
      for (const result of scanResults) {
        const network: WifiNetwork = {
          ssid: result.ssid || '',
          bssid: result.bssid || '',
          capabilities: result.capabilities || '',
          frequency: result.frequency || 0,
          level: result.rssi || 0,
          timestamp: Date.now()
        };
        networks.push(network);
      }
      return networks;
    } catch (error) {
      console.error('scanWifiNetworks error:', JSON.stringify(error));
      return [];
    }
  }

  private async loadWifiList(): Promise<Array<Record<string, Any>>> {
    return await this.scanWifiNetworks();
  }

  private async removeWifiNetwork(call: MethodCall): Promise<boolean> {
    try {
      const ssid = call.argument('ssid') as string;
      const configs = await wifiManager.getDeviceConfigs();
      const targetConfig = configs.find(config => config.ssid === ssid);
      if (targetConfig && targetConfig.ssid !== undefined) {
        const netWorkId = await wifiManager.addDeviceConfig(targetConfig);
        wifiManager.removeDevice(netWorkId)
        return true
      }else{
        return false;
      }
    } catch (error) {
      console.error('removeWifiNetwork error:', JSON.stringify(error));
      return false;
    }
  }


  private async isRegisteredWifiNetwork(call: MethodCall): Promise<boolean> {
    try {
      const ssid = call.argument('ssid') as string;
      const configs = await wifiManager.getDeviceConfigs();
      return configs.some(config => config.ssid === ssid);
    } catch (error) {
      console.error('isRegisteredWifiNetwork error:', JSON.stringify(error));
      return false;
    }
  }

  private async registerWifiNetwork(call: MethodCall): Promise<boolean> {
    try {
      const ssid = call.argument('ssid') as string;
      const bssid = call.argument('bssid') as string | undefined;
      const password = call.argument('password') as string | undefined;
      const security = call.argument('security') as string;
      const isHidden = call.argument('is_hidden') as boolean || false;

      const securityType = this.mapSecurityType(security);

      const wifiConfig: wifiManager.WifiDeviceConfig = {
        ssid: ssid,
        bssid: bssid,
        preSharedKey: password ?? '',
        securityType: securityType,
        isHiddenSsid: isHidden
      };

      const configId = await wifiManager.addDeviceConfig(wifiConfig);
      return configId >= 0;
    } catch (error) {
      console.error('registerWifiNetwork error:', JSON.stringify(error));
      return false;
    }
  }

  // WiFi AP 方法实现
  private async isWiFiAPEnabled(): Promise<boolean> {
    try {
      return await wifiManager.isHotspotActive();
    } catch (error) {
      console.error('isWiFiAPEnabled error:', JSON.stringify(error));
      return false;
    }
  }

  private async setWiFiAPEnabled(params: Record<string, Any>): Promise<boolean> {
    return false;
  }

  private async getWiFiAPSSID(): Promise<string | null> {
    return null;
  }

  private async getWiFiAPPreSharedKey(): Promise<string | null> {
    return null;
  }

  private async getClientList(params: Record<string, Any>): Promise<Array<Record<string, Any>>> {
    return [];
  }

  // 辅助方法
  private mapSecurityType(security: string): wifiManager.WifiSecurityType {
    switch (security) {
      case 'WPA':
        return wifiManager.WifiSecurityType.WIFI_SEC_TYPE_PSK;
      case 'WEP':
        return wifiManager.WifiSecurityType.WIFI_SEC_TYPE_WEP;
      case 'NONE':
      default:
        return wifiManager.WifiSecurityType.WIFI_SEC_TYPE_OPEN;
    }
  }
}
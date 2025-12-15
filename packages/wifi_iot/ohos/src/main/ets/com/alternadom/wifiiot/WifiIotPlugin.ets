/**
 * WifiIotPlugin for HarmonyOS
 * 鸿蒙版本的WiFi IoT插件实现
 */

import wifiManager from '@ohos.wifiManager';
import connection from '@ohos.net.connection';
import bundleManager from '@ohos.bundle.bundleManager';
import abilityAccessCtrl, { Permissions } from '@ohos.abilityAccessCtrl';
import common from '@ohos.app.ability.common';

// WiFi扫描结果接口
interface WifiScanResult {
  SSID: string;
  BSSID: string;
  capabilities: string;
  frequency: number;
  level: number;
  timestamp: number;
}

// 客户端信息接口
interface ClientInfo {
  IPAddr: string;
  HWAddr: string;
  Device: string;
  isReachable: boolean;
}

// WiFi AP状态枚举
enum WIFI_AP_STATE {
  WIFI_AP_STATE_DISABLED = 0,
  WIFI_AP_STATE_ENABLING = 1,
  WIFI_AP_STATE_ENABLED = 2,
  WIFI_AP_STATE_DISABLING = 3,
  WIFI_AP_STATE_FAILED = 4
}

// 客户端扫描结果
interface ClientScanResult {
  ipAddr: string;
  hwAddr: string;
  device: string;
  isReachable: boolean;
}

export class WifiIotPlugin {
  private context: common.UIAbilityContext | null = null;
  private localOnlyHotspotState: WIFI_AP_STATE = WIFI_AP_STATE.WIFI_AP_STATE_DISABLED;
  private ssidsToBeRemovedOnExit: string[] = [];
  private networkIdMap: Map<string, number> = new Map(); // SSID到networkId的映射
  private wifiNetHandle: connection.NetHandle | null = null; // 保存WiFi网络句柄

  /**
   * 初始化插件，传入UIAbilityContext
   */
  public init(context: common.UIAbilityContext): void {
    this.context = context;
  }

  /**
   * 清理资源
   */
  public cleanup(): void {
    // 移除需要清理的网络
    if (this.ssidsToBeRemovedOnExit.length > 0) {
      this.ssidsToBeRemovedOnExit.forEach((ssid: string) => {
        try {
          const networkId = this.networkIdMap.get(ssid);
          if (networkId !== undefined) {
            wifiManager.removeDevice(networkId);
            this.networkIdMap.delete(ssid);
          }
        } catch (error) {
          console.error(`Failed to remove network ${ssid}:`, error);
        }
      });
    }

    this.context = null;
    this.networkIdMap.clear();
    this.wifiNetHandle = null;
  }

  /**
   * 检查并请求权限
   */
  private async checkPermissions(permissions: Permissions[]): Promise<boolean> {
    if (!this.context) {
      return false;
    }

    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const bundleInfo = await bundleManager.getBundleInfoForSelf(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION
      );

      for (const permission of permissions) {
        const grantStatus = await atManager.checkAccessToken(
          bundleInfo.appInfo.accessTokenId,
          permission
        );

        if (grantStatus !== abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
          // 请求权限
          await atManager.requestPermissionsFromUser(this.context, permissions);
          return false;
        }
      }

      return true;
    } catch (error) {
      console.error('Permission check failed:', error);
      return false;
    }
  }

  /**
   * 加载WiFi列表
   */
  public async loadWifiList(): Promise<string> {
    try {
      // 检查权限
      const hasPermission = await this.checkPermissions([
        'ohos.permission.GET_WIFI_INFO',
        'ohos.permission.LOCATION'
      ]);

      if (!hasPermission) {
        throw new Error('Fine location permission denied');
      }

      // 开始扫描
      wifiManager.scan();

      // 等待扫描完成
      await this.sleep(1000);

      // 获取扫描结果
      const scanResults = wifiManager.getScanInfoList();

      // 转换为JSON数组，明确指定类型
      const wifiArray: WifiScanResult[] = scanResults.map((result): WifiScanResult => {
        return {
          SSID: result.ssid,
          BSSID: result.bssid,
          capabilities: this.getSecurityString(result.securityType),
          frequency: result.frequency,
          level: result.rssi,
          timestamp: result.timestamp
        };
      });

      return JSON.stringify(wifiArray);
    } catch (error) {
      console.error('Load wifi list failed:', error);
    }
    return '';
  }

  /**
   * 强制使用WiFi（用于IoT设备连接场景）
   *
   * 注意：HarmonyOS中没有类似Android的bindProcessToNetwork API
   * 此方法提供的是一个简化实现，保存WiFi网络句柄供后续使用
   *
   * 实际使用中，需要在创建HTTP/Socket连接时指定网络：
   * - HTTP: 使用 http.createHttp() 后调用 request 时可指定网络
   * - Socket: 创建Socket时可以指定 netId
   *
   * @param useWifi true表示强制使用WiFi，false表示使用默认网络
   */
  public async forceWifiUsage(useWifi: boolean): Promise<boolean> {
    try {
      if (useWifi) {
        // 检查WiFi是否已连接
        const linkedInfo = await wifiManager.getLinkedInfo();
        if (!linkedInfo || linkedInfo.connState !== wifiManager.ConnState.CONNECTED) {
          console.warn('WiFi not connected');
          return false;
        }

        // 获取并保存WiFi网络句柄
        const netHandle = await this.getWifiNetHandle();
        if (netHandle) {
          this.wifiNetHandle = netHandle;
          console.log(`WiFi NetHandle saved: netId=${netHandle.netId}`);
          return true;
        }
        return false;
      } else {
        // 清除WiFi网络句柄
        this.wifiNetHandle = null;
        return true;
      }
    } catch (error) {
      console.error('Force wifi usage failed:', error);
      return false;
    }
  }

  /**
   * 获取保存的WiFi网络句柄
   * 在进行网络请求时可以使用此句柄
   */
  public getWifiNetHandleForRequest(): connection.NetHandle | null {
    return this.wifiNetHandle;
  }

  /**
   * 获取WiFi网络句柄
   */
  private async getWifiNetHandle(): Promise<connection.NetHandle | null> {
    try {
      const allNets = await connection.getAllNets();

      for (const net of allNets) {
        const capabilities = await connection.getNetCapabilities(net);
        if (capabilities && capabilities.bearerTypes.includes(connection.NetBearType.BEARER_WIFI)) {
          return net;
        }
      }

      return null;
    } catch (error) {
      console.error('Get wifi net handle failed:', error);
      return null;
    }
  }

  /**
   * 检查WiFi是否启用
   */
  public isEnabled(): boolean {
    try {
      return wifiManager.isWifiActive();
    } catch (error) {
      console.error('Check wifi enabled failed:', error);
      return false;
    }
  }

  /**
   * 启用/禁用WiFi
   */
  public setEnabled(enabled: boolean, shouldOpenSettings: boolean = false): void {
    try {
      if (shouldOpenSettings) {
        console.log('Opening WiFi settings not directly supported, use system settings');
      } else {
        if (enabled) {
          wifiManager.enableWifi();
        } else {
          wifiManager.disableWifi();
        }
      }
    } catch (error) {
      console.error('Set wifi enabled failed:', error);
    }
  }

  /**
   * 连接到WiFi网络
   */
  public async connect(
    ssid: string,
    bssid: string | null,
    password: string,
    security: string | null,
    joinOnce: boolean = false,
    withInternet: boolean = false,
    isHidden: boolean = false,
    timeoutInSeconds: number = 30
  ): Promise<boolean> {
    try {
      // 创建WiFi配置
      const config: wifiManager.WifiDeviceConfig = {
        ssid: ssid,
        bssid: bssid || '',
        preSharedKey: password,
        isHiddenSsid: isHidden,
        securityType: this.getSecurityType(security)
      };

      // 添加网络配置
      const networkId = await wifiManager.addDeviceConfig(config);

      if (networkId === -1) {
        return false;
      }

      // 保存SSID到networkId的映射
      this.networkIdMap.set(ssid, networkId);

      // 如果是临时连接，记录下来以便退出时删除
      if (joinOnce) {
        this.ssidsToBeRemovedOnExit.push(ssid);
      }

      // 连接到网络
      wifiManager.connectToNetwork(networkId);

      // 等待连接完成
      const connected = await this.waitForConnection(networkId, timeoutInSeconds);

      return connected;
    } catch (error) {
      console.error('Connect to wifi failed:', error);
      return false;
    }
  }

  /**
   * 等待连接完成
   */
  private async waitForConnection(networkId: number, timeoutSeconds: number): Promise<boolean> {
    const startTime = Date.now();
    const timeout = timeoutSeconds * 1000;

    while (Date.now() - startTime < timeout) {
      try {
        const linkedInfo = await wifiManager.getLinkedInfo();
        // 检查连接状态是否为已连接
        if (linkedInfo && linkedInfo.connState === wifiManager.ConnState.CONNECTED) {
          // 注意：linkedInfo中没有networkId属性，只能通过SSID或连接状态判断
          return true;
        }
      } catch (error) {
        console.error('Check connection status failed:', error);
      }

      // 等待500ms后重试
      await this.sleep(500);
    }

    return false;
  }

  /**
   * 注册WiFi网络（保存配置）
   */
  public async registerWifiNetwork(
    ssid: string,
    bssid: string | null,
    password: string,
    security: string | null,
    isHidden: boolean = false
  ): Promise<boolean> {
    try {
      const config: wifiManager.WifiDeviceConfig = {
        ssid: ssid,
        bssid: bssid || '',
        preSharedKey: password,
        isHiddenSsid: isHidden,
        securityType: this.getSecurityType(security)
      };

      const networkId = await wifiManager.addDeviceConfig(config);

      if (networkId !== -1) {
        // 保存映射关系
        this.networkIdMap.set(ssid, networkId);
        return true;
      }

      return false;
    } catch (error) {
      console.error('Register wifi network failed:', error);
      return false;
    }
  }

  /**
   * 查找并连接到WiFi
   */
  public async findAndConnect(
    ssid: string,
    bssid: string | null,
    password: string,
    joinOnce: boolean = false,
    withInternet: boolean = false,
    timeoutInSeconds: number = 30
  ): Promise<boolean> {
    try {
      // 扫描网络
      wifiManager.scan();
      await this.sleep(1000);

      const scanResults = wifiManager.getScanInfoList();

      // 查找目标网络
      let targetNetwork: wifiManager.WifiScanInfo | null = null;
      let detectedSecurity: string | null = null;

      for (const result of scanResults) {
        if (result.ssid === ssid) {
          if (!bssid || result.bssid === bssid) {
            targetNetwork = result;
            detectedSecurity = this.getSecurityString(result.securityType);
            break;
          }
        }
      }

      if (!targetNetwork) {
        console.warn(`Network ${ssid} not found in scan results`);
        return false;
      }

      // 使用检测到的安全类型连接
      return await this.connect(
        ssid,
        targetNetwork.bssid,
        password,
        detectedSecurity,
        joinOnce,
        withInternet,
        false,
        timeoutInSeconds
      );
    } catch (error) {
      console.error('Find and connect failed:', error);
      return false;
    }
  }

  /**
   * 检查是否已连接到WiFi
   */
  public isConnected(): boolean {
      return wifiManager.isConnected();
  }

  /**
   * 断开WiFi连接
   */
  public disconnect(): boolean {
    try {
      wifiManager.disconnect();
      return true;
    } catch (error) {
      console.error('Disconnect failed:', error);
      return false;
    }
  }

  /**
   * 获取当前连接的SSID
   */
  public getSSID(): string {
    try {
      const linkedInfo = wifiManager.getLinkedInfoSync();
      return linkedInfo?.ssid || '';
    } catch (error) {
      console.error('Get SSID failed:', error);
      return '';
    }
  }

  /**
   * 获取当前连接的BSSID
   */
  public getBSSID(): string {
    try {
      const linkedInfo = wifiManager.getLinkedInfoSync();
      return linkedInfo?.bssid?.toUpperCase() || '';
    } catch (error) {
      console.error('Get BSSID failed:', error);
      return '';
    }
  }

  /**
   * 获取当前信号强度
   */
  public getCurrentSignalStrength(): number {
    try {
      const linkedInfo = wifiManager.getLinkedInfoSync();
      return linkedInfo?.rssi || 0;
    } catch (error) {
      console.error('Get signal strength failed:', error);
      return 0;
    }
  }

  /**
   * 获取当前频率
   */
  public async getFrequency(): Promise<number> {
    try {
      const linkedInfo = await wifiManager.getLinkedInfo();
      return linkedInfo?.frequency || 0;
    } catch (error) {
      console.error('Get frequency failed:', error);
      return 0;
    }
  }

  /**
   * 获取当前IP地址
   */
  public getIP(): string {
    try {
      const linkedInfo = wifiManager.getIpInfo();
      if (linkedInfo && linkedInfo.ipAddress) {
        return this.intToIp(linkedInfo.ipAddress);
      }
      return '';
    } catch (error) {
      console.error('Get IP failed:', error);
      return '';
    }
  }

  /**
   * 移除WiFi网络配置
   */
  public removeWifiNetwork(ssidPrefix: string): boolean {
    try {
      return this.removeNetworkBySsid(ssidPrefix);
    } catch (error) {
      console.error('Remove wifi network failed:', error);
      return false;
    }
  }

  /**
   * 根据SSID移除网络的辅助方法
   */
  private removeNetworkBySsid(ssidPrefix: string): boolean {
    try {
      let removed = false;
      const ssidsToRemove: string[] = [];
      // ⚠️ 不要在遍历时 delete
      this.networkIdMap.forEach((networkId, ssid) => {
        if (ssid.startsWith(ssidPrefix)) {
          ssidsToRemove.push(ssid);
        }
      });

      ssidsToRemove.forEach((ssid) => {
        const networkId = this.networkIdMap.get(ssid);
        if (networkId !== undefined) {
          wifiManager.removeDevice(networkId); // ⚠️ 确认接口存在
          this.networkIdMap.delete(ssid);
          removed = true;
        }
      });

      return removed;
    } catch (error) {
      console.error('Remove network by SSID failed:', error);
      return false;
    }
  }


  /**
   * 检查网络是否已注册
   */
  public isRegisteredWifiNetwork(ssid: string): boolean {
    try {
      // 注意：需要检查鸿蒙是否有类似getDeviceConfigs的API
      // 此处为简化实现
      return false;
    } catch (error) {
      console.error('Check registered network failed:', error);
      return false;
    }
  }

  /**
   * 检查WiFi热点是否启用
   */
  public isWiFiAPEnabled(): boolean {
    try {
      return wifiManager.isHotspotActive();
    } catch (error) {
      console.error('Check hotspot enabled failed:', error);
      return false;
    }
  }

  /**
   * 启用/禁用WiFi热点
   */
  public async setWiFiAPEnabled(enabled: boolean, ssid?: string, password?: string): Promise<boolean> {
    console.error('setWiFiAPEnabled faild......');
    return false;
  }

  /**
   * 获取WiFi热点状态
   */
  public getWiFiAPState(): number {
    return this.localOnlyHotspotState;
  }

  /**
   * 获取热点客户端列表
   */
  public async getClientList(
    onlyReachables: boolean = false,
    reachableTimeout: number = 300
  ): Promise<string> {
    try {
      // 注意：鸿蒙WiFi API可能不直接提供客户端列表
      const clients: ClientScanResult[] = [];

      const result: ClientInfo[] = clients.map((client): ClientInfo => {
        return {
          IPAddr: client.ipAddr,
          HWAddr: client.hwAddr,
          Device: client.device,
          isReachable: client.isReachable
        };
      });

      return JSON.stringify(result);
    } catch (error) {
      console.error('Get client list failed:', error);
    }
    return '';
  }

  // ========== 辅助方法 ==========

  /**
   * 获取安全类型
   */
  private getSecurityType(security: string | null): wifiManager.WifiSecurityType {
    if (!security) {
      return wifiManager.WifiSecurityType.WIFI_SEC_TYPE_OPEN;
    }

    const securityUpper = security.toUpperCase();

    if (securityUpper === 'WPA' || securityUpper === 'WPA2') {
      return wifiManager.WifiSecurityType.WIFI_SEC_TYPE_PSK;
    } else if (securityUpper === 'WEP') {
      return wifiManager.WifiSecurityType.WIFI_SEC_TYPE_WEP;
    } else {
      return wifiManager.WifiSecurityType.WIFI_SEC_TYPE_OPEN;
    }
  }

  /**
   * 获取安全类型字符串
   */
  private getSecurityString(securityType: wifiManager.WifiSecurityType): string {
    switch (securityType) {
      case wifiManager.WifiSecurityType.WIFI_SEC_TYPE_OPEN:
        return '';
      case wifiManager.WifiSecurityType.WIFI_SEC_TYPE_WEP:
        return 'WEP';
      case wifiManager.WifiSecurityType.WIFI_SEC_TYPE_PSK:
        return 'WPA';
      case wifiManager.WifiSecurityType.WIFI_SEC_TYPE_SAE:
        return 'WPA3';
      default:
        return 'UNKNOWN';
    }
  }

  /**
   * 整数转IP地址
   */
  private intToIp(ip: number): string {
    const bytes: number[] = [
      (ip & 0xFF),
      ((ip >> 8) & 0xFF),
      ((ip >> 16) & 0xFF),
      ((ip >> 24) & 0xFF)
    ];
    return bytes.join('.');
  }

  /**
   * 睡眠函数
   */
  private sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, ms);
    });
  }
}

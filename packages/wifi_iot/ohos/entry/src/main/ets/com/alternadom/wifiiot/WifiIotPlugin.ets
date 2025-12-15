import wifi from '@ohos.wifi'
import {
  FlutterPlugin,
  MethodCall,
  MethodChannel,
  EventChannel
} from '@ohos/flutter_ohos'

export class WifiIotPlugin implements FlutterPlugin {

  private channel?: MethodChannel
  private scanEvent?: EventChannel
  private scanSink?: EventChannel.EventSink

  // =========================
  // Flutter 生命周期
  // =========================
  onAttachedToEngine(binding: any): void {
    this.channel = new MethodChannel(
      binding.binaryMessenger,
      'wifi_iot'
    )

    this.scanEvent = new EventChannel(
      binding.binaryMessenger,
      'wifi_iot_scan'
    )

    this.channel.setMethodCallHandler(this.onMethodCall.bind(this))
    this.scanEvent.setStreamHandler({
      onListen: this.onListen.bind(this),
      onCancel: this.onCancel.bind(this)
    })
  }

  onDetachedFromEngine(): void {
    this.channel?.setMethodCallHandler(null)
    this.scanSink = undefined
  }

  // =========================
  // MethodChannel
  // =========================
  private async onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    try {
      switch (call.method) {

        case 'isEnabled':
          result.success(wifi.isWifiActive())
          break

        case 'enableWifi':
          wifi.enableWifi()
          result.success(true)
          break

        case 'loadWifiList':
          result.success(this.getScanList())
          break

        case 'getSSID':
          result.success(wifi.getLinkedInfo()?.ssid ?? '')
          break

        case 'getBSSID':
          result.success(wifi.getLinkedInfo()?.bssid ?? '')
          break

        case 'getCurrentSignalStrength':
          result.success(wifi.getLinkedInfo()?.rssi ?? 0)
          break

        case 'connect':
          await this.connectWifi(
            call.argument('ssid'),
            call.argument('password')
          )
          result.success(true)
          break

        default:
          result.notImplemented()
      }
    } catch (e) {
      result.error(
        'WIFI_ERROR',
        JSON.stringify(e),
        null
      )
    }
  }

  // =========================
  // EventChannel（扫描）
  // =========================
  private onListen(_: any, sink: EventChannel.EventSink) {
    this.scanSink = sink
    this.startScan()
  }

  private onCancel() {
    this.scanSink = undefined
  }

  private startScan() {
    try {
      wifi.scan()
      wifi.on('wifiScanStateChange', (state) => {
        // 0 = 扫描完成
        if (state === 0) {
          this.scanSink?.success(this.getScanList())
        }
      })
    } catch (e) {
      this.scanSink?.error('SCAN_ERROR', JSON.stringify(e), null)
    }
  }

  // =========================
  // Wi-Fi 扫描结果
  // =========================
  private getScanList(): any[] {
    const list = wifi.getScanInfos()
    const result: any[] = []

    list.forEach(item => {
      if (item.ssid) {
        result.push({
          SSID: item.ssid,
          BSSID: item.bssid,
          level: item.rssi,
          frequency: item.frequency,
          security: item.securityType
        })
      }
    })

    return result
  }

  // =========================
  // Wi-Fi 连接（核心）
  // =========================
  private async connectWifi(ssid: string, password: string) {
    if (!wifi.isWifiActive()) {
      wifi.enableWifi()
    }

    const config: wifi.WifiDeviceConfig = {
      ssid: ssid,
      preSharedKey: password,
      securityType: wifi.WifiSecurityType.WIFI_SEC_TYPE_PSK
    }

    const netId = await wifi.addDeviceConfig(config)
    if (netId < 0) {
      throw new Error('addDeviceConfig failed')
    }

    await wifi.connectToNetworkId(netId)
  }
}

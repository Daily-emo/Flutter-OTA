# MineLamp OTA 开源方案调研与底层 POC 计划

> 日期：2026-11-18  
> 目标硬件：ESP32-C3FH4  
> 当前工程基线：Arduino-ESP32 3.3.10-cn（自定义板包）；本文件不假定该板包与官方 Arduino-ESP32 / ESP-IDF 完全一致。  
> 当前阶段：开源方案调研与实测路线确定；**尚未完成 C3 真机编译、烧录或 OTA 实测**。

## 0. 本次决策

暂停客户端正式功能与 UI 开发，不继续修补当前未跑通的 OTA 流程。建立独立的 ESP32-C3 OTA POC 工程，先证明 BLE 与 Wi-Fi 两条数据源都能把完整 BIN 写入 OTA 非活动分区、通过校验、切换启动分区、重启并回读版本。

**首选验证：Espressif `esp_ota_service`。**

它将 OTA 分成 Source、Target、Checker、Verifier 四层，官方组件已提供 HTTP/HTTPS、BLE GATT、应用分区写入、Manifest 版本检查、SHA-256、事件进度和 rollback 能力。BLE 与 Wi-Fi 使用不同 Source，但复用同一个 OTA Service / App Partition Target，不必再自研两套 Flash 写入和启动切换流程。

这是一项新近发布的官方组件，不应因为“官方”就直接判定成熟或已兼容 C3FH4。必须锁定版本、单独构建、真机双向升级和故障注入后才能决定是否采用。

## 1. 当前项目事实与边界

- 目标芯片为 ESP32-C3FH4。
- 当前固件工程基于 Arduino-ESP32 3.3.10-cn 自定义板包；该板包内嵌的 ESP-IDF 具体修订版本仍须从实际构建环境确认。
- 当前固件已有 Espressif 原生 `esp_ota_begin/write/end`、分区读取和 `esp_ota_set_boot_partition` 调用；因此当前主要待验证的是传输入口、会话状态、完整性校验、分区布局和升级生命周期，而不是重新发明 Flash 写入 API。
- 现有 BLE A5 控制帧、GATT UUID、MITM 权限和 15 秒上电准备窗口是 MineLamp 自有协议；不能假定它与 Espressif BLE OTA Profile 兼容。
- 历史诊断中，设备曾返回明确的 `WINDOW_EXPIRED`（15 秒窗口从设备上电开始计时），因此“准备窗口过期”与“完全没有收到设备 ACK”必须区分。
- 现有 Wi-Fi 路径与目标设计不同：目标是 ESP32 主动通过 HTTPS 下载 BIN（PULL），不是手机向设备局域网 HTTP PUSH。
- 本 POC 不修改现有灯控协议、UniApp 客户端或当前生产固件；先用 USB 串口烧录独立测试固件。
- 不使用独立 `.sig` 文件，不加入 RSA/ECDSA/Ed25519 应用层签名流程；保留 HTTPS 证书验证与 SHA-256 完整性校验。SHA-256 不等同于发布者身份认证。

## 2. 首选：Espressif ESP OTA Service

### 2.1 官方入口

| 资源 | 地址 | 用途 |
|---|---|---|
| Component Registry（固定版本） | https://components.espressif.com/components/espressif/esp_ota_service/versions/0.5.2~3/readme | 主组件文档 |
| 中文说明 | https://components.espressif.com/components/espressif/esp_ota_service/versions/0.5.2~3/readme?language=zh | 中文架构、配置和 API |
| BLE OTA 示例 | https://components.espressif.com/components/espressif/esp_ota_service/versions/0.5.2~3/examples/ota_ble?language=en | 官方 BLE GATT OTA |
| HTTP OTA 示例 | https://components.espressif.com/components/espressif/esp_ota_service/versions/0.5.2~3/examples/ota_http?language=en | Wi-Fi HTTP/HTTPS OTA |
| 版本变更 | https://components.espressif.com/components/espressif/esp_ota_service/versions/0.5.2~3/changelog?language=en | 版本变更记录 |
| License | https://components.espressif.com/components/espressif/esp_ota_service/versions/0.5.2~3/license?language=en | Espressif Modified MIT |

固定版本依赖配置（建议在 `main/idf_component.yml` 中声明精确版本，并提交 Component Manager 生成的锁文件）：

```yaml
dependencies:
  espressif/esp_ota_service:
    version: "0.5.2~3"
```

不要使用 `latest` 或宽泛版本范围。实际解析出的组件版本必须记录在构建报告中。

### 2.2 为什么优先选它

- **Source 层**：内置 HTTP/HTTPS、BLE GATT、文件系统等来源；也允许通过 Source 接口扩展。
- **Target 层**：内置应用 OTA 分区目标；同一 Target 可承接不同 Source 的升级。
- **Checker 层**：支持应用镜像版本、语义版本和 JSON Manifest 检查。
- **Verifier 层**：内置 SHA-256 / MD5；本项目只选择 SHA-256。
- **事件**：提供 Session、版本检查、条目开始、进度、条目结束和 Session 结束事件。
- **Rollback**：提供 pending-verify 检查、确认新固件和回滚 API。
- **Wi-Fi 断点续传**：HTTP Source 支持 seek 时可使用 NVS 断点；BLE Source 不支持 seek，必须将对应 item 的 `resumable=false`。

典型 HTTP + SHA-256 流程：

```text
HTTP/HTTPS Source
  -> Manifest Checker
  -> SHA-256 Verifier
  -> App Partition Target
  -> Commit
  -> Reboot
  -> Self-test
  -> Confirm or Rollback
```

BLE 使用 BLE GATT Source，复用相同 App Partition Target / Verifier / OTA Service。两个通道不能同时写同一 OTA 会话；必须由 OTA Manager 做互斥。

### 2.3 必须注意的限制

1. `esp_ota_service` v0.5.2~3 是较新的组件，生态使用量和第三方实测样本有限。它是最值得先跑的候选，不是已通过 MineLamp 实机认证的成品。
2. Component Registry 标注支持所有目标，但当前 `ota_ble` 示例页面给出的直接构建命令使用 `esp32s3`，默认分区配置为 4 MB。**必须在独立 POC 中切换 `esp32c3` 并完成完整编译、烧录和传输验证**，不能只凭组件支持矩阵推断 C3 示例已通过。
3. `ota_ble` 使用 Espressif BLE OTA APP Profile，与当前 MineLamp A5 自定义帧和 GATT UUID 不同。它用于证明底层 OTA 数据路径，不是直接替换当前 App 协议。
4. **已核对官方 BLE 示例源码：它当前把 `.verifier = NULL`，并只挂了 App 版本 Checker。** 因而官方示例默认只验证 BLE Sector CRC / 镜像结构，不会自动完成整个 BIN 的 SHA-256。要满足 MineLamp 需求，POC 必须显式创建 `esp_ota_service_verifier_sha256` 并提供 32 字节 expected_hash；第一轮可将测试 BIN 的摘要预置在设备，随后再验证由独立、受保护的元数据命令动态传入摘要。不能把 Sector CRC 当成整镜像 SHA-256。
5. **已核对官方 HTTP 示例源码：它默认使用明文 HTTP URL，并把 BIN URL 单独写在宏中。** Manifest Checker 当前解析 `version`、`project_name`、`size` 和可选 `sha256` / `md5`，并不完整覆盖 MineLamp 的 `device`、`url`、`changelog` 字段。HTTP 示例在缺少 SHA 或 SHA Verifier 创建失败时会继续无完整性校验地运行；MineLamp POC 必须改成 fail-closed：Manifest 缺 hash、摘要格式错误、Verifier 创建失败、device 不匹配或 URL 不合法时，全部拒绝升级。HTTPS 必须配置 CA/证书验证。
6. ESP32-C3FH4 官方数据手册标明片内 Flash 为 4 MB。官方 BLE 示例的 `sdkconfig.defaults` 将 `CONFIG_IDF_TARGET` 固定为 `esp32s3`；其 4 MB 分区 CSV 给两个 OTA Slot 各分配 1500 KB。相反，官方 HTTP 示例的 `sdkconfig.defaults` 固定 8 MB，分区 CSV 给两个 OTA Slot 各 2 MB，**不能直接照搬到 C3FH4**。统一 POC 应以 4 MB BLE 示例分区表为基础，让 BLE / Wi-Fi 共用完全相同的分区布局，并用 `idf.py size` 确认 BIN 小于 1500 KB（若不够，先评估裁剪或更改分区布局，不要直接烧录）。组件虽声明支持 all targets，但 C3 仍需独立修改 target 并实测。
7. 官方 BLE 示例把等待 START 的超时配置为 180 秒，不是 MineLamp 当前的 15 秒上电窗口；POC 应先按官方 START/ACK 生命周期测试，不沿用旧 15 秒门槛。
8. 官方组件 License 为 **Espressif Modified MIT**，限定与 Espressif 产品配合使用；ESP32 属于其适用范围，但分发时应保留许可文本。
9. 当前发布的 BLE Source 不支持 seek，因此不要错误启用 BLE 断点续传；断连后应中止/清理会话并从头重试，除非后续另行实现经验证的持久化偏移协议。

## 3. 第二优先：Espressif BLE OTA Raw Profile + 原生 OTA API

如果完整 `esp_ota_service` 在 C3 构建、依赖体积或当前工程集成方面遇到障碍，退回更小的官方 BLE 传输层：

| 资源 | 地址 |
|---|---|
| `ble_ota_raw` v0.2.0 | https://components.espressif.com/components/espressif/ble_ota_raw/versions/0.2.0/readme |
| 官方 BLE 示例 | https://components.espressif.com/components/espressif/ble_ota_raw/versions/0.2.0/examples/ble_ota?language=en |
| 组件变更记录 | https://components.espressif.com/components/espressif/ble_ota_raw/versions/0.2.0/changelog?language=en |
| License | https://components.espressif.com/components/espressif/ble_ota_raw/versions/0.2.0/license?language=en |
| ESP-IoT-Solution BLE Profile 文档 | https://docs.espressif.com/projects/esp-iot-solution/en/latest/bluetooth/ble_ota.html |

组件特征：

- NimBLE / `esp_ble_conn_mgr` 后端。
- GATT Service `0x8018`；特征 `0x8020` 至 `0x8023`。
- 按 4 KB Sector 接收，校验包序号、Sector 顺序和 CRC16。
- Sector CRC 通过后才回调应用层。
- ACK 由官方 Profile 负责；应用层只需把已校验的数据送入 OTA 写入任务。
- v0.2.0 增加 OTA Begin Hook：例如 `esp_ota_begin()` 成功后才允许接收；并支持根据 ring buffer 容量配置 Sector Send Window。
- License：Apache-2.0；Registry 标注支持所有目标。

此方案需要应用层把 BLE Source 回调交给 OTA 写入任务，并与 Wi-Fi HTTP Source 共用同一个 OTA Writer / Session Manager。它比完整 OTA Service 多一些应用层接线，但 BLE 协议解析不必自己实现。

## 4. Wi-Fi 路径：Espressif 原生 HTTPS OTA

| 资源 | 地址 |
|---|---|
| ESP-IDF OTA 总览（C3） | https://docs.espressif.com/projects/esp-idf/en/stable/esp32c3/api-reference/system/ota.html |
| ESP-IDF HTTPS OTA | https://docs.espressif.com/projects/esp-idf/en/latest/esp32/api-reference/system/esp_https_ota.html |
| ESP-IDF OTA 示例目录 | https://github.com/espressif/esp-idf/tree/master/examples/system/ota |
| ESP-IDF Simple HTTPS OTA | https://github.com/espressif/esp-idf/tree/master/examples/system/ota/simple_ota_example |
| ESP-IDF Advanced HTTPS OTA | https://github.com/espressif/esp-idf/tree/master/examples/system/ota/advanced_https_ota |

官方 `esp_https_ota` 是现有 OTA API 的 HTTPS 抽象层，支持证书验证、分段下载和断点续传相关能力。TLS 必须校验可信根证书/证书包与主机名，禁止 TrustAll。

注意：高层 `esp_https_ota` 的 Finish 成功路径会设置新启动分区。如果项目要求先完成自定义 Manifest / SHA-256 校验再 Commit，应使用 `esp_ota_service` 的 Verifier → Target Commit 流程，或明确控制原生 OTA API 的校验和启动分区提交顺序；不能在额外 SHA-256 校验前就提前切换启动分区。

ESP-IDF 应用安全 OTA 至少需要：
- 两个 App OTA Slot（`ota_0`、`ota_1`）。
- `otadata` 分区。
- 当前运行分区与待写入分区不同。
- `esp_ota_end()` / 镜像校验成功后才能提交启动分区。
- 开启 `CONFIG_BOOTLOADER_APP_ROLLBACK_ENABLE`，新固件启动自检通过后调用确认 API；自检失败则回滚。

C3FH4 的实际 Flash 容量和现有分区表必须从芯片与当前构建产物读取，不得照搬其他板子的分区 CSV。每个 OTA Slot 必须容纳实际 BIN，4 MB 总 Flash 下还要给 NVS、PHY、OTA data、应用和其他数据分区留空间。

## 5. 其他可复用项目

### 5.1 Arduino BLE OTA：gb88/BLEOTA

- 地址：https://github.com/gb88/BLEOTA
- Web Bluetooth 客户端：https://gb88.github.io/BLEOTA/
- 支持 Arduino-ESP32 3.3.0+，README 列出 ESP32-C3/C6。
- 使用 4 KB Sector CRC16、zlib 压缩和分段流水线。
- 提供 Web Bluetooth 客户端，适合快速验证 Arduino Core 3.3.x BLE 传输。
- 可选 RSA-2048 + SHA-256 签名；本项目不需要该签名功能。
- **License：AGPL-3.0**。不建议直接作为 MineLamp 最终依赖，除非先审查许可证义务；可作为独立技术对照。

### 5.2 h2zero/NimBLEOta

- 地址：https://github.com/h2zero/NimBLEOta
- 基于 Espressif BLE OTA Profile，使用 Service `0x8018` 和官方特征布局。
- 依赖 NimBLE-Arduino 2.1+ / esp-nimble-cpp 2.0+。
- 提供 Python 上传脚本，适合 Arduino + NimBLE 的 BLE 对照实验。
- 仅解决 BLE，不是完整双通道 OTA；Wi-Fi 仍需单独使用官方 OTA API。
- 当前 Arduino Core 3.3.x 已有自身 NimBLE 后端变化，必须按实际 core 版本检查依赖，避免重复链接 BLE Host。

### 5.3 kodira/simple_ble_ota

- 地址：https://components.espressif.com/components/kodira/simple_ble_ota/versions/0.2.0/readme
- ESP-IDF >= 5.4，NimBLE only，Registry 列出 ESP32-C3/C6。
- CRC32、错误 Notify、Python Bleak 客户端，文档声称典型 40+ KB/s。
- MIT License。
- 仅 BLE，Registry 使用量较少；适合作为 BLE 最小对照，不作为双通道主架构。

### 5.4 fbiego/ESP32_BLE_OTA_Arduino

- 地址：https://github.com/fbiego/ESP32_BLE_OTA_Arduino
- MIT License；有 Android App 和 Python 客户端。
- README 记录约 1 MB / 85 秒、峰值约 12 KB/s 的 BLE 传输示例。
- 可用于了解 Arduino BLE OTA 分包和客户端流程；年代较早，不作为 C3 新项目主选。

### 5.5 Meshtastic 双通道实验

- 地址：https://github.com/meshtastic/esp32-unified-ota
- 仓库明确是 Wi-Fi / BLE updater 的实验性拼接，协议同时支持 Wi-Fi TCP 和 BLE GATT ACK。
- BLE 有应用层 ACK；Wi-Fi 使用 TCP；使用 SHA-256 和 NVS 预置摘要。
- **不推荐直接采用**：README 自述为实验性 mash-up；仓库体量和采用度较低；License 为 GPL-3.0；构建指引主要列 ESP32 / ESP32-S3，未提供 C3 验证步骤；其 hash 预置与网络信任假设也不符合本项目最终 HTTPS Manifest 工作流。
- 可阅读其双通道握手和 ACK 设计，但不要复制为 MineLamp 主协议。

### 5.6 Wi-Fi 回滚参考

- 地址：https://github.com/izhardh/esp32-secure-fota
- 作者记录了 ESP32-WROOM、ESP-IDF 5.5.4、4 MB Flash 的 Wi-Fi OTA、SHA-256、A/B 分区、断电中断和 rollback 手动测试。
- 仅 Wi-Fi、不是 C3 目标、项目采用度有限；适合作为故障注入测试清单参考，不作为依赖。

## 6. 方案比较与选择

| 方案 | BLE | Wi-Fi | SHA-256 / Manifest | C3 适配证据 | 决策 |
|---|---|---|---|---|---|
| Espressif `esp_ota_service` | 官方 BLE GATT Source | HTTP/HTTPS Source | 内置 | 组件标注 all targets；示例需实测 C3 | **首选 POC** |
| Espressif `ble_ota_raw` + 原生 OTA | 官方 BLE Profile | 需另接 HTTP(S) Source | 应用层配置 | 组件标注 all targets | 首选回退 |
| `gb88/BLEOTA` | Arduino BLE | 无内置 Wi-Fi OTA | Sector CRC；可选签名 | README 明列 C3、Core 3.3+ | Arduino BLE 对照 |
| `simple_ble_ota` | NimBLE | 无 | CRC32 | Registry 明列 C3 | BLE 最小对照 |
| Meshtastic Unified OTA | BLE | TCP | SHA-256 / NVS 预置 | 未见 C3 实测步骤 | 仅阅读 |
| ESP-IDF `esp_https_ota` | 无 | HTTPS | TLS / OTA API；可扩展摘要 | 官方 C3 文档 | Wi-Fi 基准 |

## 7. 独立 POC 的实际执行顺序

### P0：环境与分区盘点

1. 固定 ESP-IDF 版本和工具链；记录 `idf.py --version`、目标芯片、Flash 容量、分区表。
2. 备份当前 C3 稳定固件和分区 CSV；POC 只通过 USB 烧录独立固件。
3. C3FH4 为 4 MB Flash；检查至少有两个可容纳测试 BIN 的 OTA App Slot 和 `otadata` 分区。上游 BLE 示例的 1500 KB 双 Slot 可作为起点；HTTP 示例的 8 MB / 2 MB 双 Slot 布局不能直接用在此芯片上。
4. 选择固定 `esp_ota_service` 版本，先在 C3 执行完整编译；如果 C3 不通过，记录首个错误和依赖链，不用改现有 Arduino 项目绕过。
5. POC 不沿用 MineLamp 当前 15 秒上电 PREPARE 窗口；先按官方 Profile 自身 START/ACK 流程测试，避免把旧应用层窗口故障带进新底层验证。

### P1：BLE 单通道端到端

1. 从官方 `ota_ble` 示例创建独立工程；先按原始官方流程证明 BLE 传输 / Sector CRC / ACK 通路，再增加整镜像 SHA-256 Verifier。第一轮把已知测试 BIN 的 32 字节 SHA-256 预置到 POC，专门验证 hash mismatch 时 Target 不会 Commit。
2. 由于官方 BLE APP 协议本身没有提供 MineLamp Manifest 的 SHA-256 字段，动态更新时必须增加独立元数据步骤：由已配对且通过权限校验的控制通道先提交 `device/version/size/sha256`，设备校验后保存到当前 OTA session；随后 BLE Source 传输 BIN。不要修改 Sector 数据包格式来夹带未经验证的字段。
3. 将目标切换为 `esp32c3`，确认 NimBLE Host、实际 Flash 容量和 OTA 分区配置。
4. USB 烧录并保存完整串口启动日志、GATT Service/Characteristic 清单。
5. 安装 Espressif BLE OTA Android App：https://github.com/EspressifApps/esp-ble-ota-android/releases
6. 选择 BIN 进行 BLE 传输，记录每个 START / Sector / ACK / STOP、字节数、CRC 错误、耗时和设备串口日志。
7. 配置并验证整镜像 SHA-256；故意使用错误摘要时必须失败，且不能提交启动分区。
8. 设备重启后读取版本号和运行分区，确认升级成功。

### P2：Wi-Fi HTTPS 单通道端到端

1. 基于官方 `ota_http` 示例配置设备 Wi-Fi。注意上游示例默认是 HTTP，且在 SHA 缺失/Verifier 创建失败时可能降级为不校验；POC 必须改为 HTTPS + fail-closed。
2. 使用测试 HTTPS 服务器，固件内置可信 CA 根证书或使用 ESP x509 Certificate Bundle；不能关闭证书校验。
3. Manifest 至少包含 `device`、`version`、`url`、`size`、`sha256`、`changelog`。先确认组件内置 Manifest Checker 的字段要求；不支持的扩展字段通过自定义 Checker 处理。
4. 设备主动 HTTPS GET Manifest 和 BIN（PULL），记录 HTTP 状态、TLS 验证、下载字节数、SHA-256、Commit 与重启日志。
5. 测试错误 CA、错误 Hostname、HTTP 404/500、下载中断、长度不匹配、SHA-256 错误；均不得切换启动分区。

### P3：双向交叉验证（最重要）

先分别以官方 `ota_ble` 与 `ota_http` 示例作为基准，两个通道各自通过后，再建立**一个同时编译 BLE Source 与 HTTP Source 的统一 POC 固件**：共用同一个 `esp_ota_service_t`、同一个 App Partition Target 和同一套 SHA-256 / Commit / Rollback 生命周期；由测试命令选择本次使用 BLE 或 Wi-Fi，禁止两个 Source 并发写入。不能只用两个互不相关的 Demo 分别成功来宣称双通道共用 OTA 核心。

使用不同版本号和可识别的固件 Build ID：

- USB 初始烧录 POC v0.1.0。
- BLE 升级到 v0.1.1，重启并回读版本。
- Wi-Fi HTTPS 升级到 v0.1.2，重启并回读版本。
- BLE 再升级到 v0.1.3，重启并回读版本。
- Wi-Fi 再升级到 v0.1.4，重启并回读版本。

这一步证明两种 Source 交替使用同一 OTA App Target / A-B 分区生命周期，而不是只证明两个独立 Demo 分别可以运行。

### P4：可靠性与回滚

- BLE 传输中主动断开连接。
- Wi-Fi 下载中断网或停止服务器。
- 在 OTA 擦除、写入、校验、Commit 和首次启动阶段分别断电。
- 注入错误 SHA-256、错误镜像头、错误长度和不足分区空间。
- 新固件首次启动自检失败，验证 bootloader rollback 回到上一版本。
- 每种传输至少重复 10 次；交叉升级至少重复 5 轮。
- 所有失败路径都要确认旧固件仍可启动，失败固件不能被提交。

### POC 通过标准

只有同时满足以下条件才算“底层 OTA 已跑通”：

- C3 完整编译、烧录成功。
- BLE OTA 与 Wi-Fi HTTPS OTA 各自完成真实 BIN 传输。
- BLE 与 Wi-Fi 能交替升级同一设备、同一 A/B OTA 分区机制。
- 接收长度与源 BIN 一致，SHA-256 一致。
- 错误摘要、TLS 验证失败、损坏镜像、传输中断均不能切换启动分区。
- 新固件重启并读取目标版本后才报告 SUCCESS。
- 断电与自检失败回滚通过。
- 有可复现的串口日志、App/PC 传输日志、BIN SHA-256 和每轮测试记录。

## 8. POC 之后才进入 App

底层验证通过后，再按以下顺序接入 UniApp：

- 若采用 `esp_ota_service`：先使用 Espressif 官方 BLE OTA App 验证设备端，再由 UniApp BLE 客户端按相同官方 ESP BLE OTA Profile 实现；Wi-Fi 通道向设备下发 HTTPS Manifest / 启动请求和查询状态，BIN 由设备自行下载。
- 若采用 `ble_ota_raw`：UniApp BLE 端按官方 Sector / Sequence / CRC16 / ACK 协议实现；Wi-Fi 仍为设备端 HTTPS PULL。
- MineLamp 原有身份服务、灯控协议和配对安全策略单独保留；不要把 OTA Profile 的测试 UUID 与现有灯控 UUID 混为一谈。
- 当前 A5 自定义 OTA 协议只有在完成兼容性评估后才决定保留或替换，不预先把它当成新底层协议的前提。

## 9. 当前未完成 / 不能宣称的事项

- 尚未在本执行环境安装 ESP-IDF 工具链；当前没有 `idf.py`、RISC-V ESP 编译器或 Arduino CLI。
- 当前没有连接可供我直接烧录和测量的 ESP32-C3FH4 开发板。
- 因此本报告是基于官方文档、Component Registry 和公开源码的调研与可执行测试计划；**不是已完成的 C3 编译报告，更不是 BLE/Wi-Fi OTA 真机通过报告**。
- 现有客户端代码没有被改动；本分支先承载 OTA POC 调研和设备端工程。下一步应建立独立的最小 ESP-IDF POC 工程并在 C3 上实测，底层通过后再开发 UniApp 通信测试模块。

## 10. 参考资料总表

1. Espressif OTA Service v0.5.2~3: https://components.espressif.com/components/espressif/esp_ota_service/versions/0.5.2~3/readme
2. Espressif OTA Service BLE example: https://components.espressif.com/components/espressif/esp_ota_service/versions/0.5.2~3/examples/ota_ble?language=en
3. Espressif OTA Service HTTP example: https://components.espressif.com/components/espressif/esp_ota_service/versions/0.5.2~3/examples/ota_http?language=en
4. Espressif BLE OTA Raw v0.2.0: https://components.espressif.com/components/espressif/ble_ota_raw/versions/0.2.0/readme
5. Espressif BLE OTA Profile docs: https://docs.espressif.com/projects/esp-iot-solution/en/latest/bluetooth/ble_ota.html
6. Espressif BLE OTA Android App: https://github.com/EspressifApps/esp-ble-ota-android/releases
7. ESP-IDF OTA docs for ESP32-C3: https://docs.espressif.com/projects/esp-idf/en/stable/esp32c3/api-reference/system/ota.html
8. ESP-IDF HTTPS OTA docs: https://docs.espressif.com/projects/esp-idf/en/latest/esp32/api-reference/system/esp_https_ota.html
9. ESP-IDF OTA examples: https://github.com/espressif/esp-idf/tree/master/examples/system/ota
10. gb88 BLEOTA: https://github.com/gb88/BLEOTA
11. h2zero NimBLEOta: https://github.com/h2zero/NimBLEOta
12. kodira simple_ble_ota: https://components.espressif.com/components/kodira/simple_ble_ota/versions/0.2.0/readme
13. fbiego ESP32 BLE OTA Arduino: https://github.com/fbiego/ESP32_BLE_OTA_Arduino
14. Meshtastic ESP32 Unified OTA: https://github.com/meshtastic/esp32-unified-ota
15. ESP32 Secure FOTA: https://github.com/izhardh/esp32-secure-fota
16. OTA BLE example source (verifier currently NULL): https://github.com/espressif/esp-adf/blob/master/components/esp_ota_service/examples/ota_ble/main/esp_ota_service_ble_example.c
17. OTA HTTP example source (Manifest / SHA-256 flow): https://github.com/espressif/esp-adf/blob/master/components/esp_ota_service/examples/ota_http/main/esp_ota_service_http_example.c
18. Manifest Checker schema: https://github.com/espressif/esp-adf/blob/master/components/esp_ota_service/include/checker/esp_ota_service_checker_manifest.h
19. SHA-256 Verifier API: https://github.com/espressif/esp-adf/blob/master/components/esp_ota_service/include/verifier/esp_ota_service_verifier_sha256.h
20. BLE example partition table: https://github.com/espressif/esp-adf/blob/master/components/esp_ota_service/examples/ota_ble/partitions.csv
21. BLE example sdkconfig defaults: https://github.com/espressif/esp-adf/blob/master/components/esp_ota_service/examples/ota_ble/sdkconfig.defaults
22. ESP32-C3 Series Datasheet (C3FH4 4 MB Flash): https://documentation.espressif.com/esp32-c3_datasheet_en.pdf

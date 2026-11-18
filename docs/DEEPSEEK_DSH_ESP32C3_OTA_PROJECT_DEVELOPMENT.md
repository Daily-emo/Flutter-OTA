# DeepSeek DSH：MineLamp ESP32-C3 双通道 OTA 项目开发总任务书

> 文档性质：可直接交给 DeepSeek 执行的完整工程任务书  
> 目标硬件：ESP32-C3FH4，片内 Flash 4 MB  
> 固件开发方式：原生 ESP-IDF 工程  
> 首选 OTA 底层：Espressif `esp_ota_service`，固定版本 `0.5.2~3`  
> 客户端验证顺序：Espressif 官方 BLE OTA 测试 App → UniApp 通信测试 → 稳定性测试 → 回滚测试 → 正式 UI  
> 重要原则：先固件、后通信客户端、最后 UI。任何阶段没有实际运行证据，不得标记为已通过。

---

# 0. 总任务与最终目标

请把本文档作为当前 OTA 项目的**唯一执行规范**。不要停留在方案讨论，不要先做客户端页面，也不要继续修补过去未跑通的 OTA 实现。

本项目要从设备端重新建立一套可实测、可复现、可验证的 ESP32-C3 双通道 OTA 基础设施。

最终必须实现：

1. 一份可独立构建和烧录的 ESP32-C3FH4 固件。
2. 固件支持 BLE OTA 与 Wi-Fi HTTPS OTA 两种数据来源。
3. 两种来源共用同一 OTA Manager、同一 OTA Service、同一 SHA-256 校验、同一 App OTA 分区写入和同一回滚机制。
4. 先通过 Espressif 官方 BLE OTA 测试 App 完成真实 BIN 传输，证明 BLE 底层链路可用。
5. 再编写 UniApp 通信测试模块，复现相同 BLE OTA Profile，完成真实 BIN 传输。
6. Wi-Fi OTA 由设备主动 HTTPS 下载 Manifest 和 BIN（PULL），不是手机向设备推送 BIN。
7. 完成连续升级、交叉升级、断连、断网、错误镜像、错误摘要、意外复位、断电和启动失败测试。
8. 证明 OTA 失败不会破坏原有可启动固件；新固件自检失败时能由 bootloader 回滚。
9. 以上全部通过后，才开发正式 OTA UI。

**明确开发顺序：**

```text
P0 工具链 / 硬件 / 分区核查
  ↓
P1 ESP32-C3 最小固件启动与 OTA 分区验证
  ↓
P2 BLE OTA 固件实现
  ↓
P3 Espressif 官方 BLE OTA App 实测
  ↓
P4 Wi-Fi HTTPS OTA 固件实现与实测
  ↓
P5 统一双通道固件与交叉升级验证
  ↓
P6 UniApp BLE 通信测试模块
  ↓
P7 UniApp 与设备端联合传输测试
  ↓
P8 稳定性 / 故障注入测试
  ↓
P9 意外回滚 / 启动自检 / 恢复测试
  ↓
P10 正式 OTA UI
```

不要跳过阶段。前一阶段未达到验收条件，不得进入后一阶段。若硬件或工具链缺失，完成能够完成的代码和文档，并明确列出必须由用户执行的实机操作；不得伪造测试结果。

---

# 1. 项目背景、当前问题和硬件约束

## 1.1 当前已知情况

- 目标 MCU：ESP32-C3FH4。
- 芯片片内 Flash：4 MB；仍需在实际开发板上读取 Flash ID / 容量进行确认。
- 当前历史固件使用 Arduino-ESP32 3.3.10-cn 自定义板包；该板包所绑定的 ESP-IDF 具体修订版本不能凭版本名称猜测，必须从原工程构建日志或板包中确认。
- 历史 OTA 实现曾出现准备指令发送失败、GATT 属性不支持、等待设备响应超时、BLE 连接中断等问题。
- 现有灯控 BLE Service、设备身份 UUID、配对权限和 A5 控制帧属于 MineLamp 自有协议。
- 历史固件存在 15 秒 OTA 准备窗口。新 POC 不沿用这个 15 秒限制，先使用官方 OTA Profile 的 Start / ACK 流程和合理等待时间，避免把旧逻辑问题带入底层验证。
- 本任务先建立独立 OTA 测试固件，不修改现有灯控固件，不修改现有灯控通信协议。

## 1.2 必须坚持的硬件约束

1. 所有固件必须以 ESP32-C3 为目标编译，不能使用 ESP32-S3 的 sdkconfig 或分区表直接代替。
2. 按 4 MB Flash 规划双 OTA App Slot。
3. 两个 OTA Slot 都必须能够容纳最终实际编译出的 BIN。
4. 烧录独立 POC 固件前，必须备份现有可用固件和分区表，并向用户说明烧录会覆盖设备 Flash。
5. 实机测试使用稳定供电；不得在供电不稳定、储能不足或负载异常的情况下进行断电故障测试。
6. 不允许因为分区不足就删除 OTA 回滚、SHA-256 或 TLS 校验。

---

# 2. 技术路线与开源项目选择

## 2.1 首选：Espressif 官方 OTA Service

固定研究和验证以下组件：

- Component：`espressif/esp_ota_service`
- 固定版本：`0.5.2~3`
- 官方 BLE Source：ESP BLE OTA APP Profile
- 官方 HTTP / HTTPS Source
- 官方 App Partition Target
- 官方 SHA-256 Verifier
- 官方 OTA Service 事件与 rollback API

官方入口：

| 资源 | 地址 |
|---|---|
| OTA Service 组件文档 | https://components.espressif.com/components/espressif/esp_ota_service/versions/0.5.2~3/readme |
| BLE OTA 示例 | https://components.espressif.com/components/espressif/esp_ota_service/versions/0.5.2~3/examples/ota_ble |
| HTTP OTA 示例 | https://components.espressif.com/components/espressif/esp_ota_service/versions/0.5.2~3/examples/ota_http |
| 上游源码 | https://github.com/espressif/esp-adf/tree/master/components/esp_ota_service |
| 官方 BLE OTA Android 测试 App | https://github.com/EspressifApps/esp-ble-ota-android |
| 官方 BLE OTA App Releases | https://github.com/EspressifApps/esp-ble-ota-android/releases |
| ESP-IDF OTA 文档 | https://docs.espressif.com/projects/esp-idf/en/stable/esp32c3/api-reference/system/ota.html |
| ESP-IDF HTTPS OTA 文档 | https://docs.espressif.com/projects/esp-idf/en/latest/esp32/api-reference/system/esp_https_ota.html |
| ESP32-C3 数据手册 | https://documentation.espressif.com/esp32-c3_datasheet_en.pdf |

Component Manager 依赖必须精确锁定版本。建议在 `main/idf_component.yml` 中使用：

```yaml
dependencies:
  espressif/esp_ota_service:
    version: "0.5.2~3"
```

必须提交 Component Manager 实际生成的依赖锁文件，并在报告中记录实际解析的组件版本。不得使用 `latest` 或无上限版本范围。

## 2.2 为什么选择 OTA Service

整体结构为：

```text
BLE Source ─────────┐
                    ├── OTA Service ── SHA-256 Verifier
HTTPS Source ───────┘                    │
                                        ▼
                               App Partition Target
                                        │
                                  Commit / Reboot
                                        │
                              Boot Self-test / Rollback
```

- BLE 和 HTTPS 只负责提供固件数据。
- OTA Service 负责统一调度读取、校验、写入和生命周期。
- App Partition Target 负责写入非活动 OTA App Slot。
- SHA-256 Verifier 负责对完整 BIN 计算摘要并与期望摘要比对。
- 只有校验成功后才允许 Target Commit。
- 新固件启动后先进行自检，通过后才确认固件；未确认而发生异常复位时由 bootloader 回滚。

禁止分别实现两套 Flash 写入逻辑。

## 2.3 官方示例存在的缺口，必须在 POC 中补齐

1. 官方 BLE 示例的 `.verifier` 当前为 NULL，不能直接视为已经启用整镜像 SHA-256。必须显式创建 SHA-256 Verifier。
2. BLE Sector CRC16 只用于传输分包完整性，不等同于整个 BIN 的 SHA-256。
3. 官方 HTTP 示例默认配置和示例 URL 不能直接视为生产 HTTPS 安全配置。必须启用 CA / 证书验证，并验证主机名。
4. 官方 HTTP 示例存在缺少摘要或摘要校验器初始化失败时继续运行的示例逻辑。MineLamp 必须采用 **fail-closed**：任何必需校验缺失或初始化失败都拒绝 OTA。
5. 官方 BLE 示例默认 sdkconfig 使用 ESP32-S3，必须切换为 ESP32-C3，并检查 C3 实际可用的 NimBLE 配置。
6. 官方 HTTP 示例分区表按 8 MB 配置，不得直接用于 4 MB 的 C3FH4。
7. BLE Source 不支持 `seek()`，所以第一阶段 BLE OTA 必须设置 `resumable=false`，不能启用并不存在的 BLE 断点续传能力。

---

# 3. 工程目录与代码组织

在仓库中新建完全独立的设备端目录，不要将 OTA POC 混入客户端源码。

建议结构：

```text
ota-poc/
  esp32/
    CMakeLists.txt
    sdkconfig.defaults
    partitions.csv
    main/
      CMakeLists.txt
      idf_component.yml
      app_main.c
      ota_manager.c
      ota_manager.h
      ota_ble.c
      ota_ble.h
      ota_wifi.c
      ota_wifi.h
      ota_manifest.c
      ota_manifest.h
      ota_console.c
      ota_console.h
      ota_events.c
      ota_events.h
      ota_boot_check.c
      ota_boot_check.h
  tools/
    make_manifest.py
    verify_bin.py
    https_test_server.py
    generate_test_cert.ps1
  uniapp-test/
    README.md
    protocol/
    services/
    pages/
  docs/
    BUILD_AND_FLASH.md
    BLE_PROFILE_PROTOCOL.md
    WIFI_HTTPS_TEST.md
    UNIAPP_TRANSPORT_TEST.md
    STABILITY_TEST_PLAN.md
    ROLLBACK_TEST_PLAN.md
    TEST_RESULTS_TEMPLATE.md
    TEST_RESULTS/
  .gitignore
```

目录创建可以分阶段进行：

- P0-P5 只实现 `esp32/`、`tools/` 和对应固件测试文档。
- P6 固件 BLE OTA 通过官方测试 App 后，才创建并实现 `uniapp-test/`。
- P10 所有测试通过后，再开发正式页面；诊断测试页面不等于正式 UI。

所有生成目录、编译产物、真实 Wi-Fi 密码、私钥和用户本地证书必须加入 `.gitignore`。

---

# 4. P0：工具链、环境和硬件核查

## 4.1 环境核查

DeepSeek 首先检查执行环境，不要直接写大量代码。

必须记录：

- 操作系统版本。
- ESP-IDF 精确版本。
- Python 版本。
- CMake 版本。
- Ninja 版本。
- RISC-V GCC 工具链版本。
- ESP-IDF Component Manager 版本。
- `IDF_PATH`。
- `idf.py --version`。
- 目标芯片和 Flash 容量。
- 依赖解析结果。

使用 ESP-IDF 官方安装和构建流程。不要将 Arduino Core 的构建环境与本次原生 ESP-IDF POC 混在一起。

## 4.2 硬件核查

通过串口启动信息或 esptool 读取：

- 芯片型号。
- 芯片修订版本。
- Flash Manufacturer / Device ID。
- Flash 实际容量。
- MAC 地址（日志中可脱敏）。
- 当前固件版本。
- 当前运行分区。

如果没有真实开发板，只能完成代码和静态检查，实机项目全部标记为 NOT RUN。

## 4.3 备份和烧录保护

在第一次完整擦写前：

1. 指导用户备份原固件。
2. 备份原分区表。
3. 记录原固件版本和可恢复烧录命令。
4. 说明全片擦除与普通烧录的区别。
5. 未经用户确认，不得执行可能覆盖唯一可用固件的全片擦除操作。

**P0 验收：** 工具链、目标芯片、Flash 容量、分区规划和恢复方案都有明确记录。

---

# 5. P1：最小 ESP32-C3 固件和 A/B 分区

## 5.1 先建立能稳定启动的最小固件

第一份固件不加入复杂 UI、不加入完整升级流程，只完成：

- ESP32-C3 正常启动。
- 串口日志。
- 设备版本信息。
- Flash / Partition 信息输出。
- NVS 初始化。
- 当前运行分区输出。
- OTA 可用分区输出。
- 基本看门狗和异常重启原因输出。

先构建、烧录、启动和复位，确保工具链和板级配置可靠。

## 5.2 4 MB 分区表

可以从官方 BLE 示例的 4 MB 分区布局开始：

```csv
# Name,   Type, SubType, Offset,   Size,   Flags
nvs,      data, nvs,     0x9000,   0x4000,
otadata,  data, ota,     0xd000,   0x2000,
phy_init, data, phy,     0xf000,   0x1000,
ota_0,    app,  ota_0,   0x10000,  1500K,
ota_1,    app,  ota_1,   ,         1500K,
```

要求：

- BLE 和 Wi-Fi 最终必须使用同一分区表。
- 两个 OTA Slot 均需能容纳同一个最终固件 BIN。
- 使用 `idf.py size` 和实际 BIN 大小检查容量。
- 如果固件超过 1500 KB，先分析组件依赖和配置，不允许直接删除核心校验与回滚。
- 如确需调整分区，先计算完整 4 MB 布局，并提交修改理由和容量计算。
- 不得复制官方 HTTP 示例的 8 MB / 双 2 MB 分区表。

## 5.3 启用回滚

至少检查并启用：

```text
CONFIG_OTA_ENABLE_ROLLBACK=y
CONFIG_BOOTLOADER_APP_ROLLBACK_ENABLE=y
```

确认 bootloader、partition table 和应用配置均支持回滚。不能只在应用层打印“rollback enabled”。

**P1 验收：**

- [ ] C3 目标构建成功。
- [ ] 4 MB Flash 识别正确。
- [ ] 两个 OTA Slot 容量足够。
- [ ] 固件能烧录和启动。
- [ ] 串口可读当前运行分区。
- [ ] OTA rollback 配置已生效并有配置证据。

---

# 6. P2：BLE OTA 固件实现

## 6.1 必须复用官方 BLE OTA Source

使用：

```c
esp_ota_service_source_ble_create()
```

使用官方 BLE OTA APP Profile，不得自己重新设计 BLE GATT 分包、ACK、Sector CRC、窗口和重传。

官方 Profile 已知关键参数：

| 项目 | 值 |
|---|---|
| Service UUID | `0x8018` |
| Firmware Receive Characteristic | `0x8020` |
| Command Characteristic | `0x8022` |
| 传输结构 | Sector-based |
| ACK | 20-byte ACK indication |
| 分包校验 | CRC16-CCITT |
| Source seek | 不支持 |

DeepSeek 必须进一步阅读官方 Android App 和 ESP-IDF / ESP-IoT-Solution 对应源码，整理完整的字节级协议，包含命令码、字段长度、字节序、Sector 结构、ACK 字段和错误处理，输出：

`docs/BLE_PROFILE_PROTOCOL.md`

禁止凭经验猜测协议字段。

## 6.2 NimBLE 配置

按 ESP32-C3 的实际支持情况配置 NimBLE。检查官方组件 Kconfig：

- `CONFIG_OTA_ENABLE_BLE_SOURCE=y`
- `CONFIG_BT_ENABLED=y`
- `CONFIG_BT_NIMBLE_ENABLED=y`
- `CONFIG_BT_NIMBLE_ATT_PREFERRED_MTU`：根据芯片和客户端能力配置。
- BLE OTA 等待 Start 的超时：先设置合理值，例如 120 秒；不得沿用历史 15 秒上电窗口。

不能盲目复制 ESP32-S3 专属 sdkconfig。

## 6.3 整镜像 SHA-256 与长度校验

必须显式创建：

```c
esp_ota_service_verifier_sha256_create()
```

SHA-256 Verifier 配置需要完整 BIN 的 32 字节 expected hash。

官方 BLE APP Profile 的 Start 命令会携带固件长度。设备必须校验：

- Start 声明长度与本次预期长度相同。
- 实际收到的总字节数与预期长度相同。
- 最终 SHA-256 与预期摘要相同。
- ESP 镜像结构校验通过。

若 OTA Service 的默认 Verifier 接口不能直接检查总长度，增加最薄的计数包装层或在 OTA Service 允许的扩展点中实现长度检查；不得改写 BLE 传输层。

**校验失败必须在 Commit 之前拒绝升级。**

## 6.4 初始 SHA-256 元数据来源

第一轮使用串口控制台输入预期元数据，避免在 OTA Profile 尚未验证时又引入新的 BLE 元数据协议。

命令建议：

```text
help
status
ota ble <version> <size_bytes> <sha256_hex>
ota abort
reboot
```

例如：

```text
ota ble 0.1.1 456789 <64位SHA256十六进制摘要>
```

要求：

- 摘要必须为 64 位十六进制。
- 解析后必须得到 32 字节。
- size 必须大于 0 且小于等于 OTA Slot 大小。
- version 必须合法且高于当前运行版本。
- 元数据只绑定当前 OTA Session，完成或失败后清除。
- 不允许缺少摘要时自动退化为无校验升级。

第一阶段不要求官方 BLE App 提供 SHA-256；由串口预先设置预期摘要，官方 App 只负责按官方 Profile 发送 BIN。

## 6.5 BLE Source 与旧灯控 BLE 的关系

本 POC 使用独立固件，只启用 OTA 测试所需 BLE 服务。

必须记录官方 BLE Source 对 NimBLE Host 的初始化和释放方式。后续若要把 OTA Profile 与 MineLamp 原有灯控 GATT Service 合并，必须先检查两者是否使用同一个 BLE Host、是否存在 Bluedroid / NimBLE 冲突、Host 重复初始化和广播资源冲突。

不得在本 POC 中同时启动两个互相独立的 BLE Host。

**P2 验收：**

- [ ] BLE Source 能正常初始化。
- [ ] OTA 广播可被手机扫描。
- [ ] 官方 BLE OTA App 能连接。
- [ ] Start 命令能到达设备。
- [ ] 设备能收到完整 BIN。
- [ ] 分包 ACK / CRC 正常。
- [ ] 整镜像 SHA-256 正确。
- [ ] 长度正确。
- [ ] 正确 BIN 可提交并重启。
- [ ] 错误摘要和错误长度不能 Commit。

---

# 7. P3：使用官方 BLE OTA 测试 App 完成首次真实传输

**此阶段只验证设备固件和官方协议，不开发 UniApp。**

## 7.1 测试工具

官方 Android App：

- 项目：https://github.com/EspressifApps/esp-ble-ota-android
- Releases：https://github.com/EspressifApps/esp-ble-ota-android/releases

同时可以使用 nRF Connect 等 GATT 调试工具检查 Service / Characteristic、属性、Notify / Indicate 和连接参数，但它们不能替代官方 OTA App 完成完整 OTA Profile 传输。

## 7.2 首次测试流程

1. 先通过 USB 串口烧录 P1 / P2 固件。
2. 读取设备版本和当前分区。
3. 编译一个可识别的测试固件，例如版本 `0.1.1`，在启动日志中输出 Build ID。
4. PC 计算 BIN 的实际长度和 SHA-256。
5. 串口输入 `ota ble` 命令设置版本、长度和摘要。
6. 设备开始广播 OTA Service。
7. Android 官方 OTA App 扫描并连接设备。
8. 选择对应 BIN 文件。
9. 开始传输，记录 Sector、ACK、CRC、总字节数和耗时。
10. 设备完成 SHA-256、长度和镜像校验。
11. 设备 Commit 新 OTA Slot 并重启。
12. 重启后通过串口确认 Build ID、版本和运行分区。

## 7.3 需要保存的证据

每一轮必须保存：

- PC 端 BIN 文件名。
- BIN 字节长度。
- BIN SHA-256。
- 设备升级前版本和运行分区。
- Android App 的连接 / 传输结果。
- 设备串口完整日志。
- 传输总耗时和平均速率。
- 设备升级后版本和运行分区。

不要只凭 App 显示 100% 就认定升级成功。

**P3 验收：** 至少完成 3 次正确 BIN 的 BLE 真实升级；每次均有设备端和客户端证据。错误 SHA-256 必须拒绝提交。

---

# 8. P4：Wi-Fi HTTPS OTA 固件实现

## 8.1 传输模式

Wi-Fi OTA 采用设备主动下载：

```text
UniApp / UART 发起升级请求
          ↓
设备连接 Wi-Fi
          ↓
HTTPS GET Manifest
          ↓
校验设备型号、版本、URL、size、SHA-256
          ↓
HTTPS GET BIN
          ↓
官方 HTTP Source
          ↓
统一 OTA Service / SHA-256 Verifier
          ↓
App Partition Target
          ↓
Commit / Reboot / Self-test
```

手机不直接向设备上传 BIN。设备通过 HTTPS 从服务器拉取固件。

## 8.2 Manifest 格式

```json
{
  "device": "ESP32-C3FH4",
  "version": "0.1.2",
  "url": "https://ota.example.test/firmware.bin",
  "size": 123456,
  "sha256": "64-character-hex-string",
  "changelog": "OTA POC test build"
}
```

必需校验：

- `device`：必须与设备固件配置的型号标识完全一致。
- `version`：必须是合法 SemVer，且严格高于当前运行版本。
- `url`：必须是 HTTPS；第一阶段限制在配置的测试服务器 Host。
- `size`：必须大于 0 且不超过 OTA Slot 容量。
- `sha256`：必须为 64 位十六进制，解码为 32 字节。
- `changelog`：可选展示，必须限制最大长度。

缺字段、解析失败、设备不匹配、版本不合法、摘要格式错误、size 越界或 URL 不安全，必须拒绝升级。

官方 Manifest Checker 的字段与本项目 Manifest 不完全相同，不能假设它自动处理所有业务字段。需要一个轻量 Manifest Preflight Parser，完成业务字段校验，再把经过校验的 BIN URL、size 和 expected SHA-256 交给官方 HTTP Source / Verifier。

## 8.3 HTTPS 证书验证

- 使用可信 CA 证书或 ESP x509 Certificate Bundle。
- Manifest 和 BIN 下载都必须验证证书链。
- 必须验证主机名。
- 禁止 TrustAll、跳过 Common Name / Hostname 校验和关闭 TLS 验证。
- 测试服务器使用测试 CA 签发证书，证书 SAN 必须覆盖设备实际访问的域名。
- 服务器私钥不得提交 Git。
- 公开仓库可以提交公开测试 CA 证书，但不得提交 CA 私钥。

## 8.4 测试服务器工具

实现：

- `tools/make_manifest.py`：读取 BIN，自动生成 size 和 SHA-256。
- `tools/https_test_server.py`：通过 HTTPS 提供 Manifest 和 BIN。
- `tools/generate_test_cert.ps1`：生成本地测试证书的可复现脚本，或提供等价说明。
- Windows PowerShell 下的启动命令和设备访问配置。

## 8.5 Wi-Fi OTA 首轮测试

第一轮通过串口控制台触发，避免同时排查客户端控制协议。

测试项目：

1. 正常 Wi-Fi 连接。
2. 正常 HTTPS Manifest 获取。
3. 正常 BIN 下载。
4. SHA-256 一致。
5. 设备版本更新并重启。
6. 错误 CA。
7. 错误 Hostname。
8. 服务器 404 / 500。
9. Manifest 设备型号不匹配。
10. Manifest 版本不高于当前版本。
11. size 不匹配。
12. SHA-256 错误。
13. 下载中断网。
14. 下载过程中服务器停止。

任何校验失败均不得 Commit。

**P4 验收：** Wi-Fi HTTPS OTA 正常完成真实 BIN 升级，错误 TLS / 错误摘要 / 错误长度均能拒绝。

---

# 9. P5：统一双通道固件与交叉升级

此阶段是项目最重要的架构验收。

不能用两个不同固件、两个不同分区布局、两个独立 OTA 实现分别演示成功。

必须形成**一份同时支持 BLE 和 HTTPS 的 ESP32-C3 固件**：

- 同一个 OTA Manager。
- 同一个 OTA Service 生命周期。
- 同一个 App Partition Target。
- 同一个 SHA-256 校验接口。
- 同一套 Commit / Reboot / Pending Verify / Confirm / Rollback。
- 同一张 4 MB 分区表。

通过 OTA Manager 的互斥锁保证同一时间只能启动一个 OTA Session。

交叉测试：

| 顺序 | 方式 | 目标版本 | 结果证据 |
|---|---|---|---|
| USB 初始烧录 | USB | 0.1.0 | 启动日志 |
| 第 1 次升级 | BLE | 0.1.1 | BLE 日志 + 重启版本 |
| 第 2 次升级 | Wi-Fi HTTPS | 0.1.2 | HTTPS 日志 + 重启版本 |
| 第 3 次升级 | BLE | 0.1.3 | BLE 日志 + 重启版本 |
| 第 4 次升级 | Wi-Fi HTTPS | 0.1.4 | HTTPS 日志 + 重启版本 |

每次都必须记录实际运行分区，证明两种 Source 使用同一 OTA 分区机制。

**P5 验收：** 同一块 ESP32-C3、同一份双通道固件，连续完成 BLE → Wi-Fi → BLE → Wi-Fi 交叉升级。

---

# 10. P6：UniApp BLE 通信测试模块

**只有 P3 官方 BLE App 已经通过后，才开始本阶段。**

本阶段不是正式 UI，只做最小化通信测试工具。

## 10.1 目标

让 UniApp 作为 BLE Central，复现官方 ESP BLE OTA App 的 OTA Profile，与 P2/P5 固件完成相同 BIN 传输。

不得另造一套 GATT UUID、Sector 格式、CRC、ACK 和重传协议。

## 10.2 编码前必须完成协议逆向核对

DeepSeek 必须先阅读：

- 官方 Android 测试 App 源码。
- 官方 ESP BLE OTA Source 源码。
- ESP-IoT-Solution BLE OTA Profile 相关实现。

将完整协议写入：

`docs/BLE_PROFILE_PROTOCOL.md`

至少包括：

- Service / Characteristic UUID。
- Characteristic 属性。
- Write / Write Without Response 的使用条件。
- Notify / Indicate 的使用条件。
- Start / Stop / Abort 命令格式。
- Sector 大小和字段结构。
- CRC16-CCITT 参数、覆盖范围和字节序。
- ACK 的字段定义和返回时机。
- 错误码。
- 重传规则。
- MTU 协商和单次写入最大字节数。
- 断连后的状态处理。

协议字段必须从源码和真实抓包核对，不能凭推测编写。

## 10.3 UniApp 最小功能

先只实现：

1. 初始化蓝牙适配器。
2. 扫描 OTA Service。
3. 按 Service UUID 过滤设备。
4. 连接设备。
5. 查询 Service / Characteristic。
6. 订阅所需 Notify / Indicate。
7. 获取并协商 MTU（按平台能力处理）。
8. 选择本地 BIN 文件。
9. 读取文件长度。
10. 计算 SHA-256。
11. 将版本、长度、摘要通过已确认的元数据控制路径交给设备。
12. 按官方 Profile 顺序传输 Sector。
13. 等待 ACK。
14. 依据官方协议处理错误和重试。
15. 传输结束后查询设备升级状态。
16. 监听断连并停止传输。
17. 保存完整调试日志。

建议封装：

```text
uniapp-test/
  protocol/
    esp_ble_ota_codec.js
    esp_ble_ota_crc.js
  services/
    ble_adapter.js
    ble_connection.js
    ble_ota_service.js
    ota_file_service.js
    ota_log_service.js
  pages/
    ota-diagnostic/
```

## 10.4 UniApp BLE 关键要求

- Android 先行，iOS 作为后续兼容目标。
- 按系统版本正确申请蓝牙扫描和连接权限。
- 不能假设 MTU 一定为 517。
- 单次 GATT 写入长度必须依据实际协商 MTU 和 Characteristic 能力计算。
- 不允许并发无序写入导致 ACK 与 Sector 错配。
- 按协议要求等待 ACK 后才能推进相应 Sector。
- 断连后立即停止发送，清理计时和队列。
- 不允许用固定延时假装 ACK 已到达。
- 不允许用模拟进度代替设备真实字节数。
- 文件读取和分包不能造成大文件内存溢出。
- 对手机型号、系统版本、MTU、连接间隔和传输速率进行记录。

## 10.5 SHA-256 元数据通道

官方 OTA Profile 的 BLE 数据协议不应被擅自修改以塞入自定义摘要字段。

第一轮官方 App 测试使用 UART 输入 expected SHA-256。

UniApp 阶段必须实现独立的元数据提交步骤，传入：

- device
- version
- size
- sha256

该元数据通道必须有明确协议文档，并绑定当前 OTA Session。优先复用已经审查通过的设备控制 Service；若现有控制 Service 无法满足安全要求，先设计独立的最小控制接口并单独评审。

要求：

- 元数据与 OTA 数据传输必须关联同一个 Session。
- 设备验证元数据后才能允许 BLE Start。
- 元数据不完整、摘要错误或权限不满足时拒绝传输。
- Session 结束后清除元数据。
- BLE 生产安全必须检查配对、绑定、链路加密和写入权限；若官方 OTA Source 默认没有满足要求，必须明确标记为实验环境限制，不能宣称生产安全。

## 10.6 Wi-Fi OTA 的 UniApp 控制方式

Wi-Fi OTA 仍由设备主动 HTTPS PULL。

第一轮 Wi-Fi OTA 已通过串口验证后，再由 UniApp 提供：

- Wi-Fi 配网或已有可信网络配置。
- Manifest URL。
- OTA 开始请求。
- OTA 状态查询。
- 取消请求（仅在设备端支持安全取消时）。

UniApp 不把 BIN 通过 BLE 再传一次来冒充 Wi-Fi OTA。

客户端控制接口优先复用经审查的设备控制通道。不要未经评审就增加公开、无认证的 HTTP 控制端口。

**P6 验收：** UniApp 不依赖官方 Android App，能独立完成 BLE 扫描、连接、元数据提交、BIN 传输、ACK 处理、真实进度和升级结果确认。

---

# 11. P7：UniApp 与设备端联合传输测试

本阶段重点不是 UI，而是协议和设备状态的一致性。

每次测试必须同时记录：

- UniApp 日志。
- 设备串口日志。
- BIN 文件长度。
- BIN SHA-256。
- BLE MTU。
- 每个 Sector 的序号。
- 每个 ACK 的序号和状态。
- 重传次数。
- 总耗时。
- 设备最终版本。
- 设备最终运行分区。

测试：

1. 正常传输。
2. 大 BIN。
3. 小 BIN。
4. 传输开始前取消。
5. 传输中断开蓝牙。
6. 传输中 App 进入后台。
7. 传输中锁屏。
8. 手机蓝牙关闭。
9. 设备重启。
10. 设备距离变远导致链路不稳定。
11. 重复点击开始。
12. 连续连接 / 断开。
13. 同一 BIN 重复升级。
14. 错误 SHA-256。
15. 错误 size。
16. 不匹配的设备型号。
17. 低版本固件。
18. BLE 传输中尝试启动 Wi-Fi OTA。
19. Wi-Fi OTA 中尝试启动 BLE OTA。

必须证明 OTA Manager 的互斥机制有效，不允许两个通道同时操作同一 OTA Target。

---

# 12. P8：稳定性与故障注入测试

稳定性测试必须在正常功能跑通之后进行。

## 12.1 重复升级测试

至少：

- BLE 连续成功升级 10 次。
- Wi-Fi HTTPS 连续成功升级 10 次。
- BLE / Wi-Fi 交替升级至少 10 轮。
- 连续连接 / 断开至少 30 次。
- 反复开始 / 取消至少 20 次。

每轮使用不同 Build ID 或可追踪版本号，避免误把旧固件启动当作成功。

## 12.2 传输异常

- BLE 传输中关闭手机蓝牙。
- BLE 传输中强制关闭 App。
- BLE 传输中走出有效距离。
- Wi-Fi 传输中断开路由器。
- HTTPS 服务器主动停止。
- HTTP 返回 404 / 500。
- TLS 证书过期或不可信。
- Manifest 缺字段。
- Manifest 摘要错误。
- BIN 长度不符。
- BIN 内容损坏。
- 非 ESP32-C3 目标固件。
- OTA Slot 空间不足。

## 12.3 资源稳定性

记录：

- OTA 前后可用 Heap。
- 最小可用 Heap。
- 最大连续可用 Heap（若可取得）。
- BLE 任务 Stack High Water Mark。
- OTA Worker Stack High Water Mark。
- OTA 期间 CPU / 任务异常。
- 看门狗触发。
- 重复初始化后资源是否泄漏。
- OTA 中止后是否正确释放 source / target / verifier / event group / mutex。

## 12.4 性能记录

每轮记录：

- BIN 大小。
- 总传输时间。
- 平均速率。
- BLE MTU。
- BLE 重传次数。
- Wi-Fi RSSI。
- HTTPS 下载时间。
- SHA-256 校验时间。
- Flash Commit / 重启时间。

先建立实测基线，再确定产品目标；不得虚构吞吐量指标。

**P8 验收：** 重复测试没有不可恢复故障、没有错误 Commit、没有持续内存泄漏；所有失败状态都能正确结束会话并恢复可用状态。

---

# 13. P9：意外回滚、断电保护和恢复测试

这一阶段是可靠性核心，不得只做“手动调用 rollback 函数”的表面测试。

## 13.1 回滚机制

启用 ESP-IDF bootloader rollback：

- `CONFIG_BOOTLOADER_APP_ROLLBACK_ENABLE=y`
- OTA Service rollback 支持开启。
- 新固件启动时检查 Pending Verify 状态。
- 只有自检通过后才调用确认 API。

官方 API 重点核对：

- `esp_ota_service_is_pending_verify()`
- `esp_ota_service_confirm_update()`
- `esp_ota_service_rollback()`

具体 API 以锁定版本的头文件为准。

## 13.2 新固件自检

新固件首次启动不能无条件 Confirm。

自检至少包含：

1. NVS 初始化成功。
2. 当前运行分区有效。
3. 应用描述信息和版本正确。
4. 核心任务创建成功。
5. 设备基础外设初始化成功。
6. BLE / Wi-Fi 基础模块能够初始化（按本 POC 启用的模块）。
7. 在限定观察窗口内没有异常重启或看门狗复位。

所有必要检查通过后才 Confirm。

任一关键检查失败：

- 输出失败阶段和错误码。
- 调用官方 Rollback API，或保留 Pending Verify 状态并通过 bootloader 机制回滚。
- 重启后确认旧版本重新运行。

## 13.3 断电阶段测试

断电测试由用户在确认备份和风险后手动执行，不得自动控制真实电源。

至少区分：

| 断电时机 | 预期行为 |
|---|---|
| OTA 开始前 | 原固件正常启动 |
| 擦除 OTA Slot 时 | 原运行分区不受影响 |
| 写入 BIN 中途 | 原固件仍可启动，未完成镜像不能 Commit |
| SHA-256 校验时 | 不完整镜像不得 Commit |
| Commit 前 | 原固件仍是启动分区 |
| Commit 后、首次启动前 | 新镜像启动流程按 bootloader 状态处理 |
| 新固件 Pending Verify 时 | 若未确认而再次复位，验证 bootloader 自动回滚 |
| 自检失败时 | 验证主动 Rollback 并恢复旧版本 |

必须根据 ESP-IDF 实际 bootloader 状态机验证，不要简单声称“任何时刻断电都必然回滚”。

## 13.4 人为制造启动失败

准备一个专门的故障测试版本：

- 能成功写入且 SHA-256 正确。
- 镜像头有效。
- 新固件启动后在自检阶段故意失败，或在用户确认的测试条件下触发看门狗复位。
- 不调用 Confirm。
- 观察 bootloader 回滚旧版本。
- 记录旧版本 Build ID、运行分区和回滚原因。

不得把错误镜像校验失败与启动后回滚混为一类。两者必须分别测试。

## 13.5 恢复测试

- 回滚后 BLE 是否能重新广播。
- 回滚后 Wi-Fi 是否能重新连接。
- OTA Manager 是否能重新启动。
- NVS 数据是否保持。
- 设备身份和灯控数据是否受损。
- 是否能再次正常升级到新版本。

**P9 验收：** 至少一次完整的新固件启动失败回滚成功；至少一次传输中断后旧固件仍正常运行；至少一次 Pending Verify 未确认导致的 bootloader 自动回滚成功。全部有串口证据。

---

# 14. P10：最后开发正式 UI

只有 P0-P9 达到验收要求，才允许进入正式 UI。

UI 不负责重新实现 OTA 协议，所有升级行为通过已经验证的服务接口调用。

正式页面至少包含：

## 14.1 设备信息

- 设备名称。
- 设备型号。
- MAC / 设备身份。
- 当前固件版本。
- 当前运行分区。
- OTA 能力。
- BLE / Wi-Fi 连接状态。

## 14.2 升级通道

- BLE OTA。
- Wi-Fi HTTPS OTA。
- 当前选择的升级通道。
- 设备是否允许开始升级。
- OTA Session 是否正在运行。
- 两种通道互斥状态。

## 14.3 固件与校验

- BIN 文件选择。
- 文件名。
- 文件大小。
- 目标设备型号。
- 目标版本。
- SHA-256。
- 校验结果。
- Manifest 信息。
- TLS / 服务器状态（Wi-Fi 通道）。

## 14.4 实时升级状态

状态必须来自设备真实事件，不允许用定时器伪造进度：

```text
IDLE
PREPARING
READY
RECEIVING
VERIFYING
COMMITTING
REBOOTING
RECONNECTING
VERSION_CHECKING
SUCCESS
FAILED
CANCELLED
ROLLBACK
```

显示：

- 真实接收字节数 / 总字节数。
- 真实百分比。
- 传输速率。
- 已耗时。
- ACK / 重传统计（BLE）。
- 下载状态（Wi-Fi）。
- SHA-256 状态。
- 设备错误码。
- 重启后版本确认结果。

## 14.5 调试日志

提供：

- 时间戳。
- 设备连接状态。
- GATT Service / Characteristic。
- 发出和接收的原始数据（必要时 HEX）。
- Start / ACK / Sector 信息。
- OTA 事件。
- SHA-256 结果。
- TLS 错误。
- Commit / Reboot / Rollback 日志。
- 导出日志功能。

UI 最终设计应简洁清晰，先确保状态准确，再优化视觉效果和动画。

---

# 15. 安全要求

## 15.1 固件完整性

- BLE 和 Wi-Fi 都必须进行整镜像 SHA-256。
- 长度必须严格一致。
- ESP 镜像结构必须合法。
- 所有校验失败都不能 Commit。
- SHA-256 缺失或初始化失败必须 fail-closed。

## 15.2 Wi-Fi 安全

- 只允许 HTTPS。
- 校验证书链和主机名。
- Manifest 和 BIN 下载都必须校验。
- 测试服务器 Host 应有白名单。
- 不允许跳过 TLS 校验。

## 15.3 BLE 安全

SHA-256 本身不提供发布者身份认证。BLE 数据通道若未加密，摘要元数据也可能被中间人替换。

因此必须检查：

- BLE 配对与绑定。
- GATT 写入是否需要加密。
- 是否具备 MITM 保护要求。
- OTA 元数据是否通过受保护通道提交。
- 是否能阻止未授权设备启动 OTA。

如果官方 BLE OTA Profile 默认没有满足产品要求的认证和加密，必须将其标记为 POC 限制，并在正式产品集成前补齐安全控制。不得仅凭“有 SHA-256”宣称 BLE OTA 安全。

## 15.4 签名策略

本项目不使用独立 `.sig` 文件，不重新引入 RSA / ECDSA / Ed25519 应用层签名方案。

但必须明确：

- SHA-256 只保证数据与预期摘要一致。
- HTTPS 证书验证用于保护 Wi-Fi 下载链路和 Manifest 来源。
- BLE 链路必须有适当的加密与授权保护。
- 如果未来需要抵御恶意物理刷写或供应链攻击，应单独评估 Secure Boot / Flash Encryption 等芯片安全机制，不能把普通 SHA-256 当成固件签名。

---

# 16. 日志规范和测试证据

每个 OTA Session 都应有唯一 session_id 和 request_id（若组件提供），日志按阶段结构化输出。

设备启动日志：

- Chip / Flash。
- Firmware Version / Build ID。
- Running Partition。
- Next OTA Partition。
- Pending Verify。
- Rollback 配置。

BLE 日志：

- BLE Host 初始化。
- 广播开始。
- Service / Characteristic 注册。
- 连接 / MTU。
- Start 命令和镜像长度。
- Sector 接收。
- ACK 状态。
- CRC 错误。
- 实际接收字节数。
- SHA-256 结果。

Wi-Fi 日志：

- Wi-Fi 连接结果。
- Manifest URL（可隐藏敏感查询参数）。
- HTTP 状态码。
- TLS 验证结果。
- Manifest 解析结果。
- BIN URL。
- Content-Length。
- 实际接收字节数。
- SHA-256 结果。

OTA 生命周期：

- Session Begin。
- Item Begin。
- Progress。
- Item End status / reason / error。
- Session End。
- Commit。
- Reboot。
- Pending Verify。
- Confirm / Rollback。

严禁在日志中输出 Wi-Fi 密码、私钥、完整安全令牌等秘密。

每轮测试必须保存：

- 测试编号。
- 固件版本。
- BIN 文件。
- BIN size。
- BIN SHA-256。
- 客户端日志。
- 设备串口日志。
- 测试步骤。
- 预期结果。
- 实际结果。
- PASS / FAIL / NOT RUN。
- 失败原因和复现步骤。

---

# 17. Git 提交和 DeepSeek 工作纪律

## 17.1 分阶段提交

每个阶段完成后独立提交：

- P0：工具链和硬件核查文档。
- P1：C3 最小启动固件与分区表。
- P2：BLE OTA Source。
- P3：官方 BLE App 实测报告。
- P4：Wi-Fi HTTPS OTA。
- P5：统一双通道固件。
- P6：UniApp BLE 协议和通信测试。
- P7：联合传输测试报告。
- P8：稳定性报告。
- P9：回滚与恢复报告。
- P10：正式 UI。

Commit message 使用清晰英文前缀，例如：

```text
feat(device): add ESP32-C3 OTA baseline
feat(ota): integrate Espressif BLE OTA source
feat(ota): add HTTPS OTA source
test(ota): verify BLE OTA with official app
feat(uniapp): add BLE OTA transport diagnostics
test(ota): add stability and rollback evidence
```

## 17.2 不允许的行为

- 不得只修改文档而不实现代码，却声称功能完成。
- 不得只编译 ESP32-S3 后声称 C3 通过。
- 不得只运行静态分析后声称真机通过。
- 不得用两个不同固件冒充统一双通道。
- 不得删除 SHA-256 或关闭 TLS 来规避问题。
- 不得编造传输速度、成功次数、回滚结果或硬件日志。
- 不得在没有备份和用户确认的情况下执行高风险全片擦除。
- 不得在底层未通过前开发正式 UI。
- 不得把测试页面的模拟进度作为真实 OTA 进度。

## 17.3 每个阶段的汇报格式

每个阶段结束后必须向用户汇报：

1. 本阶段目标。
2. 实际修改的文件。
3. 实际执行的命令。
4. 构建结果。
5. 真机测试结果。
6. 日志位置。
7. PASS / FAIL / NOT RUN。
8. 当前阻塞问题。
9. 需要用户执行的硬件操作。
10. 下一阶段是否具备开始条件。

如果需要用户上电、接线、选择串口、打开 Android App、选择 BIN 或手动断电，必须给出清晰、可复制的操作步骤，等待用户完成后再继续依赖实测结果。

---

# 18. 最终验收清单

## 固件基础

- [ ] 独立 ESP-IDF 工程。
- [ ] ESP32-C3FH4 实际目标编译。
- [ ] 4 MB Flash 容量确认。
- [ ] 双 OTA App Slot。
- [ ] OTA Data 分区。
- [ ] 回滚配置生效。
- [ ] 最小固件可烧录和启动。

## BLE OTA

- [ ] 官方 BLE OTA Source。
- [ ] 官方 BLE OTA Android App 可连接。
- [ ] Start 命令正常。
- [ ] Sector / ACK / CRC 正常。
- [ ] BIN 长度正确。
- [ ] 整镜像 SHA-256 正确。
- [ ] 正确固件成功升级。
- [ ] 错误摘要不能 Commit。

## Wi-Fi OTA

- [ ] 设备主动 HTTPS PULL。
- [ ] Manifest 字段校验。
- [ ] TLS 证书链和主机名校验。
- [ ] BIN 长度正确。
- [ ] 整镜像 SHA-256 正确。
- [ ] 正确固件成功升级。
- [ ] 错误证书和错误摘要不能 Commit。

## 双通道统一

- [ ] 同一份固件同时包含 BLE 和 HTTPS Source。
- [ ] 共用 OTA Manager。
- [ ] 共用 OTA Service / App Target。
- [ ] 共用分区表和回滚机制。
- [ ] 两通道互斥。
- [ ] 完成 BLE / Wi-Fi 交叉升级。

## UniApp

- [ ] 官方协议源码核对完成。
- [ ] BLE Profile 字节级文档完成。
- [ ] UniApp 扫描和连接正常。
- [ ] MTU 和 Characteristic 属性正确。
- [ ] Sector / ACK 流程与官方 App 一致。
- [ ] 能传输真实 BIN。
- [ ] 设备端 SHA-256 验证通过。
- [ ] 真实进度和错误日志正常。
- [ ] Wi-Fi OTA 可由客户端发起并查询结果。

## 稳定性与回滚

- [ ] BLE 连续成功 10 次。
- [ ] Wi-Fi 连续成功 10 次。
- [ ] 双通道交替升级至少 10 轮。
- [ ] 断连 / 断网测试。
- [ ] 错误摘要 / 错误长度测试。
- [ ] 错误镜像测试。
- [ ] TLS 错误测试。
- [ ] OTA 期间资源稳定。
- [ ] Pending Verify 失败回滚。
- [ ] 意外复位回滚。
- [ ] 传输中断后旧固件可启动。
- [ ] 回滚后可再次升级。

## UI

- [ ] 只有底层验收通过后开始。
- [ ] 真实设备状态。
- [ ] 真实传输进度。
- [ ] 真实校验状态。
- [ ] 真实重启和版本确认。
- [ ] 错误日志可导出。
- [ ] 不存在模拟成功和虚假进度。

---

# 19. DeepSeek 开始执行时的第一条指令

请先读取本文件，然后立即开始 P0：

1. 检查仓库和当前分支。
2. 检查 ESP-IDF 工具链是否可用。
3. 检查 ESP32-C3FH4 工程和分区信息是否已存在。
4. 建立独立的 `ota-poc/esp32` 工程目录。
5. 先完成 P1 最小 C3 固件构建和启动。
6. 再依次实施 BLE OTA、官方 BLE App 实测、Wi-Fi HTTPS OTA、统一双通道、UniApp 通信测试、稳定性测试、回滚测试。
7. 最后才开发正式 UI。

遇到不确定的组件 API，先阅读锁定版本的官方头文件和示例源码；遇到构建错误，定位真实依赖和配置原因；遇到硬件测试要求，向用户提供可执行步骤。

**本项目的第一成功标准不是页面做出来，而是 ESP32-C3 真正通过 BLE 和 Wi-Fi 两种路径升级真实 BIN，并且升级失败时仍然能够安全恢复。**

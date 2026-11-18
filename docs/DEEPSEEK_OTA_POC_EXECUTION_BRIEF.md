# DeepSeek 执行任务书：MineLamp ESP32-C3 双通道 OTA 底层 POC

> **用途：** 请将本文档作为直接执行指令，而不是继续做方案讨论。  
> **仓库：** `Daily-emo/Flutter-OTA`  
> **工作分支：** `ota-poc`  
> **目标硬件：** ESP32-C3FH4，片内 Flash 4 MB  
> **首选底层：** Espressif `esp_ota_service` v0.5.2~3  
> **日期：** 2026-11-18

---

## 0. 你的任务是什么

请在当前仓库的 `ota-poc` 分支中，建立一个**独立、可编译、可烧录、可实测**的 ESP32-C3 原生 ESP-IDF OTA 测试工程，先完成 OTA 底层，不要继续开发 Flutter / UniApp 页面。

最终目标不是写一个 OTA Demo，也不是分别找两个互不相关的例程，而是：

1. ESP32-C3FH4 设备端编译出**同一个固件**，同时具备 BLE OTA Source 和 Wi-Fi HTTPS OTA Source。
2. 两种传输方式都调用同一套 OTA Service、SHA-256 Verifier、App Partition Target、A/B 分区提交和回滚流程。
3. 通过 BLE 传输真实 BIN，完成校验、设置启动分区、重启、回读版本。
4. 通过 Wi-Fi 由 ESP32 主动 HTTPS 下载真实 BIN（PULL），完成同样的校验、提交、重启和版本回读。
5. BLE 与 Wi-Fi 交替升级同一块 C3 开发板，证明它们确实共用同一个底层 OTA 生命周期。
6. 对错误摘要、错误镜像、断连、断网、断电和启动失败进行故障测试，证明失败不会破坏当前可启动固件。

**完成定义：** 只有代码已实现、C3 构建成功、真实硬件传输成功并留下日志证据，才允许标记“实测通过”。如果你没有硬件或工具链，必须如实标记“未实测”，并提交可供用户复现的工程、命令和测试表，不得编造成功记录。

## 1. 先阅读并遵守已有设计

开始前必须先阅读：

- `docs/OTA_OPEN_SOURCE_RESEARCH_AND_POC_PLAN.md`
- 本文档

研究文档已经记录官方组件、第三方候选、上游示例的 SHA-256 / HTTPS 缺口、C3 分区限制和测试顺序。遇到冲突时，以本执行任务书的验收目标为准，并在最终报告中说明差异。

### 项目现状

- 现有 Flutter / UniApp OTA 实现曾出现准备指令超时、GATT 属性错误、设备响应超时等问题。
- 现有灯控通信协议、A5 OTA 控制帧、身份 Service、配对权限和 15 秒上电准备窗口均属于 MineLamp 自有实现。
- 现有固件基于 Arduino-ESP32 3.3.10-cn 自定义板包；其对应 ESP-IDF 具体修订版需要从实际工程确认，不能凭版本号猜测。
- 当前 POC 必须与现有 App、现有固件分离，不修改旧工程，不把旧 A5 协议故障带进新的底层验证。
- 目标 Wi-Fi OTA 是**设备主动 HTTPS GET Manifest 和 BIN**，不是手机向 ESP32 HTTP PUSH。
- 项目不需要独立 `.sig` 文件，不实现 RSA / ECDSA / Ed25519 应用层签名。保留 HTTPS 证书验证和 SHA-256 完整性校验。注意：SHA-256 只能证明内容与可信摘要一致，不单独证明发布者身份。

## 2. 技术选型与禁止事项

### 2.1 首选官方组件

固定使用 Espressif Component Registry 的：

- `espressif/esp_ota_service` **0.5.2~3**
- 官方 BLE Source：ESP BLE OTA APP Profile
- 官方 HTTP Source：HTTP/HTTPS
- 官方 App Partition Target
- 官方 SHA-256 Verifier
- 官方 OTA Service 事件与 rollback 生命周期

入口：

- 组件文档：https://components.espressif.com/components/espressif/esp_ota_service/versions/0.5.2~3/readme
- BLE 示例：https://components.espressif.com/components/espressif/esp_ota_service/versions/0.5.2~3/examples/ota_ble
- HTTP 示例：https://components.espressif.com/components/espressif/esp_ota_service/versions/0.5.2~3/examples/ota_http
- BLE Android 测试工具：https://github.com/EspressifApps/esp-ble-ota-android/releases
- 组件上游源码：https://github.com/espressif/esp-adf/tree/master/components/esp_ota_service

在 `main/idf_component.yml` 中锁定精确版本（不要使用 `latest` 或宽泛版本范围），并提交 Component Manager 生成的依赖锁文件。示意：

```yaml
dependencies:
  espressif/esp_ota_service:
    version: "0.5.2~3"
```

如果 Component Manager 的当前语法或 Registry 解析结果与示意不一致，按实际工具链验证后修正，并在报告中记录最终解析到的确切版本。

### 2.2 绝对禁止

- 不要自行编写 BLE GATT 分包协议、ACK、Sector CRC、重传和窗口控制。
- 不要自行重写 OTA Flash 写入、A/B 分区切换和 bootloader 回滚。
- 不要用两个互不相干的 Demo 分别成功，便声称双通道已经完成。
- 不要为了通过编译而删除 SHA-256、跳过证书验证或忽略错误。
- 不要把 Sector CRC16 当作整个 BIN 的 SHA-256。
- 不要在 SHA-256 验证完成前 Commit / 设置新启动分区。
- 不要把 Wi-Fi OTA 改成 HTTP 明文；测试服务器也必须使用 HTTPS。
- 不要把 `.sig`、签名验证或 RSA/ECDSA/Ed25519 重新加回来。
- 不要提交 Wi-Fi 密码、私钥、个人证书或其他秘密到 Git。
- 不要改动 Flutter 的 `lib/`、`pubspec.yaml` 或现有 App 协议实现。
- 不要把 C3FH4 的 4 MB Flash 当作 8 MB，也不要复制官方 HTTP 示例的 8 MB 分区表。
- 不要将未经验证的“编译通过”“传输成功”写成事实。

允许编写的自有代码仅限必要的 OTA 编排、Manifest 业务校验、控制台测试入口、日志、配置和测试工具；底层传输、目标写入和 SHA-256 计算尽量复用官方组件。

## 3. 仓库交付结构

在 `ota-poc/` 下建立独立工程，建议结构如下（可按实际工程需要调整，但必须保持与 Flutter App 隔离）：

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
      ota_manifest.c
      ota_manifest.h
      ota_console.c
      ota_console.h
      wifi_manager.c
      wifi_manager.h
  tools/
    make_manifest.py
    https_test_server.py
    verify_bin.py
  docs/
    BUILD_AND_FLASH.md
    HARDWARE_TEST_PLAN.md
    TEST_RESULTS_TEMPLATE.md
  .gitignore
```

要求：
- 工程必须可独立执行 `idf.py build`。
- 不依赖现有 Flutter 工程即可烧录和测试。
- 不把生成的 `build/`、私钥、真实 Wi-Fi 凭据、用户本地证书提交到 Git。
- 提供 `secrets.example` 或 menuconfig 配置说明；本地秘密文件加入 `.gitignore`。
- README / 文档中写清楚工程入口和 Windows PowerShell 下的构建、烧录命令。

## 4. 硬件与分区约束

目标是 ESP32-C3FH4，片内 Flash 4 MB。

先确认开发板实际 Flash ID / 容量，不得仅依赖配置推断。使用 4 MB 分区布局，初始可参考官方 BLE 示例：

```csv
# Name,   Type, SubType, Offset,   Size,   Flags
nvs,      data, nvs,     0x9000,   0x4000,
otadata,  data, ota,     0xd000,   0x2000,
phy_init, data, phy,     0xf000,   0x1000,
ota_0,    app,  ota_0,   0x10000,  1500K,
ota_1,    app,  ota_1,   ,         1500K,
```

注意：
- 官方 BLE 示例为 4 MB / 双 1500 KB OTA Slot。
- 官方 HTTP 示例使用 8 MB / 双 2 MB OTA Slot，**禁止直接复制**。
- 统一 POC 的 BLE 和 Wi-Fi 必须使用同一张分区表。
- 使用 `idf.py size` 和实际 BIN 文件大小确认固件可放入两个 OTA Slot。
- 如果最终 BIN 大于 1500 KB，先检查组件裁剪、日志级别和配置；确需改分区时，必须先计算完整 4 MB 布局并说明取舍，不能越界。
- 烧录前备份用户当前可用固件和原分区表；POC 烧录可能覆盖 Flash，必须明确提示用户。

启用并验证 OTA rollback：

- `CONFIG_OTA_ENABLE_ROLLBACK=y`
- `CONFIG_BOOTLOADER_APP_ROLLBACK_ENABLE=y)

同时按 C3 目标启用 NimBLE；BLE Source 需要的关键配置以当前组件 Kconfig / 官方示例为准，包括 `CONFIG_OTA_ENABLE_BLE_SOURCE=y`、NimBLE Host 和合适的 ATT MTU。不要盲目复制 ESP32-S3 专属配置。

## 5. 核心软件架构

统一架构必须是：

```text
             UART test console / future App control
                            |
                       OTA Manager
                            |
               exclusive session mutex
                    /             \
             BLE Source        HTTPS Source
                    \             /
                     OTA Service
                           |
                 SHA-256 + size verifier
                           |
                  App Partition Target
                           |
                 verify -> commit -> reboot
                           |
                  boot self-test / rollback
```

关键原则：
- 一个设备同一时间只能运行一个 OTA 会话。
- BLE 与 Wi-Fi 两种 Source 在同一个固件中编译，但一次只启动一个。
- 两种 Source 共用 OTA Service 逻辑、App Partition Target、校验和回滚生命周期。
- 不允许 BLE 和 Wi-Fi 同时写入 OTA Slot。
- 第一阶段两种 Source 均设置 `resumable=false`，先证明基础完整传输与校验；基础通过后，再单独评估 HTTP 断点续传。BLE Source 不支持 seek，禁止启用 BLE NVS 断点续传。
- 使用 OTA Service 的事件回调记录 Session Begin、Version Check、Item Begin、Progress、Item End、Session End。必须检查事件中的真实错误码和状态，不能只凭“进度达到 100%”显示成功。
- 对组件对象的 ownership 严格按官方 API 约定处理：`esp_ota_service_set_upgrade_list()` 接管 source / target / verifier / checker 对象后，不得重复 destroy/free。

## 6. BLE OTA 实现要求

### 6.1 传输层

使用官方 `esp_ota_service_source_ble_create()`，采用 Espressif BLE OTA APP Profile。官方 Source 已实现 NimBLE GATT Server 和 APP Profile，不要自行重新实现协议。

官方 Profile 关键点：
- Service UUID：`0x8018`
- Firmware receive characteristic：`0x8020`
- Command characteristic：`0x8022`
- Sector 分包、CRC16 和 ACK 由官方 Source 处理
- Source `seek()` 不支持，所以 `resumable=false)

使用 Espressif 官方 BLE OTA Android App 做第一轮传输测试。第一轮不需要 Flutter App。

### 6.2 BLE SHA-256 如何提供

官方 BLE 示例当前把 `.verifier = NULL`，因此示例本身并没有强制整镜像 SHA-256。你必须补上：

`esp_ota_service_verifier_sha256_create()`

其配置需要完整 BIN 的 32 字节 expected SHA-256。不能省略。

为避免在 POC 阶段自创 BLE 控制协议，**第一版通过 USB UART 控制台把本次测试 BIN 的 size、version、sha256 输入设备**，然后启动 BLE OTA Source。该元数据只保存在 RAM 中，绑定当前一次 OTA session，成功、失败或超时后立即清除，不写入 NVS 作为下次升级默认值。

建议控制台命令：

```text
help
status
ota ble <version> <size_bytes> <sha256_hex>
ota abort
reboot
```

例子仅说明命令格式，不要在代码中写死示例摘要。

BLE APP 发起 Start OTA 时携带的镜像长度必须与控制台输入的 `size_bytes` 完全一致。若官方 Source 没有把这个长度暴露给应用层或 SHA Verifier，必须检查 Source / Verifier 接口并增加**最小的 size guard**，确保在 Target Commit 前校验实际接收字节数等于期望长度。允许实现一个轻量自定义 verifier wrapper（计数并委托 SHA-256），但不得修改 BLE Sector 协议或重写传输层。

测试时：
1. PC 端计算待传 BIN 的 SHA-256 和文件长度。
2. 串口输入 `ota ble` 命令，设备打印当前期望 version / size / SHA-256。
3. 设备开始 BLE 广播，使用官方 Android App 连接并发送同一个 BIN。
4. 记录连接、Start、Sector、ACK、接收进度、CRC 错误、校验结果和结束状态。
5. SHA 错误、长度错误、断连时必须失败且不 Commit。
6. 正确 BIN 传输完成后才允许 Commit 并重启。

BLE Source 的 Start 等待时间可先配置为 180 秒，避免把现有 MineLamp 15 秒准备窗口的问题带进本次测试。该值仅用于 POC，不代表最终产品策略。

## 7. Wi-Fi HTTPS OTA 实现要求

### 7.1 设备主动拉取

设备连接 Wi-Fi 后，由设备主动执行：

1. HTTPS GET Manifest。
2. 解析 JSON。
3. 校验设备型号、版本、URL、大小和 SHA-256。
4. HTTPS GET BIN。
5. 通过官方 HTTP Source + App Partition Target 写入非活动 OTA Slot。
6. SHA-256 和大小校验成功后才 Commit。
7. 重启、自检、确认或回滚。

### 7.2 Manifest 格式

必须支持以下 JSON 字段：

```json
{
  "device": "ESP32-C3FH4",
  "version": "0.1.2",
  "url": "https://ota.example.test/firmware.bin",
  "size": 123456,
  "sha256": "64-character-lowercase-or-uppercase-hex",
  "changelog": "OTA POC test build"
}
```

校验要求：
- `device` 必须与固件配置的目标设备标识完全匹配。
- `version` 必须是合法 SemVer，且严格高于当前运行版本。
- `url` 必须是 HTTPS；第一版建议限制为配置的测试服务器 host，避免任意 URL。
- `size` 必须大于 0，且不超过目标 OTA Slot 容量。
- `sha256` 必须恰好 64 位十六进制，解码后 32 字节。
- `changelog` 可选展示/日志，但长度必须受限。
- 缺少任何必需字段、JSON 错误、设备不匹配、版本不合法、摘要错误、URL 不安全、size 越界，全部拒绝升级。
- Manifest 获取失败、TLS 验证失败、Verifier 创建失败，全部拒绝升级；**绝不允许降级为不校验继续运行**。

官方 Manifest Checker 当前只解析 `version`、`project_name`、`size` 和可选 `sha256` / `md5`，不完整覆盖本项目的 `device`、`url`、`changelog`。并且它不会自动把 Manifest 的 URL 注入 HTTP Source。因此需要一个很薄的 Manifest Preflight Parser：使用 ESP-IDF HTTP Client + cJSON 获取和校验业务字段，再把校验通过的 BIN URL、SHA-256 和 size 交给官方 HTTP Source / Verifier。不要重复实现 HTTP OTA 数据流或 Flash 写入。

### 7.3 HTTPS 证书

- 使用 `esp_ota_service_source_http_cfg_t.cert_pem` 或 ESP x509 Certificate Bundle。
- Manifest 请求和 BIN 下载都必须验证证书链与主机名。
- 测试服务器使用测试 CA 签发证书，设备信任该 CA；证书 SAN 必须覆盖设备访问的域名或 IP。
- 不允许 `skip_cert_common_name_check`、TrustAll、关闭 TLS 校验或把 HTTP URL 当作临时绕过。
- 服务器地址、SSID、密码、CA 私钥等配置不能提交到公开仓库。测试 CA 根证书如确实需要固件内置，只能提交公开测试 CA 证书，不得提交 CA 私钥。

### 7.4 测试服务器工具

请实现 `tools/make_manifest.py` 和 `tools/https_test_server.py`，或提供功能等价工具：

- 从指定 BIN 读取文件大小和 SHA-256。
- 自动生成上述 Manifest。
- 通过 HTTPS 提供 Manifest 和 BIN。
- 命令行指定 BIN、device、version、changelog、证书和私钥路径。
- 不把私钥写入 Git。
- 给出 Windows PowerShell 下启动服务器的示例命令。
- 提供证书生成说明（含 SAN），并解释设备端如何信任测试 CA。

## 8. 版本、启动和回滚

### 8.1 OTA 提交顺序

必须保证顺序：

```text
Receive
  -> exact size check
  -> SHA-256 check
  -> ESP image validation
  -> OTA Target commit / set boot partition
  -> reboot
  -> pending-verify self-test
  -> confirm image OR rollback
```

不要在校验之前调用 Commit。

### 8.2 新固件自检

开启 rollback 后，新镜像第一次启动会处于 Pending Verify。应用启动时检查镜像状态：

- NVS 可正常初始化 / 读取。
- 当前运行分区和应用描述信息有效。
- 核心任务可启动。
- OTA 服务基础组件初始化成功（若该测试固件启用）。
- 设备没有立即发生异常重启。

全部通过后调用官方确认接口（例如 `esp_ota_service_confirm_update()`）。任一关键自检失败，调用官方 rollback API 并重启。**不能一启动就无条件确认**，否则回滚机制失去意义。

## 9. 构建与执行顺序

必须按阶段执行，不允许跳过构建验证直接堆代码。

### P0：环境与项目检查

1. 检查本地 ESP-IDF、Python、CMake、Ninja、RISC-V 工具链和 Component Manager。
2. 记录 `idf.py --version`、`IDF_PATH`、目标芯片和组件解析版本。
3. 确认 ESP32-C3FH4 的 4 MB Flash。
4. 备份原固件 / 原分区表（若硬件可用）。
5. 记录开发板是否真实连接；没有板子时不得写“烧录成功”。

### P1：单一官方组件最小构建

1. 先建立原生 ESP-IDF 项目。
2. 锁定 `esp_ota_service 0.5.2~3`。
3. 以 `esp32c3` 为 target。
4. 配置 4 MB 双 OTA Slot。
5. 同时编译 BLE Source、HTTP Source、App Target、SHA-256 Verifier 和 rollback。
6. 执行完整构建，解决真实编译错误；不得用删除功能的方式绕过。

### P2：统一 OTA Manager + UART Console

实现统一会话管理、互斥、事件日志和控制台命令。先确认空会话、状态查询、Abort 和资源释放行为正确。

### P3：BLE 真机传输

按第 6 节完成真实 BIN 升级、SHA-256 错误拒绝和断连失败测试。

### P4：Wi-Fi HTTPS 真机传输

按第 7 节完成真实 Manifest / BIN 下载、TLS 错误拒绝、SHA-256 错误拒绝和断网失败测试。

### P5：同一固件双通道交叉升级

使用同一个统一 POC 固件和同一张分区表，执行：

- USB 初始烧录 v0.1.0
- BLE 升级到 v0.1.1
- Wi-Fi HTTPS 升级到 v0.1.2
- BLE 升级到 v0.1.3
- Wi-Fi HTTPS 升级到 v0.1.4

每次重启后读取实际运行版本和运行分区。每次成功必须有对应 BIN SHA-256、串口日志和传输端日志。

### P6：可靠性和回滚

至少测试：
- BLE 传输中断开连接。
- Wi-Fi 下载中断网。
- 错误 SHA-256。
- Manifest device 不匹配。
- Manifest version 不高于当前版本。
- size 不匹配或超过分区。
- 错误证书 / 错误主机名 / HTTPS 服务器不可达。
- 无效 ESP 镜像。
- OTA 写入中断电（由用户在确认风险后执行）。
- 新固件 Pending Verify 阶段自检失败并回滚。

断电测试必须由用户在已备份且明确同意后执行；不要自动控制真实电源。

## 10. 必须提供的日志

串口日志必须至少包含：

- 启动时：芯片型号、Flash 容量、当前版本、当前运行分区、下一 OTA 分区、OTA 状态。
- BLE：BLE Source 初始化、GATT 广播开始、等待 Start、接收镜像长度、传输进度、错误码、Sector / CRC 统计（若官方事件可取得）、Verifier 结果。
- Wi-Fi：连接结果、Manifest URL、HTTP 状态、TLS 验证结果、Manifest 关键字段（不要打印密码）、BIN URL、Content-Length、接收字节数、SHA-256 结果。
- OTA 生命周期：Session Begin、Item Begin、Progress、Item End status/reason/error、Session End、Commit、Reboot。
- 重启后：新版本、当前运行分区、Pending Verify 状态、自检结果、Confirm 或 Rollback。

禁止只打印“OTA 成功”。每个错误必须带具体阶段、ESP-IDF 错误码和可读错误文本。

## 11. 交付清单

完成后在 `ota-poc/` 下提交：

1. 可独立构建的 ESP-IDF 固件工程。
2. 4 MB 分区表和 sdkconfig defaults。
3. 锁定版本的 Component Manager manifest / lock file。
4. 统一 BLE + HTTPS 双通道 OTA Manager。
5. UART 测试控制台。
6. Manifest 解析与 fail-closed 校验。
7. SHA-256 + size 校验。
8. HTTPS 测试服务器与 Manifest 生成工具。
9. Windows PowerShell 构建 / 烧录 / 测试说明。
10. 硬件测试矩阵与测试结果模板。
11. 最终报告：已完成、已编译、已烧录、已真机验证、未验证、已知问题分栏列出。
12. Git commit，并提供分支、提交 SHA 和文件路径。

如果构建环境或开发板不可用：
- 仍要完成工程代码、静态检查、文档和复现命令。
- 报告准确阻塞原因。
- 把所有“未运行”的测试明确标记为 NOT RUN。
- 不得伪造串口日志、硬件结果、OTA 成功记录或性能数据。

## 12. 验收标准（逐项打勾）

- [ ] 独立 ESP-IDF 工程，不修改 Flutter / UniApp 原项目。
- [ ] 目标为 ESP32-C3，实际 Flash 确认 4 MB。
- [ ] 单个固件同时编译 BLE 和 HTTPS Source。
- [ ] BLE 和 Wi-Fi 使用同一 OTA Manager / Service / App Target / 分区布局。
- [ ] 两种 Source 互斥，不会并发写入。
- [ ] BLE 使用官方 ESP BLE OTA APP Profile，不自研 GATT 分包协议。
- [ ] Wi-Fi 由设备主动 HTTPS PULL，不使用明文 HTTP。
- [ ] Manifest 校验 device / version / url / size / sha256。
- [ ] BLE 与 Wi-Fi 都强制整镜像 SHA-256。
- [ ] SHA-256 缺失或初始化失败时 fail-closed。
- [ ] 实际接收长度必须与期望 size 一致，且在 Commit 前检查。
- [ ] 校验成功后才 Commit / 设置 boot partition。
- [ ] Pending Verify 自检成功后才 Confirm。
- [ ] 自检失败可 Rollback。
- [ ] BLE 与 Wi-Fi 各自真实升级成功。
- [ ] 同一设备完成 BLE / Wi-Fi 交叉升级。
- [ ] 错误摘要、断连、断网、TLS 错误均不能提交坏固件。
- [ ] 有完整可复现日志、BIN 哈希、测试报告和 Git 提交。

**最重要：先完成独立 ESP32-C3 OTA 底层 POC。Flutter App 暂时不在本任务范围内。**

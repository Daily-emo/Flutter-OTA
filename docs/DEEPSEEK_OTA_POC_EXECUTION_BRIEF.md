# 旧执行说明归档

本文件已由新的完整项目开发总任务书取代，不再作为执行依据。

请只按以下文件实施 ESP32-C3 双通道 OTA 项目：

`docs/DEEPSEEK_DSH_ESP32C3_OTA_PROJECT_DEVELOPMENT.md`

新任务书明确规定了完整顺序：

1. ESP32-C3 原生固件和 A/B 分区。
2. BLE OTA 固件实现。
3. Espressif 官方 BLE OTA 测试 App 实测。
4. Wi-Fi HTTPS OTA。
5. 同一固件双通道交叉升级。
6. UniApp BLE 通信测试。
7. 稳定性测试。
8. 意外回滚和恢复测试。
9. 所有底层测试通过后再开发正式 UI。

新任务书为唯一有效执行规范。本文档中的旧阶段安排不再适用。

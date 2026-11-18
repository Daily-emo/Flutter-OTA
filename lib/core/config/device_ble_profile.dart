/// UUIDs stay unset until confirmed against ESP32 GATT registration.
class DeviceBleProfile {
 const DeviceBleProfile({this.otaServiceUuid,this.controlWriteUuid,this.dataWriteUuid,this.eventNotifyUuid});
 final String? otaServiceUuid,controlWriteUuid,dataWriteUuid,eventNotifyUuid;
 bool get isConfigured=>otaServiceUuid!=null&&controlWriteUuid!=null&&dataWriteUuid!=null&&eventNotifyUuid!=null;
}

import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';
import '../features/devices/devices_page.dart';
import '../features/ota/ota_page.dart';
import '../features/logs/logs_page.dart';
class MineLampOtaApp extends StatelessWidget {
 const MineLampOtaApp({super.key});
 @override Widget build(BuildContext context) => MaterialApp(title:'MineLamp Flutter OTA',debugShowCheckedModeBanner:false,theme:AppTheme.light,darkTheme:AppTheme.dark,themeMode:ThemeMode.system,home:const _Shell());
}
class _Shell extends StatefulWidget { const _Shell(); @override State<_Shell> createState()=>_ShellState(); }
class _ShellState extends State<_Shell> {
 int index=0; static const pages=<Widget>[DevicesPage(),OtaPage(),LogsPage()]; static const labels=['设备','固件升级','调试日志'];
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text('MineLamp OTA · ${labels[index]}')),body:IndexedStack(index:index,children:pages),bottomNavigationBar:NavigationBar(selectedIndex:index,onDestinationSelected:(v)=>setState(()=>index=v),destinations:const[NavigationDestination(icon:Icon(Icons.bluetooth_searching),label:'设备'),NavigationDestination(icon:Icon(Icons.system_update_alt),label:'升级'),NavigationDestination(icon:Icon(Icons.receipt_long),label:'日志')]));
}

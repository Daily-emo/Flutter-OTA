import 'package:flutter/material.dart';
abstract final class AppTheme {
 static ThemeData get light=>ThemeData(useMaterial3:true,colorSchemeSeed:const Color(0xFF16856B),brightness:Brightness.light);
 static ThemeData get dark=>ThemeData(useMaterial3:true,colorSchemeSeed:const Color(0xFF36B99A),brightness:Brightness.dark);
}

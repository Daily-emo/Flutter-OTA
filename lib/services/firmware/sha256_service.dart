import 'dart:typed_data';
import 'package:crypto/crypto.dart';
class Sha256Service { const Sha256Service(); String digestBytes(Uint8List bytes)=>sha256.convert(bytes).toString(); bool matches(Uint8List bytes,String expected)=>digestBytes(bytes).toLowerCase()==expected.toLowerCase(); }

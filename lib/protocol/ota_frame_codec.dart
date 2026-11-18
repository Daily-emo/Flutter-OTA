import 'dart:typed_data';
import 'ota_command.dart'; import 'ota_frame.dart';
abstract final class OtaFrameCodec {
 static const sof=0xA5,protocolVersion=1,headerLength=12,trailerLength=2;
 static Uint8List encode(OtaFrame f){final p=f.payload;final b=Uint8List(headerLength+p.length+trailerLength);final v=ByteData.sublistView(b);b[0]=sof;b[1]=f.version;b[2]=f.command.code;b[3]=f.flags;v.setUint16(4,f.requestId,Endian.little);v.setUint32(6,f.sessionId,Endian.little);v.setUint16(10,p.length,Endian.little);b.setRange(headerLength,headerLength+p.length,p);v.setUint16(headerLength+p.length,crc16(b.sublist(1,headerLength+p.length)),Endian.little);return b;}
 static OtaFrame decode(Uint8List b){if(b.length<headerLength+trailerLength||b[0]!=sof||b[1]!=protocolVersion)throw const FormatException('Invalid OTA frame header');final v=ByteData.sublistView(b);final n=v.getUint16(10,Endian.little);if(b.length!=headerLength+n+trailerLength)throw const FormatException('Frame length mismatch');if(v.getUint16(headerLength+n,Endian.little)!=crc16(b.sublist(1,headerLength+n)))throw const FormatException('CRC mismatch');return OtaFrame(version:b[1],command:OtaCommand.fromCode(b[2]),flags:b[3],requestId:v.getUint16(4,Endian.little),sessionId:v.getUint32(6,Endian.little),payload:Uint8List.fromList(b.sublist(headerLength,headerLength+n)));}
 static int crc16(List<int> bytes){var c=0xFFFF;for(final x in bytes){c^=(x&255)<<8;for(var i=0;i<8;i++){c=(c&0x8000)!=0?((c<<1)^0x1021)&0xFFFF:(c<<1)&0xFFFF;}}return c;}
}

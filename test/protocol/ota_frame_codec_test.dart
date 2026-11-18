import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:minelamp_flutter_ota/protocol/ota_command.dart';
import 'package:minelamp_flutter_ota/protocol/ota_frame.dart';
import 'package:minelamp_flutter_ota/protocol/ota_frame_codec.dart';
void main(){test('frame round trip',(){final f=OtaFrame(command:OtaCommand.prepare,requestId:0x1234,sessionId:0x12345678,payload:Uint8List.fromList([1,2,3]));final d=OtaFrameCodec.decode(OtaFrameCodec.encode(f));expect(d.command,OtaCommand.prepare);expect(d.requestId,0x1234);expect(d.sessionId,0x12345678);expect(d.payload,[1,2,3]);});test('CRC corruption rejected',(){final b=OtaFrameCodec.encode(OtaFrame(command:OtaCommand.queryCaps,requestId:1,sessionId:0,payload:Uint8List.fromList([1,2])));b[12]^=255;expect(()=>OtaFrameCodec.decode(b),throwsFormatException);});}

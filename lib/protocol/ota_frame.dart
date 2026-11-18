import 'dart:typed_data';
import 'ota_command.dart';
class OtaFrame { OtaFrame({required this.command,required this.requestId,required this.sessionId,this.flags=0,Uint8List? payload,this.version=1}):payload=payload??Uint8List(0); final int version,flags,requestId,sessionId; final OtaCommand command; final Uint8List payload; bool get isResponse=>(flags&OtaFrameFlags.response)!=0; bool get isError=>(flags&OtaFrameFlags.error)!=0; }

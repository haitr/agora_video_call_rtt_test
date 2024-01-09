// ignore_for_file: invalid_use_of_protected_member

import 'dart:async';
import 'dart:developer';
import 'dart:typed_data';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:agora_uikit/agora_uikit.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as io;

import 'message.pb.dart' as pb;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple), useMaterial3: true),
      home: MyPage(),
    );
  }
}

class MyPage extends StatelessWidget {
  final controller = TextEditingController(text: 'user');

  MyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: controller),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => CallPage(name: controller.text)));
              },
              child: const Text('Agora'),
            ),
            const SizedBox(height: 24),
            TextButton(
              onPressed: () {
                Navigator.push(
                    context, MaterialPageRoute(builder: (context) => CallPage(name: controller.text, ownServer: true)));
              },
              child: const Text('Our'),
            ),
          ],
        ),
      ),
    );
  }
}

class CallPage extends StatefulWidget {
  const CallPage({super.key, required this.name, this.ownServer = false});

  final String name;

  final bool ownServer;

  @override
  State<CallPage> createState() => _CallPageState(ownServer);
}

class _CallPageState extends State<CallPage> {
  _CallPageState(this.ownServer);

  late final AgoraClient _agoraClient;
  final channelName = 'test';

  final _serverUri = 'http://192.168.2.122:3000';
  final _socketUri = 'http://192.168.2.122:3001';
  // final _serverUri = 'http://13.209.133.141:3000';

  final tempToken =
      "007eJxTYLDKapOvXvk6saI6RL3o/vsl527XTNmb+FX3gEb7FP1pR/UVGBKTUowMjIxMU5JTLU1SUiwTTS2TTJNNTZMskwxSLIwMVm2JS20IZGRI0D/NyMgAgSA+C0NJanEJAwMAvPUhAw==";

  late io.Socket _socket;
  final bool ownServer;
  var isFirst = true;
  late LimitedQueue<int> _queue;
  late int _samplesPerChannel;
  Timer? timer;

  final _loading = Completer<bool>();
  final _transcribe = StreamController<String>();

  @override
  void initState() {
    super.initState();
    if (ownServer) {
      // Future.wait([_initAgora()]).then((value) => _loading.complete(true));
      Future.wait([_initAgora(), _socketConnect()]).then((value) => _loading.complete(true));
    } else {
      Future.wait([_initAgora(), _agoraRTTStart(0)]).then((value) => _loading.complete(true));
    }
  }

  @override
  void dispose() {
    super.dispose();
    _dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: Theme.of(context).colorScheme.inversePrimary, title: Text(widget.name)),
      body: SafeArea(
        child: FutureBuilder<bool>(
            future: _loading.future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              return Center(
                child: Stack(
                  children: [
                    AgoraVideoViewer(client: _agoraClient),
                    AgoraVideoButtons(client: _agoraClient),
                    StreamBuilder(
                      stream: _transcribe.stream,
                      builder: (_, snap) {
                        if (snap.connectionState == ConnectionState.active) {
                          return Align(
                            alignment: Alignment.topCenter,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              color: Colors.black.withOpacity(0.2),
                              child: Text(
                                snap.data ?? '',
                                style: const TextStyle(color: Colors.white, fontSize: 14),
                              ),
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    )
                  ],
                ),
              );
            }),
      ),
      // floatingActionButton: FloatingActionButton(
      //   onPressed: () {},
      //   tooltip: 'Increment',
      //   child: const Icon(Icons.add),
      // ),
    );
  }
}

extension on _CallPageState {
  Future<void> _initAgora() async {
    _agoraClient = AgoraClient(
      agoraConnectionData: AgoraConnectionData(
        username: widget.name,
        appId: "abd20225dce94dd9a59b5c55b9b0d820",
        channelName: channelName,
        tempToken: tempToken,
        rtmEnabled: false,
        screenSharingEnabled: false,
      ),
      agoraChannelData: AgoraChannelData(
        audioProfileType: AudioProfileType.audioProfileSpeechStandard,
      ),
      enabledPermission: [Permission.camera, Permission.microphone],
      agoraEventHandlers: AgoraRtcEventHandlers(
        onJoinChannelSuccess: (connection, uid) {
          log('joined: $uid');
          if (!ownServer) _agoraRTTStart(uid);
        },
        onStreamMessage: (connection, remoteUid, streamId, data, length, sentTs) {
          log('------');
          log('received: $length bytes');
          final text = pb.Text.fromBuffer(data);
          final collect = text.words.map((e) => e.text);
          _transcribe.add(collect.join());
        },
      ),
    );
    await _agoraClient.initialize();
    // add observer
    _agoraClient.engine.getMediaEngine().registerAudioFrameObserver(
      AudioFrameObserver(
        onRecordAudioFrame: (channelId, audioFrame) {
          // if (isFirst) {
          //   const secs = 2;
          //   _samplesPerChannel = audioFrame.samplesPerSec!;
          //   final nSamples = audioFrame.samplesPerSec! * secs;
          //   final nChannels = audioFrame.channels!;
          //   final nBytesPerChannel = audioFrame.bytesPerSample!.value();
          //   _queue = LimitedQueue(nSamples, nChannels, nBytesPerChannel);
          //   isFirst = false;
          // }
          if (ownServer) {
            if (audioFrame.buffer != null) {
              // _queue.addAll(audioFrame.buffer!);
              _socket.emit('data', audioFrame.buffer!);
            }
          }
        },
      ),
    );
    // Future.delayed(const Duration(seconds: 1)).then((value) async {
    //   timer = Timer.periodic(const Duration(seconds: 5), (timer) {
    //     post();
    //   });
    // });
  }

  void _dispose() {
    timer?.cancel();
    _agoraClient.release();
    _socket.close();
  }

  void post() {
    final request = http.MultipartRequest('POST', Uri.parse('$_serverUri/inference'));
    var file = http.MultipartFile.fromBytes('file', _createWavBuffer());
    request.files.add(file);
    request.fields['response-format'] = "json";
    request.fields['temperature'] = '0.5';
    request.send();
  }

  Uint8List _createWavBuffer() {
    // Calculate the total length of the audio data in bytes
    const bytesPerSample = 2;
    final dataLength = _queue.length;

    // Calculate the total file size in bytes
    final fileSize = 44 + dataLength;
    // Create a WAV file header
    final wavHeader = Uint8List(44);
    var offset = 0;
    wavHeader.setAll(offset, 'RIFF'.codeUnits); // Chunk ID
    offset += 4;
    ByteData.view(wavHeader.buffer, offset, 4).setUint32(0, fileSize - 8, Endian.little); // File Size
    offset += 4;
    wavHeader.setAll(offset, 'WAVE'.codeUnits); // Format
    offset += 4;
    wavHeader.setAll(offset, 'fmt '.codeUnits); // Format
    offset += 4;
    ByteData.view(wavHeader.buffer, offset, 4).setUint32(0, 16, Endian.little); // Subchunk1 Size
    offset += 4;
    ByteData.view(wavHeader.buffer, offset, 2).setUint16(0, 1, Endian.little); // Audio Format (PCM)
    offset += 2;
    ByteData.view(wavHeader.buffer, offset, 2).setUint16(0, _queue.nChannels, Endian.little); // Num Channels
    offset += 2;
    ByteData.view(wavHeader.buffer, offset, 4).setUint32(0, _samplesPerChannel, Endian.little); // Sample Rate
    offset += 4;
    ByteData.view(wavHeader.buffer, offset, 4)
        .setUint32(0, _samplesPerChannel * _queue.nChannels * bytesPerSample, Endian.little); // Byte Rate
    offset += 4;
    ByteData.view(wavHeader.buffer, offset, 2)
        .setUint16(0, _queue.nChannels * bytesPerSample, Endian.little); // Block Align
    offset += 2;
    ByteData.view(wavHeader.buffer, offset, 2).setUint16(0, bytesPerSample * 8, Endian.little); // Bits Per Sample
    offset += 2;
    wavHeader.setAll(offset, 'data'.codeUnits); // Subchunk2 ID
    offset += 4;
    ByteData.view(wavHeader.buffer, offset, 4).setUint32(0, dataLength, Endian.little); // Subchunk2 Size

    // Concatenate the WAV header and PCM data
    final wavData = Uint8List.fromList([...wavHeader, ..._queue.list]);
    return wavData;
  }

  Future<void> _socketConnect() async {
    // return;
    var opts = io.OptionBuilder()
        .enableReconnection()
        .setReconnectionDelay(1000)
        .disableAutoConnect()
        .setTransports(['websocket']) // for Flutter or Dart VM
        .build();
    _socket = io.io(_socketUri, opts);
    _socket.connect();
    return Future.delayed(const Duration(milliseconds: 500));
  }

  Future<void> _agoraRTTStart(int uid) async {
    // return;
    final response = await http.get(Uri.parse('$_serverUri/rttStart/$channelName/$uid'));
    print('rttStart with code ${response.statusCode}');
  }
}

class LimitedQueue<E> {
  final int _maxSize;

  final int nSamples;
  final int nChannels;
  final int nBytesPerChannel;

  var _internalQueue = <E>[];

  LimitedQueue(this.nSamples, this.nChannels, this.nBytesPerChannel)
      : _maxSize = nSamples * nChannels * nBytesPerChannel;

  int get length => _internalQueue.length;

  List<E> get list => _internalQueue;

  void add(E element) {
    if (_internalQueue.length >= _maxSize) {
      _internalQueue.remove(0); // Remove the oldest element
    }
    _internalQueue.add(element); // Add the new element
  }

  void addAll(Iterable<E> iterable) {
    final newLength = _internalQueue.length + iterable.length;
    if (newLength >= _maxSize) {
      _internalQueue = _internalQueue.skip(newLength - _maxSize).toList();
    }
    _internalQueue.addAll(iterable);
  }
}

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:musicplayer/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methodChannel = MethodChannel('com.aravindprojects.musicplayer/media');
  const eventChannelName = 'com.aravindprojects.musicplayer/player_events';
  const codec = StandardMethodCodec();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (call) async {
          switch (call.method) {
            case 'getMusicFiles':
              return <Map<String, Object?>>[];
            case 'playTrack':
            case 'pausePlayback':
            case 'resumePlayback':
            case 'seekTo':
            case 'stopPlayback':
              return null;
            case 'getArtwork':
              return null;
          }
          return null;
        });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(eventChannelName, (message) async {
          final methodCall = codec.decodeMethodCall(message);
          if (methodCall.method == 'listen' || methodCall.method == 'cancel') {
            return codec.encodeSuccessEnvelope(null);
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(eventChannelName, null);
  });

  testWidgets('shows the device music screen', (tester) async {
    await tester.pumpWidget(const MusicPlayerApp());
    await tester.pumpAndSettle();

    expect(find.text('All'), findsOneWidget);
    expect(find.text('Folders'), findsOneWidget);
    expect(find.text('No music files found on this device.'), findsOneWidget);
  });
}

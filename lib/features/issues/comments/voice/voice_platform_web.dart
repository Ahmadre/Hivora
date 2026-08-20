import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Web: `record` manages its own storage and ignores the path — no dir needed.
Future<String> recorderTempDir() async => '';

/// Web: never — nothing is shelled out to.
String? missingRecorderDependency() => null;

/// Web: never. The browser's MediaRecorder is in-process — there is no helper
/// program that could be missing.
String? missingRecorderTool(Object error) => null;

/// Web: the recorder handed back a `blob:` URL. Fetch it to recover the raw
/// bytes and, importantly, the browser's *actual* MIME type (Chrome/Firefox
/// emit `audio/webm`, Safari `audio/mp4`) so the upload is content-typed
/// correctly. Falls back to [fallbackMime] if the blob carries no type.
Future<({Uint8List bytes, String mime})> readRecordedAudio(
  String path,
  String fallbackMime,
) async {
  final response = await web.window.fetch(path.toJS).toDart;
  final buffer = await response.arrayBuffer().toDart;
  final bytes = buffer.toDart.asUint8List();
  final contentType = response.headers.get('content-type');
  final mime = (contentType != null && contentType.isNotEmpty)
      ? contentType
      : fallbackMime;
  return (bytes: bytes, mime: mime);
}

/// Web: wrap the downloaded audio bytes in a Blob object URL `just_audio` (which
/// uses an `<audio>` element on web) can play. `dispose` revokes the URL.
Future<({String uri, Future<void> Function() dispose})> createPlayableSource(
  Uint8List bytes,
  String mime,
) async {
  final type = mime.isEmpty ? 'audio/webm' : mime;
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: type));
  final url = web.URL.createObjectURL(blob);
  return (uri: url, dispose: () async => web.URL.revokeObjectURL(url));
}

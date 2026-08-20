// Platform bridge for voice comments. The operations below differ between
// native and web and are implemented once per platform:
//
//  • [readRecordedAudio] — after `record` finishes, turn the recorder's output
//    handle into raw bytes + the real MIME type. Native returns a file path;
//    web returns a `blob:` URL that must be fetched back.
//  • [createPlayableSource] — turn downloaded audio bytes into a URI `just_audio`
//    can play: a temp file on native, a `blob:` object URL on web. The returned
//    `dispose` frees it (deletes the file / revokes the object URL).
//  • [missingRecorderDependency] / [missingRecorderTool] — name the helper
//    program the recorder needs and cannot use: the first checks PATH before
//    capture starts, the second reads it out of a failure. Only Linux drives
//    capture through external processes; every other platform records
//    in-process, so there is nothing to name.
export 'voice_platform_io.dart'
    if (dart.library.js_interop) 'voice_platform_web.dart';

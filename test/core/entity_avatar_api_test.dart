import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/team_models.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/project_repository.dart';
import 'package:hinata/core/repositories/team_repository.dart';

/// Teams and projects grew a picture of their own (HIN-32). It is server-owned:
/// it arrives on the entity as `avatarUrl` and is written only through the
/// dedicated avatar endpoints — never as part of a PATCH body. These tests pin
/// both halves of that contract.
void main() {
  group('Team.avatarUrl', () {
    test('round-trips through fromJson', () {
      final team = Team.fromJson(const {
        'id': 't1',
        'key': 'CORE',
        'name': 'Core Platform',
        'avatarUrl': '/api/v1/teams/t1/avatar?v=1717&bh=LEHV6nWB',
      });
      expect(team.avatarUrl, '/api/v1/teams/t1/avatar?v=1717&bh=LEHV6nWB');
    });

    test('is null when the server omits it', () {
      final team = Team.fromJson(const {
        'id': 't1',
        'key': 'CORE',
        'name': 'Core Platform',
      });
      expect(team.avatarUrl, isNull);
    });

    test('takes part in equality, so a new picture is a changed team', () {
      Team withUrl(String? url) => Team.fromJson({
        'id': 't1',
        'key': 'CORE',
        'name': 'Core Platform',
        'avatarUrl': ?url,
      });
      expect(withUrl('/a?v=1'), isNot(withUrl('/a?v=2')));
      expect(withUrl(null), isNot(withUrl('/a?v=1')));
      expect(withUrl('/a?v=1'), withUrl('/a?v=1'));
    });
  });

  group('Project.avatarUrl', () {
    Project parse({String? avatarUrl}) => Project.fromJson({
      'id': 'p1',
      'key': 'HIN',
      'name': 'Hinata',
      'avatarUrl': ?avatarUrl,
    });

    test('round-trips through fromJson', () {
      expect(
        parse(avatarUrl: '/api/v1/projects/p1/avatar?v=9').avatarUrl,
        '/api/v1/projects/p1/avatar?v=9',
      );
    });

    test('is null when the server omits it', () {
      expect(parse().avatarUrl, isNull);
    });

    /// The settings screen edits a *draft* built from copyWith. If the picture
    /// were dropped there, every unrelated keystroke would silently un-set it.
    test('survives an unrelated copyWith', () {
      final edited = parse(avatarUrl: '/a?v=9').copyWith(name: 'Renamed');
      expect(edited.avatarUrl, '/a?v=9');
      expect(edited.name, 'Renamed');
    });

    test('withGit keeps the picture too', () {
      expect(parse(avatarUrl: '/a?v=9').withGit(null).avatarUrl, '/a?v=9');
    });

    test('clearAvatar is the only way to drop it', () {
      expect(
        parse(avatarUrl: '/a?v=9').copyWith(clearAvatar: true).avatarUrl,
        isNull,
      );
    });
  });

  group('avatar endpoints', () {
    late _RecordingApiClient api;

    setUp(() => api = _RecordingApiClient());

    MultipartFile file() =>
        MultipartFile.fromBytes(const [1, 2, 3], filename: 'team.png');

    test('uploading a team picture posts to the team avatar path', () async {
      api.uploadResponse = {'avatarUrl': '/api/v1/teams/t1/avatar?v=42'};
      final url = await TeamRepository(api).uploadTeamAvatar('t1', file());

      expect(api.calls, [('upload', '/api/v1/teams/t1/avatar')]);
      // The fresh `?v=` token is what the caller stores to swap the picture.
      expect(url, '/api/v1/teams/t1/avatar?v=42');
    });

    test('removing a team picture deletes the same path', () async {
      await TeamRepository(api).deleteTeamAvatar('t1');
      expect(api.calls, [('delete', '/api/v1/teams/t1/avatar')]);
    });

    test(
      'uploading a project picture posts to the project avatar path',
      () async {
        api.uploadResponse = {'avatarUrl': '/api/v1/projects/p1/avatar?v=7'};
        final url = await ProjectRepository(
          api,
        ).uploadProjectAvatar('p1', file());

        expect(api.calls, [('upload', '/api/v1/projects/p1/avatar')]);
        expect(url, '/api/v1/projects/p1/avatar?v=7');
      },
    );

    test('removing a project picture deletes the same path', () async {
      await ProjectRepository(api).deleteProjectAvatar('p1');
      expect(api.calls, [('delete', '/api/v1/projects/p1/avatar')]);
    });
  });
}

/// Records the verb + path of every call, so the tests assert the wire contract
/// rather than a mocked repository talking to itself.
class _RecordingApiClient implements ApiClient {
  final List<(String, String)> calls = [];
  Map<String, dynamic> uploadResponse = const {};

  @override
  Future<dynamic> upload(
    String path,
    MultipartFile file, {
    void Function(int sent, int total)? onSendProgress,
    CancelToken? cancelToken,
    Map<String, dynamic>? fields,
  }) async {
    calls.add(('upload', path));
    return uploadResponse;
  }

  @override
  Future<dynamic> delete(String path, {Object? body}) async {
    calls.add(('delete', path));
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

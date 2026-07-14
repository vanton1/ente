import "dart:async";
import "dart:typed_data";

import "package:dio/dio.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/core/network/endpoint_config.dart";
import "package:photos/core/network/endpoint_policy.dart";
import "package:photos/core/network/endpoint_switcher.dart";
import "package:shared_preferences/shared_preferences.dart";

const _activeEndpoint = "https://museum.example";
const _candidateEndpoint = "https://new-museum.example:8443";
const _configurablePolicy = EndpointPolicy(
  mode: EndpointMode.configurable,
  compiledEndpoint: _activeEndpoint,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    "probe canonicalizes a candidate without credentials or redirects",
    () async {
      final adapter = _ProbeAdapter.pong();
      final probe = EndpointProbe(
        policy: _configurablePolicy,
        httpClientAdapter: adapter,
      );
      addTearDown(probe.close);

      final endpoint = await probe.validate("https://New-Museum.Example:8443/");

      expect(endpoint.origin, _candidateEndpoint);
      expect(adapter.lastRequest?.uri, Uri.parse("$_candidateEndpoint/ping"));
      expect(adapter.lastRequest?.followRedirects, isFalse);
      expect(adapter.lastRequest?.connectTimeout, EndpointProbe.timeout);
      expect(adapter.lastRequest?.receiveTimeout, EndpointProbe.timeout);
      expect(
        adapter.lastRequest?.headers.keys.map((key) => key.toLowerCase()),
        isNot(contains("x-auth-token")),
      );
    },
  );

  test("invalid candidates fail before any request", () async {
    final adapter = _ProbeAdapter.pong();
    final probe = EndpointProbe(
      policy: _configurablePolicy,
      httpClientAdapter: adapter,
    );
    addTearDown(probe.close);

    await expectLater(
      probe.validate("http://museum.example"),
      throwsA(
        isA<EndpointPolicyException>().having(
          (error) => error.reason,
          "reason",
          EndpointPolicyFailureReason.invalidConfigurableEndpoint,
        ),
      ),
    );
    expect(adapter.lastRequest, isNull);
  });

  test("unexpected ping responses and redirects are rejected", () async {
    final invalidResponseProbe = EndpointProbe(
      policy: _configurablePolicy,
      httpClientAdapter: _ProbeAdapter.json('{"message":"not-pong"}'),
    );
    addTearDown(invalidResponseProbe.close);

    await expectLater(
      invalidResponseProbe.validate(_candidateEndpoint),
      throwsA(
        isA<EndpointProbeException>().having(
          (error) => error.reason,
          "reason",
          EndpointProbeFailureReason.invalidResponse,
        ),
      ),
    );

    final redirectAdapter = _ProbeAdapter.json(
      "{}",
      statusCode: 302,
      headers: {
        "location": ["https://other.example/ping"],
      },
    );
    final redirectProbe = EndpointProbe(
      policy: _configurablePolicy,
      httpClientAdapter: redirectAdapter,
    );
    addTearDown(redirectProbe.close);

    await expectLater(
      redirectProbe.validate(_candidateEndpoint),
      throwsA(
        isA<EndpointProbeException>().having(
          (error) => error.reason,
          "reason",
          EndpointProbeFailureReason.requestFailed,
        ),
      ),
    );
    expect(redirectAdapter.lastRequest?.followRedirects, isFalse);
  });

  test("a failed probe leaves the binding and account untouched", () async {
    final preferences = await _preferences({
      EndpointConfig.bindingKey: _activeEndpoint,
      "token": "token",
      "user_id": 1,
    });
    final adapter = _ProbeAdapter.connectionFailure();
    final switcher = EndpointSwitcher(
      EndpointConfig(preferences, policy: _configurablePolicy),
      probe: EndpointProbe(
        policy: _configurablePolicy,
        httpClientAdapter: adapter,
      ),
    );
    addTearDown(switcher.close);

    await expectLater(
      switcher.validateCandidate(_candidateEndpoint),
      throwsA(
        isA<EndpointProbeException>().having(
          (error) => error.reason,
          "reason",
          EndpointProbeFailureReason.requestFailed,
        ),
      ),
    );

    expect(preferences.getString(EndpointConfig.bindingKey), _activeEndpoint);
    expect(preferences.getString("token"), "token");
    expect(preferences.getInt("user_id"), 1);
  });

  test("activation refuses to change a binding before local logout", () async {
    final preferences = await _preferences({
      EndpointConfig.bindingKey: _activeEndpoint,
      "token": "token",
      "user_id": 1,
    });
    final switcher = _switcher(preferences);
    addTearDown(switcher.close);
    final endpoint = await switcher.validateCandidate(_candidateEndpoint);

    await expectLater(
      switcher.activateAfterLocalLogout(endpoint),
      throwsA(
        isA<EndpointPolicyException>().having(
          (error) => error.reason,
          "reason",
          EndpointPolicyFailureReason.accountStateNotCleared,
        ),
      ),
    );

    expect(preferences.getString(EndpointConfig.bindingKey), _activeEndpoint);
    expect(preferences.getString("token"), "token");
  });

  test("activation changes the binding only after local logout", () async {
    final preferences = await _preferences({
      EndpointConfig.bindingKey: _activeEndpoint,
      "token": "token",
      "setting": true,
    });
    final config = EndpointConfig(preferences, policy: _configurablePolicy);
    final switcher = EndpointSwitcher(
      config,
      probe: EndpointProbe(
        policy: _configurablePolicy,
        httpClientAdapter: _ProbeAdapter.pong(),
      ),
    );
    addTearDown(switcher.close);
    final endpoint = await switcher.validateCandidate(_candidateEndpoint);
    final event = Bus.instance.on<EndpointUpdatedEvent>().first;

    expect(switcher.isCurrent(endpoint), isFalse);
    await config.clearPreferencesForLogout();
    expect(await switcher.activateAfterLocalLogout(endpoint), isTrue);

    expect(preferences.getKeys(), {EndpointConfig.bindingKey});
    expect(
      preferences.getString(EndpointConfig.bindingKey),
      _candidateEndpoint,
    );
    expect(config.endpoint, _candidateEndpoint);
    expect((await event).endpoint, _candidateEndpoint);
  });

  test("activating the current endpoint is an event-free no-op", () async {
    final preferences = await _preferences({
      EndpointConfig.bindingKey: _activeEndpoint,
    });
    final switcher = _switcher(preferences);
    addTearDown(switcher.close);
    final endpoint = await switcher.validateCandidate(_activeEndpoint);
    var eventCount = 0;
    final subscription = Bus.instance.on<EndpointUpdatedEvent>().listen((_) {
      eventCount++;
    });
    addTearDown(subscription.cancel);

    expect(switcher.isCurrent(endpoint), isTrue);
    expect(await switcher.activateAfterLocalLogout(endpoint), isFalse);
    await Future<void>.delayed(Duration.zero);

    expect(eventCount, 0);
    expect(preferences.getString(EndpointConfig.bindingKey), _activeEndpoint);
  });

  test(
    "probing and guarded activation reject non-configurable modes",
    () async {
      const lockedPolicy = EndpointPolicy(
        mode: EndpointMode.locked,
        compiledEndpoint: _activeEndpoint,
      );
      final preferences = await _preferences({
        EndpointConfig.bindingKey: _activeEndpoint,
      });
      final adapter = _ProbeAdapter.pong();
      final probe = EndpointProbe(
        policy: lockedPolicy,
        httpClientAdapter: adapter,
      );
      addTearDown(probe.close);

      await expectLater(
        probe.validate(_candidateEndpoint),
        throwsA(
          isA<EndpointPolicyException>().having(
            (error) => error.reason,
            "reason",
            EndpointPolicyFailureReason.runtimeMutationNotAllowed,
          ),
        ),
      );
      await expectLater(
        EndpointConfig(
          preferences,
          policy: lockedPolicy,
        ).activateConfigurableEndpointAfterLocalLogout(_candidateEndpoint),
        throwsA(isA<EndpointPolicyException>()),
      );
      expect(adapter.lastRequest, isNull);
      expect(preferences.getString(EndpointConfig.bindingKey), _activeEndpoint);
    },
  );
}

EndpointSwitcher _switcher(SharedPreferences preferences) {
  return EndpointSwitcher(
    EndpointConfig(preferences, policy: _configurablePolicy),
    probe: EndpointProbe(
      policy: _configurablePolicy,
      httpClientAdapter: _ProbeAdapter.pong(),
    ),
  );
}

Future<SharedPreferences> _preferences(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

class _ProbeAdapter implements HttpClientAdapter {
  _ProbeAdapter._({
    required this.body,
    required this.statusCode,
    required this.headers,
    required this.failConnection,
  });

  factory _ProbeAdapter.pong() {
    return _ProbeAdapter.json('{"message":"pong"}');
  }

  factory _ProbeAdapter.json(
    String body, {
    int statusCode = 200,
    Map<String, List<String>> headers = const {},
  }) {
    return _ProbeAdapter._(
      body: body,
      statusCode: statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        ...headers,
      },
      failConnection: false,
    );
  }

  factory _ProbeAdapter.connectionFailure() {
    return _ProbeAdapter._(
      body: "",
      statusCode: 0,
      headers: {},
      failConnection: true,
    );
  }

  final String body;
  final int statusCode;
  final Map<String, List<String>> headers;
  final bool failConnection;

  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    if (failConnection) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: "test connection failure",
      );
    }
    return ResponseBody.fromString(body, statusCode, headers: headers);
  }

  @override
  void close({bool force = false}) {}
}

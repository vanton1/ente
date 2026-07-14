import "dart:io";

import "package:dio/dio.dart";
import "package:photos/core/network/endpoint_config.dart";
import "package:photos/core/network/endpoint_policy.dart";

enum EndpointProbeFailureReason { requestFailed, invalidResponse }

class EndpointProbeException implements Exception {
  const EndpointProbeException(this.reason, this.message, {this.cause});

  final EndpointProbeFailureReason reason;
  final String message;
  final Object? cause;

  @override
  String toString() => "EndpointProbeException(${reason.name}): $message";
}

class ValidatedEndpoint {
  const ValidatedEndpoint._(this.origin);

  final String origin;
}

class EndpointProbe {
  EndpointProbe({required this.policy, HttpClientAdapter? httpClientAdapter})
    : _dio = Dio(
        BaseOptions(
          connectTimeout: timeout,
          receiveTimeout: timeout,
          headers: {HttpHeaders.acceptHeader: "application/json"},
        ),
      ) {
    if (httpClientAdapter != null) {
      _dio.httpClientAdapter = httpClientAdapter;
    }
  }

  static const timeout = Duration(seconds: 15);

  final EndpointPolicy policy;
  final Dio _dio;

  Future<ValidatedEndpoint> validate(String endpoint) async {
    policy.validateModeConfiguration();
    if (!policy.isConfigurable) {
      throw const EndpointPolicyException(
        EndpointPolicyFailureReason.runtimeMutationNotAllowed,
        "Server probing for a switch is available only in configurable builds.",
      );
    }

    final canonicalEndpoint = policy.validateConfigurableEndpoint(endpoint);
    try {
      final response = await _dio.get<dynamic>(
        "$canonicalEndpoint/ping",
        options: Options(followRedirects: false),
      );
      final data = response.data;
      if (data is! Map || data["message"] != "pong") {
        throw const EndpointProbeException(
          EndpointProbeFailureReason.invalidResponse,
          "The server did not return the expected Museum ping response.",
        );
      }
    } on DioException catch (error) {
      throw EndpointProbeException(
        EndpointProbeFailureReason.requestFailed,
        "The server could not be reached and verified.",
        cause: error,
      );
    }

    return ValidatedEndpoint._(canonicalEndpoint);
  }

  void close({bool force = false}) {
    _dio.close(force: force);
  }
}

class EndpointSwitcher {
  EndpointSwitcher(this.endpointConfig, {EndpointProbe? probe})
    : _probe = probe ?? EndpointProbe(policy: endpointConfig.policy);

  final EndpointConfig endpointConfig;
  final EndpointProbe _probe;

  Future<ValidatedEndpoint> validateCandidate(String endpoint) {
    return _probe.validate(endpoint);
  }

  bool isCurrent(ValidatedEndpoint endpoint) {
    return endpointConfig.endpoint == endpoint.origin;
  }

  Future<bool> activateAfterLocalLogout(ValidatedEndpoint endpoint) {
    return endpointConfig.activateConfigurableEndpointAfterLocalLogout(
      endpoint.origin,
    );
  }

  void close({bool force = false}) {
    _probe.close(force: force);
  }
}

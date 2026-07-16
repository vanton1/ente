import "dart:convert";
import "dart:io";

import "package:flutter_test/flutter_test.dart";

import "../../scripts/prepare_self_hosted_android_release.dart";

void main() {
  test("parses the required Android package metadata", () {
    const output = """
package: name='me.vanton.ente.photos.selfhosted' versionCode='2158' versionName='1.3.59' platformBuildVersionName='16' platformBuildVersionCode='36' compileSdkVersion='36' compileSdkVersionCodename='16'
minSdkVersion:'26'
targetSdkVersion:'36'
native-code: 'arm64-v8a' 'armeabi-v7a'
""";

    final metadata = parseAaptBadging(output);

    expect(metadata.packageName, expectedPackageName);
    expect(metadata.version.name, "1.3.59");
    expect(metadata.version.code, 2158);
    expect(metadata.minSdk, expectedMinSdk);
    expect(metadata.targetSdk, expectedTargetSdk);
    expect(metadata.compileSdk, expectedCompileSdk);
    expect(metadata.abis, expectedAbis);
  });

  test("rejects incomplete Android package metadata", () {
    expect(
      () => parseAaptBadging("package: name='wrong'"),
      throwsA(isA<ReleasePreparationException>()),
    );
  });

  test("parses the signing certificate and signature schemes", () {
    const output = """
Verifies
Verified using v1 scheme (JAR signing): false
Verified using v2 scheme (APK Signature Scheme v2): true
Verified using v3 scheme (APK Signature Scheme v3): false
Verified using v3.1 scheme (APK Signature Scheme v3.1): false
Verified using v4 scheme (APK Signature Scheme v4): false
Number of signers: 1
Signer #1 certificate SHA-256 digest: 9f0a5f39668e7098d097745931bcb8fc392d50da877cf349a2b20e2db1a4ce69
""";

    final audit = parseApkSignerOutput(output);

    expect(audit.signerCount, 1);
    expect(audit.certificateSha256, expectedSigningCertificateSha256);
    expect(audit.signatureSchemes, <String, bool>{
      "v1": false,
      "v2": true,
      "v3": false,
      "v3.1": false,
      "v4": false,
    });
  });

  test("rejects a signer certificate that is not pinned", () {
    expect(
      () => validateApkSignerAudit(
        const ApkSignerAudit(
          certificateSha256:
              "0000000000000000000000000000000000000000000000000000000000000000",
          signerCount: 1,
          signatureSchemes: <String, bool>{"v2": true},
        ),
      ),
      throwsA(isA<ReleasePreparationException>()),
    );
  });

  test("rejects multiple signers and a missing v2 signature", () {
    expect(
      () => validateApkSignerAudit(
        const ApkSignerAudit(
          certificateSha256: expectedSigningCertificateSha256,
          signerCount: 2,
          signatureSchemes: <String, bool>{"v2": true},
        ),
      ),
      throwsA(isA<ReleasePreparationException>()),
    );
    expect(
      () => validateApkSignerAudit(
        const ApkSignerAudit(
          certificateSha256: expectedSigningCertificateSha256,
          signerCount: 1,
          signatureSchemes: <String, bool>{"v2": false},
        ),
      ),
      throwsA(isA<ReleasePreparationException>()),
    );
  });

  test("normalizes supported GitHub remotes", () {
    expect(
      normalizeGitHubSourceBaseUrl("https://github.com/vanton1/ente.git"),
      "https://github.com/vanton1/ente",
    );
    expect(
      normalizeGitHubSourceBaseUrl("git@github.com:vanton1/ente.git"),
      "https://github.com/vanton1/ente",
    );
    expect(
      normalizeGitHubSourceBaseUrl("ssh://git@github.com/vanton1/ente.git"),
      "https://github.com/vanton1/ente",
    );
  });

  test(
    "rejects source remotes that cannot produce the required source link",
    () {
      expect(
        () => normalizeGitHubSourceBaseUrl("/tmp/local-clone"),
        throwsA(isA<ReleasePreparationException>()),
      );
      expect(
        () => normalizeGitHubSourceBaseUrl(
          "https://user:secret@github.com/vanton1/ente.git",
        ),
        throwsA(isA<ReleasePreparationException>()),
      );
    },
  );

  test("parses and validates the source version", () {
    final version = parsePubspecVersion("name: photos\nversion: 1.3.59+2158\n");

    expect(version.name, "1.3.59");
    expect(version.code, 2158);
  });

  test("canonicalizes HTTPS origins and rejects unsafe endpoints", () {
    expect(
      canonicalizeConfigurableEndpoint("https://Museum.Example/"),
      "https://museum.example",
    );
    expect(
      () => canonicalizeConfigurableEndpoint("http://museum.example"),
      throwsA(
        isA<ReleasePreparationException>().having(
          (error) => error.exitCode,
          "exitCode",
          64,
        ),
      ),
    );
  });

  test("detects only a true debuggable manifest value", () {
    expect(
      manifestIsDebuggable(
        "A: android:debuggable(0x0101000f)=(type 0x12)0xffffffff",
      ),
      isTrue,
    );
    expect(
      manifestIsDebuggable("A: android:debuggable(0x0101000f)=(type 0x12)0x0"),
      isFalse,
    );
    expect(manifestIsDebuggable("E: application"), isFalse);
  });

  test("finds the exact compiled endpoint bytes", () {
    final haystack = utf8.encode(
      "before https://macbook-pro-2.tailcfdac8.ts.net after",
    );

    expect(
      containsBytes(
        haystack,
        utf8.encode("https://macbook-pro-2.tailcfdac8.ts.net"),
      ),
      isTrue,
    );
    expect(
      containsBytes(haystack, utf8.encode("https://wrong.example")),
      isFalse,
    );
  });

  test("writes a read-only manifest pair and refuses overwrite", () async {
    final temporaryDirectory = Directory.systemTemp.createTempSync(
      "ente-release-finalization-test-",
    );
    try {
      final sourceApk = File("${temporaryDirectory.path}/audited-source.apk")
        ..writeAsBytesSync(utf8.encode("audited apk bytes"));
      final outputDirectory = Directory("${temporaryDirectory.path}/prepared")
        ..createSync();
      final sha256 = await sha256File(sourceApk.path);
      final audit = AndroidReleaseAudit(
        packageName: expectedPackageName,
        version: const ReleaseVersion("1.3.59", 2158),
        minSdk: expectedMinSdk,
        targetSdk: expectedTargetSdk,
        compileSdk: expectedCompileSdk,
        abis: expectedAbis,
        debuggable: false,
        signingCertificateSha256: expectedSigningCertificateSha256,
        signatureSchemes: const <String, bool>{"v2": true},
        sha256: sha256,
        sizeBytes: sourceApk.lengthSync(),
      );
      const commit = "0123456789abcdef0123456789abcdef01234567";

      final result = await finalizePreparedRelease(
        buildApkPath: sourceApk.path,
        audit: audit,
        outputDirectory: outputDirectory.path,
        canonicalEndpoint: "https://museum.example",
        commit: commit,
        origin: "https://github.com/vanton1/ente.git",
        sourceCommitUrl: "https://github.com/vanton1/ente/commit/$commit",
      );

      final manifest =
          jsonDecode(File(result.manifestPath).readAsStringSync())
              as Map<String, dynamic>;
      expect(
        File(result.apkPath).readAsBytesSync(),
        sourceApk.readAsBytesSync(),
      );
      expect(manifest["schemaVersion"], releaseManifestSchemaVersion);
      expect(manifest["artifact"]["sha256"], sha256);
      expect(manifest["source"]["commit"], commit);
      expect(
        manifest["android"]["compiledDefaultEndpoint"],
        "https://museum.example",
      );
      expect(File(result.apkPath).statSync().mode & 0x1ff, 0x124);
      expect(File(result.manifestPath).statSync().mode & 0x1ff, 0x124);

      await expectLater(
        finalizePreparedRelease(
          buildApkPath: sourceApk.path,
          audit: audit,
          outputDirectory: outputDirectory.path,
          canonicalEndpoint: "https://museum.example",
          commit: commit,
          origin: "https://github.com/vanton1/ente.git",
          sourceCommitUrl: "https://github.com/vanton1/ente/commit/$commit",
        ),
        throwsA(
          isA<ReleasePreparationException>().having(
            (error) => error.exitCode,
            "exitCode",
            73,
          ),
        ),
      );
      expect(File(result.apkPath).existsSync(), isTrue);
      expect(File(result.manifestPath).existsSync(), isTrue);
      expect(await sha256File(result.apkPath), sha256);
    } finally {
      temporaryDirectory.deleteSync(recursive: true);
    }
  });

  final integrationApk = Platform.environment["ENTE_TEST_RELEASE_APK"];
  if (integrationApk != null) {
    test("audits a real signed self-hosted release APK", () async {
      final audit = await auditAndroidReleaseApk(
        apkPath: integrationApk,
        canonicalEndpoint: Platform.environment["ENTE_SELF_HOSTED_ENDPOINT"]!,
        sourceVersion: const ReleaseVersion("1.3.59", 2158),
        tools: ReleaseToolPaths.fromEnvironment(Platform.environment),
      );

      expect(audit.packageName, expectedPackageName);
      expect(audit.signingCertificateSha256, expectedSigningCertificateSha256);
      expect(audit.debuggable, isFalse);
      expect(audit.abis, expectedAbis);
      expect(audit.signatureSchemes["v2"], isTrue);
    });

    test("rejects an APK version that differs from committed source", () async {
      await expectLater(
        auditAndroidReleaseApk(
          apkPath: integrationApk,
          canonicalEndpoint: Platform.environment["ENTE_SELF_HOSTED_ENDPOINT"]!,
          sourceVersion: const ReleaseVersion("1.3.59", 9999),
          tools: ReleaseToolPaths.fromEnvironment(Platform.environment),
        ),
        throwsA(isA<ReleasePreparationException>()),
      );
    });

    test("rejects an APK compiled for another endpoint", () async {
      await expectLater(
        auditAndroidReleaseApk(
          apkPath: integrationApk,
          canonicalEndpoint: "https://wrong.example",
          sourceVersion: const ReleaseVersion("1.3.59", 2158),
          tools: ReleaseToolPaths.fromEnvironment(Platform.environment),
        ),
        throwsA(isA<ReleasePreparationException>()),
      );
    });
  }

  final wrongPackageApk =
      Platform.environment["ENTE_TEST_WRONG_PACKAGE_RELEASE_APK"];
  if (wrongPackageApk != null) {
    test("rejects the legacy self-hosted Android package", () async {
      await expectLater(
        auditAndroidReleaseApk(
          apkPath: wrongPackageApk,
          canonicalEndpoint: Platform.environment["ENTE_SELF_HOSTED_ENDPOINT"]!,
          sourceVersion: const ReleaseVersion("1.3.59", 2158),
          tools: ReleaseToolPaths.fromEnvironment(Platform.environment),
        ),
        throwsA(isA<ReleasePreparationException>()),
      );
    });
  }
}

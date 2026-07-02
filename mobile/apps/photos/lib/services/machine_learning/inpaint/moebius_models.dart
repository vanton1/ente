import "package:logging/logging.dart";
import "package:photos/services/remote_assets_service.dart";
import "package:photos/src/rust/api/inpaint_api.dart"
    show RustInpaintModelPaths;

/// Delivery of the Moebius inpainting ONNX graphs.
///
/// The three graphs are downloaded on first use (gated behind the AI-edit entry
/// point) and cached on device by [RemoteAssetsService]. The Rust pipeline loads
/// them from the returned filesystem paths; nothing is loaded in Dart.
///
/// NOTE: for now these are fp16 graphs hosted on a temporary dev asset host
/// (~0.6 GB total). Once validated they will move to the Ente CDN.
class MoebiusModels {
  static final _logger = Logger("MoebiusModels");

  static const String _base = "https://entedevassets.priem.dev/";

  static const String unetUrl = "${_base}unet_fp16.onnx";
  static const String vaeEncoderUrl = "${_base}vae_encoder_fp16.onnx";
  static const String vaeDecoderUrl = "${_base}vae_decoder_fp16.onnx";

  // SHA-256 of the fp16 graphs.
  static const String _unetSha =
      "f0995182c30d92ef32c54f048b0906c26534d65def9aeffd01521da8280bdb90";
  static const String _vaeEncoderSha =
      "c4a8c399498bea2c5817e1701f5a59e312a5be0a09139157f7934743eecb98e8";
  static const String _vaeDecoderSha =
      "2c51ab793f17a91246ce97c0f553751355b9de9b896051739d72762ab1c9c0fd";

  /// Approximate combined on-disk size, used for the first-run download prompt.
  static const int approxTotalBytes = 459820322 + 101260614 + 70585594;

  /// All three model URLs, useful for filtering [RemoteAssetsService.progressStream].
  static const List<String> urls = [unetUrl, vaeEncoderUrl, vaeDecoderUrl];

  /// True if all three graphs are already cached on device.
  static Future<bool> isDownloaded() async {
    final svc = RemoteAssetsService.instance;
    return await svc.hasAsset(unetUrl) &&
        await svc.hasAsset(vaeEncoderUrl) &&
        await svc.hasAsset(vaeDecoderUrl);
  }

  /// Ensures all three graphs are present (downloading if needed) and returns
  /// their on-device paths for the Rust pipeline.
  static Future<RustInpaintModelPaths> ensureDownloaded() async {
    final svc = RemoteAssetsService.instance;
    _logger.info("Resolving Moebius model paths (downloading if needed)");
    final unet = await svc.getAssetPath(unetUrl, expectedSha256: _unetSha);
    final vaeEncoder = await svc.getAssetPath(
      vaeEncoderUrl,
      expectedSha256: _vaeEncoderSha,
    );
    final vaeDecoder = await svc.getAssetPath(
      vaeDecoderUrl,
      expectedSha256: _vaeDecoderSha,
    );
    return RustInpaintModelPaths(
      unet: unet,
      vaeEncoder: vaeEncoder,
      vaeDecoder: vaeDecoder,
    );
  }
}

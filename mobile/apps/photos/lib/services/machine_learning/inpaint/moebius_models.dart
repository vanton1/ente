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
/// NOTE: for now these are the upstream fp32 graphs hosted on HuggingFace
/// (~1.24 GB total). Once validated they will move to the Ente CDN.
class MoebiusModels {
  static final _logger = Logger("MoebiusModels");

  static const String _base =
      "https://huggingface.co/simonw/Moebius-ONNX/resolve/main/";

  static const String unetUrl = "${_base}unet.onnx";
  static const String vaeEncoderUrl = "${_base}vae_encoder.onnx";
  static const String vaeDecoderUrl = "${_base}vae_decoder.onnx";

  // SHA-256 of the published fp32 graphs (HuggingFace LFS oids).
  static const String _unetSha =
      "e3f90f52f72378339b990459fadb29a68d3c7b5c6851545ba42774f489160b08";
  static const String _vaeEncoderSha =
      "b8b81d41e757222a0707665ba9d826703987855e5bed056036b90b988968042f";
  static const String _vaeDecoderSha =
      "d90ef0b7f6c8c8b7234459c8b449d70be0033bf1576c842e8b9991baf3934280";

  /// Approximate combined on-disk size, used for the first-run download prompt.
  static const int approxTotalBytes = 906698976 + 198078671 + 136757093;

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

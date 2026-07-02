use ente_photos::ml::{inpaint as shared_inpaint, runtime::ExecutionProviderPolicy};

use super::ml_indexing_api::{RustExecutionProviderPolicy, RustMlError};

/// Filesystem paths to the three Moebius ONNX graphs.
#[derive(Clone, Debug)]
pub struct RustInpaintModelPaths {
    pub unet: String,
    pub vae_encoder: String,
    pub vae_decoder: String,
}

/// Request for a single on-device object-removal ("AI edit") run.
#[derive(Clone, Debug)]
pub struct InpaintImageRequest {
    /// Source image on disk.
    pub image_path: String,
    /// Mask on disk: region to erase is non-black (white strokes on black).
    pub mask_path: String,
    pub model_paths: RustInpaintModelPaths,
    pub provider_policy: RustExecutionProviderPolicy,
    /// Scheduler steps (0 => default of 20). 19 effective after the strength drop.
    pub num_steps: u32,
    /// Classifier-free guidance scale (<= 0 => default of 2.0).
    pub guidance: f32,
    /// Seed for the initial noise (deterministic within this implementation).
    pub seed: u64,
}

/// Runs the full Moebius inpainting pipeline in Rust and returns the resulting
/// full-resolution JPEG bytes.
pub fn inpaint_image_rust(req: InpaintImageRequest) -> Result<Vec<u8>, RustMlError> {
    let shared_req = shared_inpaint::InpaintRequest {
        image_path: req.image_path,
        mask_path: req.mask_path,
        model_paths: shared_inpaint::InpaintModelPaths {
            unet: req.model_paths.unet,
            vae_encoder: req.model_paths.vae_encoder,
            vae_decoder: req.model_paths.vae_decoder,
        },
        provider_policy: to_provider_policy(&req.provider_policy),
        num_steps: req.num_steps as usize,
        guidance: req.guidance,
        seed: req.seed,
    };

    shared_inpaint::inpaint(shared_req).map_err(RustMlError::from)
}

fn to_provider_policy(policy: &RustExecutionProviderPolicy) -> ExecutionProviderPolicy {
    ExecutionProviderPolicy {
        prefer_coreml: policy.prefer_coreml,
        prefer_nnapi: policy.prefer_nnapi,
        prefer_xnnpack: policy.prefer_xnnpack,
        allow_cpu_fallback: policy.allow_cpu_fallback,
    }
}

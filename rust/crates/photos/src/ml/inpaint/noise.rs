//! Deterministic Gaussian noise generation for the inpainting pipeline.
//!
//! We avoid pulling in an RNG dependency (the workspace has none) and instead
//! use splitmix64 + Box-Muller. The stream is reproducible for a given seed
//! within this implementation; it does not attempt to match NumPy's MT19937, so
//! seeds are only comparable across Rust runs, not against the Python reference.

/// Small, fast, deterministic Gaussian sampler.
pub struct GaussianRng {
    state: u64,
}

impl GaussianRng {
    pub fn new(seed: u64) -> Self {
        // Avoid a zero state degenerating the stream.
        Self {
            state: seed ^ 0x9E37_79B9_7F4A_7C15,
        }
    }

    #[inline]
    fn next_u64(&mut self) -> u64 {
        // splitmix64
        self.state = self.state.wrapping_add(0x9E37_79B9_7F4A_7C15);
        let mut z = self.state;
        z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
        z ^ (z >> 31)
    }

    /// Uniform in (0, 1).
    #[inline]
    fn next_f64(&mut self) -> f64 {
        // 53-bit mantissa, shifted off zero to keep ln() finite in Box-Muller.
        ((self.next_u64() >> 11) as f64 + 0.5) * (1.0 / (1u64 << 53) as f64)
    }

    /// Standard normal sample, N(0, 1).
    #[inline]
    pub fn next_normal(&mut self) -> f32 {
        let u1 = self.next_f64();
        let u2 = self.next_f64();
        let r = (-2.0 * u1.ln()).sqrt();
        (r * (2.0 * std::f64::consts::PI * u2).cos()) as f32
    }

    /// Fill a buffer with standard-normal samples.
    pub fn fill_normal(&mut self, out: &mut [f32]) {
        for value in out.iter_mut() {
            *value = self.next_normal();
        }
    }
}

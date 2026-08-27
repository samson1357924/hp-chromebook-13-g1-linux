# Graphics CDCLK Fix (QHD+ FIFO Underrun)

Root cause is documented in [README](../../README.md) section 3.

- Panel requires 361.31MHz pixel clock, default CDCLK 337.5MHz insufficient -> FIFO underrun
- Fix: `i915.enable_psr=0 i915.enable_fbc=0 i915.enable_dc=0` raises CDCLK to 450MHz

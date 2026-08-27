<!-- markdownlint-disable MD013 -->

# 顯示 CDCLK 修正 (QHD+ FIFO Underrun)

根本原因請見 [README](https://github.com/samson1357924/hp-chromebook-13-g1-linux/blob/main/README.md) 第 3 節。

- 面板需 361.31MHz pixel clock，預設 CDCLK 337.5MHz 不足 → FIFO underrun
- 解法：`i915.enable_psr=0 i915.enable_fbc=0 i915.enable_dc=0` 將 CDCLK 提升至 450MHz

# RVQ硬件（8级 × 每级256码字）

当前RVQ与硬件编码格式：

- Encoder latent：64维signed INT8；
- RVQ：8级；
- 每级：256个64维码字；
- 码本：signed INT8，每级使用独立Scale；
- Residual：signed INT16；
- 距离：UINT32饱和累加；
- 输出：每级UINT8索引，8级组成64-bit最终码流。

## 码本地址

```text
addr[13:11] = stage             (0~7)
addr[10:3]  = codeword index    (0~255)
addr[2:0]   = dimension group   (0~7，每组8维)
```

```text
address = stage * 2048 + codeword_index * 8 + dimension_group
```

总容量为`8 × 256 × 64 × 1 Byte = 128 KiB`。

## 数据与Scale

每个64-bit码本word保存8个INT8元素。每一级配置一组32-bit multiplier和
6-bit shift，把码本INT8映射到公共INT16 Residual尺度：

```text
aligned_codeword = sat16(
    round_away_from_zero(codebook_int8 * multiplier / 2^shift)
)
```

训练导出应满足：

```text
multiplier / 2^shift ≈ S_codebook_stage / S_residual_common
```

## Latent与最终索引

64维latent分8拍送入，每拍8个INT8，最后一拍同时置位`latent_last`。

```text
result_indices[8*q +: 8] = 第q级获胜码字index
```

只能在`result_valid=1`时读取最终索引。`result_ready=0`期间，valid和数据必须保持稳定。

## 独立仿真

```powershell
powershell -ExecutionPolicy Bypass -File .\RVQ\run_rvq_modelsim.ps1
```

测试覆盖码本装载、8级完整搜索、Scale对齐、INT16残差更新、UINT8索引和输出反压。

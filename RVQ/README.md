# RVQ硬件（32D，9级非均匀码本）

编码数据流：`Encoder 64D -> Projection-In 64x32 -> RVQ 32D -> 64-bit indices`。

- q0：256个32维INT8码字，8-bit index；
- q1~q8：每级128个32维INT8码字，每级7-bit index；
- 距离：平方Euclidean；
- 码本：`(256 + 8*128) * 32 = 40960 Byte = 40 KiB`；
- Projection-In：2048个INT8权重，通过256个64-bit word装载；
- 输出：q0位于`[7:0]`，q1~q8顺序占用后续8个7-bit字段；
- 50 frame/s时payload为`64*50=3.2 kb/s`。

码本紧凑word地址：q0 base=0；qN base=`1024+(N-1)*512`；
地址=`base + index*4 + dimension_group`。

独立RVQ测试：

```powershell
powershell -ExecutionPolicy Bypass -File .\RVQ\run_rvq_modelsim.ps1
```

Encoder集成测试：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run_full_encoder_rvq_modelsim.ps1
```

完整动态通过必须出现`[TB_PASS]`；只有`vlog Errors: 0`不能替代动态数值对拍。

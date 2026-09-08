# S28HS512T simulation model

- Source: https://freemodelfoundry.com/vlog_flash.php
- Retrieved: 2026-08-27
- Part: Infineon/Cypress S28HS512T, 512-Mbit Octal SPI NOR
- Files: `s28hs512t.sv`, `s28hs512t.v`, `s28hs512t.ftmv`
- License: GNU GPL version 2, as stated in the model source header

The model is simulation-only and must not be included in synthesis file lists.
It models the S28HS512T pins and OPI command protocol; it is not protocol-compatible
with the PULP HyperBus transaction controller without a dedicated OPI command layer.

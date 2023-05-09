// Copyright 2021 Thales DIS design services SAS
//
// Licensed under the Solderpad Hardware Licence, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.0
// You may obtain a copy of the License at https://solderpad.org/licenses/
//
// Original Author: Jean-Roch COULON - Thales

// this is needed to propagate the
// configuration in case Ariane is
// instantiated in OpenPiton
`ifdef PITON_ARIANE
  `include "l15.tmp.h"
  `include "define.tmp.h"
`endif

`ifndef CONFIG_L1I_CACHELINE_WIDTH
    `define CONFIG_L1I_CACHELINE_WIDTH 128
`endif

`ifndef CONFIG_L1I_ASSOCIATIVITY
    `define CONFIG_L1I_ASSOCIATIVITY 4
`endif

`ifndef CONFIG_L1I_SIZE
    `define CONFIG_L1I_SIZE 16*1024
`endif

`ifndef CONFIG_L1D_CACHELINE_WIDTH
    `define CONFIG_L1D_CACHELINE_WIDTH 128
`endif

`ifndef CONFIG_L1D_ASSOCIATIVITY
    `define CONFIG_L1D_ASSOCIATIVITY 8
`endif

`ifndef CONFIG_L1D_SIZE
    `define CONFIG_L1D_SIZE 32*1024
`endif

`ifndef L15_THREADID_WIDTH
    `define L15_THREADID_WIDTH 3
`endif

`ifndef CONFIG_L15_ASSOCIATIVITY
    `define CONFIG_L15_ASSOCIATIVITY 4
`endif

`ifndef TLB_CSM_WIDTH
    `define TLB_CSM_WIDTH 33
`endif

package cva6_config_pkg;

    typedef enum logic {
      WB = 0,
      WT = 1
    } cache_type_t ;

    localparam CVA6ConfigXlen = 64;

    localparam CVA6ConfigFpuEn = 1;
    localparam CVA6ConfigF16En = 0;
    localparam CVA6ConfigF16AltEn = 0;
    localparam CVA6ConfigF8En = 0;
    localparam CVA6ConfigFVecEn = 0;

    localparam CVA6ConfigCvxifEn = 0;
    localparam CVA6ConfigCExtEn = 1;
    localparam CVA6ConfigAExtEn = 1;
    localparam CVA6ConfigBExtEn = 0;

    localparam CVA6ConfigAxiIdWidth = 4;
    localparam CVA6ConfigAxiAddrWidth = 64;
    localparam CVA6ConfigAxiDataWidth = 64;
    localparam CVA6ConfigFetchUserEn = 0;
    localparam CVA6ConfigFetchUserWidth = CVA6ConfigXlen;
    localparam CVA6ConfigDataUserEn = 0;
    localparam CVA6ConfigDataUserWidth = CVA6ConfigXlen;

    localparam CVA6ConfigRenameEn = 0;

    localparam CVA6ConfigIcacheByteSize = `CONFIG_L1I_SIZE;
    localparam CVA6ConfigIcacheSetAssoc = `CONFIG_L1I_ASSOCIATIVITY;
    localparam CVA6ConfigIcacheLineWidth = `CONFIG_L1I_CACHELINE_WIDTH;
    localparam CVA6ConfigDcacheByteSize = `CONFIG_L1D_SIZE;
    localparam CVA6ConfigDcacheSetAssoc = `CONFIG_L1D_ASSOCIATIVITY;
    localparam CVA6ConfigDcacheLineWidth = `CONFIG_L1D_CACHELINE_WIDTH;

    localparam CVA6ConfigDcacheIdWidth = 1;
    localparam CVA6ConfigMemTidWidth = `L15_THREADID_WIDTH;

    localparam CVA6ConfigWtDcacheWbufDepth = 8;

    localparam CVA6ConfigL15Associativity = `CONFIG_L15_ASSOCIATIVITY;
    localparam CVA6ConfigL15TLBCSMWidth = `TLB_CSM_WIDTH;

    localparam CVA6ConfigNrCommitPorts = 2;
    localparam CVA6ConfigNrScoreboardEntries = 8;

    localparam CVA6ConfigFPGAEn = 0;

    localparam CVA6ConfigNrLoadPipeRegs = 1;
    localparam CVA6ConfigNrStorePipeRegs = 0;

    localparam CVA6ConfigInstrTlbEntries = 16;
    localparam CVA6ConfigDataTlbEntries = 16;

    localparam CVA6ConfigRASDepth = 2;
    localparam CVA6ConfigBTBEntries = 32;
    localparam CVA6ConfigBHTEntries = 128;

    localparam CVA6ConfigNrPMPEntries = 8;

    localparam CVA6ConfigPerfCounterEn = 1;

    localparam cache_type_t CVA6ConfigDcacheType = WT;

    localparam CVA6ConfigMmuPresent = 1;

    `undef RVFI_PORT

    // Do not modify
    `ifdef RVFI_PORT
       localparam CVA6ConfigRvfiTrace = 1;
    `else
       localparam CVA6ConfigRvfiTrace = 0;
    `endif

endpackage

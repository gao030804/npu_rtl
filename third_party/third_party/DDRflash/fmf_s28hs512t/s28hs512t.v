///////////////////////////////////////////////////////////////////////////////
//  File name : s28hs512t.v
///////////////////////////////////////////////////////////////////////////////
// Copyright (C) 2018-2020 Free Model Foundry; https://www.FreeModelFoundry.com
//
//  This program is free software; you can redistribute it and/or modify
//  it under the terms of the GNU General Public License version 2 as
//  published by the Free Software Foundation.
//
//  MODIFICATION HISTORY :
//
//  version: |   author:  |  mod date: |  changes made:
//    V1.0      B.Barac     18 Apr 16     Inital Release
//    V1.1      M.Dinic     18 Jul 20     Updated according rev *G
//    V1.2      B.Barac     19 Feb 01     Updated according rev *J
//    V1.3      M.Dinic     19 Mar 01     Bug39 fixed Page Program  of 256 Bytes 
//    V1.4      M.Dinic     19 Mar 07     Bug39.2 fixed (ignore upper bits for a
//                                        all commands when given address is
//                                        larger then acrual device max adderss )
//    V1.5      B.Barac     19 Aug 09     Updated according rev *N
//    V1.6      B.Barac     19 Oct 14     Bit-walking bug fixed
//    V1.7      M.Krneta    20 Jun 15     bug50 fixed, RDBSY and WRPGEN bits
//                                        stay '1' if bit walking error occurs
//
///////////////////////////////////////////////////////////////////////////////
//  PART DESCRIPTION:
//
//  Library:    FLASH
//  Technology: FLASH MEMORY
//  Part:       S28HS512T
//
//  Description: 512 Megabit Serial Flash Memory
//
//////////////////////////////////////////////////////////////////////////////
//  Comments :
//      For correct simulation, simulator resolution should be set to 1 ps
//      A device ordering (trim) option determines whether a feature is enabled
//      or not, or provide relevant parameters:
//        -15th character in TimingModel determines if enhanced high
//         performance option is available
//            (0,2) General Market
//
//////////////////////////////////////////////////////////////////////////////
//  Known Bugs:
//
//////////////////////////////////////////////////////////////////////////////

//////////////////////////////////////////////////////////////////////////////
// MODULE DECLARATION                                                       //
//////////////////////////////////////////////////////////////////////////////
`timescale 1 ps/1 ps

module s28hs512t
    (
        // Data Inputs/Outputs
        SI     ,
        SO     ,
        IO7    ,
        IO6    ,
        IO5    ,
        IO4    ,
        IO3    ,
        IO2    ,
        // Controls
        SCK    ,
        CSNeg  ,
        DS     ,
        RESETNeg,
        INTNeg
    );

///////////////////////////////////////////////////////////////////////////////
// Port / Part Pin Declarations
///////////////////////////////////////////////////////////////////////////////

    inout  SI ;
    inout  SO ;
    inout  IO7;
    inout  IO6;
    inout  IO5;
    inout  IO4;
    inout  IO3;
    inout  IO2;

    input  SCK  ;
    input  CSNeg;
    inout  DS   ;
    input  RESETNeg;
    output INTNeg;

    // interconnect path delay signals
    wire   SCK_ipd     ;
    wire   SI_ipd      ;
    wire   SO_ipd      ;
    wire   CSNeg_ipd   ;
    wire   RESETNeg_ipd;
    wire IO7_ipd;
    wire IO6_ipd;
    wire IO5_ipd;
    wire IO4_ipd;
    wire IO3_ipd;
    wire IO2_ipd;
    wire IO1_ipd;
    wire IO0_ipd;

    wire [7:0] Din;
    assign Din = { IO7_ipd,
                   IO6_ipd,
                   IO5_ipd,
                   IO4_ipd,
                   IO3_ipd,
                   IO2_ipd,
                   SO_ipd,
                   SI_ipd};

    wire [7:0] Dout;
    assign Dout = { IO7,
                    IO6,
                    IO5,
                    IO4,
                    IO3,
                    IO2,
                    SO,
                    SI };

    wire IO7_in;
    assign IO7_in = IO7_ipd;
    wire IO6_in;
    assign IO6_in = IO6_ipd;
    wire IO5_in;
    assign IO5_in = IO5_ipd;
    wire IO4_in;
    assign IO4_in = IO4_ipd;
    wire IO3_in;
    assign IO3_in = IO3_ipd;
    wire IO2_in;
    assign IO2_in = IO2_ipd;

    wire SI_in            ;
    assign SI_in = SI_ipd ;

    wire SI_out           ;
    assign SI_out = SI    ;

    wire SO_in            ;
    assign SO_in = SO_ipd ;

    wire SO_out           ;
    assign SO_out = SO    ;

    wire   RESETNeg_in              ;
    //Internal pull-up
    assign RESETNeg_in = (RESETNeg_ipd === 1'bx) ? 1'b1 : RESETNeg_ipd;

    wire   RESETNeg_out             ;
    assign RESETNeg_out = RESETNeg  ;

    // internal delays
    reg RST_in      ;
    reg RST_out     ;
    reg SWRST_in    ;
    reg SWRST_out   ;
    reg ERSSUSP_in  ;
    reg ERSSUSP_out ;
    reg PRGSUSP_in  ;
    reg PRGSUSP_out ;
    reg PPBERASE_in ;
    reg PPBERASE_out;
    reg PASSULCK_in ;
    reg PASSULCK_out;
    reg PASSACC_in  ;
    reg PASSACC_out ;
    reg DPD_in      ;
    reg DPD_entered ;
    reg DPD_out     ;
    reg DPD_POR_in  ;
    reg DPD_POR_out ;
    reg DPDExt_out_start ;
    reg ICRC_ent    ;
    reg [2:0] counter_clock = 3'b000;

    wire   DPDEX_in;       // DPD Exit event
    reg    DPDExt_out  = 0; // DPD Exit event confirmed
    reg    DPDExt      = 0; // DPD Exit event detected

    // event control registers
    reg PRGSUSP_out_event;
    reg ERSSUSP_out_event;

    reg rising_edge_CSNeg_ipd  = 1'b0;
    reg falling_edge_CSNeg_ipd = 1'b0;
    reg rising_edge_SCK_ipd    = 1'b0;
    reg falling_edge_SCK_ipd   = 1'b0;
    reg rising_edge_RESETNeg   = 1'b0;
    reg falling_edge_RESETNeg  = 1'b0;
    reg falling_edge_RST       = 1'b0;
    reg rising_edge_RST_out    = 1'b0;
    reg rising_edge_SWRST_out  = 1'b0;
    reg rising_edge_reseted    = 1'b0;

    reg falling_edge_write     = 1'b0;

    reg rising_edge_PoweredUp  = 1'b0;
    reg rising_edge_PSTART     = 1'b0;
    reg rising_edge_PDONE      = 1'b0;
    reg rising_edge_ESTART     = 1'b0;
    reg rising_edge_EDONE      = 1'b0;
    reg rising_edge_SEERC_START= 1'b0;
    reg rising_edge_SEERC_DONE = 1'b0;
    reg rising_edge_WSTART     = 1'b0;
    reg rising_edge_WDONE      = 1'b0;
    reg rising_edge_CSDONE     = 1'b0;
    reg rising_edge_BCDONE     = 1'b0;
    reg rising_edge_EESSTART   = 1'b0;
    reg rising_edge_EESDONE    = 1'b0;
    reg rising_edge_CRCSTART   = 1'b0;
    reg rising_edge_CRCDONE    = 1'b0;
    reg rising_edge_START_T1_in= 1'b0;
    
    reg rising_edge_DPD_out    = 1'b0;
    reg falling_edge_DPD_POR_out = 1'b0;
    reg rising_edge_DPDEX_out   = 1'b0;
    reg rising_edge_DPDEX_out_start  = 1'b0; 
    
    reg falling_edge_RDYBSY       = 0;

    reg falling_edge_PASSULCK_in = 1'b0;
    reg falling_edge_PPBERASE_in = 1'b0;

    reg RST;
    
    reg read_transaction  = 1;

    reg SOut_zd            = 1'bZ;
    reg SIOut_zd           = 1'bZ;
    reg RESETNegOut_zd     = 1'bZ;
    reg [7:0] Dout_zd = 8'bzzzzzzzz;

    wire  IO7_zd   ;
    wire  IO6_zd   ;
    wire  IO5_zd   ;
    wire  IO4_zd   ;
    wire  IO3_zd   ;
    wire  IO2_zd   ;
    wire  IO1_zd   ;
    wire  IO0_zd   ;

    assign {IO7_zd,
            IO6_zd,
            IO5_zd,
            IO4_zd,
            IO3_zd,
            IO2_zd,
            IO1_zd,
            IO0_zd  } = Dout_zd;

    reg DS_zd      = 1'bz;
    reg INTNeg_zd  = 1'bz;

    // Pull-up recomended for INTNeg
    wire INTNeg_pull_up;
    assign INTNeg_pull_up = (INTNeg_zd === 1'bx) ? 1 : INTNeg_zd;

    parameter UserPreload       = 1;
    parameter mem_file_name     = "none";//"s28hs512t.mem";
    parameter otp_file_name     = "s28hs512tOTP.mem";//"none";

    parameter TimingModel       = "S28HS512TGABHI010_15pF";

    parameter  PartID           = "s28hs512t";
    parameter  MaxData          = 255;
    parameter  MemSize          = 28'h3FFFFFF;
    parameter  SecSize256       = 20'h3FFFF;
    parameter  SecSize4         = 12'hFFF;
    parameter  SecNumUni        = 255;
    parameter  SecNumHyb        = 287;
    parameter  PageNum512       = 20'h1FFFF;
    parameter  PageNum256       = 20'h3FFFF;
    parameter  AddrRANGE        = 28'h3FFFFFF;
    parameter  HiAddrBit        = 25; //for 512
    parameter  OTPSize          = 1023;
    parameter  OTPLoAddr        = 12'h000;
    parameter  OTPHiAddr        = 12'h3FF;
    parameter  SFDPLoAddr       = 16'h0000;
    parameter  SFDPHiAddr       = 16'h0243;
    parameter  SFDPLength       = 16'h0243;
    parameter  IDLength         = 15;
    parameter  BYTE             = 8;
    
    // Parameter page program time, in sector
    reg param_sec_write_time = 0;
    
    
    // ECC data unit check
    reg [31:0] ECC_data = 32'h00000000;
    integer ECC_check = 0;
    integer DEBUG_ADDR = 0;
    integer ECC_ERR = 0;
    integer DEBUG_CHECK = 0;


    //varaibles to resolve architecture used
    reg [24*8-1:0] tmp_timing;//stores copy of TimingModel
    reg [7:0] tmp_char1; //Define General Market or Secure Device
    reg       non_industrial_temp;
    integer found = 1'b0;
    integer dummy_cnt  = 0;
    integer rd_crc = 0;
    
    wire DMYCNT_ODD;
    assign DMYCNT_ODD = dummy_cnt[0];

    // If speedsimulation is needed uncomment following line

       `define SPEEDSIM;

    // powerup
    reg PoweredUp;

    // Memory Array Configuration
    reg BottomBoot = 1'b0;
    reg TopBoot    = 1'b0;
    reg UniformSec = 1'b0;

    // FSM control signals
    reg PDONE     ;
    reg PSTART    ;
    reg PGSUSP    ;
    reg PGRES     ;

    reg RES_TO_SUSP_TIME;

    reg CSDONE    ;
    reg CSSTART   ;

    reg WDONE     ;
    reg WSTART    ;

    reg EESDONE   ;
    reg EESSTART  ;

    reg EDONE     ;
    reg ESTART    ;
    reg ESUSP     ;
    reg ERES      ;

    reg SEERC_START ;
    reg SEERC_DONE  ;

    reg CRCSTART  ;
    reg CRCDONE   ;
    reg CRCSUSP   ;
    reg CRCRES    ;
    

    reg reseted   ;

    //Flag for Password unlock command
    reg PASS_UNLOCKED     = 1'b0;
    reg [63:0] PASS_TEMP  = 64'hFFFFFFFFFFFFFFFF;

    reg INITIAL_CONFIG    = 1'b0;
    reg CHECK_FREQ        = 1'b0;

    reg ZERO_DETECTED     = 1'b0;

    // Flag for Blank Check
    reg NOT_BLANK         = 1'b0;

    // Wrap Length
    integer WrapLength;

    integer CRC_Start_Addr_reg = 0;
    integer CRC_End_Addr_reg   = 0;
    reg [31:0] icrc_in = 32'h00000000;
    reg [31:0] icrc_out = 32'hFFFFFFFF;
    reg icrc_tmp;

    wire ICRC_DATA;
    assign ICRC_DATA = (~((IO7_ipd === 1'bz) || (IO7_ipd === 1'bx)) &&
                        ~((IO6_ipd === 1'bz) || (IO6_ipd === 1'bx)) &&
                        ~((IO5_ipd === 1'bz) || (IO5_ipd === 1'bx)) &&
                        ~((IO4_ipd === 1'bz) || (IO4_ipd === 1'bx)) &&
                        ~((IO3_ipd === 1'bz) || (IO3_ipd === 1'bx)) &&
                        ~((IO2_ipd === 1'bz) || (IO2_ipd === 1'bx)) &&
                        ~((SO_ipd === 1'bz)  || (SO_ipd === 1'bx))  &&
                        ~((SI_ipd === 1'bz)  || (SI_ipd === 1'bx)));

    // Programming buffer
    integer WByte[0:511];
    // SFDP array
    integer SFDP_array[SFDPLoAddr:SFDPHiAddr];
    // OTP Memory Array
    integer OTPMem[OTPLoAddr:OTPHiAddr];
    // Flash Memory Array
    integer Mem[0:AddrRANGE];

    //-----------------------------------------
    //  Registers
    //-----------------------------------------
    reg [7:0] SR1_in   = 8'h00;

    //Nonvolatile Status Register 1
    reg [7:0] STR1N    = 8'h00;

    wire [2:0] LBPROT_NV;

    assign LBPROT_NV = STR1N[4:2];

    //Volatile Status Register 1
    reg [7:0] STR1V    = 8'h00;

    wire       PRGERR;
    wire       ERSERR;
    wire [2:0] LBPROT;
    wire       WRPGEN;
    wire       RDYBSY;

    assign PRGERR = STR1V[6]  ;
    assign ERSERR = STR1V[5]  ;
    assign LBPROT = STR1V[4:2];
    assign WRPGEN = STR1V[1]  ;
    assign RDYBSY = STR1V[0]  ;

    //Volatile Status Register 2
    reg [7:0] STR2V    = 8'h00;

    wire DICRCS;
    wire DICRCA;
    wire SESTAT;
    wire ERASES;
    wire PROGMS;

    assign DICRCS = STR2V[4];
    assign DICRCA = STR2V[3];
    assign SESTAT = STR2V[2];
    assign ERASES = STR2V[1];
    assign PROGMS = STR2V[0];

    //Nonvolatile Configuration Register 1
    reg [7:0] CFR1_in   = 8'h00;

    reg [7:0] CFR1N    = 8'h00;

    wire   SP4KBS_NV;
    wire   TBPROT_NV;
    wire   PLPROT_O;
//     wire   BPNV_O;
    wire   TB4KBS_NV;

    assign SP4KBS_NV = CFR1N[6];
    assign TBPROT_NV = CFR1N[5];
    assign PLPROT_O  = CFR1N[4];
//     assign BPNV_O    = CFR1N[3];
    assign TB4KBS_NV = CFR1N[2];

    //Volatile Configuration Register 1
    reg [7:0] CFR1V    = 8'h00;

    wire   SP4KBS;
    wire   TBPROT;
    wire   PLPROT;
    wire   BPNV;
    wire   TB4KBS;
    wire   TLPROT;

    assign SP4KBS = CFR1V[6];
    assign TBPROT = CFR1V[5];
    assign PLPROT = CFR1V[4];
    assign BPNV   = CFR1V[3];
    assign TB4KBS = CFR1V[2];
    assign TLPROT = CFR1V[0];
    

    //Nonvolatile Configuration Register 2
    reg [7:0] CFR2N    = 8'h08;

    //Volatile Configuration Register 2
    reg [7:0] CFR2V    = 8'h08;

    //Nonvolatile Configuration Register 3
    reg [7:0] CFR3N    = 8'h00;

    //Volatile Configuration Register 3
    reg [7:0] CFR3V    = 8'h00;
    
    wire   UNHYSA;

    assign UNHYSA = CFR3V[3];

    //Nonvolatile Configuration Register 4
    reg [7:0] CFR4N    = 8'hA8;

    //Volatile Configuration Register 4
    reg [7:0] CFR4V    = 8'hA8;
    
    assign DPDPOR = CFR4V[2];

    //Nonvolatile Configuration Register 5
    reg [7:0] CFR5N    =  8'h40;

    //Volatile Configuration Register 5
    reg [7:0] CFR5V    = 8'h40;

//     wire   DSOSDR;
//     wire   PDSSDR;
    wire   SDRDDR;
    wire   OPI_IT;

//     assign DSOSDR = CFR5V[7];
//     assign PDSSDR = CFR5V[6];
    assign SDRDDR = CFR5V[1];
    assign OPI_IT = CFR5V[0];

    // ASP Register
    reg[15:0] ASPO    = 16'hFFFF;
    reg[15:0] ASPO_in = 16'hFFFF;

    wire    ASPRDP;
    wire    ASPDYB;
    wire    ASPPPB;
    wire    ASPPWD;
    wire    ASPPER;
    wire    ASPPRM;
    assign  ASPRDP = ASPO[5];
    assign  ASPDYB = ASPO[4];
    assign  ASPPPB = ASPO[3];
    assign  ASPPWD = ASPO[2];
    assign  ASPPER = ASPO[1];
    assign  ASPPRM = ASPO[0];

    // Password register
    reg[63:0] PWDO    = 64'hFFFFFFFFFFFFFFFF;
    reg[63:0] PWDO_in = 64'hFFFFFFFFFFFFFFFF;

    // PPB Lock Register
    reg[7:0] PPLV     = 8'h01;
    reg[7:0] PPLV_in  = 8'h01;

    wire   PPBLCK;
    assign PPBLCK = PPLV[0];

    // PPB Access Register
    reg[7:0] PPAV             = 8'hFF;
    reg[7:0] PPAV_in          = 8'hFF;

    reg[SecNumHyb:0] PPB_bits  = {288{1'b1}};

    // DYB Access Register
    reg[7:0] DYAV             = 8'hFF;
    reg[7:0] DYAV_in          = 8'hFF;

    reg[SecNumHyb:0] DYB_bits  = {288{1'b1}};
    // AutoBoot Register
    reg[31:0] ATBN    = 32'h00000000;
    reg[31:0] ATBN_in = 32'h00000000;

    wire   ATBTEN;
    assign ATBTEN = ATBN[0];

    // Pointer Address Registers
    reg[15:0] EFX0O    = 16'h0000;
    reg[15:0] EFX0O_in = 16'h0000;
    reg[15:0] EFX1O    = 16'h0000;
    reg[15:0] EFX1O_in = 16'h0000;
    reg[15:0] EFX2O    = 16'h0000;
    reg[15:0] EFX2O_in = 16'h0000;
    reg[15:0] EFX3O    = 16'h0000;
    reg[15:0] EFX3O_in = 16'h0000;
    reg[15:0] EFX4O    = 16'h0000;
    reg[15:0] EFX4O_in = 16'h0000;
    // Address Trap Register
    reg[31:0] EATV     = 32'h00000000;
    reg[31:0] EATV_in  = 32'h00000000;
    // CRC Register
    reg[31:0] DCRV     = 32'h00000000;
    reg[31:0] DCRV_in  = 32'h00000000;
    // ICRC Registers
    reg[31:0] ICRV     = 32'hFFFFFFFF;
    reg[31:0] ICRV_in  = 32'hFFFFFFFF;
    reg[7:0]  ICEV     = 8'h00;

    wire   ITCRCE;
    assign ITCRCE = ICEV[0];

    // Sector Erase Count Register
    reg[23:0] SECV     = 24'h000000;
    reg [23:0] SECV_in [SecNumHyb:0];

    // For multi-pass programming
    reg   MPASSREG [SecNumHyb:0];

    // Manufacturer and Device ID Register
    reg[8*(IDLength+1)-1:0] MDID_reg = 128'hFFFFFFFFFFFFFFFFFFFF90030F1A5B34;
    // Unique ID Register
    reg[63:0] UID_reg  = 64'h0000000000000000;

    reg [7:0] WRAR_reg_in = 8'h00;
    reg [7:0] RDAR_reg    = 8'h00;

    // ECC Register
    reg[7:0] ESCV      = 8'h00;
    // Error Detection Counter Register
    reg[15:0] ECTV     = 16'h0000;

    reg[SecNumHyb:0] ERS_nosucc  = {288{1'b0}};

    // Interrupt Configuration register
    reg [7:0] INCV = 8'hFF;
    // Interrupt Status register
    reg [7:0] INSV = 8'hFF;

    //The Lock Protection Registers for OTP Memory space
    reg[7:0] LOCK_BYTE1;
    reg[7:0] LOCK_BYTE2;
    reg[7:0] LOCK_BYTE3;
    reg[7:0] LOCK_BYTE4;
    
    reg READ_PROTECT   = 0;
    reg [7:0] FIDR_reg = 16'hFF;

    reg write;
    reg cfg_write;
    reg read_out;
    reg dual          = 1'b0;
    reg rd_fast       = 1'b1;
    reg rd_slow       = 1'b0;
    reg ddr           = 1'b0;
    reg any_read      = 1'b0;

    reg DOUBLE        = 1'b0; //Double Data Rate (DDR) flag
    reg prog_erase    = 1'b0;
    
    reg DATA_STROBE   = 1'b0;
    reg DS_OPI   = 1'b1;
    

    reg change_TBPARM = 0;

    reg change_BP     = 0;
    reg[2:0] BP_bits  = 3'b0;

    reg     change_PageSize = 0;
    integer PageSize = 255;
    integer PageNum  = PageNum256;

    integer ASP_ProtSE = 0;
    integer Sec_ProtSE = 0;

    integer RESET_EN = 0; //Reset Enable Flag

    reg     change_addr;
    integer Address = 0;
    integer SectorSuspend = 0;
    integer SectorErased = 0;

    reg     bc_done ;

    reg oe   = 1'b0;
    reg oe_z = 1'b0;

    reg sSTART_T1 = 1'b0;
    reg START_T1_in = 1'b0;

    integer start_delay;
    reg start_autoboot;
    integer ABSD;

    integer Byte_number = 0;

    // Sector is protect if Sec_Prot(SecNum) = '1'
    reg [SecNumHyb:0] Sec_Prot  = 288'b0;

    reg [8*(SFDPLength+1)-1:0] SFDP_array_tmp ;
    reg [7:0]                  SFDP_tmp;

    // timing check violation
    reg Viol = 1'b0;

    integer WOTPByte;
    integer AddrLo;
    integer AddrHi;

    reg[7:0]  old_bit, new_bit;
    integer old_int, new_int;
    reg[63:0] old_pass;
    reg[63:0] new_pass;
    reg[7:0]  old_pass_byte;
    reg[7:0]  new_pass_byte;
    integer wr_cnt;
    integer cnt;

    integer read_cnt  = 0;
    integer icrc_cnt  = 0;
    integer cnt_icrc32  = 0;
    integer read_addr = 0;
    integer byte_cnt  = 1;
    integer pgm_page = 0;

    reg[7:0] data_out;

    time SCK_cycle = 0;
    time prev_SCK;
    time tdevice_SEERC;
    reg  glitch = 1'b0;
    reg  glitch_ds = 1'b0;
    reg  DataDriveOut_SO = 1'bZ ;
    reg  DataDriveOut_SI = 1'bZ ;
    reg [5:0] DataDriveOut_Dout = 6'bZ ;
    reg DataDriveOut_DS  = 1'bZ ;

///////////////////////////////////////////////////////////////////////////////
//Interconnect Path Delay Section
///////////////////////////////////////////////////////////////////////////////
    buf   (IO7_ipd , IO7 );
    buf   (IO6_ipd , IO6 );
    buf   (IO5_ipd , IO5 );
    buf   (IO4_ipd , IO4 );
    buf   (IO3_ipd , IO3 );
    buf   (IO2_ipd , IO2 );
    buf   (SCK_ipd, SCK);
    buf   (SI_ipd, SI);
    buf   (SO_ipd, SO);
    buf   (CSNeg_ipd, CSNeg);
    buf   (RESETNeg_ipd, RESETNeg);

///////////////////////////////////////////////////////////////////////////////
// Propagation  delay Section
///////////////////////////////////////////////////////////////////////////////
    nmos   (IO7 ,   IO7_zd  , 1);
    nmos   (IO6 ,   IO6_zd  , 1);
    nmos   (IO5 ,   IO5_zd  , 1);
    nmos   (IO4 ,   IO4_zd  , 1);
    nmos   (IO3 ,   IO3_zd  , 1);
    nmos   (IO2 ,   IO2_zd  , 1);
    nmos   (SO  ,   IO1_zd  , 1);
    nmos   (SI  ,   IO0_zd  , 1);
    nmos   (SI,       SIOut_zd       , 1);
    nmos   (SO,       SOut_zd        , 1);
    nmos   (DS, DS_zd, 1);
    nmos   (INTNeg  ,   INTNeg_pull_up   , 1);

    // Needed for TimingChecks
    // VHDL CheckEnable Equivalent

    //Single Data Rate Operations
    wire sdro;
    assign sdro = PoweredUp && ~DOUBLE;
    wire sdro_io1;
    assign sdro_io1 = PoweredUp && ~DOUBLE && ~dual;

    //Dual Data Rate Operations
    wire ddro;
    assign ddro = PoweredUp && ddr;

    wire ddro_io1;
    assign ddro_io1 = PoweredUp && DOUBLE && ~dual;

    wire rd ;
    wire fast_rd ;
    wire ddrd ;
    wire oddr ;
    wire osdr ;

    assign fast_rd = rd_fast;
    assign rd      = rd_slow;
    assign ddrd    = ddr;
    assign oddr    = SDRDDR & OPI_IT;
    assign osdr    = ~SDRDDR & OPI_IT;
    
    // IF F>50MHz F51M = 1
    reg freq51;
    wire F51M;
    assign F51M = freq51;

    wire prg_ers;
    assign prg_ers = prog_erase;

    wire datain;
    assign datain = ~OPI_IT & (SOut_zd === 1'bz);

    wire odatain;
    assign odatain = OPI_IT & ~SDRDDR & (SOut_zd === 1'bz);

    wire odatain_ddr;
    assign odatain_ddr = OPI_IT & SDRDDR & (SOut_zd === 1'bz);
    
     // SPI and F > 50MHz 4ns
    wire NegOPI_F51M;
    assign NegOPI_F51M  = ~OPI_IT && F51M ; 
    
    // SPI and F <= 50MHz 5ns
    wire NegOPI_NegF51M;
    assign NegOPI_NegF51M  = ~OPI_IT && ~F51M ;
    
    reg mode3;
    always @(CSNeg or SDRDDR or OPI_IT)
    begin
        if ((falling_edge_CSNeg_ipd || rising_edge_CSNeg_ipd) && !(SDRDDR & OPI_IT) && SCK)
            mode3 = 1'b1;
        else if ((falling_edge_CSNeg_ipd || rising_edge_CSNeg_ipd) && (!SCK || (SDRDDR & OPI_IT)))
            mode3 = 1'b0;
    end
    wire mode3sdr;
    wire mode3spi;
    assign mode3sdr = mode3 & OPI_IT;
    assign mode3spi = mode3 & ~OPI_IT;
    

specify
        // tipd delays: interconnect path delays , mapped to input port delays.
        // In Verilog is not necessary to declare any tipd_ delay variables,
        // they can be taken from SDF file
        // With all the other delays real delays would be taken from SDF file

    // tpd delays
    specparam        tpd_SCK_SO_spi              = 1;   // tV
    specparam        tpd_SCK_SO_sdr              = 1;   // tV
    specparam        tpd_CSNeg_SO            = 1;   // tDIS
    specparam        tpd_SCK_DS              = 1;   // tV DS
    specparam        tpd_CSNeg_DS            = 1;   //tDSV,tDSZ

    //tsetup values: setup times
    specparam        tsetup_CSNeg_SCK_NegF51 = 1;   // tCSS edge /
    specparam        tsetup_CSNeg_SCK_F51    = 1;   // tCSS edge /
    specparam        tsetup_CSNeg_SCK_osdr   = 1;   // tCSS edge /
    specparam        tsetup_CSNeg_SCK_oddr   = 1;   // tCSS edge /

    specparam        tsetup_SI_SCK_spiF51       = 1;   // tSU  edge /
    specparam        tsetup_SI_SCK_spiNegF51    = 1;   // tSU  edge /
    specparam        tsetup_SI_SCK_osdr      = 1;   // tSU  edge /
    specparam        tsetup_SI_SCK_oddr      = 1;   // tSU
    specparam        tsetup_RESETNeg_CSNeg   = 1;   // tRS  edge \

    //thold values: hold times
    specparam        thold_CSNeg_SCK_mode0   = 1;  //tCSH3 edge /
    specparam        thold_CSNeg_SCK_mode3sdr   = 1;  //tCSH3 edge /
    specparam        thold_CSNeg_SCK_mode3spi   = 1;  //tCSH3 edge /
    specparam        thold_CSNeg_SCK_sdr     = 1;   // tCSH edge /
    specparam        thold_CSNeg_SCK_ddr     = 1;   // tCSH edge /
    specparam        thold_SI_SCK_sdr        = 1;   // tHD  edge /
    specparam        thold_SI_SCK_ddr        = 1;   // tHD
    specparam        thold_SI_SCK_spiF51        = 1;   // tHD
    specparam        thold_SI_SCK_spiNegF51        = 1;   // tHD
    specparam        thold_SI_SCK_osdr       = 1;   // tHD  edge /
    specparam        thold_SI_SCK_oddr       = 1;   // tHD
    specparam        thold_CSNeg_RESETNeg    = 1;   // tRH  edge /

    // tpw values: pulse width
    specparam        tpw_SCK_normal_rd       = 1;
    specparam        tpw_SCK_fast_rd         = 1;
    specparam        tpw_SCK_ddr_rd          = 1;
    specparam        tpw_CSNeg_posedge       = 1;   // tCS
    specparam        tpw_CSNeg_wip_posedge   = 1;   // tCS
    specparam        tpw_CSNeg_prg_ers_posedge = 1; // tCS
    specparam        tpw_RESETNeg_negedge    = 1;   // tRP
    specparam        tpw_RESETNeg_posedge    = 1;   // tRS

    // tperiod min (calculated as 1/max freq)
    specparam        tperiod_SCK_normal_rd   = 1;   // 50 MHz
    specparam        tperiod_SCK_fast_rd     = 1;   //166 MHz
    specparam        tperiod_SCK_ddr_rd      = 1;   //100 MHz

    `ifdef SPEEDSIM
        // WRR Cycle Time
        specparam        tdevice_WRR               = 357.5e6;//tW = 357.5us
        // Page Program Operation 4KB/256B
        specparam        tdevice_PP_4_256          = 217.5e6; //tPP = 217.5us
        // Page Program Operation 4KB/512B
        specparam        tdevice_PP_4_512          = 217.5e6; //tPP = 217.5us
         // Page Program Operation 256KB/256B
        specparam        tdevice_PP_256_256        = 170e6; //tPP = 170us
        // Page Program Operation 256KB/512B
        specparam        tdevice_PP_256_512        = 170e6; //tPP = 170us
        
        // Sector Erase Operation
        specparam        tdevice_SE4               = 3350e6;//tSE = 3350us
        // Sector Erase Operation
        specparam        tdevice_SE256             = 26.77e9; //tSE = 26.77ms
        // Sector Erase Count register max time
        specparam        tdevice_SEERC_max         = 63e6; //tSEC = 63 us
        // Sector Erase Count register typ time
        specparam        tdevice_SEERC_typ         = 55e6; //tSEC = 55 us
        // Sector Erase Count register mic time
        specparam        tdevice_SEERC_min         = 55e6; //tSEC = 55 us
        // Bulk Erase Operation
        specparam        tdevice_BE                = 696e9;//tBE = 696ms
        // Evaluate Erase Status Time
        specparam        tdevice_EES               = 5.1e6; //tEES = 5.1us
        // Suspend Latency
        specparam        tdevice_SUSP              = 4e6;  //tSL = 4us
        // Resume to next Suspend Time
        specparam        tdevice_RS                = 10e6; //tRS = 10 us
        // RESET# Low to CS# Low
        specparam        tdevice_RPH               = 500e6; //tRPH = 500 us
        // internal device reset form soft reset
        specparam        tdevice_SR               = 83e6; //tRPH = 83 us
        // CS# High other transactions
        specparam        tdevice_CS                = 50e3; //tCS = 50 ns
        // CS# High Read
        specparam        tdevice_CSR               = 10e3; //tCS = 10 ns
        // VDD (min) to CS# Low
        specparam        tdevice_PU                = 500e6;//tPU = 500us
        // CRC setup time
        specparam        tdevice_CRCSETUP          = 17e6;//tCRCSETUP = 17us
        // CRC suspend latency
        specparam        tdevice_CRCSL             = 64e6;//tCRCSL = 64us
        // CRC Resume to next suspend
        specparam        tdevice_CRCRL             = 100e6;//tCRCRL = 100us
        // ICRC suspend time
        specparam        tdevice_PS                = 15e6;//tCRCRL = 15us
        // Password Unlock to Password Unlock Time
        specparam        tdevice_PASSACC           = 100e6;// 100us
        // CS# High to Power Down Mode - Time to Enter DPD mode
        specparam        tdevice_ENTDPD            = 3e6;     // 3 us
        // Time to Exit DPD mode
        specparam        tdevice_EXTDPD            = 430e6;   // 430 us
        // CS# pulse width to exit DPD mode
        specparam        tdevice_CSDPD             = 20e3;    // 0.02us - minimum
        // Blank Check (256KB Sector) time 13 ms (typical, max is 17 ms)
        specparam        tdevice_BC                = 17e9;
    `else
        // WRR Cycle Time
        specparam        tdevice_WRR               = 357.5e9; //tW = 357.5ms
        // Page Program Operation 4KB/256B
        specparam        tdevice_PP_4_256          = 2175e6; //tPP = 2175us
        // Page Program Operation 4KB/512B
        specparam        tdevice_PP_4_512          = 2175e6; //tPP = 2175us
         // Page Program Operation 256KB/256B
        specparam        tdevice_PP_256_256        = 1700e6; //tPP = 1700us
        // Page Program Operation 256KB/512B
        specparam        tdevice_PP_256_512        = 1700e6; //tPP = 1700us
        // Sector Erase Operation
        specparam        tdevice_SE4               = 335e9; //tSE = 335ms
        // Sector Erase Operation
        specparam        tdevice_SE256             = 2677e9;//tSE = 2677ms
        // Sector Erase Count register max time
        specparam        tdevice_SEERC_max         = 63e6; //tSEC = 63 us
        // Sector Erase Count register typ time
        specparam        tdevice_SEERC_typ         = 55e6; //tSEC = 55 us
        // Sector Erase Count register mic time
        specparam        tdevice_SEERC_min         = 55e6; //tSEC = 55 us
        // Bulk Erase Operation
        specparam        tdevice_BE                = 696e12;//tBE = 696s
        // Evaluate Erase Status Time
        specparam        tdevice_EES               = 51e6;//tEES = 51us
        // Suspend Latency
        specparam        tdevice_SUSP              = 40e6; //tSL = 40us
        // Resume to next Suspend Time
        specparam        tdevice_RS                = 100e6;//tRS = 100 us
        // RESET# Low to CS# Low
        specparam        tdevice_RPH               = 500e6; //tRPH = 500 us
        // internal device reset form soft reset
        specparam        tdevice_SR                = 83e6; //tRPH = 83 us
         // CS# High other transactions
        specparam        tdevice_CS                = 50e3; //tCS = 50 ns
        // CS# High Read
        specparam        tdevice_CSR               = 10e3; //tCS = 10 ns
        // VDD (min) to CS# Low
        specparam        tdevice_PU                = 500e6;//tPU = 500us
        // CRC setup time
        specparam        tdevice_CRCSETUP          = 17e6;//tCRCSETUP = 17us
        // CRC suspend latency
        specparam        tdevice_CRCSL             = 64e6;//tCRCSL = 64us
        // CRC Resume to next suspend
        specparam        tdevice_CRCRL             = 100e6;//tCRCRL = 100us
        // ICRC suspend time
        specparam        tdevice_PS                = 15e6;//tCRCRL = 15us
        // Password Unlock to Password Unlock Time
        specparam        tdevice_PASSACC           = 100e6;// 100us
        // CS# High to Power Down Mode
        specparam        tdevice_ENTDPD            = 3e6;     // 3 us
        // Time to Exit DPD mode
        specparam        tdevice_EXTDPD            = 430e6;    // 430 us
        // CS# pulse width to exit DPD mode
        specparam        tdevice_CSDPD             = 20e3;    // 0.02us - minimum
        // Blank Check (256KB Sector) time 13 ms (typical, max is 17 ms)
        specparam        tdevice_BC                = 17e9;
    `endif // SPEEDSIM

///////////////////////////////////////////////////////////////////////////////
// Input Port  Delays  don't require Verilog description
///////////////////////////////////////////////////////////////////////////////
// Path delays                                                               //
///////////////////////////////////////////////////////////////////////////////
    if (~OPI_IT && ~glitch )     (SCK => SO)  = tpd_SCK_SO_spi;
    if (~OPI_IT && ~glitch )     (SCK => SI)  = tpd_SCK_SO_spi;
    if (~OPI_IT && ~glitch )     (SCK => IO2) = tpd_SCK_SO_spi;
    if (~OPI_IT && ~glitch )     (SCK => IO3) = tpd_SCK_SO_spi;
    if (~OPI_IT && ~glitch )     (SCK => IO4) = tpd_SCK_SO_spi;
    if (~OPI_IT && ~glitch )     (SCK => IO5) = tpd_SCK_SO_spi;
    if (~OPI_IT && ~glitch )     (SCK => IO6) = tpd_SCK_SO_spi;
    if (~OPI_IT && ~glitch )     (SCK => IO7) = tpd_SCK_SO_spi;
    
    if (OPI_IT && ~glitch )     (SCK => SO)  = tpd_SCK_SO_sdr;
    if (OPI_IT && ~glitch )     (SCK => SI)  = tpd_SCK_SO_sdr;
    if (OPI_IT && ~glitch )     (SCK => IO2) = tpd_SCK_SO_sdr;
    if (OPI_IT && ~glitch )     (SCK => IO3) = tpd_SCK_SO_sdr;
    if (OPI_IT && ~glitch )     (SCK => IO4) = tpd_SCK_SO_sdr;
    if (OPI_IT && ~glitch )     (SCK => IO5) = tpd_SCK_SO_sdr;
    if (OPI_IT && ~glitch )     (SCK => IO6) = tpd_SCK_SO_sdr;
    if (OPI_IT && ~glitch )     (SCK => IO7) = tpd_SCK_SO_sdr;

    if (~glitch)   (CSNeg => SI)  = tpd_CSNeg_SO;
    if (~glitch)   (CSNeg => SO)  = tpd_CSNeg_SO;
    if (~glitch)   (CSNeg => IO2) = tpd_CSNeg_SO;
    if (~glitch)   (CSNeg => IO3) = tpd_CSNeg_SO;
    if (~glitch)   (CSNeg => IO4) = tpd_CSNeg_SO;
    if (~glitch)   (CSNeg => IO5) = tpd_CSNeg_SO;
    if (~glitch)   (CSNeg => IO6) = tpd_CSNeg_SO;
    if (~glitch)   (CSNeg => IO7) = tpd_CSNeg_SO;
    
    if (OPI_IT && ~glitch )     (SCK => DS)  = tpd_SCK_DS;

    (CSNeg => DS) = tpd_CSNeg_DS;

///////////////////////////////////////////////////////////////////////////////
// Timing Violation                                                          //
///////////////////////////////////////////////////////////////////////////////
    $setup ( CSNeg   &&& NegOPI_NegF51M , posedge SCK ,  tsetup_CSNeg_SCK_NegF51);
    $setup ( CSNeg   &&& NegOPI_F51M     , posedge SCK ,  tsetup_CSNeg_SCK_F51);
    $setup ( CSNeg   &&& osdr        , posedge SCK ,  tsetup_CSNeg_SCK_osdr);
    $setup ( CSNeg   &&& oddr        ,         SCK ,  tsetup_CSNeg_SCK_oddr);

    $setup ( SI     &&& NegOPI_F51M      , posedge SCK   ,  tsetup_SI_SCK_spiF51);
    $setup ( SI     &&& NegOPI_NegF51M   , posedge SCK   ,  tsetup_SI_SCK_spiNegF51);
    $setup ( SI     &&& odatain         , posedge SCK   ,  tsetup_SI_SCK_osdr);
    $setup ( SI     &&& odatain_ddr     ,         SCK   ,  tsetup_SI_SCK_oddr);

    $setup ( RESETNeg, CSNeg                  ,  tsetup_RESETNeg_CSNeg  , Viol);//
    
    $hold (negedge SCK, CSNeg &&& ~mode3, thold_CSNeg_SCK_mode0);
    $hold (posedge SCK, posedge CSNeg &&& mode3sdr, thold_CSNeg_SCK_mode3sdr);
    $hold (posedge SCK, posedge CSNeg &&& mode3spi, thold_CSNeg_SCK_mode3spi);


//     $hold  ( posedge SCK , CSNeg &&& ~ddrd    ,  thold_CSNeg_SCK_sdr);
//     $hold  ( posedge SCK , CSNeg &&& ddrd     ,  thold_CSNeg_SCK_ddr);


    $hold ( posedge SCK, SI  &&& NegOPI_F51M    ,   thold_SI_SCK_spiF51);
    $hold ( posedge SCK, SI  &&& NegOPI_NegF51M ,   thold_SI_SCK_spiNegF51);
    $hold  ( posedge SCK, SI &&& odatain        ,    thold_SI_SCK_osdr);
    $hold  (         SCK, SI &&& odatain_ddr    ,    thold_SI_SCK_oddr);

    $hold  ( posedge RESETNeg, negedge CSNeg  ,  thold_CSNeg_RESETNeg   , Viol);//

    $width ( posedge SCK &&& rd          , tpw_SCK_normal_rd);
    $width ( negedge SCK &&& rd          , tpw_SCK_normal_rd);
    $width ( posedge SCK &&& fast_rd     , tpw_SCK_fast_rd);
    $width ( negedge SCK &&& fast_rd     , tpw_SCK_fast_rd);
    $width ( posedge SCK &&& ddrd        , tpw_SCK_ddr_rd);
    $width ( negedge SCK &&& ddrd        , tpw_SCK_ddr_rd);

    $width ( posedge CSNeg &&& any_read  , tpw_CSNeg_posedge);
    $width ( posedge CSNeg &&& prg_ers   , tpw_CSNeg_prg_ers_posedge);
    $width ( posedge CSNeg &&& RDYBSY       , tpw_CSNeg_wip_posedge);
    $width ( negedge RESETNeg            , tpw_RESETNeg_negedge);
    $width ( posedge RESETNeg            , tpw_RESETNeg_posedge);

    $period ( posedge SCK &&& rd         , tperiod_SCK_normal_rd);
    $period ( posedge SCK &&& fast_rd    , tperiod_SCK_fast_rd);
    $period ( posedge SCK &&& ddrd       , tperiod_SCK_ddr_rd);


endspecify

///////////////////////////////////////////////////////////////////////////////
// Main Behavior Block                                                       //
///////////////////////////////////////////////////////////////////////////////
// FSM states
 parameter IDLE             = 5'd0;
 parameter RESET_STATE      = 5'd1;
 parameter PGERS_ERROR      = 5'd2;
 parameter WRITE_ALL_REG    = 5'd5;
 parameter PAGE_PG          = 5'd6;
 parameter OTP_PG           = 5'd7;
 parameter PG_SUSP          = 5'd8;
 parameter SECTOR_ERS       = 5'd9;
 parameter BULK_ERS         = 5'd10;
 parameter ERS_SUSP         = 5'd11;
 parameter ERS_SUSP_PG      = 5'd12;
 parameter ERS_SUSP_PG_SUSP = 5'd13;
 parameter CRC_Calc         = 5'd14;
 parameter CRC_SUSP         = 5'd15;
 parameter DP_DOWN          = 5'd16;
 parameter PASS_PG          = 5'd17;
 parameter PASS_UNLOCK      = 5'd18;
 parameter PPB_PG           = 5'd19;
 parameter PPB_ERS          = 5'd20;
 parameter ASP_PG           = 5'd22;
 parameter PLB_PG           = 5'd23;
 parameter DYB_PG           = 5'd25;
//  parameter NVDLR_PG         = 5'd26;
 parameter BLANK_CHECK      = 5'd27;
 parameter EVAL_ERS_STAT    = 5'd28;
 parameter SEERC            = 5'd29;
 parameter AUTOBOOT         = 6'd30;
 

 reg [4:0] current_state;
 reg [4:0] next_state;


// Instruction type
 parameter NONE            = 6'd0;
 parameter WRENB_0_0       = 6'd1;
 parameter WRDIS_0_0       = 6'd2;
 parameter WRARG_4_1       = 6'd3;
 parameter CLPEF_0_0       = 6'd4;
 parameter RDARG_4_0       = 6'd5;
 parameter RDSR1           = 6'd6; // RDSR1_0_0 for SPI, RDSR1_4_0 for OCTAL
 parameter RDSR2           = 6'd7; // RDSR2_0_0 for SPI, RDSR2_4_0 for OCTAL
 parameter RDIDN           = 6'd8; // RDIDN_0_0 for SPI, RDIDN_4_0 for OCTAL
 parameter RSFDP           = 6'd9; // RSFDP_3_0 for SPI, RSFDP_4_0 for OCTAL
 parameter RDUID           = 6'd10; // RDUID_0_0 for SPI, RDUID_4_0 for OCTAL
 parameter RDECC_4_0       = 6'd11;
 parameter RDAY1_C_0       = 6'd12;
 parameter RDAY1_4_0       = 6'd13;
 parameter RDAY2_4_0       = 6'd14;
 parameter PRPGE_4_1       = 6'd15;
 parameter ERCHP_0_0       = 6'd16;
 parameter ER256_4_0       = 6'd17;
 parameter ER004_4_0       = 6'd18;
 parameter EVERS_4_0       = 6'd19;
 parameter SPEPD_0_0       = 6'd20;
 parameter RSEPD_0_0       = 6'd21;
 parameter PRSSR_4_1       = 6'd22;
 parameter RDSSR_4_0       = 6'd23;
 parameter RDDYB_4_0       = 6'd24;
 parameter WRDYB_4_1       = 6'd25;
 parameter RDPPB_4_0       = 6'd26;
 parameter PRPPB_4_0       = 6'd27;
 parameter ERPPB_0_0       = 6'd28;
 parameter RDPLB_0_0       = 6'd29; // RDPLB_0_0 for SPI, RDPLB_4_0 for OCTAL
 parameter WRPLB_0_0       = 6'd30;
 parameter SRSTE_0_0       = 6'd31;
 parameter SFRST_0_0       = 6'd32;
 parameter CLECC_0_0       = 6'd33;
 parameter RDCRC_4_0       = 6'd34;
 parameter DICHK_4_1       = 6'd35;
 parameter PWDUL_0_1       = 6'd36;
 parameter ENDPD_0_0       = 6'd37;
 parameter SEERC_4_0       = 6'd38;
 parameter RDPLB_4_0       = 6'd39; // RDPLB_0_0 for SPI, RDPLB_4_0 for OCTAL
 parameter WRARG_C_1       = 6'd40;
 parameter RDAY2_C_0       = 6'd41;
 

// Command Register
 reg [5:0] Instruct;

//Bus cycle state
 parameter STAND_BY        = 3'd0;
 parameter OPCODE_BYTE     = 3'd1;
 parameter ADDRESS_BYTES   = 3'd2;
 parameter DUMMY_BYTES     = 3'd3;
 parameter MODE_BYTE       = 3'd4;
 parameter DATA_BYTES      = 3'd5;

 reg [2:0] bus_cycle_state;

// CS# Signaling Reset states
 parameter SIGRES_IDLE          = 4'd0;
 parameter SIGRES_FIRST_FE      = 4'd1;
 parameter SIGRES_FIRST_RE      = 4'd2;
 parameter SIGRES_SECOND_FE     = 4'd3;
 parameter SIGRES_SECOND_RE     = 4'd4;
 parameter SIGRES_THIRD_FE      = 4'd5;
 parameter SIGRES_THIRD_RE      = 4'd6;
 parameter SIGRES_FOURTH_FE      = 4'd7;
 parameter SIGRES_FOURTH_RE      = 4'd8;
 parameter SIGRES_NOT_A_RESET   = 4'd9;

 reg  [4:0]  sigres_state;

    // CS# Signaling Reset state machine
    always @(CSNeg_ipd or SI_ipd or rising_edge_SCK_ipd       or
              falling_edge_SCK_ipd  or rising_edge_CSNeg_ipd  or
              falling_edge_CSNeg_ipd)
    begin:CSNegSignalingResetStateTran

        case (sigres_state)

        SIGRES_IDLE:
        begin
            // Start check once CSNeg is asserted
            // For first CS# assertion data needs to be 1'b0.
            // ---------------------------------------------
            if ((falling_edge_CSNeg_ipd == 1'b1) && (SI_ipd == 1'b0))
                sigres_state = SIGRES_FIRST_FE;
        end

        SIGRES_FIRST_FE:  // 1st falling edge occured
        begin
            // Data needs to be constant zero during and at the end of
            // memory selection - check if this is the case
            if ((rising_edge_CSNeg_ipd == 1'b1) && (SI_ipd == 1'b0))
                sigres_state = SIGRES_FIRST_RE;
            // SI data cannot toggle during memory selection
            // SCK cannot toggle during memory selection
            else if ((rising_edge_SCK_ipd || falling_edge_SCK_ipd ||
                      (SI_ipd == 1'b1)) && (CSNeg_ipd == 1'b0))
                sigres_state = SIGRES_NOT_A_RESET;
        end

        SIGRES_FIRST_RE:  // 1st rising edge occured
        begin
            // For second CS# assertion data needs to be 1'b1.
            // ---------------------------------------------
            if ((falling_edge_CSNeg_ipd == 1'b1) && (SI_ipd == 1'b1))
                sigres_state = SIGRES_SECOND_FE;
            // SI data cannot toggle during memory selection
            // SCK cannot toggle during memory selection
            else if ((rising_edge_SCK_ipd || falling_edge_SCK_ipd ||
                      (SI_ipd == 1'b0)) && (CSNeg_ipd == 1'b0))
                sigres_state = SIGRES_NOT_A_RESET;
        end

        SIGRES_SECOND_FE:   // 2nd falling edge occured
        begin
            // Data needs to be constant one during and at the end of
            // memory selection - check if this is the case
            if ((rising_edge_CSNeg_ipd == 1'b1) && (SI_ipd == 1'b1))
                sigres_state = SIGRES_SECOND_RE;
            // SI data cannot toggle during memory selection
            // SCK cannot toggle during memory selection
            else if ((rising_edge_SCK_ipd || falling_edge_SCK_ipd ||
                      (SI_ipd == 1'b0)) && (CSNeg_ipd == 1'b0))
                sigres_state = SIGRES_NOT_A_RESET;
        end

        SIGRES_SECOND_RE:   // 2nd rising edge occured
        begin
            // For 3rd CS# assertion data needs to be 1'b0.
            // ---------------------------------------------
            if ((falling_edge_CSNeg_ipd == 1'b1) && (SI_ipd == 1'b0))
                sigres_state = SIGRES_THIRD_FE;
            // SI data cannot toggle during memory selection
            // SCK cannot toggle during memory selection
            else if ((rising_edge_SCK_ipd || falling_edge_SCK_ipd ||
                      (SI_ipd == 1'b1)) && (CSNeg_ipd == 1'b0))
                sigres_state = SIGRES_NOT_A_RESET;
        end

        SIGRES_THIRD_FE:    // 3rd falling edge occured
        begin
            // Data needs to be constant one during and at the end of
            // memory selection - check if this is the case
            if ((rising_edge_CSNeg_ipd == 1'b1) && (SI_ipd == 1'b0))
                sigres_state = SIGRES_THIRD_RE;
            // SI data cannot toggle during memory selection
            // SCK cannot toggle during memory selection
            else if ((rising_edge_SCK_ipd || falling_edge_SCK_ipd ||
                      (SI_ipd == 1'b1)) && (CSNeg_ipd == 1'b0))
                sigres_state = SIGRES_NOT_A_RESET;
        end

        SIGRES_THIRD_RE:   // 3rd rising edge occured
        begin
            // For 4th CS# assertion data needs to be 1'b1.
            // ---------------------------------------------
            if ((falling_edge_CSNeg_ipd == 1'b1) && (SI_ipd == 1'b1))
                sigres_state = SIGRES_FOURTH_FE;
            // SI data cannot toggle during memory selection
            // SCK cannot toggle during memory selection
            else if ((rising_edge_SCK_ipd || falling_edge_SCK_ipd ||
                      (SI_ipd == 1'b0)) && (CSNeg_ipd == 1'b0))
                sigres_state = SIGRES_NOT_A_RESET;
        end
        

        SIGRES_FOURTH_FE:    // 4th falling edge occured
        begin
            // Data needs to be constant one during and at the end of
            // memory selection - check if this is the case
            if ((rising_edge_CSNeg_ipd == 1'b1) && (SI_ipd == 1'b1))
                sigres_state = SIGRES_FOURTH_RE;
            // SI data cannot toggle during memory selection
            // SCK cannot toggle during memory selection
            else if ((rising_edge_SCK_ipd || falling_edge_SCK_ipd ||
                      (SI_ipd == 1'b0)) && (CSNeg_ipd == 1'b0))
                sigres_state = SIGRES_NOT_A_RESET;
        end
        

        SIGRES_FOURTH_RE:    // 4th risig edge occured
        begin
            // Final state - reset memory
                #10 RST = 1'b0;
                #10 RST = 1'b1;
                sigres_state = SIGRES_IDLE;
        end

        SIGRES_NOT_A_RESET:
        begin
            if (CSNeg_ipd == 1'b1)
                sigres_state = SIGRES_IDLE;
        end

        endcase
    end

    //Power Up time;
    initial
    begin
        PoweredUp = 1'b0;
        #tdevice_PU PoweredUp = 1'b1;
    end

    initial
    begin : Init
        integer sec_i;
        // initialize Sector Erase registers, and multi-passing register
        for (sec_i=0; sec_i<=SecNumHyb; sec_i=sec_i+1)
        begin
            SECV_in[sec_i]  = 24'h000000;
            MPASSREG[sec_i]   = 1'b0;
        end

        write       = 1'b0;
        cfg_write   = 1'b0;
        read_out    = 1'b0;
        Address     = 0;
        change_addr = 1'b0;
        RST         = 1'b0;
        RST_in      = 1'b0;
        RST_out     = 1'b1;
        SWRST_in    = 1'b0;
        SWRST_out   = 1'b1;
        PDONE       = 1'b1;
        PSTART      = 1'b0;
        PGSUSP      = 1'b0;
        PGRES       = 1'b0;
        PRGSUSP_in  = 1'b0;
        ERSSUSP_in  = 1'b0;
        PPBERASE_in = 1'b0;
        PASSULCK_in = 1'b0;
        RES_TO_SUSP_TIME = 1'b0;

        EDONE       = 1'b1;
        ESTART      = 1'b0;
        ESUSP       = 1'b0;
        ERES        = 1'b0;

        SEERC_DONE  = 1'b1;
        SEERC_START = 1'b0;

        CRCDONE     = 1'b1;
        CRCSTART    = 1'b0;
        CRCSUSP     = 1'b0;
        CRCRES      = 1'b0;

        WDONE       = 1'b1;
        WSTART      = 1'b0;

        DPD_in      = 1'b0;
        DPD_entered = 1'b0;
        DPD_out     = 1'b1;

        EESDONE     = 1'b1;
        EESSTART    = 1'b0;

        CSDONE      = 1'b1;
        CSSTART     = 1'b0;

        reseted     = 1'b0;

        Instruct        = NONE;
        bus_cycle_state = STAND_BY;
        current_state   = RESET_STATE;
        next_state      = RESET_STATE;
        sigres_state    = SIGRES_IDLE;
    end

    // initialize memory and load preload files if any
    initial
    begin: InitMemory
        integer i;

        for (i=0;i<=AddrRANGE;i=i+1)
        begin
            Mem[i] = MaxData;
        end

        if ((UserPreload) && !(mem_file_name == "none"))
        begin
           // Memory Preload
           //s28hs512t.mem, memory preload file
           //  @aaaaaaa - <aaaaaaa> stands for address
           //  dd       - <dd> is byte to be written at Mem(aaaaaaa++)
           // (aaaaaaa is incremented at every load)
           $readmemh(mem_file_name,Mem);
        end

        for (i=OTPLoAddr;i<=OTPHiAddr;i=i+1)
        begin
            OTPMem[i] = MaxData;
        end

        if (UserPreload && !(otp_file_name == "none"))
        begin
        //s28hs512t_otp memory file
        //   /        - comment
        //   @aaa - <aaa> stands for address
        //   dd  - <dd> is byte to be written at OTPMem(aaa++)
        //   (aaa is incremented at every load)
        //   only first 1-4 columns are loaded. NO empty lines !!!!!!!!!!!!!!!!
           $readmemh(otp_file_name,OTPMem);
        end

        LOCK_BYTE1[7:0] = OTPMem[16];
        LOCK_BYTE2[7:0] = OTPMem[17];
        LOCK_BYTE3[7:0] = OTPMem[18];
        LOCK_BYTE4[7:0] = OTPMem[19];
    end

    // initialize memory and load preload files if any
    initial
    begin: InitTimingModel
    integer i;
    integer j;
        //UNIFORM OR HYBRID arch model is used
        //assumptions:
        //1. TimingModel has format as S28HS512TXXXXXXXX_X_XXpF
        //2. TimingModel does not have more then 24 characters
        tmp_timing = TimingModel;//copy of TimingModel

        i = 23;
        while ((i >= 0) && (found != 1'b1))//search for first non null character
        begin        //i keeps position of first non null character
            j = 7;
            while ((j >= 0) && (found != 1'b1))
            begin
                if (tmp_timing[i*8+j] != 1'd0)
                    found = 1'b1;
                else
                    j = j-1;
            end
            i = i - 1;
        end
        i = i +1;
        if (found)//if non null character is found
        begin
            for (j=0;j<=7;j=j+1)
            begin
            //Security character is 15
                tmp_char1[j] = TimingModel[(i-13)*8+j];
            end
        end
        if (tmp_char1  == "V" || tmp_char1  == "A" ||
            tmp_char1  == "B" || tmp_char1  == "M")
        begin
            non_industrial_temp = 1'b1;
        end
        else if (tmp_char1 == "I")
        begin
            non_industrial_temp = 1'b0;
        end

    end

    //SFDP
    initial
    begin: InitSFDP
    integer i;
    integer j;
    integer k,l,m;
        ///////////////////////////////////////////////////////////////////////
        // SFDP Header
        ///////////////////////////////////////////////////////////////////////
        SFDP_array[16'h0000] = 8'h53;
        SFDP_array[16'h0001] = 8'h46;
        SFDP_array[16'h0002] = 8'h44;
        SFDP_array[16'h0003] = 8'h50;
        SFDP_array[16'h0004] = 8'h08;
        SFDP_array[16'h0005] = 8'h01;
        SFDP_array[16'h0006] = 8'h05;
        SFDP_array[16'h0007] = 8'hFE;
        // 1st Parameter Header
        SFDP_array[16'h0008] = 8'h00;
        SFDP_array[16'h0009] = 8'h00;
        SFDP_array[16'h000A] = 8'h01;
        SFDP_array[16'h000B] = 8'h14;
        SFDP_array[16'h000C] = 8'h00;
        SFDP_array[16'h000D] = 8'h01;
        SFDP_array[16'h000E] = 8'h00;
        SFDP_array[16'h000F] = 8'hFF;
        // 2nd Parameter Header
        SFDP_array[16'h0010] = 8'h84;
        SFDP_array[16'h0011] = 8'h00;
        SFDP_array[16'h0012] = 8'h01;
        SFDP_array[16'h0013] = 8'h02;
        SFDP_array[16'h0014] = 8'h50;
        SFDP_array[16'h0015] = 8'h01;
        SFDP_array[16'h0016] = 8'h00;
        SFDP_array[16'h0017] = 8'hFF;
        // 3rd Parameter Header
        SFDP_array[16'h0018] = 8'h05;
        SFDP_array[16'h0019] = 8'h00;
        SFDP_array[16'h001A] = 8'h01;
        SFDP_array[16'h001B] = 8'h05;
        SFDP_array[16'h001C] = 8'h58;
        SFDP_array[16'h001D] = 8'h01;
        SFDP_array[16'h001E] = 8'h00;
        SFDP_array[16'h001F] = 8'hFF;
        // 4th Parameter Header
        SFDP_array[16'h0020] = 8'h87;
        SFDP_array[16'h0021] = 8'h00;
        SFDP_array[16'h0022] = 8'h01;
        SFDP_array[16'h0023] = 8'h1C;
        SFDP_array[16'h0024] = 8'h6C;
        SFDP_array[16'h0025] = 8'h01;
        SFDP_array[16'h0026] = 8'h00;
        SFDP_array[16'h0027] = 8'hFF;
        // 5th Parameter Header
        SFDP_array[16'h0028] = 8'h0A;
        SFDP_array[16'h0029] = 8'h00;
        SFDP_array[16'h002A] = 8'h01;
        SFDP_array[16'h002B] = 8'h04;
        SFDP_array[16'h002C] = 8'hDC;
        SFDP_array[16'h002D] = 8'h01;
        SFDP_array[16'h002E] = 8'h00;
        SFDP_array[16'h002F] = 8'hFF;
        // 6th Parameter Header
        SFDP_array[16'h0030] = 8'h81;
        SFDP_array[16'h0031] = 8'h00;
        SFDP_array[16'h0032] = 8'h01;
        SFDP_array[16'h0033] = 8'h16;
        SFDP_array[16'h0034] = 8'hEC;
        SFDP_array[16'h0035] = 8'h01;
        SFDP_array[16'h0036] = 8'h00;
        SFDP_array[16'h0037] = 8'hFF;
//         // 7th Parameter Header
//         SFDP_array[16'h0038] = 8'h09;
//         SFDP_array[16'h0039] = 8'h00;
//         SFDP_array[16'h003A] = 8'h01;
//         SFDP_array[16'h003B] = 8'h04;
//         SFDP_array[16'h003C] = 8'h14;
//         SFDP_array[16'h003D] = 8'h02;
//         SFDP_array[16'h003E] = 8'h00;
//         SFDP_array[16'h003F] = 8'hFF;
        // Unused
        for (i=16'h0038;i< 16'h0100;i=i+1)
        begin
           SFDP_array[i]=MaxData;
        end

        ///////////////////////////////////////////////////////////////////////
        // JEDEC Basic Flash Parameters
        ///////////////////////////////////////////////////////////////////////
        // DWORD-1
        SFDP_array[16'h0100] = 8'hE7;
        SFDP_array[16'h0101] = 8'h21;
        SFDP_array[16'h0102] = 8'h8A;
        SFDP_array[16'h0103] = 8'hFF;
        // DWORD-2
        SFDP_array[16'h0104] = 8'hFF;
        SFDP_array[16'h0105] = 8'hFF;
        SFDP_array[16'h0106] = 8'hFF;
        SFDP_array[16'h0107] = 8'h1F; //512
        // DWORD-3
        SFDP_array[16'h0108] = 8'h00;
        SFDP_array[16'h0109] = 8'h00;
        SFDP_array[16'h010A] = 8'h00;
        SFDP_array[16'h010B] = 8'h00;
        // DWORD-4
        SFDP_array[16'h010C] = 8'h00;
        SFDP_array[16'h010D] = 8'h00;
        SFDP_array[16'h010E] = 8'h00;
        SFDP_array[16'h010F] = 8'h00;
        // DWORD-5
        SFDP_array[16'h0110] = 8'hEE;
        SFDP_array[16'h0111] = 8'hFF;
        SFDP_array[16'h0112] = 8'hFF;
        SFDP_array[16'h0113] = 8'hFF;
        // DWORD-6
        SFDP_array[16'h0114] = 8'hFF;
        SFDP_array[16'h0115] = 8'hFF;
        SFDP_array[16'h0116] = 8'h00;
        SFDP_array[16'h0117] = 8'h00;
        // DWORD-7
        SFDP_array[16'h0118] = 8'hFF;
        SFDP_array[16'h0119] = 8'hFF;
        SFDP_array[16'h011A] = 8'h00;
        SFDP_array[16'h011B] = 8'h00;
        // DWORD-8
        SFDP_array[16'h011C] = 8'h0C;
        SFDP_array[16'h011D] = 8'h21;
        SFDP_array[16'h011E] = 8'h00;
        SFDP_array[16'h011F] = 8'hFF;
        // DWORD-9
        SFDP_array[16'h0120] = 8'h00;
        SFDP_array[16'h0121] = 8'hFF;
        SFDP_array[16'h0122] = 8'h12;
        SFDP_array[16'h0123] = 8'hDC;
        // DWORD-10
        SFDP_array[16'h0124] = 8'h23;
        SFDP_array[16'h0125] = 8'hFA;
        SFDP_array[16'h0126] = 8'hFF;
        SFDP_array[16'h0127] = 8'h8B;
        // DWORD-11
        SFDP_array[16'h0128] = 8'h91;
        SFDP_array[16'h0129] = 8'hE8;
        SFDP_array[16'h012A] = 8'hFF;
        SFDP_array[16'h012B] = 8'hE3; //512
        // DWORD-12
        SFDP_array[16'h012C] = 8'hEC;
        SFDP_array[16'h012D] = 8'h03;
        SFDP_array[16'h012E] = 8'h1C;
        SFDP_array[16'h012F] = 8'h60;
        // DWORD-13
        SFDP_array[16'h0130] = 8'h30;
        SFDP_array[16'h0131] = 8'hB0;
        SFDP_array[16'h0132] = 8'h30;
        SFDP_array[16'h0133] = 8'hB0;
        // DWORD-14
        SFDP_array[16'h0134] = 8'hF7;
        SFDP_array[16'h0135] = 8'h66;
        SFDP_array[16'h0136] = 8'h72;
        SFDP_array[16'h0137] = 8'h01;
        // DWORD-15
        SFDP_array[16'h0138] = 8'h00;
        SFDP_array[16'h0139] = 8'h00;
        SFDP_array[16'h013A] = 8'h00;
        SFDP_array[16'h013B] = 8'hFF;
        // DWORD-16
        SFDP_array[16'h013C] = 8'hF9;
        SFDP_array[16'h013D] = 8'h10;
        SFDP_array[16'h013E] = 8'h00;
        SFDP_array[16'h013F] = 8'hA0;
        // DWORD-17
        SFDP_array[16'h0140] = 8'h00;
        SFDP_array[16'h0141] = 8'h00;
        SFDP_array[16'h0142] = 8'h00;
        SFDP_array[16'h0143] = 8'h00;
        // DWORD-18
        SFDP_array[16'h0144] = 8'h00;
        SFDP_array[16'h0145] = 8'h00;
        SFDP_array[16'h0146] = 8'h84;
        SFDP_array[16'h0147] = 8'h02;
        // DWORD-19
        SFDP_array[16'h0148] = 8'h00;
        SFDP_array[16'h0149] = 8'h00;
        SFDP_array[16'h014A] = 8'h00;
        SFDP_array[16'h014B] = 8'h00;
        // DWORD-20
        SFDP_array[16'h014C] = 8'hFF;
        SFDP_array[16'h014D] = 8'hFF;
        SFDP_array[16'h014E] = 8'h8E; //HS
        SFDP_array[16'h014F] = 8'h8E; //HS

        // JEDEC 4-Byte Address Instructions Parameter DWORD-1
        SFDP_array[16'h0150] = 8'h43;
        SFDP_array[16'h0151] = 8'h12;
        SFDP_array[16'h0152] = 8'h0F;
        SFDP_array[16'h0153] = 8'hFE;
        // JEDEC 4-Byte Address Instructions Parameter DWORD-2
        SFDP_array[16'h0154] = 8'h21;
        SFDP_array[16'h0155] = 8'hFF;
        SFDP_array[16'h0156] = 8'hFF;
        SFDP_array[16'h0157] = 8'hDC;

        // JEDEC xSPI Profile 1.0 DWORD-1
        SFDP_array[16'h0158] = 8'h00;
        SFDP_array[16'h0159] = 8'hEE;
        SFDP_array[16'h015A] = 8'h80;
        SFDP_array[16'h015B] = 8'h9B;
        // JEDEC xSPI Profile 1.0 DWORD-2
        SFDP_array[16'h015C] = 8'h00;
        SFDP_array[16'h015D] = 8'h00;
        SFDP_array[16'h015E] = 8'h00;
        SFDP_array[16'h015F] = 8'h00;
        // JEDEC xSPI Profile 1.0 DWORD-3
        SFDP_array[16'h0160] = 8'h00;
        SFDP_array[16'h0161] = 8'hB0;
        SFDP_array[16'h0162] = 8'h8C;
        SFDP_array[16'h0163] = 8'h95;
        // JEDEC xSPI Profile 1.0 DWORD-4
        SFDP_array[16'h0164] = 8'hA8;
        SFDP_array[16'h0165] = 8'h0B;
        SFDP_array[16'h0166] = 8'h00;
        SFDP_array[16'h0167] = 8'h00;

        // JEDEC xSPI Profile 1.0 DWORD-5
        SFDP_array[16'h0168] = 8'h0C;
        SFDP_array[16'h0169] = 8'h55;
        SFDP_array[16'h016A] = 8'h1C;
        SFDP_array[16'h016B] = 8'hA2;

        // Status, Control and Configuration Register Map DWORD-1
        SFDP_array[16'h016C] = 8'h00;
        SFDP_array[16'h016D] = 8'h00;
        SFDP_array[16'h016E] = 8'h80;
        SFDP_array[16'h016F] = 8'h00;
        // Status, Control and Configuration Register Map DWORD-2
        SFDP_array[16'h0170] = 8'h00;
        SFDP_array[16'h0171] = 8'h00;
        SFDP_array[16'h0172] = 8'h00;
        SFDP_array[16'h0173] = 8'h00;
        // Status, Control and Configuration Register Map DWORD-3
        SFDP_array[16'h0174] = 8'hC0;
        SFDP_array[16'h0175] = 8'hCC;
        SFDP_array[16'h0176] = 8'hFF;
        SFDP_array[16'h0177] = 8'hEB;
        // Status, Control and Configuration Register Map DWORD-4
        SFDP_array[16'h0178] = 8'h88;
        SFDP_array[16'h0179] = 8'hFF;
        SFDP_array[16'h017A] = 8'hFF;
        SFDP_array[16'h017B] = 8'hEB;
        // Status, Control and Configuration Register Map DWORD-5
        SFDP_array[16'h017C] = 8'h00;
        SFDP_array[16'h017D] = 8'h65;
        SFDP_array[16'h017E] = 8'h00;
        SFDP_array[16'h017F] = 8'h90;
        // Status, Control and Configuration Register Map DWORD-6
        SFDP_array[16'h0180] = 8'h06;
        SFDP_array[16'h0181] = 8'h65;
        SFDP_array[16'h0182] = 8'h00;
        SFDP_array[16'h0183] = 8'h96;
        // Status, Control and Configuration Register Map DWORD-7
        SFDP_array[16'h0184] = 8'h00;
        SFDP_array[16'h0185] = 8'h65;
        SFDP_array[16'h0186] = 8'h00;
        SFDP_array[16'h0187] = 8'h96;
        // Status, Control and Configuration Register Map DWORD-8
        SFDP_array[16'h0188] = 8'h00;
        SFDP_array[16'h0189] = 8'h65;
        SFDP_array[16'h018A] = 8'h00;
        SFDP_array[16'h018B] = 8'h95;
        // Status, Control and Configuration Register Map DWORD-9
        SFDP_array[16'h018C] = 8'h71;
        SFDP_array[16'h018D] = 8'h65;
        SFDP_array[16'h018E] = 8'h04;
        SFDP_array[16'h018F] = 8'h97;
        // Status, Control and Configuration Register Map DWORD-10
        SFDP_array[16'h0190] = 8'h71;
        SFDP_array[16'h0191] = 8'h65;
        SFDP_array[16'h0192] = 8'h03;
        SFDP_array[16'h0193] = 8'hD0;
        // Status, Control and Configuration Register Map DWORD-11
        SFDP_array[16'h0194] = 8'hA4;
        SFDP_array[16'h0195] = 8'h6B;
        SFDP_array[16'h0196] = 8'hFB;
        SFDP_array[16'h0197] = 8'h02;
        // Status, Control and Configuration Register Map DWORD-12
        SFDP_array[16'h0198] = 8'h90;
        SFDP_array[16'h0199] = 8'hA5;
        SFDP_array[16'h019A] = 8'h79;
        SFDP_array[16'h019B] = 8'hA2;
        // Status, Control and Configuration Register Map DWORD-13
        SFDP_array[16'h019C] = 8'h00;
        SFDP_array[16'h019D] = 8'h40;
        SFDP_array[16'h019E] = 8'h28;
        SFDP_array[16'h019F] = 8'h8E;
        // Status, Control and Configuration Register Map DWORD-14
        SFDP_array[16'h01A0] = 8'h00;
        SFDP_array[16'h01A1] = 8'h00;
        SFDP_array[16'h01A2] = 8'hFF;
        SFDP_array[16'h01A3] = 8'h00;
        // Status, Control and Configuration Register Map DWORD-15
        SFDP_array[16'h01A4] = 8'h00;
        SFDP_array[16'h01A5] = 8'h00;
        SFDP_array[16'h01A6] = 8'hFF;
        SFDP_array[16'h01A7] = 8'h00;
        // Status, Control and Configuration Register Map DWORD-16
        SFDP_array[16'h01A8] = 8'h71;
        SFDP_array[16'h01A9] = 8'h65;
        SFDP_array[16'h01AA] = 8'h06;
        SFDP_array[16'h01AB] = 8'h90;
        // Status, Control and Configuration Register Map DWORD-17
        SFDP_array[16'h01AC] = 8'h71;
        SFDP_array[16'h01AD] = 8'h65;
        SFDP_array[16'h01AE] = 8'h06;
        SFDP_array[16'h01AF] = 8'h90;
        // Status, Control and Configuration Register Map DWORD-18
        SFDP_array[16'h01B0] = 8'h00;
        SFDP_array[16'h01B1] = 8'h00;
        SFDP_array[16'h01B2] = 8'h00;
        SFDP_array[16'h01B3] = 8'h00;
        // Status, Control and Configuration Register Map DWORD-19
        SFDP_array[16'h01B4] = 8'h00;
        SFDP_array[16'h01B5] = 8'h00;
        SFDP_array[16'h01B6] = 8'h00;
        SFDP_array[16'h01B7] = 8'h00;
        // Status, Control and Configuration Register Map DWORD-20
        SFDP_array[16'h01B8] = 8'h71;
        SFDP_array[16'h01B9] = 8'h65;
        SFDP_array[16'h01BA] = 8'h06;
        SFDP_array[16'h01BB] = 8'hD1;
        // Status, Control and Configuration Register Map DWORD-21
        SFDP_array[16'h01BC] = 8'h71;
        SFDP_array[16'h01BD] = 8'h65;
        SFDP_array[16'h01BE] = 8'h06;
        SFDP_array[16'h01BF] = 8'hD1;
        // Status, Control and Configuration Register Map DWORD-22
        SFDP_array[16'h01C0] = 8'h71;
        SFDP_array[16'h01C1] = 8'h65;
        SFDP_array[16'h01C2] = 8'h06;
        SFDP_array[16'h01C3] = 8'h91;
        // Status, Control and Configuration Register Map DWORD-23
        SFDP_array[16'h01C4] = 8'h71;
        SFDP_array[16'h01C5] = 8'h65;
        SFDP_array[16'h01C6] = 8'h06;
        SFDP_array[16'h01C7] = 8'h91;
        // Status, Control and Configuration Register Map DWORD-24
        SFDP_array[16'h01C8] = 8'h00;
        SFDP_array[16'h01C9] = 8'h00;
        SFDP_array[16'h01CA] = 8'hFF;
        SFDP_array[16'h01CB] = 8'h00;
        // Status, Control and Configuration Register Map DWORD-25
        SFDP_array[16'h01CC] = 8'h00;
        SFDP_array[16'h01CD] = 8'h00;
        SFDP_array[16'h01CE] = 8'hFF;
        SFDP_array[16'h01CF] = 8'h00;
        // Status, Control and Configuration Register Map DWORD-26
        SFDP_array[16'h01D0] = 8'h71;
        SFDP_array[16'h01D1] = 8'h65;
        SFDP_array[16'h01D2] = 8'h05;
        SFDP_array[16'h01D3] = 8'hD7;
        // Status, Control and Configuration Register Map DWORD-27
        SFDP_array[16'h01D4] = 8'h71;
        SFDP_array[16'h01D5] = 8'h65;
        SFDP_array[16'h01D6] = 8'h05;
        SFDP_array[16'h01D7] = 8'hD7;
        // Status, Control and Configuration Register Map DWORD-28
        SFDP_array[16'h01D8] = 8'h00;
        SFDP_array[16'h01D9] = 8'h00;
        SFDP_array[16'h01DA] = 8'hEE;
        SFDP_array[16'h01DB] = 8'h72;

        ///////////////////////////////////////////////////////////////////////
        // Command Sequences to Change to Octal DDR mode
        ///////////////////////////////////////////////////////////////////////
        // DWORD-1
        SFDP_array[16'h01DC] = 8'h00;
        SFDP_array[16'h01DD] = 8'h00;
        SFDP_array[16'h01DE] = 8'h06;
        SFDP_array[16'h01DF] = 8'h01;
        // DWORD-2
        SFDP_array[16'h01E0] = 8'h00;
        SFDP_array[16'h01E1] = 8'h00;
        SFDP_array[16'h01E2] = 8'h00;
        SFDP_array[16'h01E3] = 8'h00;
        // DWORD-3
        SFDP_array[16'h01E4] = 8'h80;
        SFDP_array[16'h01E5] = 8'h00;
        SFDP_array[16'h01E6] = 8'h71;
        SFDP_array[16'h01E7] = 8'h06;
        // DWORD-4
        SFDP_array[16'h01E8] = 8'h00;
        SFDP_array[16'h01E9] = 8'h03;
        SFDP_array[16'h01EA] = 8'h06;
        SFDP_array[16'h01EB] = 8'h00;
        
        ///////////////////////////////////////////////////////////////////////
        // Command Sequences to Change to Octal DDR mode
        ///////////////////////////////////////////////////////////////////////
        // Sector Map DWORD-1
        SFDP_array[16'h01EC] = 8'hFC;
        SFDP_array[16'h01ED] = 8'h65;
        SFDP_array[16'h01EE] = 8'hFF;
        SFDP_array[16'h01EF] = 8'h08;
        // Sector Map DWORD-2
        SFDP_array[16'h01F0] = 8'h04;
        SFDP_array[16'h01F1] = 8'h00;
        SFDP_array[16'h01F2] = 8'h80;
        SFDP_array[16'h01F3] = 8'h00;

        // Sector Map DWORD-3
        SFDP_array[16'h01F4] = 8'hFC;
        SFDP_array[16'h01F5] = 8'h65;
        SFDP_array[16'h01F6] = 8'hFF;
        SFDP_array[16'h01F7] = 8'h40;
        // Sector Map DWORD-4
        SFDP_array[16'h01F8] = 8'h02;
        SFDP_array[16'h01F9] = 8'h00;
        SFDP_array[16'h01FA] = 8'h80;
        SFDP_array[16'h01FB] = 8'h00;
        // Sector Map DWORD-5
        SFDP_array[16'h01FC] = 8'hFD;
        SFDP_array[16'h01FD] = 8'h65;
        SFDP_array[16'h01FE] = 8'hFF;
        SFDP_array[16'h01FF] = 8'h04;
        // Sector Map DWORD-6
        SFDP_array[16'h0200] = 8'h02;
        SFDP_array[16'h0201] = 8'h00;
        SFDP_array[16'h0202] = 8'h80;
        SFDP_array[16'h0203] = 8'h00;
        // Sector Map DWORD-7
        SFDP_array[16'h0204] = 8'hFE;
        SFDP_array[16'h0205] = 8'h00;
        SFDP_array[16'h0206] = 8'h02;
        SFDP_array[16'h0207] = 8'hFF;
        // Sector Map DWORD-8
        SFDP_array[16'h0208] = 8'hF1;
        SFDP_array[16'h0209] = 8'hF3;
        SFDP_array[16'h020A] = 8'h01;
        SFDP_array[16'h020B] = 8'h00;
        // Sector Map DWORD-9
        SFDP_array[16'h020C] = 8'hF8;
        SFDP_array[16'h020D] = 8'hF3;
        SFDP_array[16'h020E] = 8'h01;
        SFDP_array[16'h020F] = 8'h00;
        // Sector Map DWORD-10
        SFDP_array[16'h0210] = 8'hF8;
        SFDP_array[16'h0211] = 8'h17;
        SFDP_array[16'h0212] = 8'hE4; //512
        SFDP_array[16'h0213] = 8'h03; //512
        //  Sector Map DWORD-11
        SFDP_array[16'h0214] = 8'hFE;
        SFDP_array[16'h0215] = 8'h03;
        SFDP_array[16'h0216] = 8'h02;
        SFDP_array[16'h0217] = 8'hFF;
        //  Sector Map DWORD-12
        SFDP_array[16'h0218] = 8'hF8;
        SFDP_array[16'h0219] = 8'h17;
        SFDP_array[16'h021A] = 8'hE4; //512
        SFDP_array[16'h021B] = 8'h03; //512
        //  Sector Map DWORD-13
        SFDP_array[16'h021C] = 8'hF8;
        SFDP_array[16'h021D] = 8'hF3;
        SFDP_array[16'h021E] = 8'h01;
        SFDP_array[16'h021F] = 8'h00; 
        //  Sector Map DWORD-14
        SFDP_array[16'h0220] = 8'hF1;
        SFDP_array[16'h0221] = 8'hF3;
        SFDP_array[16'h0222] = 8'h01;
        SFDP_array[16'h0223] = 8'h00;
        //  Sector Map DWORD-15
        SFDP_array[16'h0224] = 8'hFE;
        SFDP_array[16'h0225] = 8'h01;
        SFDP_array[16'h0226] = 8'h04;
        SFDP_array[16'h0227] = 8'hFF;
        //  Sector Map DWORD-16
        SFDP_array[16'h0228] = 8'hF1;
        SFDP_array[16'h0229] = 8'hF3;
        SFDP_array[16'h022A] = 8'h01;
        SFDP_array[16'h022B] = 8'h00;
        //  Sector Map DWORD-17
        SFDP_array[16'h022C] = 8'hF8;
        SFDP_array[16'h022D] = 8'hED;
        SFDP_array[16'h022E] = 8'h02;
        SFDP_array[16'h022F] = 8'h00;
        //  Sector Map DWORD-18
        SFDP_array[16'h0230] = 8'hF8;
        SFDP_array[16'h0231] = 8'h2F;
        SFDP_array[16'h0232] = 8'hE0; //512
        SFDP_array[16'h0233] = 8'h03; //512
        //  Sector Map DWORD-19
        SFDP_array[16'h0234] = 8'hF8;
        SFDP_array[16'h0235] = 8'hED;
        SFDP_array[16'h0236] = 8'h02;
        SFDP_array[16'h0237] = 8'h00;
        //  Sector Map DWORD-20
        SFDP_array[16'h0238] = 8'hF1;
        SFDP_array[16'h0239] = 8'hF3;
        SFDP_array[16'h023A] = 8'h01;
        SFDP_array[16'h023B] = 8'h00;
        //  Sector Map DWORD-21
        SFDP_array[16'h023C] = 8'hFF;
        SFDP_array[16'h023D] = 8'h04;
        SFDP_array[16'h023E] = 8'h00;
        SFDP_array[16'h023F] = 8'hFF;
        //  Sector Map DWORD-22
        SFDP_array[16'h0240] = 8'hF8;
        SFDP_array[16'h0241] = 8'hFF;
        SFDP_array[16'h0242] = 8'hE7; //512
        SFDP_array[16'h0243] = 8'h03; //512

        for(l=SFDPHiAddr;l>=0;l=l-1)
        begin
            SFDP_tmp = SFDP_array[SFDPLength-l];
            for(m=7;m>=0;m=m-1)
            begin
                SFDP_array_tmp[8*l+m] = SFDP_tmp[m];
            end
        end

    end

    always @(next_state or PoweredUp or falling_edge_RST or RST_out or SWRST_out )
    begin: StateTransition1
        if (PoweredUp)
        begin
            if (falling_edge_RST)
            begin
            // no state transition while RESET# low
                current_state = RESET_STATE;
                sigres_state  = SIGRES_IDLE;
                RST_in = 1'b1;
                #1 RST_in = 1'b0;
                reseted   = 1'b0;
            end
            else if (RST_out && SWRST_out)
            begin
                current_state = next_state;
                reseted = 1;
            end
        end
    end

    always @(falling_edge_write)
    begin: StateTransition2
        if (Instruct == SFRST_0_0 && RESET_EN)
        begin
            // no state transition while RESET is in progress
            current_state = RESET_STATE;
            sigres_state  = SIGRES_IDLE;
            SWRST_in = 1'b1;
            #1 SWRST_in = 1'b0;
            reseted   = 1'b0;
            RESET_EN = 0;
        end
    end

    ////////////////////////////////////////////////////////////////////////////
    // Timing control for the Hardware Reset
    ////////////////////////////////////////////////////////////////////////////
    always @(posedge RST_in)
    begin:Threset
        RST_out = 1'b0;
        #(tdevice_RPH -200000) RST_out = 1'b1;
    end

    always @(RESETNeg)
        begin
        RST <= #199000 RESETNeg;
    end

    ////////////////////////////////////////////////////////////////////////////
    // Timing control for the Software Reset
    ////////////////////////////////////////////////////////////////////////////
    always @(posedge SWRST_in)
    begin:Tswreset
        SWRST_out = 1'b0;
        #tdevice_SR SWRST_out = 1'b1;
    end

    always @(negedge CSNeg_ipd)
    begin:CheckCSOnPowerUP
        if (~PoweredUp)
            $display ("Device is selected during Power Up");
    end

    ///////////////////////////////////////////////////////////////////////////
    //// Internal Delays
    ///////////////////////////////////////////////////////////////////////////

    always @(posedge PRGSUSP_in)
    begin:PRGSuspend
        PRGSUSP_out = 1'b0;
        #tdevice_SUSP PRGSUSP_out = 1'b1;
    end

    always @(posedge ERSSUSP_in)
    begin:ERSSuspend
        ERSSUSP_out = 1'b0;
        #tdevice_SUSP ERSSUSP_out = 1'b1;
    end

    always @(posedge PPBERASE_in)
    begin:PPBErs
        PPBERASE_out = 1'b0;
        #tdevice_SE256 PPBERASE_out = 1'b1;
    end

    always @(posedge PASSULCK_in)
    begin:PASSULock
        PASSULCK_out = 1'b0;
        #tdevice_PP_256_256 PASSULCK_out = 1'b1;
    end

    always @(posedge PASSACC_in)
    begin:PASSAcc
        PASSACC_out = 1'b0;
        #tdevice_PASSACC PASSACC_out = 1'b1;
    end

    always @(CSNeg_ipd or rising_edge_SCK_ipd or falling_edge_SCK_ipd)
    begin : icrc_calc_proc
        integer j;
        if (ITCRCE == 0 && SDRDDR == 1'b1 && OPI_IT && RST_out && ICRC_DATA)
        begin
            if (CSNeg_ipd == 1'b0 &&  rd_crc == 0) // if memory is selected and not RDCRC_4_0 command
            begin
                    if ((rising_edge_SCK_ipd || falling_edge_SCK_ipd))// if complete 16 bit data is captured
                    begin
                        cnt_icrc32 = cnt_icrc32 + 1;
                        if (cnt_icrc32%4 == 0)
                        begin
                            icrc_in[7:0] = Din;
                        end
                        else if (cnt_icrc32%4 == 1)
                        begin
                            icrc_in[15:8] = Din;
                        end
                        else if  (cnt_icrc32%4 == 2)
                        begin
                            icrc_in[23:16] = Din;
                        end
                        else if  (cnt_icrc32%4 == 3)
                        begin
                            icrc_in[31:24] = Din;
                            icrc_cnt = icrc_cnt + 1;
                            for(j=31;j>=0;j=j-1)
                            begin
                                icrc_tmp = icrc_in[j] ^ icrc_out[31];
                                icrc_out[31]  = icrc_out[30];
                                icrc_out[30]  = icrc_out[29];
                                icrc_out[29]  = icrc_out[28];
                                icrc_out[28]  = icrc_out[27]  ^ icrc_tmp;
                                icrc_out[27]  = icrc_out[26]  ^ icrc_tmp;
                                icrc_out[26]  = icrc_out[25]  ^ icrc_tmp;
                                icrc_out[25]  = icrc_out[24]  ^ icrc_tmp;
                                icrc_out[24]  = icrc_out[23];
                                icrc_out[23]  = icrc_out[22]  ^ icrc_tmp;
                                icrc_out[22]  = icrc_out[21]  ^ icrc_tmp;
                                icrc_out[21]  = icrc_out[20];
                                icrc_out[20]  = icrc_out[19]  ^ icrc_tmp;
                                icrc_out[19]  = icrc_out[18]  ^ icrc_tmp;
                                icrc_out[18]  = icrc_out[17]  ^ icrc_tmp;
                                icrc_out[17]  = icrc_out[16];
                                icrc_out[16]  = icrc_out[15];
                                icrc_out[15]  = icrc_out[14];
                                icrc_out[14]  = icrc_out[13]  ^ icrc_tmp;
                                icrc_out[13]  = icrc_out[12]  ^ icrc_tmp;
                                icrc_out[12]  = icrc_out[11];
                                icrc_out[11]  = icrc_out[10]  ^ icrc_tmp;
                                icrc_out[10]  = icrc_out[9]   ^ icrc_tmp;
                                icrc_out[9]   = icrc_out[8]   ^ icrc_tmp;
                                icrc_out[8]   = icrc_out[7]   ^ icrc_tmp;
                                icrc_out[7]   = icrc_out[6];
                                icrc_out[6]   = icrc_out[5]   ^ icrc_tmp;
                                icrc_out[5]   = icrc_out[4];
                                icrc_out[4]   = icrc_out[3];
                                icrc_out[3]   = icrc_out[2];
                                icrc_out[2]   = icrc_out[1];
                                icrc_out[1]   = icrc_out[0];
                                icrc_out[0]   = icrc_tmp;
                            end
                        end
                    end
                if (icrc_cnt >= 4)
                   ICRV = icrc_out;
                else
                   ICRV = ICRV;
            end
        end
    end
    


    // ------------------------------------------------------------------------
    // Deep Power Down time
    // ------------------------------------------------------------------------
    // DPDExit_in is any write or read access for which CSNeg_ipd is asserted
    // more than tDPDCSL time. No exit event is detected until DPD is entered,
    // which is after tENTDPD
    assign DPDExt_in = ((falling_edge_CSNeg_ipd == 1'b1) && (DPD_entered == 1'b1)) ?
                         1'b1 : 1'b0;

    always @(posedge DPDExt_in)
    begin : DPDExtEvent
      #(tdevice_CSDPD - 1) DPDExt_out = 1'b1;
    end

    // DPD entry event, generated after tENTDPD time (minumum 3 us)
    // While entering DPD memory is not accessable so DPD exit event cannot be generated
    always @(posedge DPD_in)
    begin : DPDEntEvent
      #(tdevice_ENTDPD - 1) DPD_entered = 1'b1;
    end

    // Generate event to trigger exiting from DPD mode
    always @(posedge DPDExt_out or CSNeg_ipd or RESETNeg or falling_edge_RST or
             DPD_in)
    begin : DPDExtDetected
      if ((DPDExt_out == 1'b1) && (CSNeg_ipd == 1'b0) || 
          (falling_edge_RST && DPD_in))
      begin
        DPDExt = 1'b1;
        #1 DPDExt = 1'b0;
      end
    end

    // DPD exit event, generated after tDPDOUT time (maximal: 300 us)
    always @(posedge DPDExt)
    begin : DPDExtTime
        DPD_out = 1'b0;
        #(tdevice_EXTDPD - 1) DPD_out = 1'b1;
    end
    
    always @(posedge PoweredUp or posedge RST_in)
    begin:DPDown_POR
        DPD_POR_out = 1'b0;
        #tdevice_PU DPD_POR_out = 1'b1;
    end

///////////////////////////////////////////////////////////////////////////////
// write cycle decode
///////////////////////////////////////////////////////////////////////////////
    integer opcode_cnt = 0;
    integer addr_cnt   = 0;
    integer mode_cnt   = 0;
    integer data_cnt   = 0;
    integer bit_cnt    = 0;

    reg [4095:0] Data_in = {4096{1'b1}};
    reg    [7:0] opcode;
    reg    [7:0] opcode_in;
    reg    [7:0] opcode_tmp;
    reg   [31:0] addr_bytes;
    reg   [31:0] hiaddr_bytes;
    reg   [31:0] Address_in;
    reg    [7:0] mode_bytes;
    reg    [7:0] mode_in;
    integer Latency_code;
    integer Register_Latency;
    integer octal_data_in [0:511];
    reg [7:0] octal_byte = 8'b0;
    reg [7:0] Byte_slv;

    reg CRC_ACT      = 1'b0; // CRC Active
    reg CRC_RD_SETUP = 1'b0; // CRC read setup
    reg [15:0] crc_in;
    reg [31:0] crc_out;
    reg crc_tmp;
    
    
    ///////////////////////////////////////////////////////////////////////////
    // Process that determines clock frequency
    ///////////////////////////////////////////////////////////////////////////
     always @(rising_edge_SCK_ipd or CSNeg_ipd)
     begin : check_freq
        time CK_PER_freq;
        time LAST_CK_freq;
        CK_PER_freq = $time - LAST_CK_freq;
        LAST_CK_freq = $time;
        # 1;
        
        if (CSNeg_ipd)
           counter_clock = 3'b000;
        else if (counter_clock < 3'b111)
            counter_clock = counter_clock + 1;
        else 
            counter_clock = 3'b111;
            
        if (CK_PER_freq < 20000 || counter_clock < 3'b010 )
            freq51 = 1'b1;
        else 
            freq51 = 1'b0;
    
     end 
     
       ///////////////////////////////////////////////////////////////////////////
    // Process for Data Strobe / DS
    ///////////////////////////////////////////////////////////////////////////
     always @(CSNeg_ipd or OPI_IT or SDRDDR)
     begin : check_DS
        
        if (~CSNeg_ipd)
        begin
            if (OPI_IT && SDRDDR)
            begin
                DATA_STROBE = 1'b1;
                DS_OPI = 1'b1;
            end
            else if (OPI_IT  && ~SDRDDR)
            begin
                DATA_STROBE = 1'b1;
                DS_OPI = 1'b0;
            end
            else
            begin
                DATA_STROBE = 1'b0;
                DS_OPI = 1'b1;
                
            end
        end
        else
        begin
            DATA_STROBE = 1'b0;
            DS_OPI = 1'b1;
        end
     end 

   always @(rising_edge_CSNeg_ipd or falling_edge_CSNeg_ipd or
            rising_edge_SCK_ipd or falling_edge_SCK_ipd)
   begin: Buscycle
        integer i;
        integer j;
        integer k;
        time CLK_PER;
        time LAST_CLK;

        if (falling_edge_CSNeg_ipd)
        begin
            if (bus_cycle_state==STAND_BY)
            begin
                Instruct = NONE;
                write = 1'b1;
                cfg_write  = 0;
                opcode_cnt = 0;
                addr_cnt   = 0;
                mode_cnt   = 0;
                dummy_cnt  = 0;
                data_cnt   = 0;

                Data_in = {4096{1'b1}};

                CLK_PER    = 1'b0;
                LAST_CLK   = 1'b0;

                ZERO_DETECTED = 1'b0;
                DOUBLE = 1'b0;
                bus_cycle_state = OPCODE_BYTE;
            end
        end

        if (rising_edge_SCK_ipd) // Instructions, addresses or data present at
        begin                    // input are latched on the rising edge of SCK

            CLK_PER = $time - LAST_CLK;
            LAST_CLK = $time;
            if (CHECK_FREQ)
            begin
                if (((Instruct == RDSSR_4_0) || (Instruct == RDARG_4_0  && 
                     (Address < 32'h00800000)) || (Instruct == RDPPB_4_0) ||
                   (Instruct == RDECC_4_0) || (Instruct == RDAY2_C_0)) && ~OPI_IT)
                begin
                    if ((CLK_PER <  20000 && Latency_code == 0) || // <=50MHz
                        (CLK_PER <  14705 && Latency_code == 1) || // <=68MHz
                        (CLK_PER <  12345 && Latency_code == 2) || // <=81MHz
                        (CLK_PER <  10752 && Latency_code == 3) || // <=93MHz
                        (CLK_PER <  9433  && Latency_code == 4) || // <=106MHz
                        (CLK_PER <  8475  && Latency_code == 5) || // <=118MHz
                        (CLK_PER <  7633  && Latency_code == 6) || // <=131MHz
                        (CLK_PER <  6993  && Latency_code == 7) || // <=143MHz
                        (CLK_PER <  6410  && Latency_code == 8) || // <=156MHz
                        (CLK_PER <  6020  && Latency_code >= 9))   // <=166MHz
                    begin
                        $display ("More wait states are required for");
                        $display ("this clock frequency value");
                    end
                    CHECK_FREQ = 0;
                end
                if (((Instruct == RDSSR_4_0) || (Instruct == RDARG_4_0  && 
                     (Address < 32'h00800000)) || (Instruct == RDPPB_4_0) ||
                   (Instruct == RDECC_4_0) || (Instruct == RDAY1_4_0)) && OPI_IT && ~SDRDDR)
                begin
                    if ((CLK_PER <  20000 && Latency_code == 0) || // <=50MHz
                        (CLK_PER <  15625 && Latency_code == 1) || // <=64MHz
                        (CLK_PER <  11111 && Latency_code == 2) || // <=92MHz
                        (CLK_PER <  8264  && Latency_code == 3) || // <=121MHz
                        (CLK_PER <  6666  && Latency_code == 4) || // <=150MHz
                        (CLK_PER <  5618  && Latency_code == 5) || // <=178MHz
                        (CLK_PER <  5000  && Latency_code >= 6))   // <=200MHz
                    begin
                        $display ("More wait states are required for");
                        $display ("this clock frequency value");
                    end
                    CHECK_FREQ = 0;
                end
                if (((Instruct == RDSSR_4_0) || (Instruct == RDARG_4_0  && 
                     (Address < 32'h00800000)) || (Instruct == RDPPB_4_0) ||
                   (Instruct == RDECC_4_0) || (Instruct == RDAY2_4_0)) && OPI_IT && SDRDDR)
                begin
                    if ((CLK_PER <  23800 && Latency_code == 0) || // <=42MHz
                        (CLK_PER <  17544 && Latency_code == 1) || // <=57MHz
                        (CLK_PER <  11748 && Latency_code == 2) || // <=85MHz
                        (CLK_PER <  9345  && Latency_code == 3) || // <=107MHz
                        (CLK_PER <  8264  && Latency_code == 4) || // <=121MHz
                        (CLK_PER <  7407  && Latency_code == 5) || // <=135MHz
                        (CLK_PER <  6666  && Latency_code == 6) || // <=150MHz
                        (CLK_PER <  6097  && Latency_code == 7) || // <=164MHz
                        (CLK_PER <  5618  && Latency_code == 8) || // <=178MHz
                        (CLK_PER <  5208  && Latency_code == 9) || // <=192MHz
                        (CLK_PER <  5000  && Latency_code >= 10))  // <=200MHz
                    begin
                        $display ("More wait states are required for");
                        $display ("this clock frequency value");
                    end
                    CHECK_FREQ = 0;
                end
                if (((Instruct == RDARG_4_0 && (Address >= 32'h00800000)) || 
                      Instruct == RDDYB_4_0) && ~OPI_IT)
                    begin
                    if ((CLK_PER < 20000 && Register_Latency == 0) || // <=50MHz
                       (CLK_PER <  7510 && Register_Latency == 1)  || // <=133MHz
                       (CLK_PER <  6020 && Register_Latency == 2)) // <=166MHz
                    begin
                        $display ("More wait states are required for");
                        $display ("this clock frequency value");
                    end
                    CHECK_FREQ = 0;
                end
                if   ((Instruct == RDSR1 || Instruct == RDIDN ||
                     Instruct == RDSR2 || Instruct == RDPLB_0_0) && ~OPI_IT)
                    begin
                    if ((CLK_PER < 20000 && Register_Latency == 0) || // <=50MHz
                       (CLK_PER <  7510 && Register_Latency == 0) || // <=133MHz
                       (CLK_PER <  7510 && Register_Latency == 1) || // <=133MHz
                       (CLK_PER <  6020 && Register_Latency == 2)) // <=166MHz
                    begin
                        $display ("More wait states are required for");
                        $display ("this clock frequency value");
                    end
                    CHECK_FREQ = 0;
                end
                if   ((Instruct == RDSR1 || Instruct == RDIDN || Instruct == RDDYB_4_0 ||
                      (Instruct == RDARG_4_0 && (Address >= 32'h00800000)) ||
                     Instruct == RDSR2 || Instruct == RDPLB_0_0) && OPI_IT && ~SDRDDR)
                    begin
                    if ((CLK_PER < 20000 && Register_Latency == 3) || // <=50MHz
                       (CLK_PER <  7510 && Register_Latency == 4) || // <=133MHz
                       (CLK_PER <  6020 && Register_Latency == 5) || // <=133MHz
                       (CLK_PER <  5000 && Register_Latency == 6)) // <=166MHz
                    begin
                        $display ("More wait states are required for");
                        $display ("this clock frequency value");
                    end
                    CHECK_FREQ = 0;
                end
                if   ((Instruct == RDSR1 || Instruct == RDIDN || Instruct == RDDYB_4_0 ||
                      (Instruct == RDARG_4_0 && (Address >= 32'h00800000)) ||
                     Instruct == RDSR2 || Instruct == RDPLB_0_0) && OPI_IT && SDRDDR)
                    begin
                    if ((CLK_PER < 40000 && Register_Latency == 3) || // <=25MHz
                       (CLK_PER <  15151 && Register_Latency == 4) || // <=66MHz
                       (CLK_PER <  5000 && Register_Latency == 5) || // <=200MHz
                       (CLK_PER <  5000 && Register_Latency == 6)) // <=200MHz
                    begin
                        $display ("More wait states are required for");
                        $display ("this clock frequency value");
                    end
                    CHECK_FREQ = 0;
                end
            end

            if (~CSNeg_ipd)
            begin
                case (bus_cycle_state)
                    OPCODE_BYTE:
                    begin
                        if (OPI_IT)
                          case (CFR2V[3:0])
                            4'b0000 : // 0h
                            begin
                                Latency_code = 5;
                            end
                            4'b0001 : // 1h
                            begin
                                Latency_code = 6;
                            end
                            4'b0010 : // 2h
                            begin
                                Latency_code = 8;
                            end
                            4'b0011 : // 3h
                            begin
                                Latency_code = 10;
                            end
                            4'b0100 : // 4h
                            begin
                                Latency_code = 12;
                            end
                            4'b0101 : // 5h
                            begin
                                Latency_code = 14;
                            end
                            4'b0110 : // 6h
                            begin
                                Latency_code = 16;
                            end
                            4'b0111 : // 7h
                            begin
                                Latency_code = 18;
                            end
                            4'b1000 : // 8h
                            begin
                                Latency_code = 20;
                            end
                            4'b1001 : // 0h
                            begin
                                Latency_code = 22;
                            end
                            4'b1010 : // 10h
                            begin
                                Latency_code = 23;
                            end
                            4'b1011 : // 11h
                            begin
                                Latency_code = 24;
                            end
                            4'b1100 : // 12h
                            begin
                                Latency_code = 25;
                            end
                            4'b1101: // 13h
                            begin
                                Latency_code = 26;
                            end
                            4'b1110 : // 14h
                            begin
                                Latency_code = 27;
                            end
                            4'b1111 : // 15h
                            begin
                                Latency_code = 28;
                            end
                          endcase
                        else
                            Latency_code = CFR2V[3:0];

                        if (OPI_IT)
                        Register_Latency = CFR3V[7:6] + 3;
                        else if (opcode == 8'h65 || opcode == 8'hE0)
                        Register_Latency = CFR3V[7] + CFR3V[6];
                        else
                        Register_Latency = CFR3V[7] + CFR3V[7]*CFR3V[6];

                        prog_erase = 1'b0;

                        //Wrap Length
                        if (CFR4V[1:0] == 1)
                        begin
                            WrapLength = 16;
                        end
                        else if (CFR4V[1:0] == 2)
                        begin
                            WrapLength = 32;
                        end
                        else if (CFR4V[1:0] == 3)
                        begin
                            WrapLength = 64;
                        end
                        else
                        begin
                            WrapLength = 8;
                        end

                        if (OPI_IT)
                        begin
                            opcode_in[0] = IO7_in;
                            opcode_in[1] = IO6_in;
                            opcode_in[2] = IO5_in;
                            opcode_in[3] = IO4_in;
                            opcode_in[4] = IO3_in;
                            opcode_in[5] = IO2_in;
                            opcode_in[6] = SO_in;
                            opcode_in[7] = SI_in;
                        end
                        else
                            opcode_in[opcode_cnt] = SI_in;

                        opcode_cnt = opcode_cnt + 1;

                        if ((OPI_IT && ((opcode_cnt == BYTE/8) || (opcode_cnt == 2))) ||
                        (~OPI_IT && (opcode_cnt == BYTE)))
                        begin
                            for(i=7;i>=0;i=i-1)
                            begin
                                opcode[i] = opcode_in[7-i];
                            end
                            case (opcode)

                                8'b00000011 : // 03h
                                begin
                                    Instruct = RDAY1_C_0;
                                    if (OPI_IT)
                                    begin
                                    //Command not supported in OPI mode
                                        bus_cycle_state = STAND_BY;
                                    end
                                    else
                                        bus_cycle_state = ADDRESS_BYTES;
                                end

                                8'b00000100 : // 04h
                                begin
                                    Instruct = WRDIS_0_0;
                                    if (~SDRDDR)
                                    begin
                                        if ((~OPI_IT) || (OPI_IT && (opcode_cnt == 2)))
                                        begin
                                            bus_cycle_state = DATA_BYTES;
                                            opcode_cnt = 0;
                                        end
                                        else if (OPI_IT && (opcode_cnt == 1))
                                        begin
                                            bus_cycle_state = OPCODE_BYTE;
                                        end
                                    end
                                end

                                8'b00000101 : // 05h
                                begin
                                    Instruct = RDSR1;
                                    if (~SDRDDR)
                                    begin
                                        if (~OPI_IT)
                                        begin
                                            if (Register_Latency == 0)
                                                bus_cycle_state = DATA_BYTES;
                                            else
                                                bus_cycle_state = DUMMY_BYTES;
                                         end
                                        else if (OPI_IT && (opcode_cnt == 2))
                                        begin
                                            bus_cycle_state = ADDRESS_BYTES;
                                            if (OPI_IT && (opcode_cnt == 2))
                                                opcode_cnt = 0;
                                        end
                                        else if (OPI_IT && (opcode_cnt == 1))
                                        begin
                                            bus_cycle_state = OPCODE_BYTE;
                                        end
                                    end
                                end

                                8'b00000110 : // 06h
                                begin
                                    Instruct = WRENB_0_0;
                                    if (~SDRDDR)
                                    begin
                                        if ((~OPI_IT) || (OPI_IT && (opcode_cnt == 2)))
                                        begin
                                            bus_cycle_state = DATA_BYTES;
                                            opcode_cnt = 0;
                                        end
                                        else if (OPI_IT && (opcode_cnt == 1))
                                        begin
                                            bus_cycle_state = OPCODE_BYTE;
                                        end
                                    end
                                end

                                8'b00000111 : // 07h
                                begin
                                    Instruct = RDSR2;
                                     if (~SDRDDR)
                                     begin
                                        if (~OPI_IT)
                                        begin
                                            if (Register_Latency == 0)
                                                bus_cycle_state = DATA_BYTES;
                                            else
                                                bus_cycle_state = DUMMY_BYTES;
                                         end
                                        else if (OPI_IT && (opcode_cnt == 2))
                                        begin
                                            bus_cycle_state = ADDRESS_BYTES;
                                            if (OPI_IT && (opcode_cnt == 2))
                                                opcode_cnt = 0;
                                        end
                                        else if (OPI_IT && (opcode_cnt == 1))
                                        begin
                                            bus_cycle_state = OPCODE_BYTE;
                                        end
                                    end
                                end

                                8'b00001011 : // 0Bh
                                begin
                                    Instruct = RDAY2_C_0;
                                    bus_cycle_state = ADDRESS_BYTES;
                                    CHECK_FREQ = 1'b1;
                                end

                                8'b00010010 : // 12h
                                begin
                                    Instruct = PRPGE_4_1;
                                    if (~SDRDDR)
                                    begin
                                        if (WRPGEN == 1)
                                        begin
                                            if ((~OPI_IT) || (OPI_IT && (opcode_cnt == 2)))
                                            begin
                                                bus_cycle_state = ADDRESS_BYTES;
                                                if (OPI_IT && (opcode_cnt == 2))
                                                    opcode_cnt = 0;
                                            end
                                            else if (OPI_IT && (opcode_cnt == 1))
                                            begin
                                                bus_cycle_state = OPCODE_BYTE;
                                            end
                                        end
                                        else
                                            bus_cycle_state = STAND_BY;
                                    end
                                end

                                8'b00010011 : // 13h
                                begin
                                    Instruct = RDAY1_4_0;
                                    bus_cycle_state = ADDRESS_BYTES;
                                end

                                8'b00011001 : // 19h
                                begin
                                    Instruct = RDECC_4_0;
                                    if (~SDRDDR)
                                    begin
                                        if ((~OPI_IT) || (OPI_IT && (opcode_cnt == 2)))
                                        begin
                                            bus_cycle_state = ADDRESS_BYTES;
                                            CHECK_FREQ = 1'b1;
                                            if (OPI_IT && (opcode_cnt == 2))
                                                opcode_cnt = 0;
                                        end
                                        else if (OPI_IT && (opcode_cnt == 1))
                                        begin
                                            bus_cycle_state = OPCODE_BYTE;
                                        end
                                    end
                                end

                                8'b00011011 : // 1Bh
                                begin
                                    Instruct = CLECC_0_0;
                                    if (WRPGEN == 1)
                                    begin
                                    if (~SDRDDR)
                                        begin
                                            if ((~OPI_IT) || (OPI_IT && (opcode_cnt == 2)))
                                            begin
                                                bus_cycle_state = DATA_BYTES;
                                                if (OPI_IT && (opcode_cnt == 2))
                                                    opcode_cnt = 0;
                                            end
                                            else if (OPI_IT && (opcode_cnt == 1))
                                            begin
                                                bus_cycle_state = OPCODE_BYTE;
                                            end
                                        end
                                    end
                                    else
                                    begin
                                        bus_cycle_state = STAND_BY;
                                    end
                                end

                                8'b00100001 : // 21h
                                begin
                                    Instruct = ER004_4_0;
                                    if (~SDRDDR)
                                    begin
                                        if (WRPGEN == 1 && ~UNHYSA)
                                        begin
                                            if ((~OPI_IT) || (OPI_IT && (opcode_cnt == 2)))
                                            begin
                                                bus_cycle_state = ADDRESS_BYTES;
                                                if (OPI_IT && (opcode_cnt == 2))
                                                    opcode_cnt = 0;
                                            end
                                            else if (OPI_IT && (opcode_cnt == 1))
                                            begin
                                                bus_cycle_state = OPCODE_BYTE;
                                            end
                                        end
                                        else
                                            bus_cycle_state = STAND_BY;
                                    end
                                end

                                8'b00101100 : // 2Ch
                                begin
                                    Instruct = WRPLB_0_0;
                                    if (WRPGEN == 1)
                                    begin
                                        if (~SDRDDR)
                                        begin
                                            if (OPI_IT && (opcode_cnt == 2))
                                            begin
                                                if (WRPGEN == 1)
                                                begin
                                                    bus_cycle_state = DATA_BYTES;
                                                    opcode_cnt = 0;
                                                end
                                                else
                                                    bus_cycle_state = STAND_BY;
                                            end
                                            else if (OPI_IT && (opcode_cnt == 1))
                                                bus_cycle_state = OPCODE_BYTE;
                                        end
                                    end
                                    else 
                                    begin
                                        bus_cycle_state = STAND_BY;
                                    end
                                end

                                8'b00101101 : // 2Dh
                                begin
                                    Instruct = RDPLB_4_0; // RDPLB
                                    if (~SDRDDR)
                                    begin
                                        if (OPI_IT && (opcode_cnt == 2))
                                        begin
                                            bus_cycle_state = ADDRESS_BYTES;
                                            opcode_cnt = 0;
                                        end
                                        else if (OPI_IT && (opcode_cnt == 1))
                                            bus_cycle_state = OPCODE_BYTE;
                                    end
                                end

                                8'b00110000 : // 30h
                                begin
                                    Instruct = RSEPD_0_0;
                                    if (~SDRDDR)
                                    begin
                                        if ((~OPI_IT) || (OPI_IT && (opcode_cnt == 2)))
                                        begin
                                            bus_cycle_state = DATA_BYTES;
                                            if (OPI_IT && (opcode_cnt == 2))
                                                opcode_cnt = 0;
                                        end
                                        else if (OPI_IT && (opcode_cnt == 1))
                                        begin
                                            bus_cycle_state = OPCODE_BYTE;
                                        end
                                    end
                                end

                                8'b01000010 : // 42h
                                begin
                                    Instruct = PRSSR_4_1;
                                    if (~SDRDDR)
                                    begin
                                        if (WRPGEN == 1)
                                        begin
                                            if ((~OPI_IT) || (OPI_IT && (opcode_cnt == 2)))
                                            begin
                                                bus_cycle_state = ADDRESS_BYTES;
                                                if (OPI_IT && (opcode_cnt == 2))
                                                    opcode_cnt = 0;
                                            end
                                            else if (OPI_IT && (opcode_cnt == 1))
                                            begin
                                                bus_cycle_state = OPCODE_BYTE;
                                            end
                                        end
                                        else
                                            bus_cycle_state = STAND_BY;
                                    end
                                end

                                8'b01001011 : // 4Bh
                                begin
                                    Instruct = RDSSR_4_0;
                                    if (~SDRDDR)
                                    begin
                                       if ((~OPI_IT) || (OPI_IT && (opcode_cnt == 2)))
                                       begin
                                           bus_cycle_state = ADDRESS_BYTES;
                                           if (OPI_IT && (opcode_cnt == 2))
                                               opcode_cnt = 0;
                                       end
                                       else if (OPI_IT && (opcode_cnt == 1))
                                       begin
                                           bus_cycle_state = OPCODE_BYTE;
                                       end
                                    end
                                end

                                8'b01001100 : // 4Ch
                                begin
                                    Instruct = RDUID;
                                    if (~SDRDDR)
                                    begin
                                        if ((~OPI_IT) || (OPI_IT && (opcode_cnt == 2)))
                                        begin
                                            bus_cycle_state = DUMMY_BYTES;
                                            if (OPI_IT && (opcode_cnt == 2))
                                                opcode_cnt = 0;
                                        end
                                        else if (OPI_IT && (opcode_cnt == 1))
                                        begin
                                            bus_cycle_state = OPCODE_BYTE;
                                        end
                                    end
                                end

                                8'b01011010 : // 5Ah
                                begin
                                    Instruct = RSFDP;
                                    if (~SDRDDR)
                                    begin
                                        if ((~OPI_IT) || (OPI_IT && (opcode_cnt == 2)))
                                        begin
                                            bus_cycle_state = ADDRESS_BYTES;
                                            if (OPI_IT && (opcode_cnt == 2))
                                                opcode_cnt = 0;
                                        end
                                        else if (OPI_IT && (opcode_cnt == 1))
                                        begin
                                            bus_cycle_state = OPCODE_BYTE;
                                        end
                                    end
                                end

                                8'b01011011 : // 5Bh
                                begin
                                    Instruct = DICHK_4_1;
                                    if (~SDRDDR)
                                    begin
                                        if (~OPI_IT)
                                        begin
                                            bus_cycle_state = ADDRESS_BYTES;
                                        end
                                        else if (OPI_IT && (opcode_cnt == 1))
                                        begin
                                            bus_cycle_state = OPCODE_BYTE;
                                        end
                                        else if (OPI_IT && (opcode_cnt == 2))
                                        begin
                                            opcode_cnt = 0;
                                            bus_cycle_state = DUMMY_BYTES;
                                        end
                                    end
                                end

                                8'b01011101 : // 5Dh
                                begin
                                    Instruct = SEERC_4_0;
                                    if (~SDRDDR)
                                    begin
                                        if ((~OPI_IT) || (OPI_IT && (opcode_cnt == 2)))
                                        begin
                                            bus_cycle_state = ADDRESS_BYTES;
                                            opcode_cnt = 0;
                                        end
                                        else if (OPI_IT && (opcode_cnt == 1))
                                        begin
                                            bus_cycle_state = OPCODE_BYTE;
                                        end
                                    end
                                end

                                8'b01100000 : // 60h
                                begin
                                    Instruct = ERCHP_0_0;
                                    if (~SDRDDR)
                                    begin
                                        if (WRPGEN == 1)
                                        begin
                                            if ((~OPI_IT) || (OPI_IT && (opcode_cnt == 2)))
                                            begin
                                                bus_cycle_state = DATA_BYTES;
                                                if (OPI_IT && (opcode_cnt == 2))
                                                    opcode_cnt = 0;
                                            end
                                            else if (OPI_IT && (opcode_cnt == 1))
                                            begin
                                                bus_cycle_state = OPCODE_BYTE;
                                            end
                                        end
                                        else
                                            bus_cycle_state = STAND_BY;
                                    end
                                end

                                8'b01100100 : // 64h
                                begin
                                    Instruct = RDCRC_4_0;
                                    if (SDRDDR)
                                    begin
                                        rd_crc = 1;
                                        if (SDRDDR && OPI_IT && (opcode_cnt == 2))
                                        begin
                                            bus_cycle_state = ADDRESS_BYTES;
                                            opcode_cnt = 0;
                                        end
                                        else if (SDRDDR && OPI_IT && (opcode_cnt == 1))
                                        begin
                                            bus_cycle_state = OPCODE_BYTE;
                                        end
                                    end
                                end

                                8'b01100101 : // 65h
                                begin
                                    Instruct = RDARG_4_0;
                                    if (~SDRDDR)
                                    begin
                                        if ((~OPI_IT) || (OPI_IT && (opcode_cnt == 2)))
                                        begin
                                            bus_cycle_state = ADDRESS_BYTES;
                                            opcode_cnt = 0;
                                        end
                                        else if (OPI_IT && (opcode_cnt == 1))
                                        begin
                                            bus_cycle_state = OPCODE_BYTE;
                                        end
                                    end
                                end

                                8'b01100110 : // 66h
                                begin
                                    Instruct = SRSTE_0_0;
                                    if (~SDRDDR)
                                    begin
                                        if ((~OPI_IT) || (OPI_IT && (opcode_cnt == 2)))
                                        begin
                                            bus_cycle_state = DATA_BYTES;
                                            if (OPI_IT && (opcode_cnt == 2))
                                                opcode_cnt = 0;
                                        end
                                        else if (OPI_IT && (opcode_cnt == 1))
                                        begin
                                            bus_cycle_state = OPCODE_BYTE;
                                        end
                                    end
                                end

                                8'b01110001 : // 71h
                                begin
                                    if (OPI_IT == 1'b1)
                                        Instruct = WRARG_4_1;
                                    else
                                        Instruct = WRARG_C_1;
                                    if (~SDRDDR)
                                    begin
                                        if (WRPGEN == 1)
                                        begin
                                            if ((~OPI_IT) || (OPI_IT && (opcode_cnt == 2)))
                                            begin
                                                bus_cycle_state = ADDRESS_BYTES;
                                                opcode_cnt = 0;
                                            end
                                            else if (OPI_IT && (opcode_cnt == 1))
                                                bus_cycle_state = OPCODE_BYTE;
                                        end
                                        else
                                            bus_cycle_state = STAND_BY;
                                    end
                                end

                                8'b10000010 : // 82h
                                begin
                                    Instruct = CLPEF_0_0;
                                    if (~SDRDDR)
                                    begin
                                        if ((~OPI_IT) || (OPI_IT && (opcode_cnt == 2)))
                                        begin
                                            bus_cycle_state = DATA_BYTES;
                                            if (OPI_IT && (opcode_cnt == 2))
                                                opcode_cnt = 0;
                                        end
                                        else if (OPI_IT && (opcode_cnt == 1))
                                        begin
                                            bus_cycle_state = OPCODE_BYTE;
                                        end
                                    end
                                end

                                8'b10011001 : // 99h
                                begin
                                    Instruct = SFRST_0_0;
                                    if (~SDRDDR)
                                    begin
                                        if ((~OPI_IT) || (OPI_IT && (opcode_cnt == 2)))
                                        begin
                                            bus_cycle_state = DATA_BYTES;
                                            if (OPI_IT && (opcode_cnt == 2))
                                                opcode_cnt = 0;
                                        end
                                        else if (OPI_IT && (opcode_cnt == 1))
                                        begin
                                            bus_cycle_state = OPCODE_BYTE;
                                        end
                                    end
                                end

                                8'b10011111 : // 9Fh
                                begin
                                    Instruct = RDIDN;
                                    if (~SDRDDR)
                                    begin
                                        if (~OPI_IT)
                                        begin
                                            if (Register_Latency == 0)
                                            bus_cycle_state = DATA_BYTES;
                                            else
                                            bus_cycle_state = DUMMY_BYTES;
                                        end
                                        else if (OPI_IT && (opcode_cnt == 2))
                                        begin
                                            bus_cycle_state = ADDRESS_BYTES;
                                            if (OPI_IT && (opcode_cnt == 2))
                                                opcode_cnt = 0;
                                        end
                                        else if (OPI_IT && (opcode_cnt == 1))
                                        begin
                                            bus_cycle_state = OPCODE_BYTE;
                                        end
                                    end
                                end

                                8'b10100110 : // A6h
                                begin
                                    Instruct = WRPLB_0_0;
                                    if (WRPGEN == 1)
                                        bus_cycle_state = DATA_BYTES;
                                    else
                                        bus_cycle_state = STAND_BY;
                                end

                                8'b10100111 : // A7h
                                begin
                                    if (~OPI_IT)
                                    begin
                                        Instruct = RDPLB_0_0; // RDPLB
                                        if (Register_Latency == 0)
                                            bus_cycle_state = DATA_BYTES;
                                        else
                                            bus_cycle_state = DUMMY_BYTES;
                                    end
                                    else
                                        bus_cycle_state = STAND_BY;
                                end

                                8'b10110000 : // B0h
                                begin
                                    Instruct = SPEPD_0_0;
                                    if (~SDRDDR)
                                    begin
                                        if ((~OPI_IT) || (OPI_IT && (opcode_cnt == 2)))
                                        begin
                                            bus_cycle_state = DATA_BYTES;
                                            if (OPI_IT && (opcode_cnt == 2))
                                                opcode_cnt = 0;
                                        end
                                        else if (OPI_IT && (opcode_cnt == 1))
                                        begin
                                            bus_cycle_state = OPCODE_BYTE;
                                        end
                                    end
                                end

                                8'b10111001 : // B9h
                                begin
                                    Instruct = ENDPD_0_0;
                                    if (~SDRDDR)
                                    begin
                                        if ((~OPI_IT) || (OPI_IT && (opcode_cnt == 2)))
                                        begin
                                            bus_cycle_state = DATA_BYTES;
                                            if (OPI_IT && (opcode_cnt == 2))
                                                opcode_cnt = 0;
                                        end
                                        else if (OPI_IT && (opcode_cnt == 1))
                                        begin
                                            bus_cycle_state = OPCODE_BYTE;
                                        end
                                    end
                                end

                                8'b11000111 : // C7h
                                begin
                                    Instruct = ERCHP_0_0;
                                    if (~SDRDDR)
                                    begin
                                        if (WRPGEN == 1)
                                        begin
                                            if ((~OPI_IT) || (OPI_IT && (opcode_cnt == 2)))
                                            begin
                                                bus_cycle_state = DATA_BYTES;
                                                if (OPI_IT && (opcode_cnt == 2))
                                                    opcode_cnt = 0;
                                            end
                                            else if (OPI_IT && (opcode_cnt == 1))
                                            begin
                                                bus_cycle_state = OPCODE_BYTE;
                                            end
                                        end
                                        else
                                            bus_cycle_state = STAND_BY;
                                    end
                                end

                                8'b11010000 : // D0h
                                begin
                                    Instruct = EVERS_4_0;
                                    if (~SDRDDR)
                                    begin
                                        if ((~OPI_IT) || (OPI_IT && (opcode_cnt == 2)))
                                        begin
                                            bus_cycle_state = ADDRESS_BYTES;
                                            if (OPI_IT && (opcode_cnt == 2))
                                                opcode_cnt = 0;
                                        end
                                        else if (OPI_IT && (opcode_cnt == 1))
                                        begin
                                            bus_cycle_state = OPCODE_BYTE;
                                        end
                                    end
                                end

                                8'b11011100 : // DCh
                                begin
                                    Instruct = ER256_4_0;
                                    if (~SDRDDR)
                                    begin
                                        if (WRPGEN == 1)
                                        begin
                                            if ((~OPI_IT) || (OPI_IT && (opcode_cnt == 2)))
                                            begin
                                                bus_cycle_state = ADDRESS_BYTES;
                                                if (OPI_IT && (opcode_cnt == 2))
                                                    opcode_cnt = 0;
                                            end
                                            else if (OPI_IT && (opcode_cnt == 1))
                                            begin
                                                bus_cycle_state = OPCODE_BYTE;
                                            end
                                        end
                                        else
                                            bus_cycle_state = STAND_BY;
                                    end
                                end

                                8'b11100000 : // E0h
                                begin
                                    Instruct = RDDYB_4_0;
                                    if (~SDRDDR)
                                    begin
                                        if ((~OPI_IT) || (OPI_IT && (opcode_cnt == 2)))
                                        begin
                                            bus_cycle_state = ADDRESS_BYTES;
                                            if (OPI_IT && (opcode_cnt == 2))
                                                opcode_cnt = 0;
                                        end
                                        else if (OPI_IT && (opcode_cnt == 1))
                                        begin
                                            bus_cycle_state = OPCODE_BYTE;
                                        end
                                    end
                                end

                                8'b11100001 : // E1h
                                begin
                                    Instruct = WRDYB_4_1;
                                    if (~SDRDDR)
                                    begin
                                        if (WRPGEN == 1)
                                        begin
                                            if ((~OPI_IT) || (OPI_IT && (opcode_cnt == 2)))
                                            begin
                                                bus_cycle_state = ADDRESS_BYTES;
                                                if (OPI_IT && (opcode_cnt == 2))
                                                    opcode_cnt = 0;
                                            end
                                            else if (OPI_IT && (opcode_cnt == 1))
                                            begin
                                                bus_cycle_state = OPCODE_BYTE;
                                            end
                                        end
                                        else
                                            bus_cycle_state = STAND_BY;
                                    end
                                end

                                8'b11100010 : // E2h
                                begin
                                    Instruct = RDPPB_4_0;
                                    if (~SDRDDR)
                                    begin
                                        if ((~OPI_IT) || (OPI_IT && (opcode_cnt == 2)))
                                        begin
                                            bus_cycle_state = ADDRESS_BYTES;
                                            if (OPI_IT && (opcode_cnt == 2))
                                                opcode_cnt = 0;
                                        end
                                        else if (OPI_IT && (opcode_cnt == 1))
                                        begin
                                            bus_cycle_state = OPCODE_BYTE;
                                        end
                                    end
                                end

                                8'b11100011 : // E3h
                                begin
                                    Instruct = PRPPB_4_0;
                                    if (~SDRDDR)
                                    begin
                                        if (WRPGEN == 1)
                                        begin
                                            if ((~OPI_IT) || (OPI_IT && (opcode_cnt == 2)))
                                            begin
                                                bus_cycle_state = ADDRESS_BYTES;
                                                if (OPI_IT && (opcode_cnt == 2))
                                                    opcode_cnt = 0;
                                            end
                                            else if (OPI_IT && (opcode_cnt == 1))
                                            begin
                                                bus_cycle_state = OPCODE_BYTE;
                                            end
                                        end
                                        else
                                            bus_cycle_state = STAND_BY;
                                    end
                                end

                                8'b11100100 : // E4h
                                begin
                                    Instruct = ERPPB_0_0;
                                    if (~SDRDDR)
                                    begin
                                        if (WRPGEN == 1)
                                        begin
                                            if ((~OPI_IT) || (OPI_IT && (opcode_cnt == 2)))
                                            begin
                                                bus_cycle_state = DATA_BYTES;
                                                if (OPI_IT && (opcode_cnt == 2))
                                                    opcode_cnt = 0;
                                            end
                                            else if (OPI_IT && (opcode_cnt == 1))
                                            begin
                                                bus_cycle_state = OPCODE_BYTE;
                                            end
                                        end
                                        else 
                                        begin
                                           bus_cycle_state = STAND_BY;
                                       end
                                    end
                                end

                                8'b11101001 : // E9h
                                begin
                                    Instruct = PWDUL_0_1;
                                    if (~SDRDDR)
                                    begin
                                        if (~OPI_IT)
                                        begin
                                            bus_cycle_state = DATA_BYTES;
                                        end
                                        else if (OPI_IT && (opcode_cnt == 2))
                                        begin
                                            bus_cycle_state = ADDRESS_BYTES;
                                            if (OPI_IT && (opcode_cnt == 2))
                                                opcode_cnt = 0;
                                        end
                                        else if (OPI_IT && (opcode_cnt == 1))
                                        begin
                                            bus_cycle_state = OPCODE_BYTE;
                                        end
                                    end
                                end

                                8'b11101100 : // ECh
                                begin
                                    Instruct = RDAY1_4_0;
                                    if (OPI_IT && (opcode_cnt == 2))
                                    begin
                                        bus_cycle_state = ADDRESS_BYTES;
                                        opcode_cnt = 0;
                                    end
                                    else if (OPI_IT && (opcode_cnt == 1))
                                        bus_cycle_state = OPCODE_BYTE;
                                end

                                8'b11101110 : // EEh
                                begin
                                    if (OPI_IT && SDRDDR)
                                        Instruct = RDAY2_4_0;
                                end

                            endcase
                        end
                    end //end of OPCODE BYTE

                    ADDRESS_BYTES :
                    begin
                        if ((Instruct == RDAY2_4_0) && OPI_IT && SDRDDR)
                            DOUBLE = 1'b1;
                        else
                            DOUBLE = 1'b0;

                        if (~SDRDDR)
                        begin
                            if (Instruct == RDARG_4_0)
                            begin
                            //Instruction + 4 Bytes Address + Dummy Byte
                                if (OPI_IT)
                                begin
                                    Address_in[8*addr_cnt]   = IO7_in;
                                    Address_in[8*addr_cnt+1] = IO6_in;
                                    Address_in[8*addr_cnt+2] = IO5_in;
                                    Address_in[8*addr_cnt+3] = IO4_in;
                                    Address_in[8*addr_cnt+4] = IO3_in;
                                    Address_in[8*addr_cnt+5] = IO2_in;
                                    Address_in[8*addr_cnt+6] = SO_in;
                                    Address_in[8*addr_cnt+7] = SI_in;
                                    read_cnt = 0;
                                    addr_cnt = addr_cnt + 1;
                                    if (addr_cnt == 4*BYTE/8)
                                    begin
                                        for(i=31;i>=0;i=i-1)
                                        begin
                                            hiaddr_bytes[31-i] = Address_in[i];
                                        end
                                        Address = {6'b000000,hiaddr_bytes[25:0]};
                                        change_addr = 1'b1;
                                        #1 change_addr = 1'b0;

                                        if (Address >= 32'h00800000) //Volatile REGS
                                        begin
                                            if (Register_Latency == 0)
                                                bus_cycle_state = DATA_BYTES;
                                            else
                                                bus_cycle_state = DUMMY_BYTES;
                                        end 
                                        else // NV REGS
                                        begin
                                            if (Latency_code == 0)
                                                bus_cycle_state = DATA_BYTES;
                                            else
                                                bus_cycle_state = DUMMY_BYTES;
                                        end
                                    end
                                end
                                else
                                begin
                                    Address_in[addr_cnt] = SI_in;
                                    addr_cnt = addr_cnt + 1;

                                    for(i=31;i>=0;i=i-1)
                                    begin
                                        hiaddr_bytes[31-i] = Address_in[i];
                                    end
                                    Address = {6'b000000,hiaddr_bytes[25:0]};
                                    if (addr_cnt == 4*BYTE)
                                    begin
                                        change_addr = 1'b1;
                                        #1 change_addr = 1'b0;

                                        if (Address >= 32'h00800000) //Volatile REGS
                                        begin
                                            if (Register_Latency == 0)
                                                bus_cycle_state = DATA_BYTES;
                                            else
                                                bus_cycle_state = DUMMY_BYTES;
                                        end 
                                        else // NV REGS
                                        begin
                                            if (Latency_code == 0)
                                                bus_cycle_state = DATA_BYTES;
                                            else
                                                bus_cycle_state = DUMMY_BYTES;
                                        end

                                    end
                                end
                            end
                            else if ((Instruct == RDAY2_C_0) && (CFR2V[7]))
                            begin
                            //Instruction + 4 Bytes Address + Dummy Byte
                                Address_in[addr_cnt] = SI_in;
                                addr_cnt = addr_cnt + 1;
                                if (addr_cnt == 4*BYTE)
                                begin
                                    for(i=31;i>=0;i=i-1)
                                    begin
                                        hiaddr_bytes[31-i] = Address_in[i];
                                    end
                                    Address = {6'b000000,hiaddr_bytes[25:0]};
                                    change_addr = 1'b1;
                                    #1 change_addr = 1'b0;

                                    if (Latency_code == 0)
                                        bus_cycle_state = DATA_BYTES;
                                    else
                                        bus_cycle_state = DUMMY_BYTES;
                                end
                            end
                            else if ((Instruct == RDAY2_C_0) && (~CFR2V[7]))
                            begin
                            //Instruction + 3 Bytes Address
                                Address_in[addr_cnt] = SI_in;
                                addr_cnt = addr_cnt + 1;
                                if (addr_cnt == 3*BYTE)
                                begin
                                    for(i=23;i>=0;i=i-1)
                                    begin
                                        addr_bytes[23-i] = Address_in[i];
                                    end
                                    addr_bytes[31:24] = 8'b00000000;
                                    Address = addr_bytes[31:0];
                                    change_addr = 1'b1;
                                    #1 change_addr = 1'b0;

                                    if (Latency_code == 0)
                                        bus_cycle_state = DATA_BYTES;
                                    else
                                        bus_cycle_state = DUMMY_BYTES;
                                end
                            end
                            else if ((Instruct == RDSSR_4_0) || (Instruct == RDECC_4_0))
                            begin
                            //Instruction + 4 Bytes Address + Dummy Byte
                                if (OPI_IT)
                                begin
                                    Address_in[8*addr_cnt]   = IO7_in;
                                    Address_in[8*addr_cnt+1] = IO6_in;
                                    Address_in[8*addr_cnt+2] = IO5_in;
                                    Address_in[8*addr_cnt+3] = IO4_in;
                                    Address_in[8*addr_cnt+4] = IO3_in;
                                    Address_in[8*addr_cnt+5] = IO2_in;
                                    Address_in[8*addr_cnt+6] = SO_in;
                                    Address_in[8*addr_cnt+7] = SI_in;
                                    read_cnt = 0;
                                    addr_cnt = addr_cnt + 1;
                                    if (addr_cnt == 4*BYTE/8)
                                    begin
                                        for(i=31;i>=0;i=i-1)
                                        begin
                                            hiaddr_bytes[31-i] = Address_in[i];
                                        end
                                        Address = {6'b000000,hiaddr_bytes[25:0]};
                                        change_addr = 1'b1;
                                        #1 change_addr = 1'b0;

                                        if (Latency_code == 0)
                                            bus_cycle_state = DATA_BYTES;
                                        else
                                            bus_cycle_state = DUMMY_BYTES;
                                    end
                                end
                                else
                                begin
                                    Address_in[addr_cnt] = SI_in;
                                    addr_cnt = addr_cnt + 1;
                                    if (addr_cnt == 4*BYTE)
                                    begin
                                        for(i=31;i>=0;i=i-1)
                                        begin
                                            hiaddr_bytes[31-i] = Address_in[i];
                                        end
                                        Address = {6'b000000,hiaddr_bytes[25:0]};
                                        change_addr = 1'b1;
                                        #1 change_addr = 1'b0;

                                        if (Latency_code == 0)
                                            bus_cycle_state = DATA_BYTES;
                                        else
                                            bus_cycle_state = DUMMY_BYTES;
                                    end
                                end
                            end 
                            else if (Instruct==RDDYB_4_0)
                            begin
                            //Instruction + 4 Bytes Address + Dummy Byte
                                if (OPI_IT)
                                begin
                                    Address_in[8*addr_cnt]   = IO7_in;
                                    Address_in[8*addr_cnt+1] = IO6_in;
                                    Address_in[8*addr_cnt+2] = IO5_in;
                                    Address_in[8*addr_cnt+3] = IO4_in;
                                    Address_in[8*addr_cnt+4] = IO3_in;
                                    Address_in[8*addr_cnt+5] = IO2_in;
                                    Address_in[8*addr_cnt+6] = SO_in;
                                    Address_in[8*addr_cnt+7] = SI_in;
                                    read_cnt = 0;
                                    addr_cnt = addr_cnt + 1;
                                    if (addr_cnt == 4*BYTE/8)
                                    begin
                                        for(i=31;i>=0;i=i-1)
                                        begin
                                            hiaddr_bytes[31-i] = Address_in[i];
                                        end
                                        Address = {6'b000000,hiaddr_bytes[25:0]};
                                        change_addr = 1'b1;
                                        #1 change_addr = 1'b0;

                                        if (Register_Latency == 0)
                                            bus_cycle_state = DATA_BYTES;
                                        else
                                            bus_cycle_state = DUMMY_BYTES;
                                    end
                                end
                                else
                                begin
                                    Address_in[addr_cnt] = SI_in;
                                    addr_cnt = addr_cnt + 1;
                                    if (addr_cnt == 4*BYTE)
                                    begin
                                        for(i=31;i>=0;i=i-1)
                                        begin
                                            hiaddr_bytes[31-i] = Address_in[i];
                                        end
                                        Address = {6'b000000,hiaddr_bytes[25:0]};
                                        change_addr = 1'b1;
                                        #1 change_addr = 1'b0;

                                        if (Register_Latency == 0)
                                            bus_cycle_state = DATA_BYTES;
                                        else
                                            bus_cycle_state = DUMMY_BYTES;
                                    end
                                end
                            end
                            else if  (Instruct==RDPPB_4_0)
                            begin
                            //Instruction + 4 Bytes Address + Dummy Byte
                                if (OPI_IT)
                                begin
                                    Address_in[8*addr_cnt]   = IO7_in;
                                    Address_in[8*addr_cnt+1] = IO6_in;
                                    Address_in[8*addr_cnt+2] = IO5_in;
                                    Address_in[8*addr_cnt+3] = IO4_in;
                                    Address_in[8*addr_cnt+4] = IO3_in;
                                    Address_in[8*addr_cnt+5] = IO2_in;
                                    Address_in[8*addr_cnt+6] = SO_in;
                                    Address_in[8*addr_cnt+7] = SI_in;
                                    read_cnt = 0;
                                    addr_cnt = addr_cnt + 1;
                                    if (addr_cnt == 4*BYTE/8)
                                    begin
                                        for(i=31;i>=0;i=i-1)
                                        begin
                                            hiaddr_bytes[31-i] = Address_in[i];
                                        end
                                        Address = {6'b000000,hiaddr_bytes[25:0]};
                                        change_addr = 1'b1;
                                        #1 change_addr = 1'b0;

                                        if (Latency_code == 0)
                                            bus_cycle_state = DATA_BYTES;
                                        else
                                            bus_cycle_state = DUMMY_BYTES;
                                    end
                                end
                                else
                                begin
                                    Address_in[addr_cnt] = SI_in;
                                    addr_cnt = addr_cnt + 1;
                                    if (addr_cnt == 4*BYTE)
                                    begin
                                        for(i=31;i>=0;i=i-1)
                                        begin
                                            hiaddr_bytes[31-i] = Address_in[i];
                                        end
                                        Address = {6'b000000,hiaddr_bytes[25:0]};
                                        change_addr = 1'b1;
                                        #1 change_addr = 1'b0;

                                        if (Latency_code == 0)
                                            bus_cycle_state = DATA_BYTES;
                                        else
                                            bus_cycle_state = DUMMY_BYTES;
                                    end
                                end
                            end
                            else if (Instruct==RDPLB_4_0 || Instruct == RDSR1 
                            || Instruct == RDSR2) 
                            begin
                            //Instruction + 4 Bytes Address + Dummy Byte
                                Address_in[8*addr_cnt]   = IO7_in;
                                Address_in[8*addr_cnt+1] = IO6_in;
                                Address_in[8*addr_cnt+2] = IO5_in;
                                Address_in[8*addr_cnt+3] = IO4_in;
                                Address_in[8*addr_cnt+4] = IO3_in;
                                Address_in[8*addr_cnt+5] = IO2_in;
                                Address_in[8*addr_cnt+6] = SO_in;
                                Address_in[8*addr_cnt+7] = SI_in;
                                read_cnt = 0;
                                addr_cnt = addr_cnt + 1;
                                if (addr_cnt == 4*BYTE/8)
                                begin
                                    for(i=31;i>=0;i=i-1)
                                    begin
                                        hiaddr_bytes[31-i] = Address_in[i];
                                    end
                                    Address = 32'h00000000;
                                    change_addr = 1'b1;
                                    #1 change_addr = 1'b0;

                                    if (Register_Latency == 0)
                                        bus_cycle_state = DATA_BYTES;
                                    else
                                        bus_cycle_state = DUMMY_BYTES;
                                end
                            end
                            else if (Instruct == PWDUL_0_1) 
                            begin
                            //Instruction + 4 Bytes Address + Dummy Byte
                                Address_in[8*addr_cnt]   = IO7_in;
                                Address_in[8*addr_cnt+1] = IO6_in;
                                Address_in[8*addr_cnt+2] = IO5_in;
                                Address_in[8*addr_cnt+3] = IO4_in;
                                Address_in[8*addr_cnt+4] = IO3_in;
                                Address_in[8*addr_cnt+5] = IO2_in;
                                Address_in[8*addr_cnt+6] = SO_in;
                                Address_in[8*addr_cnt+7] = SI_in;
                                read_cnt = 0;
                                addr_cnt = addr_cnt + 1;
                                if (addr_cnt == 4*BYTE/8)
                                begin
                                    for(i=31;i>=0;i=i-1)
                                    begin
                                        hiaddr_bytes[31-i] = Address_in[i];
                                    end
                                    Address = 32'h00000000;
                                    change_addr = 1'b1;
                                    #1 change_addr = 1'b0;

                                        bus_cycle_state = DATA_BYTES;

                                end
                            end
                            else if (Instruct == DICHK_4_1)
                            begin
                            // Instruction + 4 Bytes Address
                                if (OPI_IT)
                                begin
                                    Address_in[8*(addr_cnt % 4)]   = IO7_in;
                                    Address_in[8*(addr_cnt % 4)+1] = IO6_in;
                                    Address_in[8*(addr_cnt % 4)+2] = IO5_in;
                                    Address_in[8*(addr_cnt % 4)+3] = IO4_in;
                                    Address_in[8*(addr_cnt % 4)+4] = IO3_in;
                                    Address_in[8*(addr_cnt % 4)+5] = IO2_in;
                                    Address_in[8*(addr_cnt % 4)+6] = SO_in;
                                    Address_in[8*(addr_cnt % 4)+7] = SI_in;
                                    read_cnt = 0;
                                    addr_cnt = addr_cnt + 1;
                                    if (addr_cnt == 4*BYTE/8)
                                    begin
                                        for(i=31;i>=0;i=i-1)
                                        begin
                                            hiaddr_bytes[31-i] = Address_in[i];
                                        end
                                        Address = {6'b000000,hiaddr_bytes[25:0]};
                                        change_addr = 1'b1;
                                        #1 change_addr = 1'b0;
                                    end
                                    if (addr_cnt == BYTE)
                                    begin
                                        addr_cnt = 0;
                                        for(i=31;i>=0;i=i-1)
                                        begin
                                            hiaddr_bytes[31-i] = Address_in[i];
                                        end
                                        //High order address bits are ignored
                                        Address = {6'b000000,hiaddr_bytes[25:0]};
                                        change_addr = 1'b1;
                                        #1 change_addr = 1'b0;
    
                                        bus_cycle_state = DATA_BYTES;
                                    end
                                end
                                else
                                begin
                                    Address_in[addr_cnt % 32] = SI_in;
                                    addr_cnt = addr_cnt + 1;
                                    if (addr_cnt == 4*BYTE)
                                    begin
                                        for(i=31;i>=0;i=i-1)
                                        begin
                                            hiaddr_bytes[31-i] = Address_in[i];
                                        end
                                        Address = {6'b000000,hiaddr_bytes[25:0]};
                                        change_addr = 1'b1;
                                        #1 change_addr = 1'b0;
                                    end
                                    if (addr_cnt == 8*BYTE)
                                    begin
                                        addr_cnt = 0;
                                        for(i=31;i>=0;i=i-1)
                                        begin
                                            hiaddr_bytes[31-i] = Address_in[i];
                                        end
                                        //High order address bits are ignored
                                        Address = {6'b000000,hiaddr_bytes[25:0]};
                                        change_addr = 1'b1;
                                        #1 change_addr = 1'b0;

                                        bus_cycle_state = DATA_BYTES;
                                    end
                                end
                            end
                            else if ((Instruct == RDAY1_C_0) && (~CFR2V[7]))
                            begin
                            //Instruction + 3 Bytes Address
                                Address_in[addr_cnt] = SI_in;
                                addr_cnt = addr_cnt + 1;
                                if (addr_cnt == 3*BYTE)
                                begin
                                    for(i=23;i>=0;i=i-1)
                                    begin
                                        addr_bytes[23-i] = Address_in[i];
                                    end
                                    addr_bytes[31:24] = 8'b00000000;
                                    Address = addr_bytes;
                                    change_addr = 1'b1;
                                    #1 change_addr = 1'b0;

                                    bus_cycle_state = DATA_BYTES;
                                end
                            end
                            else if ((Instruct == RDAY1_C_0) && CFR2V[7])
                            begin
                            //Instruction + 4 Bytes Address
                                Address_in[addr_cnt] = SI_in;
                                addr_cnt = addr_cnt + 1;
                                if (addr_cnt == 4*BYTE)
                                begin
                                    for(i=31;i>=0;i=i-1)
                                    begin
                                        hiaddr_bytes[31-i] = Address_in[i];
                                    end
                                    Address = {6'b000000,hiaddr_bytes[25:0]};
                                    change_addr = 1'b1;
                                    #1 change_addr = 1'b0;

                                    bus_cycle_state = DATA_BYTES;
                                end
                            end
                            else if (Instruct == RDAY1_4_0)
                            begin
                            //Instruction + 4 Bytes Address + Dummy Byte
                                if (OPI_IT)
                                begin
                                    Address_in[8*addr_cnt]   = IO7_in;
                                    Address_in[8*addr_cnt+1] = IO6_in;
                                    Address_in[8*addr_cnt+2] = IO5_in;
                                    Address_in[8*addr_cnt+3] = IO4_in;
                                    Address_in[8*addr_cnt+4] = IO3_in;
                                    Address_in[8*addr_cnt+5] = IO2_in;
                                    Address_in[8*addr_cnt+6] = SO_in;
                                    Address_in[8*addr_cnt+7] = SI_in;
                                    read_cnt = 0;
                                    addr_cnt = addr_cnt + 1;
                                    if (addr_cnt == 4*BYTE/8)
                                    begin
                                        for(i=31;i>=0;i=i-1)
                                        begin
                                            hiaddr_bytes[31-i] = Address_in[i];
                                        end
                                        Address = {6'b000000,hiaddr_bytes[25:0]};
                                        change_addr = 1'b1;
                                        #1 change_addr = 1'b0;

                                        if (Latency_code == 0)
                                            bus_cycle_state = DATA_BYTES;
                                        else
                                            bus_cycle_state = DUMMY_BYTES;
                                    end
                                end
                                else
                                begin
                                //Instruction + 4 Bytes Address
                                    Address_in[addr_cnt] = SI_in;
                                    addr_cnt = addr_cnt + 1;
                                    if (addr_cnt == 4*BYTE)
                                    begin
                                        for(i=31;i>=0;i=i-1)
                                        begin
                                            hiaddr_bytes[31-i] = Address_in[i];
                                        end
                                        Address = {6'b000000,hiaddr_bytes[25:0]};
                                        change_addr = 1'b1;
                                        #1 change_addr = 1'b0;

                                        bus_cycle_state = DATA_BYTES;
                                    end
                                end
                            end
                            else if ((Instruct == PRPGE_4_1) || (Instruct == ER256_4_0) ||
                                    (Instruct == WRDYB_4_1) || (Instruct == PRPPB_4_0) ||
                                    (Instruct == ER004_4_0) || (Instruct == EVERS_4_0) ||
                                    (Instruct == PRSSR_4_1) || (Instruct == SEERC_4_0))
                            begin
                            //Instruction + 4 Bytes Address
                                if (OPI_IT)
                                begin
                                    Address_in[8*addr_cnt]   = IO7_in;
                                    Address_in[8*addr_cnt+1] = IO6_in;
                                    Address_in[8*addr_cnt+2] = IO5_in;
                                    Address_in[8*addr_cnt+3] = IO4_in;
                                    Address_in[8*addr_cnt+4] = IO3_in;
                                    Address_in[8*addr_cnt+5] = IO2_in;
                                    Address_in[8*addr_cnt+6] = SO_in;
                                    Address_in[8*addr_cnt+7] = SI_in;
                                    read_cnt = 0;
                                    addr_cnt = addr_cnt + 1;
                                    if (addr_cnt == 4*BYTE/8)
                                    begin
                                        for(i=31;i>=0;i=i-1)
                                        begin
                                            hiaddr_bytes[31-i] = Address_in[i];
                                        end
                                        Address = {6'b000000,hiaddr_bytes[25:0]};
                                        change_addr = 1'b1;
                                        #1 change_addr = 1'b0;

                                        bus_cycle_state = DATA_BYTES;
                                    end
                                end
                                else
                                begin
                                    Address_in[addr_cnt] = SI_in;
                                    addr_cnt = addr_cnt + 1;
                                    if (addr_cnt == 4*BYTE)
                                    begin
                                        for(i=31;i>=0;i=i-1)
                                        begin
                                            hiaddr_bytes[31-i] = Address_in[i];
                                        end
                                        Address = {6'b000000,hiaddr_bytes[25:0]};
                                        change_addr = 1'b1;
                                        #1 change_addr = 1'b0;

                                        bus_cycle_state = DATA_BYTES;
                                    end
                                end
                            end
                            else if (Instruct == WRARG_4_1)
                            begin
                                Address_in[8*addr_cnt]   = IO7_in;
                                Address_in[8*addr_cnt+1] = IO6_in;
                                Address_in[8*addr_cnt+2] = IO5_in;
                                Address_in[8*addr_cnt+3] = IO4_in;
                                Address_in[8*addr_cnt+4] = IO3_in;
                                Address_in[8*addr_cnt+5] = IO2_in;
                                Address_in[8*addr_cnt+6] = SO_in;
                                Address_in[8*addr_cnt+7] = SI_in;
                                read_cnt = 0;
                                addr_cnt = addr_cnt + 1;
                                if (addr_cnt == 4*BYTE/8)
                                begin
                                    for(i=31;i>=0;i=i-1)
                                    begin
                                        hiaddr_bytes[31-i] = Address_in[i];
                                    end
                                    //High order address bits are ignored
                                    Address = {6'b000000,hiaddr_bytes[25:0]};
                                    change_addr = 1'b1;
                                    #1 change_addr = 1'b0;

                                    bus_cycle_state = DATA_BYTES;
                                end
                            end
                            else if ((Instruct == WRARG_C_1) && (CFR2V[7]))
                            begin
                                //Instruction + 4 Bytes Address
                                Address_in[addr_cnt] = SI_in;
                                addr_cnt = addr_cnt + 1;
                                if (addr_cnt == 4*BYTE)
                                begin
                                    for(i=31;i>=0;i=i-1)
                                    begin
                                        hiaddr_bytes[31-i] = Address_in[i];
                                    end
                                    Address = {6'b000000,hiaddr_bytes[25:0]};
                                    change_addr = 1'b1;
                                    #1 change_addr = 1'b0;

                                    bus_cycle_state = DATA_BYTES;
                                end
                            end
                            else if ((Instruct == WRARG_C_1) && (~CFR2V[7]))
                            begin
                            //Instruction + 3 Bytes Address
                                Address_in[addr_cnt] = SI_in;
                                addr_cnt = addr_cnt + 1;
                                if (addr_cnt == 3*BYTE)
                                begin
                                    for(i=23;i>=0;i=i-1)
                                    begin
                                        addr_bytes[23-i] = Address_in[i];
                                    end
                                    addr_bytes[31:24] = 8'b00000000;
                                    Address = addr_bytes;
                                    change_addr = 1'b1;
                                    #1 change_addr = 1'b0;

                                    bus_cycle_state = DATA_BYTES;
                                end
                            end
                            else if (Instruct == RSFDP)
                            begin
                            // Instruction + 4 Bytes Address + Dummy Byte
                                if (OPI_IT)
                                begin
                                    Address_in[8*addr_cnt]   = IO7_in;
                                    Address_in[8*addr_cnt+1] = IO6_in;
                                    Address_in[8*addr_cnt+2] = IO5_in;
                                    Address_in[8*addr_cnt+3] = IO4_in;
                                    Address_in[8*addr_cnt+4] = IO3_in;
                                    Address_in[8*addr_cnt+5] = IO2_in;
                                    Address_in[8*addr_cnt+6] = SO_in;
                                    Address_in[8*addr_cnt+7] = SI_in;
                                    read_cnt = 0;
                                    addr_cnt = addr_cnt + 1;
                                    if (addr_cnt == 4*BYTE/8)
                                    begin
                                        addr_cnt = 0;
                                        for(i=23;i>=0;i=i-1)
                                        begin
                                            addr_bytes[23-i] = Address_in[i];
                                        end
                                        addr_bytes[31:24] = 8'b00000000;
                                        Address = addr_bytes;
                                        change_addr = 1'b1;
                                        #1 change_addr = 1'b0;

                                        bus_cycle_state = DUMMY_BYTES;
                                    end
                                end
                                else // Instruction + 3 Bytes Address + Dummy Byte
                                begin
                                    Address_in[addr_cnt] = SI_in;
                                    addr_cnt = addr_cnt + 1;
                                    if (addr_cnt == 3*BYTE)
                                    begin
                                        addr_cnt = 0;
                                        for(i=23;i>=0;i=i-1)
                                        begin
                                            addr_bytes[23-i] = Address_in[i];
                                        end
                                        addr_bytes[31:24] = 8'b00000000;
                                        Address = addr_bytes;
                                        change_addr = 1'b1;
                                        #1 change_addr = 1'b0;

                                        bus_cycle_state = DUMMY_BYTES;
                                    end
                                end
                            end
                            else if (Instruct == RDIDN)
                            begin
                            // Instruction + 4 Bytes Address + Dummy Byte
                                if (OPI_IT)
                                begin
                                    read_cnt = 0;
                                    addr_cnt = addr_cnt + 1;
                                    if (addr_cnt == 4*BYTE/8)
                                    begin
                                        addr_cnt = 0;
                                        addr_bytes[31:0] = 32'h00000000;
                                        Address = addr_bytes;
                                        change_addr = 1'b1;
                                        #1 change_addr = 1'b0;

                                        if (Register_Latency == 0)
                                            bus_cycle_state = DATA_BYTES;
                                        else
                                            bus_cycle_state = DUMMY_BYTES;
                                    end
                                end
                            end
                            else
                            begin
                            //Instruction + 4 Bytes Address
                                Address_in[addr_cnt] = SI_in;
                                addr_cnt = addr_cnt + 1;
                                if (addr_cnt == 4*BYTE)
                                begin
                                    for(i=31;i>=0;i=i-1)
                                    begin
                                        hiaddr_bytes[31-i] = Address_in[i];
                                    end
                                    Address = {6'b000000,hiaddr_bytes[25:0]};
                                    change_addr = 1'b1;
                                    #1 change_addr = 1'b0;

                                    bus_cycle_state = DATA_BYTES;
                                end
                            end
                        end
                        else // SDRDDR = 1'b1
                        begin
                            if ((Instruct == RDARG_4_0) || (Instruct == WRARG_4_1) ||
                                (Instruct == RDECC_4_0) || (Instruct == RSFDP)     ||
                                (Instruct == RDDYB_4_0) || (Instruct == RDPPB_4_0) ||
                                (Instruct == PRPGE_4_1) || (Instruct == ER256_4_0) ||
                                (Instruct == WRDYB_4_1) || (Instruct == PRPPB_4_0) ||
                                (Instruct == ER004_4_0) || (Instruct == EVERS_4_0) ||
                                (Instruct == PRSSR_4_1) || (Instruct == RDAY2_4_0) ||
                                (Instruct == SEERC_4_0) || (Instruct == RDPLB_4_0) ||
                                (Instruct == RDSR1)     || (Instruct == RDSSR_4_0) ||
                                (Instruct == PWDUL_0_1) || (Instruct == RDSR2))
                            begin
                            //OCTAL I/O DDR Read Mode (4 Bytes Address)
                                if (OPI_IT)
                                begin
                                    Address_in[8*addr_cnt]   = IO7_in;
                                    Address_in[8*addr_cnt+1] = IO6_in;
                                    Address_in[8*addr_cnt+2] = IO5_in;
                                    Address_in[8*addr_cnt+3] = IO4_in;
                                    Address_in[8*addr_cnt+4] = IO3_in;
                                    Address_in[8*addr_cnt+5] = IO2_in;
                                    Address_in[8*addr_cnt+6] = SO_in;
                                    Address_in[8*addr_cnt+7] = SI_in;

                                    addr_cnt = addr_cnt + 1;
                                    read_cnt = 0;
                                end
                            end
                            else if (Instruct == RDIDN)
                            begin
                            // Instruction + 4 Bytes Address + Dummy Byte
                                if (OPI_IT)
                                begin
                                    read_cnt = 0;
                                    addr_cnt = addr_cnt + 1;
                                    if (addr_cnt == 4*BYTE/8)
                                    begin
                                        addr_cnt = 0;
                                        addr_bytes[31:0] = 32'h00000000;
                                        Address = addr_bytes;
                                        change_addr = 1'b1;
                                        #1 change_addr = 1'b0;
                                        bus_cycle_state = DUMMY_BYTES;
                                    end
                                end
                            end
                            else if (Instruct == RDCRC_4_0)
                            begin
                            // Instruction + 4 Bytes Address + Dummy Byte
                                if (OPI_IT)
                                begin
                                    read_cnt = 0;
                                    addr_cnt = addr_cnt + 1;
                                    if (addr_cnt == 4*BYTE/8)
                                    begin
                                        addr_cnt = 0;
                                        addr_bytes[31:0] = 32'h00000000;
                                        Address = addr_bytes;
                                        change_addr = 1'b1;
                                        #1 change_addr = 1'b0;
                                        bus_cycle_state = DUMMY_BYTES;
                                    end
                                end
                            end
                            else if (Instruct == DICHK_4_1)
                            begin
                            // Instruction + 4 Bytes Address
                                if (OPI_IT)
                                begin
                                    Address_in[8*(addr_cnt % 4)]   = IO7_in;
                                    Address_in[8*(addr_cnt % 4)+1] = IO6_in;
                                    Address_in[8*(addr_cnt % 4)+2] = IO5_in;
                                    Address_in[8*(addr_cnt % 4)+3] = IO4_in;
                                    Address_in[8*(addr_cnt % 4)+4] = IO3_in;
                                    Address_in[8*(addr_cnt % 4)+5] = IO2_in;
                                    Address_in[8*(addr_cnt % 4)+6] = SO_in;
                                    Address_in[8*(addr_cnt % 4)+7] = SI_in;
                                    read_cnt = 0;
                                    addr_cnt = addr_cnt + 1;
                                end
                            end
                        end

                    end //end of ADDRESS_BYTES

                    MODE_BYTE :
                    begin
                        dummy_cnt = 0;
                    end //end of MODE_BYTE

                    DUMMY_BYTES :
                    begin
                        dummy_cnt = dummy_cnt + 1;
                        if ((Instruct == RDSR1) || (Instruct == RDSR2) || 
                        (Instruct == RDPLB_0_0) || (Instruct == RDPLB_4_0) ||
                        (Instruct == RDDYB_4_0) || (Instruct == RDIDN) ||
                         (Instruct == RSFDP) || (Instruct == RDCRC_4_0) || 
                         (Instruct == RDARG_4_0) || (Instruct == RDAY1_4_0) ||
                         (Instruct == RDAY2_4_0) || (Instruct == RDSSR_4_0))
                          if (dummy_cnt == 5 && DATA_STROBE && SDRDDR && OPI_IT)
                            begin
                                DataDriveOut_DS = 1'b0;
                            end
                    end //end of DUMMY_BYTES

                    DATA_BYTES :
                    begin
                        if (((Instruct == RDAY2_4_0) || (Instruct == RDPLB_4_0))
                              && OPI_IT && SDRDDR)
                        begin
                            read_out = 1'b1;
                            read_out <= #1 1'b0;
                            if (DATA_STROBE)
                                    DataDriveOut_DS = ~DataDriveOut_DS;
                        end
                        else if ( ((Instruct == RDAY1_4_0) ||
                            (Instruct == RDSR1)     || (Instruct == RDSR2)     ||
                            (Instruct == RDUID)     || (Instruct == RDSSR_4_0) ||
                            (Instruct == RDIDN)     || (Instruct == RDPLB_0_0) ||
                            (Instruct == RDPPB_4_0) || (Instruct == RDDYB_4_0) ||
                            (Instruct == RDECC_4_0) || (Instruct == RDCRC_4_0) ||
                            (Instruct == RSFDP)     || (Instruct == RDARG_4_0)) && SDRDDR)
                        begin
                            read_out = 1'b1;
                            read_out <= #1 1'b0;
                            if (DATA_STROBE)
                                    DataDriveOut_DS = ~DataDriveOut_DS;
                        end

                        if (OPI_IT)
                        begin
                            octal_byte = {IO7_in, IO6_in, IO5_in, IO4_in, IO3_in, IO2_in, SO_in, SI_in};
                            if (data_cnt > (PageSize))
                            begin
                            //In case of octal mode,if more than PageSize+1 bytes
                            //are sent to the device previously latched data
                            //are discarded and last 256/512 data bytes are
                            //guaranteed to be programmed correctly within
                            //the same page.
                                for(i=0;i<=(PageSize-1);i=i+1)
                                begin
                                    octal_data_in[i] = octal_data_in[i+1];
                                end
                                octal_data_in[PageSize] = octal_byte;
                                data_cnt = data_cnt + 1;
                            end
                            else
                            begin
                                if (octal_byte !== 8'bZZZZZZZZ)
                                begin
                                    octal_data_in[data_cnt] = octal_byte;
                                end
                                data_cnt = data_cnt + 1;
                                if ((DATA_STROBE && ~DS_OPI) &&
                                   ((Instruct == RDAY1_C_0) || (Instruct == RDAY1_4_0) ||
                                    (Instruct == RDAY2_C_0) || (Instruct == RDAY2_4_0) ||
                                    (Instruct == RDSR1)     || (Instruct == RDSR2)     ||
                                    (Instruct == RDUID)     || (Instruct == RDSSR_4_0) ||
                                    (Instruct == RDIDN)     || (Instruct == RDPLB_0_0) || 
                                    (Instruct == RDPLB_4_0)     ||
                                    (Instruct == RDPPB_4_0) || (Instruct == RDDYB_4_0) ||
                                    (Instruct == RDECC_4_0) || (Instruct == RDCRC_4_0) ||
                                    (Instruct == RSFDP)     || (Instruct == RDARG_4_0)))
                                        DataDriveOut_DS = ~DataDriveOut_DS;
                                
                            end
                        end
                        else
                        begin
                            if (data_cnt > ((PageSize+1)*8-1))
                            begin
                            //In case of serial mode and PP,
                            //if more than PageSize are sent to the device
                            //previously latched data are discarded and last
                            //256/512 data bytes are guaranteed to be programmed
                            //correctly within the same page.
                                if (bit_cnt == 0)
                                begin
                                    for(i=0;i<=(PageSize*BYTE-1);i=i+1)
                                    begin
                                        Data_in[i] = Data_in[i+8];
                                    end
                                end
                                Data_in[PageSize*BYTE + bit_cnt] = SI_in;
                                bit_cnt = bit_cnt + 1;
                                if (bit_cnt == 8)
                                begin
                                    bit_cnt = 0;
                                end
                                data_cnt = data_cnt + 1;
                            end
                            else
                            begin
                                Data_in[data_cnt] = SI_in;
                                data_cnt = data_cnt + 1;
                                bit_cnt = 0;
                            end
                        end
                    end //end of DATA_BYTES

                endcase
            end
        end

        if (falling_edge_SCK_ipd)
        begin

            if (~CSNeg_ipd)
            begin
                case (bus_cycle_state)
                    OPCODE_BYTE:
                    begin
                        if (OPI_IT && SDRDDR)
                        begin
                            opcode_in[0] = IO7_in;
                            opcode_in[1] = IO6_in;
                            opcode_in[2] = IO5_in;
                            opcode_in[3] = IO4_in;
                            opcode_in[4] = IO3_in;
                            opcode_in[5] = IO2_in;
                            opcode_in[6] = SO_in;
                            opcode_in[7] = SI_in;

                            opcode_cnt = opcode_cnt + 1;

                            if (opcode_cnt == 2)
                            begin
                                for(i=7;i>=0;i=i-1)
                                begin
                                    opcode[i] = opcode_in[7-i];
                                end
                                case (opcode)

                                    8'b00000100 : // 04h
                                    begin
                                        Instruct = WRDIS_0_0;
                                        bus_cycle_state = DATA_BYTES;
                                        opcode_cnt = 0;
                                    end

                                    8'b00000101 : // 05h
                                    begin
                                        Instruct = RDSR1;
                                        bus_cycle_state = ADDRESS_BYTES;
                                        opcode_cnt = 0;
                                    end

                                    8'b00000110 : // 06h
                                    begin
                                        Instruct = WRENB_0_0;
                                        bus_cycle_state = DATA_BYTES;
                                        opcode_cnt = 0;
                                    end

                                    8'b00000111 : // 07h
                                    begin
                                        Instruct = RDSR2;
                                        bus_cycle_state = ADDRESS_BYTES;
                                        opcode_cnt = 0;
                                    end

                                    8'b00010010 : // 12h
                                    begin
                                        Instruct = PRPGE_4_1;
                                        if (WRPGEN == 1)
                                            bus_cycle_state = ADDRESS_BYTES;
                                        else
                                            bus_cycle_state = STAND_BY;

                                        opcode_cnt = 0;
                                    end

                                    8'b00011001 : // 19h
                                    begin
                                        Instruct = RDECC_4_0;
                                        bus_cycle_state = ADDRESS_BYTES;
                                        CHECK_FREQ = 1'b1;
                                        opcode_cnt = 0;
                                    end

                                    8'b00011011 : // 1Bh
                                    begin
                                        Instruct = CLECC_0_0;
                                        if (WRPGEN == 1)
                                        bus_cycle_state = DATA_BYTES;
                                        else
                                        bus_cycle_state = STAND_BY;
                                        opcode_cnt = 0;
                                    end

                                    8'b00100001 : // 21h
                                    begin
                                        Instruct = ER004_4_0;
                                        if (WRPGEN == 1 && ~UNHYSA)
                                            bus_cycle_state = ADDRESS_BYTES;
                                        else
                                            bus_cycle_state = STAND_BY;

                                        opcode_cnt = 0;
                                    end

                                    8'b00101100 : // 2Ch
                                    begin
                                        Instruct = WRPLB_0_0;
                                        if (WRPGEN == 1)
                                            bus_cycle_state = DATA_BYTES;
                                        else
                                            bus_cycle_state = STAND_BY;

                                        opcode_cnt = 0;
                                    end

                                    8'b00101101 : // 2Dh
                                    begin
                                        Instruct = RDPLB_4_0; // RDPLB
                                        bus_cycle_state = ADDRESS_BYTES;
                                        opcode_cnt = 0;
                                    end

                                    8'b00110000 : // 30h
                                    begin
                                        Instruct = RSEPD_0_0;
                                        bus_cycle_state = DATA_BYTES;
                                        opcode_cnt = 0;
                                    end

                                    8'b01000010 : // 42h
                                    begin
                                        Instruct = PRSSR_4_1;
                                        if (WRPGEN == 1)
                                            bus_cycle_state = ADDRESS_BYTES;
                                        else
                                            bus_cycle_state = STAND_BY;

                                        opcode_cnt = 0;
                                    end
                                    
                                    8'b01001011 : // 4Bh
                                    begin
                                        Instruct = RDSSR_4_0;
                                        bus_cycle_state = ADDRESS_BYTES;
                                        CHECK_FREQ = 1'b1;
                                        opcode_cnt = 0;
                                    end

                                    8'b01001100 : // 4Ch
                                    begin
                                        Instruct = RDUID;
                                        bus_cycle_state = DUMMY_BYTES;
                                        opcode_cnt = 0;
                                    end

                                    8'b01011010 : // 5Ah
                                    begin
                                        Instruct = RSFDP;
                                        bus_cycle_state = ADDRESS_BYTES;
                                        opcode_cnt = 0;
                                    end

                                    8'b01011011 : // 5Bh
                                    begin
                                        Instruct = DICHK_4_1;
                                        bus_cycle_state = DUMMY_BYTES;
                                        opcode_cnt = 0;
                                    end

                                    8'b01011101 : // 5Dh
                                    begin
                                        Instruct = SEERC_4_0;
                                        bus_cycle_state = ADDRESS_BYTES;
                                        opcode_cnt = 0;
                                    end

                                    8'b01100000 : // 60h
                                    begin
                                        Instruct = ERCHP_0_0;
                                        if (WRPGEN == 1)
                                            bus_cycle_state = DATA_BYTES;
                                        else
                                            bus_cycle_state = STAND_BY;

                                        opcode_cnt = 0;
                                    end

                                    8'b01100100 : // 64h
                                    begin
                                        Instruct = RDCRC_4_0;
                                        bus_cycle_state = ADDRESS_BYTES;
                                        opcode_cnt = 0;
                                    end

                                    8'b01100101 : // 65h
                                    begin
                                        Instruct = RDARG_4_0;
                                        bus_cycle_state = ADDRESS_BYTES;
                                        opcode_cnt = 0;
                                    end

                                    8'b01100110 : // 66h
                                    begin
                                        Instruct = SRSTE_0_0;
                                        bus_cycle_state = DATA_BYTES;
                                        opcode_cnt = 0;
                                    end

                                    8'b01110001 : // 71h
                                    begin
                                        Instruct = WRARG_4_1;
                                        if (WRPGEN == 1)
                                            bus_cycle_state = ADDRESS_BYTES;
                                        else
                                            bus_cycle_state = STAND_BY;

                                        opcode_cnt = 0;
                                    end

                                    8'b10000010 : // 82h
                                    begin
                                        Instruct = CLPEF_0_0;
                                        bus_cycle_state = DATA_BYTES;
                                        opcode_cnt = 0;
                                    end

                                    8'b10011001 : // 99h
                                    begin
                                        Instruct = SFRST_0_0;
                                        bus_cycle_state = DATA_BYTES;
                                        opcode_cnt = 0;
                                    end

                                    8'b10011111 : // 9Fh
                                    begin
                                        Instruct = RDIDN;
                                        bus_cycle_state = ADDRESS_BYTES;
                                        opcode_cnt = 0;
                                    end

                                    8'b10110000 : // B0h
                                    begin
                                        Instruct = SPEPD_0_0;
                                        bus_cycle_state = DATA_BYTES;
                                        opcode_cnt = 0;
                                    end

                                    8'b10111001 : // B9h
                                    begin
                                        Instruct = ENDPD_0_0;
                                        bus_cycle_state = DATA_BYTES;
                                        opcode_cnt = 0;
                                    end

                                    8'b11000111 : // C7h
                                    begin
                                        Instruct = ERCHP_0_0;
                                        if (WRPGEN == 1)
                                            bus_cycle_state = DATA_BYTES;
                                        else
                                            bus_cycle_state = STAND_BY;

                                        opcode_cnt = 0;
                                    end

                                    8'b11010000 : // D0h
                                    begin
                                        Instruct = EVERS_4_0;
                                        bus_cycle_state = ADDRESS_BYTES;
                                        opcode_cnt = 0;
                                    end

                                    8'b11011100 : // DCh
                                    begin
                                        Instruct = ER256_4_0;
                                        if (WRPGEN == 1)
                                            bus_cycle_state = ADDRESS_BYTES;
                                        else
                                            bus_cycle_state = STAND_BY;

                                        opcode_cnt = 0;
                                    end

                                    8'b11100000 : // E0h
                                    begin
                                        Instruct = RDDYB_4_0;
                                        bus_cycle_state = ADDRESS_BYTES;
                                        opcode_cnt = 0;
                                    end

                                    8'b11100001 : // E1h
                                    begin
                                        Instruct = WRDYB_4_1;
                                        if (WRPGEN == 1)
                                            bus_cycle_state = ADDRESS_BYTES;
                                        else
                                            bus_cycle_state = STAND_BY;

                                        opcode_cnt = 0;
                                    end

                                    8'b11100010 : // E2h
                                    begin
                                        Instruct = RDPPB_4_0;
                                        bus_cycle_state = ADDRESS_BYTES;
                                        opcode_cnt = 0;
                                    end

                                    8'b11100011 : // E3h
                                    begin
                                        Instruct = PRPPB_4_0;
                                        if (WRPGEN == 1)
                                            bus_cycle_state = ADDRESS_BYTES;
                                        else
                                            bus_cycle_state = STAND_BY;

                                        opcode_cnt = 0;
                                    end

                                     8'b11100100 : // E4h
                                     begin
                                         Instruct = ERPPB_0_0;
                                         bus_cycle_state = DATA_BYTES;
                                         opcode_cnt = 0;
                                     end

                                    8'b11101001 : // E9h
                                    begin
                                        Instruct = PWDUL_0_1;
                                        bus_cycle_state = ADDRESS_BYTES;
                                        opcode_cnt = 0;
                                    end

                                    8'b11101110 : // EEh
                                    begin
                                        Instruct = RDAY2_4_0;
                                        bus_cycle_state = ADDRESS_BYTES;
                                        opcode_cnt = 0;
                                            //CHECK_FREQ = 1'b1;
                                    end
                                endcase
                            end
                        end
                    end //end of OPCODE BYTE

                    ADDRESS_BYTES :
                    begin
                        if ((Instruct == DICHK_4_1) && ~OPI_IT)
                        begin
                            if (addr_cnt == 4*BYTE)
                                CRC_Start_Addr_reg = Address;
                        end

                        if (OPI_IT && SDRDDR)
                        begin
                            if (Instruct == DICHK_4_1)
                            begin
                            // Instruction + 4 Bytes Address
                                Address_in[8*(addr_cnt % 4)]   = IO7_in;
                                Address_in[8*(addr_cnt % 4)+1] = IO6_in;
                                Address_in[8*(addr_cnt % 4)+2] = IO5_in;
                                Address_in[8*(addr_cnt % 4)+3] = IO4_in;
                                Address_in[8*(addr_cnt % 4)+4] = IO3_in;
                                Address_in[8*(addr_cnt % 4)+5] = IO2_in;
                                Address_in[8*(addr_cnt % 4)+6] = SO_in;
                                Address_in[8*(addr_cnt % 4)+7] = SI_in;
                                if (addr_cnt != 0)
                                begin
                                    addr_cnt = addr_cnt + 1;
                                end
                                read_cnt = 0;
                                if (addr_cnt == 4*BYTE/8)
                                begin
                                    for(i=31;i>=0;i=i-1)
                                    begin
                                        hiaddr_bytes[31-i] = Address_in[i];
                                    end
                                    Address = {6'b000000,hiaddr_bytes[25:0]};
                                    CRC_Start_Addr_reg = Address;
                                    change_addr = 1'b1;
                                    #1 change_addr = 1'b0;
                                end
                                if (addr_cnt == BYTE)
                                begin
                                    addr_cnt = 0;
                                    for(i=31;i>=0;i=i-1)
                                    begin
                                        hiaddr_bytes[31-i] = Address_in[i];
                                    end
                                    //High order address bits are ignored
                                    Address = {6'b000000,hiaddr_bytes[25:0]};
                                    change_addr = 1'b1;
                                    #1 change_addr = 1'b0;

                                    bus_cycle_state = DATA_BYTES;
                                end
                            end
                            else // others DDR commands
                            begin
                                Address_in[8*addr_cnt]   = IO7_in;
                                Address_in[8*addr_cnt+1] = IO6_in;
                                Address_in[8*addr_cnt+2] = IO5_in;
                                Address_in[8*addr_cnt+3] = IO4_in;
                                Address_in[8*addr_cnt+4] = IO3_in;
                                Address_in[8*addr_cnt+5] = IO2_in;
                                Address_in[8*addr_cnt+6] = SO_in;
                                Address_in[8*addr_cnt+7] = SI_in;
                                if (addr_cnt != 0)
                                begin
                                    addr_cnt = addr_cnt + 1;
                                end
                                read_cnt = 0;
                                if (addr_cnt == 4*BYTE/8)
                                begin
                                    addr_cnt = 0;
                                    if (Instruct == RSFDP)
                                    begin
                                        for(i=31;i>=0;i=i-1)
                                        begin
                                            addr_bytes[31-i] = Address_in[i];
                                        end
                                        Address = {6'b000000,addr_bytes[25:0]};
                                        change_addr = 1'b1;
                                        #1 change_addr = 1'b0;

                                        bus_cycle_state = DUMMY_BYTES;
                                    end
                                    else if (Instruct == RDIDN)
                                    begin
                                        Address = 32'h00000000;
                                        change_addr = 1'b1;
                                        #1 change_addr = 1'b0;
                                        if (Register_Latency == 0)
                                            bus_cycle_state = DATA_BYTES;
                                        else
                                            bus_cycle_state = DUMMY_BYTES;
                                    end
                                    else if (Instruct == RDCRC_4_0)
                                    begin
                                        Address = 32'h00000000;
                                        change_addr = 1'b1;
                                        #1 change_addr = 1'b0;
                                            bus_cycle_state = DUMMY_BYTES;
                                    end
                                    else if (Instruct == RDAY2_4_0)
                                    begin
                                        for(i=31;i>=0;i=i-1)
                                        begin
                                            addr_bytes[31-i] = Address_in[i];
                                        end
                                        Address = {6'b000000,addr_bytes[25:0]};
                                        change_addr = 1'b1;
                                        #1 change_addr = 1'b0;

                                        if (Latency_code == 0)
                                            bus_cycle_state = DATA_BYTES;
                                        else
                                            bus_cycle_state = DUMMY_BYTES;
                                    end
                                    else if (Instruct == RDARG_4_0)
                                    begin
                                        for(i=31;i>=0;i=i-1)
                                        begin
                                            hiaddr_bytes[31-i] = Address_in[i];
                                        end
                                        Address = {6'b000000,hiaddr_bytes[25:0]};
                                        change_addr = 1'b1;
                                        #1 change_addr = 1'b0;

                                        if (Address >= 32'h00800000) //Volatile REGS
                                        begin
                                            if (Register_Latency == 0)
                                                bus_cycle_state = DATA_BYTES;
                                            else
                                                bus_cycle_state = DUMMY_BYTES;
                                        end 
                                        else // NV REGS
                                        begin
                                            if (Latency_code == 0)
                                                bus_cycle_state = DATA_BYTES;
                                            else
                                                bus_cycle_state = DUMMY_BYTES;
                                        end
                                    end
                                    else if (Instruct == WRARG_4_1)
                                    begin
                                        for(i=31;i>=0;i=i-1)
                                        begin
                                            hiaddr_bytes[31-i] = Address_in[i];
                                        end
                                        //High order address bits are ignored
                                        Address = {6'b000000,hiaddr_bytes[25:0]};
                                        change_addr = 1'b1;
                                        #1 change_addr = 1'b0;

                                        bus_cycle_state = DATA_BYTES;
                                    end
                                    else if (Instruct == RDECC_4_0 || Instruct == RDSSR_4_0)
                                    begin
                                        for(i=31;i>=0;i=i-1)
                                        begin
                                            hiaddr_bytes[31-i] = Address_in[i];
                                        end
                                        Address = {6'b000000,hiaddr_bytes[25:0]};
                                        change_addr = 1'b1;
                                        #1 change_addr = 1'b0;

                                        if (Latency_code == 0)
                                            bus_cycle_state = DATA_BYTES;
                                        else
                                            bus_cycle_state = DUMMY_BYTES;
                                    end 
                                    else if (Instruct == RDDYB_4_0)
                                    begin
                                        for(i=31;i>=0;i=i-1)
                                        begin
                                            hiaddr_bytes[31-i] = Address_in[i];
                                        end
                                        Address = {6'b000000,hiaddr_bytes[25:0]};
                                        change_addr = 1'b1;
                                        #1 change_addr = 1'b0;

                                        if (Register_Latency == 0)
                                            bus_cycle_state = DATA_BYTES;
                                        else
                                            bus_cycle_state = DUMMY_BYTES;
                                    end
                                    else if (Instruct == RDPPB_4_0)
                                    begin
                                        for(i=31;i>=0;i=i-1)
                                        begin
                                            hiaddr_bytes[31-i] = Address_in[i];
                                        end
                                        Address = {6'b000000,hiaddr_bytes[25:0]};
                                        change_addr = 1'b1;
                                        #1 change_addr = 1'b0;

                                        if (Latency_code == 0)
                                            bus_cycle_state = DATA_BYTES;
                                        else
                                            bus_cycle_state = DUMMY_BYTES;
                                    end
                                    else if (Instruct == RDPLB_4_0  || Instruct == RDSR1 
                                             || Instruct == RDSR2)
                                    begin
                                        for(i=31;i>=0;i=i-1)
                                        begin
                                            hiaddr_bytes[31-i] = Address_in[i];
                                        end
                                        Address = 32'h00000000;
                                        change_addr = 1'b1;
                                        #1 change_addr = 1'b0;

                                        if (Register_Latency == 0)
                                            bus_cycle_state = DATA_BYTES;
                                        else
                                            bus_cycle_state = DUMMY_BYTES;
                                    end
                                    else if (Instruct == PWDUL_0_1)
                                    begin
                                        for(i=31;i>=0;i=i-1)
                                        begin
                                            hiaddr_bytes[31-i] = Address_in[i];
                                        end
                                        Address = 32'h00000000;
                                        change_addr = 1'b1;
                                        #1 change_addr = 1'b0;

 
                                            bus_cycle_state = DATA_BYTES;
 
                                    end
                                    else if ((Instruct == PRPGE_4_1) || (Instruct == ER256_4_0) ||
                                            (Instruct == WRDYB_4_1)  || (Instruct == PRPPB_4_0) ||
                                            (Instruct == ER004_4_0)  || (Instruct == EVERS_4_0) ||
                                            (Instruct == PRSSR_4_1)  || (Instruct == SEERC_4_0))
                                    begin
                                        for(i=31;i>=0;i=i-1)
                                        begin
                                            hiaddr_bytes[31-i] = Address_in[i];
                                        end
                                        Address = {6'b000000,hiaddr_bytes[25:0]};
                                        change_addr = 1'b1;
                                        #1 change_addr = 1'b0;

                                        bus_cycle_state = DATA_BYTES;
                                    end
                                end
                            end
                        end
                    end //end of ADDRESS_BYTES

                    MODE_BYTE :
                    begin

                    end //end of MODE_BYTE

                    DUMMY_BYTES :
                    begin
                        if (dummy_cnt != 0)
                            dummy_cnt = dummy_cnt + 1;
//                         if ((Instruct == RDAY1_4_0) && OPI_IT)
//                         begin
//                             read_out = 1'b1;
//                             read_out <= #1 1'b0;
//                         end
                        if (Instruct == RSFDP)
                        begin
                            if (dummy_cnt == 4 && ~SDRDDR && OPI_IT)
                                begin
                                    if (DATA_STROBE)
                                        DataDriveOut_DS = 1'b0;
                                end
                            else if (dummy_cnt == 16)
                            begin
                                bus_cycle_state = DATA_BYTES;  
                                read_out = 1'b1;
                                read_out <= #1 1'b0;
                                if (DATA_STROBE)
                                    DataDriveOut_DS = DS_OPI;
                            end
                        end
                        else if (Instruct == DICHK_4_1)
                        begin
                            if (dummy_cnt == 8)
                            begin
                                bus_cycle_state = DATA_BYTES;
                            end
                        end
                        else if (Instruct == RDCRC_4_0)
                        begin
                            if (dummy_cnt == 4 && ~SDRDDR && OPI_IT)
                                begin
                                    if (DATA_STROBE)
                                        DataDriveOut_DS = 1'b0;
                                end
                            else if (dummy_cnt == 16)
                            begin
                                bus_cycle_state = DATA_BYTES;
                                read_out = 1'b1;
                                read_out <= #1 1'b0;
                                if (DATA_STROBE)
                                    DataDriveOut_DS = DS_OPI;
                            end
                        end
                        else if (Instruct == RDUID)
                        begin
                            if (dummy_cnt == 64)
                            begin
                                bus_cycle_state = DATA_BYTES;
                            end
                        end
                        else if (Instruct == RDARG_4_0)
                        begin
                            if (Address >= 32'h00800000) // Volatile REGS
                            begin
                                if (dummy_cnt == 4 && ~SDRDDR && OPI_IT)
                                begin
                                    if (DATA_STROBE)
                                        DataDriveOut_DS = 1'b0;
                                end
                                else if (Register_Latency == dummy_cnt/2)
                                begin
                                    bus_cycle_state = DATA_BYTES;
                                    read_out = 1'b1;
                                    read_out <= #1 1'b0;
                                    if (DATA_STROBE)
                                        DataDriveOut_DS = DS_OPI;
                                end
                            end
                            else // NV REGS
                            begin
                                if (dummy_cnt == 4 && ~SDRDDR && OPI_IT)
                                begin
                                    if (DATA_STROBE)
                                        DataDriveOut_DS = 1'b0;
                                end
                                else if (Latency_code == dummy_cnt/2)
                                begin
                                    bus_cycle_state = DATA_BYTES;
                                    read_out = 1'b1;
                                    read_out <= #1 1'b0;
                                    if (DATA_STROBE)
                                    DataDriveOut_DS = DS_OPI;
                                end
                            end
                        end
                        else if ((Instruct == RDSR1) || (Instruct == RDSR2) || 
                        (Instruct == RDPLB_0_0) || 
                        (Instruct == RDDYB_4_0) || (Instruct == RDIDN) ||
                         (Instruct == RDPLB_4_0))
                        begin
                            if (dummy_cnt == 4 && ~SDRDDR && OPI_IT)
                            begin
                                if (DATA_STROBE)
                                    DataDriveOut_DS = 1'b0;
                            end
                            else if (Register_Latency == dummy_cnt/2)
                            begin
                                bus_cycle_state = DATA_BYTES;
                                read_out = 1'b1;
                                read_out <= #1 1'b0;
                                if (DATA_STROBE)
                                    DataDriveOut_DS = DS_OPI;
                            end
                        end
                        else
                        begin
                            if (dummy_cnt == 4 && ~SDRDDR && OPI_IT)
                            begin
                                if (DATA_STROBE)
                                    DataDriveOut_DS = 1'b0;
                            end
                            else if (Latency_code == dummy_cnt/2)
                            begin
                                bus_cycle_state = DATA_BYTES;
                                read_out = 1'b1;
                                read_out <= #1 1'b0;
                                if (DATA_STROBE)
                                    DataDriveOut_DS = DS_OPI;
                            end
                        end
                    end //end of DUMMY_BYTES

                    DATA_BYTES :
                    begin
                        if ((DATA_STROBE) && ((Instruct == RDAY1_C_0) || (Instruct == RDAY1_4_0) ||
                            (Instruct == RDAY2_C_0) || (Instruct == RDAY2_4_0) ||
                            (Instruct == RDSR1)     || (Instruct == RDSR2)     ||
                            (Instruct == RDUID)     || (Instruct == RDSSR_4_0) ||
                            (Instruct == RDIDN)     || (Instruct == RDPLB_0_0) || 
                            (Instruct == RDPLB_4_0)     ||
                            (Instruct == RDPPB_4_0) || (Instruct == RDDYB_4_0) ||
                            (Instruct == RDECC_4_0) || (Instruct == RDCRC_4_0) ||
                            (Instruct == RSFDP)     || (Instruct == RDARG_4_0)))
                               DataDriveOut_DS = ~DataDriveOut_DS;
                        if (OPI_IT && SDRDDR)
                        begin
                            octal_byte = {IO7_in, IO6_in, IO5_in, IO4_in, IO3_in, IO2_in, SO_in, SI_in};
                            if (data_cnt > (PageSize))
                            begin
                            //In case of octal mode,if more than PageSize+1 bytes
                            //are sent to the device previously latched data
                            //are discarded and last 256/512 data bytes are
                            //guaranteed to be programmed correctly within
                            //the same page.
                                for(i=0;i<=(PageSize-1);i=i+1)
                                begin
                                    octal_data_in[i] = octal_data_in[i+1];
                                end
                                octal_data_in[PageSize] = octal_byte;
                                data_cnt = data_cnt + 1;
                            end
                            else
                            begin
                                if (octal_byte !== 8'bZZZZZZZZ)
                                begin
                                    octal_data_in[data_cnt] = octal_byte;
                                end
                                data_cnt = data_cnt + 1;
                            end
                        end

                        if ((Instruct == RDAY1_C_0) || (Instruct == RDAY1_4_0) ||
                            (Instruct == RDAY2_C_0) || (Instruct == RDAY2_4_0) ||
                            (Instruct == RDSR1)     || (Instruct == RDSR2)     ||
                            (Instruct == RDUID)     || (Instruct == RDSSR_4_0) ||
                            (Instruct == RDIDN)     || (Instruct == RDPLB_0_0) || 
                            (Instruct == RDPLB_4_0)     ||
                            (Instruct == RDPPB_4_0) || (Instruct == RDDYB_4_0) ||
                            (Instruct == RDECC_4_0) || (Instruct == RDCRC_4_0) ||
                            (Instruct == RSFDP)     || (Instruct == RDARG_4_0))
                        begin
                            read_out = 1'b1;
                            read_out <= #1 1'b0;
                        end
                        else if (Instruct == DICHK_4_1)
                            CRC_End_Addr_reg = Address;
                    end //end of DATA_BYTES

                endcase
            end
        end

        if (rising_edge_CSNeg_ipd)
        begin
            if (bus_cycle_state != DATA_BYTES)
            begin
                bus_cycle_state = STAND_BY;
            end
            else
            begin
                bus_cycle_state = STAND_BY;
                if (rd_crc != 0)
                begin
                     rd_crc = 0;
                     ICRV = 32'hFFFFFFFF;
                     icrc_out = 32'hFFFFFFFF;
                     icrc_cnt = 0;  
                end

                case (Instruct)
                    WRENB_0_0,
                    WRDIS_0_0,
                    ERCHP_0_0,
                    ER256_4_0,
                    ER004_4_0,
                    ENDPD_0_0,
                    CLPEF_0_0,
                    SRSTE_0_0,
                    SFRST_0_0,
                    ERPPB_0_0,
                    PRPPB_4_0,
                    WRPLB_0_0,
                    EVERS_4_0,
                    SPEPD_0_0,
                    RSEPD_0_0,
                    SEERC_4_0,
                    DICHK_4_1:
                    begin
                        if (Instruct == ERCHP_0_0 || Instruct == ER256_4_0 ||
                        Instruct == ER004_4_0 || Instruct == ERPPB_0_0 || Instruct == PRPPB_4_0)
                            prog_erase = 1'b1;

                        if (data_cnt == 0)
                            write = 1'b0;
                    end

                    WRARG_4_1:
                    begin
                        if (SDRDDR)
                        begin
                            if (data_cnt == 2)
                            begin
                                write = 1'b0;
                                WRAR_reg_in = octal_data_in[0];
                            end
                        end
                        else if (OPI_IT)
                        begin
                            if (data_cnt == 1)
                            begin
                                write = 1'b0;
                                WRAR_reg_in = octal_data_in[0];
                            end
                        end
//                         CSSTART = 1'b1;
//                                 CSSTART <= #5 1'b0;
                    end
                    
                    WRARG_C_1:
                    begin
                        if (~OPI_IT)
                        begin
                            if (data_cnt == 8)
                            begin
                                write = 1'b0;
                                for(i=0;i<=7;i=i+1)
                                begin
                                    WRAR_reg_in[i] = Data_in[7-i];
                                end
                            end
                        end
                    end
                    
                    PRPGE_4_1:
                    begin
                        prog_erase = 1'b1;
                        ECC_data = Address - (Address % 16);
                        if (~OPI_IT)
                        begin
                            if (data_cnt > 0)
                            begin
                                if ((data_cnt % 8) == 0)
                                begin
                                    write = 1'b0;
                                    for(i=0;i<=PageSize;i=i+1)
                                    begin
                                        for(j=7;j>=0;j=j-1)
                                        begin
                                            if ((Data_in[(i*8)+(7-j)]) !== 1'bX)
                                            begin
                                                Byte_slv[j] =
                                                            Data_in[(i*8)+(7-j)];
                                                if (Data_in[(i*8)+(7-j)]==1'b0)
                                                begin
                                                    ZERO_DETECTED = 1'b1;
                                                end
                                            end
                                        end
                                        WByte[i] = Byte_slv;
                                    end
                                    if (data_cnt > (PageSize+1)*BYTE)
                                        Byte_number = PageSize;
                                    else
                                        Byte_number = ((data_cnt/8) - 1);
                                    if (((Address % 16) + Byte_number+1) % 16 == 0)
                                        ECC_check = ((Address % 16) + Byte_number+1) / 16;
                                    else
                                        ECC_check = ((Address % 16) + Byte_number+1) / 16 + 1;
                                end
                            end
                        end
                        else
                        begin
                            if (data_cnt > 0)
                            begin
                                write = 1'b0;
                                for(i=0;i<=PageSize;i=i+1)
                                begin
                                    Byte_slv = octal_data_in[i];
                                    WByte[i] = Byte_slv;
                                end
                                if (data_cnt > (PageSize+1))
                                    Byte_number = PageSize;
                                else
                                    Byte_number = data_cnt-1;
                                if (((Address % 16) + Byte_number+1) % 16 == 0)
                                    ECC_check = ((Address % 16) + Byte_number+1) / 16;
                                else
                                    ECC_check = ((Address % 16) + Byte_number+1) / 16 + 1;
                            end
                        end
                        ADDRHILO_PG(AddrLo, AddrHi, ECC_data);
                        cnt = 0;

                        for (i=0;i<=(ECC_check*16-1);i=i+1)
                        begin
                            if (Mem[ECC_data + i - cnt] !== MaxData)
                            begin
                                ECC_ERR = ECC_ERR + 1;
                                
                                if ((ECC_data + i) == AddrHi)
                                begin
                                    ECC_data = AddrLo;
                                    cnt = i + 1;
                                end
                            end
                        end
                    end

                    
                    PRSSR_4_1:
                    begin
                        prog_erase = 1'b1;
                        ECC_data = Address - (Address % 16);
                        if (~OPI_IT)
                        begin
                            if (data_cnt > 0)
                            begin
                                if ((data_cnt % 8) == 0)
                                begin
                                    write = 1'b0;
                                    for(i=0;i<=PageSize;i=i+1)
                                    begin
                                        for(j=7;j>=0;j=j-1)
                                        begin
                                            if ((Data_in[(i*8)+(7-j)]) !== 1'bX)
                                            begin
                                                Byte_slv[j] =
                                                            Data_in[(i*8)+(7-j)];
                                                if (Data_in[(i*8)+(7-j)]==1'b0)
                                                begin
                                                    ZERO_DETECTED = 1'b1;
                                                end
                                            end
                                        end
                                        WByte[i] = Byte_slv;
                                    end
                                    if (data_cnt > (PageSize+1)*BYTE)
                                        Byte_number = PageSize;
                                    else
                                        Byte_number = ((data_cnt/8) - 1);
                                    if (((Address % 16) + Byte_number+1) % 16 == 0)
                                        ECC_check = ((Address % 16) + Byte_number+1) / 16;
                                    else
                                        ECC_check = ((Address % 16) + Byte_number+1) / 16 + 1;
                                end
                            end
                        end
                        else
                        begin
                            if (data_cnt > 0)
                            begin
                                write = 1'b0;
                                for(i=0;i<=PageSize;i=i+1)
                                begin
                                    Byte_slv = octal_data_in[i];
                                    WByte[i] = Byte_slv;
                                end
                                if (data_cnt > (PageSize+1))
                                    Byte_number = PageSize;
                                else
                                    Byte_number = data_cnt-1;
                                if (((Address % 16) + Byte_number+1) % 16 == 0)
                                    ECC_check = ((Address % 16) + Byte_number+1) / 16;
                                else
                                    ECC_check = ((Address % 16) + Byte_number+1) / 16 + 1;
                            end
                        end

                        for (i=0;i<=(ECC_check*16-1);i=i+1)
                        begin
                            if (Mem[ECC_data + i] !== MaxData)
                            begin
                                ECC_ERR = ECC_ERR + 1;
                            end
                        end
                    end

                    WRDYB_4_1:
                    begin
                        if (~OPI_IT)
                        begin
                            if (data_cnt == 8)
                            begin
                                write = 1'b0;
                                for(j=0;j<=7;j=j+1)
                                begin
                                    DYAV_in[j] = Data_in[7-j];
                                end
                            end
                        end
                        else
                        begin
                            if (data_cnt == 1)
                            begin
                                write = 1'b0;
                                DYAV_in = octal_data_in[0];
                            end
                        end
                    end

                    PWDUL_0_1:
                    begin
                        if (~OPI_IT)
                        begin
                            if (data_cnt == 64)
                            begin
                                write = 1'b0;
                                for(j=1;j<=8;j=j+1)
                                begin
                                    for(k=1;k<=8;k=k+1)
                                    begin
                                        PASS_TEMP[j*8-k] = Data_in[8*(j-1)+k-1];
                                    end
                                end
                            end
                        end
                        else
                        begin
                            if (data_cnt == 8)
                            begin
                                write = 1'b0;
                                for(j=1;j<=8;j=j+1)
                                begin
                                    Byte_slv = octal_data_in[j-1];
                                    PASS_TEMP[8*(j-1)+7 -: 8] = Byte_slv;
                                end
                            end
                        end
                    end

                endcase
            end
        end
    end

///////////////////////////////////////////////////////////////////////////////
// Timing control for the Page Program
///////////////////////////////////////////////////////////////////////////////
    time  pob;
    time  elapsed_pgm;
    time  start_pgm;
    time  duration_pgm;
    event pdone_event;

    always @(rising_edge_PSTART or rising_edge_reseted)
    begin : ProgTime

        if (CFR3V[4] == 1'b0)
        begin
            if (param_sec_write_time==1'b1)
            begin
                pob = tdevice_PP_256_256;
            end
            else 
            begin
                pob = tdevice_PP_4_256;
            end
        end
        else
        begin
            if (param_sec_write_time==1'b1)
            begin
                pob = tdevice_PP_256_512;
            end
            else 
            begin
                pob = tdevice_PP_4_512;
            end
        end

        if (rising_edge_reseted)
        begin
            PDONE = 1; // reset done, programing terminated
            disable pdone_process;
        end
        else if (reseted)
        begin
            if (rising_edge_PSTART && PDONE)
            begin
                elapsed_pgm = 0;
                duration_pgm = pob;
                PDONE = 1'b0;
                start_pgm = $time;
                ->pdone_event;
            end
        end
    end

    always @(posedge PGSUSP)
    begin
        if (PGSUSP && (~PDONE))
        begin
            disable pdone_process;
            elapsed_pgm = $time - start_pgm;
            duration_pgm = pob - elapsed_pgm;
            PDONE = 1'b0;
        end
    end

    always @(posedge PGRES)
    begin
        start_pgm = $time;
        ->pdone_event;
    end

    always @(pdone_event)
    begin : pdone_process
        #(duration_pgm) PDONE = 1;
    end

///////////////////////////////////////////////////////////////////////////////
// Timing control for the Write Status Register
///////////////////////////////////////////////////////////////////////////////
    time  wob;
    event wdone_event;
    event csdone_event;

    always @(rising_edge_WSTART or rising_edge_reseted)
    begin:WriteTime

        wob = tdevice_WRR;

        if (rising_edge_reseted)
        begin
            WDONE = 1; // reset done, Write terminated
            disable wdone_process;
        end
        else if (reseted)
        begin
            if (rising_edge_WSTART && WDONE)
            begin
                WDONE = 1'b0;
                -> wdone_event;
            end
        end
    end

    always @(wdone_event)
    begin : wdone_process
        #wob WDONE = 1;
    end

   always @(posedge CSSTART or rising_edge_reseted)
   begin:WriteVolatileBitsTime

        if (rising_edge_reseted)
        begin
            CSDONE = 1; // reset done, Write terminated
            disable csdone_process;
        end
        else if (reseted)
        begin
            if (CSSTART && CSDONE)
            begin
                CSDONE = 1'b0;
                -> csdone_event;
            end
        end
    end

    always @(csdone_event)
    begin : csdone_process
        if (read_transaction)
            #tdevice_CSR CSDONE = 1;
        else
            #tdevice_CS CSDONE = 1;
    end

///////////////////////////////////////////////////////////////////////////////
// Timing control for Evaluate Erase Status
///////////////////////////////////////////////////////////////////////////////
    event eesdone_event;

    always @(rising_edge_EESSTART or rising_edge_reseted)
    begin:EESTime

        if (rising_edge_reseted)
        begin
            EESDONE = 1; // reset done, Write terminated
            disable eesdone_process;
        end
        else if (reseted)
        begin
            if (rising_edge_EESSTART && EESDONE)
            begin
                EESDONE = 1'b0;
                -> eesdone_event;
            end
        end
    end

    always @(eesdone_event)
    begin : eesdone_process
        #tdevice_EES EESDONE = 1;
    end

///////////////////////////////////////////////////////////////////////////////
// Timing control for Erase
///////////////////////////////////////////////////////////////////////////////
    event edone_event;
    time elapsed_ers;
    time start_ers;
    time duration_ers;

    always @(rising_edge_ESTART or rising_edge_reseted)
    begin : ErsTime

        if (Instruct == ERCHP_0_0)
        begin
            duration_ers = tdevice_BE;
        end
        else if (Instruct == ER004_4_0)
        begin
            duration_ers = tdevice_SE4;
        end
        else
        begin
            duration_ers = tdevice_SE256;
        end

        if (rising_edge_reseted)
        begin
            EDONE = 1; // reset done, ERASE terminated
            ERS_nosucc[SectorErased] = 1'b1;
            disable edone_process;
        end
        else if ((reseted) && (rising_edge_ESTART))
        begin
            elapsed_ers = 0;
            EDONE = 1'b0;
            start_ers = $time;
            ->edone_event;
        end
    end

    always @(posedge ESUSP)
    begin
        if (ESUSP && (~EDONE))
        begin
            disable edone_process;
            elapsed_ers = $time - start_ers;
            duration_ers = tdevice_SE256 - elapsed_ers;
            EDONE = 1'b0;
        end
    end

    always @(posedge ERES)
    begin
        if  (ERES && (~EDONE))
        begin
            start_ers = $time;
            ->edone_event;
        end
    end

    always @(edone_event)
    begin : edone_process
        EDONE = 1'b0;
        #duration_ers EDONE = 1'b1;
    end

    // SEERC_DONE timing process
    always @(rising_edge_SEERC_START)
    begin : seerc_done_process
        SEERC_DONE          = 1'b0;
        #tdevice_SEERC SEERC_DONE = 1'b1;
    end

    ///////////////////////////////////////////////////////////////////
    // Timing control for the suspend process
    ///////////////////////////////////////////////////////////////////
    always @(rising_edge_START_T1_in)
    begin : Start_T1_time
        if (rising_edge_START_T1_in)
        begin
            if (CRC_ACT == 1'b1)
            begin
                sSTART_T1 = 1'b0;
                sSTART_T1 <= #tdevice_CRCSL 1'b1;
            end
            else
            begin
                sSTART_T1 = 1'b0;
                sSTART_T1 <= #tdevice_SUSP 1'b1;
            end
        end
        else
        begin
            sSTART_T1 = 1'b0;
        end
    end

    ///////////////////////////////////////////////////////////////////
    // Timing control for the CRC calculation
    ///////////////////////////////////////////////////////////////////
    event crcdone_event;
    time elapsed_crc;
    time start_crc;
    time crc_duration;

    always @(rising_edge_CRCSTART or rising_edge_reseted)
    begin : CRCTime

        if (rising_edge_reseted)
        begin
            CRCDONE = 1;
            disable crcdone_process;
        end
        else if (reseted)
        begin
            if ((rising_edge_CRCSTART) && CRCDONE)
            begin
                crc_duration = tdevice_CRCSETUP;
                elapsed_crc = 0;
                CRCDONE = 1'b0;
                start_crc = $time;
                -> crcdone_event;
            end
        end
    end

    always @(posedge CRCSUSP)
    begin
        if (CRCSUSP && (~CRCDONE))
        begin
            disable crcdone_process;
            elapsed_crc = $time - start_crc;
            crc_duration = crc_duration - elapsed_crc;
            CRCDONE = 1'b0;
        end
    end

    always @(posedge CRCRES)
    begin
        start_crc = $time;
        ->crcdone_event;
    end

    always @(crcdone_event)
    begin : crcdone_process
        #(crc_duration) CRCDONE = 1;
    end

    ///////////////////////////////////////////////////////////////////
    // Process for clock frequency determination
    ///////////////////////////////////////////////////////////////////
    always @(posedge SCK_ipd)
    begin : clock_period
        if (SCK_ipd)
        begin
            SCK_cycle = $time - prev_SCK;
            prev_SCK = $time;
        end
    end

//    /////////////////////////////////////////////////////////////////////////
//    // Main Behavior Process
//    // combinational process for next state generation
//    /////////////////////////////////////////////////////////////////////////

    integer i;
    integer j;

    always @(rising_edge_PoweredUp or falling_edge_write or rising_edge_WDONE or
           rising_edge_PDONE or rising_edge_EDONE or rising_edge_RST_out or falling_edge_RST or
           rising_edge_SWRST_out or rising_edge_CSDONE or rising_edge_BCDONE or
           PRGSUSP_out_event or ERSSUSP_out_event or falling_edge_PASSULCK_in or
           rising_edge_EESDONE or falling_edge_PPBERASE_in or rising_edge_CRCDONE or
           posedge DPD_entered or rising_edge_DPD_out or rising_edge_RESETNeg or
           rising_edge_SEERC_DONE or falling_edge_DPD_POR_out)
    begin: StateGen1

        integer sect;

        if (rising_edge_PoweredUp && SWRST_out && RST_out)
        begin
            if (ATBTEN == 1 && ASPRDP !== 0 )
            begin
                next_state     = AUTOBOOT;
                read_cnt       = 0;
                byte_cnt       = 1;
                read_addr      = {ATBN[31:9], 9'b0};
                start_delay    = ATBN[8:1];
                start_autoboot = 0;
                ABSD           = ATBN[8:1];
                CFR4N[4]      = 1'b0;
            end
            else if (DPDPOR == 1'b0) 
                next_state = IDLE;
            else
                next_state = DP_DOWN;
        end
        else if (PoweredUp)
        begin
            if (RST_out == 1'b0)
                next_state = current_state;
            else if (falling_edge_write && Instruct == SFRST_0_0 && RESET_EN)
            begin
                if (ATBTEN == 1 && ASPRDP !== 0)
                begin
                    read_cnt       = 0;
                    byte_cnt       = 1;
                    read_addr      = {ATBN[31:9], 9'b0};
                    start_delay    = ATBN[8:1];
                    ABSD           = ATBN[8:1];
                    start_autoboot = 0;
                    CFR4N[4]      = 1'b0;
                    next_state     = AUTOBOOT;
                end
            else if (CFR4N[2] == 1'b1 && CSNeg_ipd==1'b1 && !DPD_POR_out)
                next_state = DP_DOWN;
            else
                next_state = IDLE;
            end
            else
            begin
                case (current_state)
                    RESET_STATE :
                    begin
                        if (rising_edge_RST_out || rising_edge_SWRST_out)
                        begin
                            if (ATBTEN == 1 && ASPRDP!== 0)
                            begin
                                next_state = AUTOBOOT;
                                CFR4N[4]      = 1'b0;
                                read_cnt       = 0;
                                byte_cnt       = 1;
                                read_addr      = {ATBN[31:9],9'b0};
                                start_delay    = ATBN[8:1];
                                start_autoboot = 0;
                                ABSD           = ATBN[8:1];
                            end
                            else if (CFR4N[2] == 1'b1 && CSNeg_ipd==1'b1 && !DPD_POR_out)
                                next_state = DP_DOWN;
                            else 
                                next_state = IDLE;
                        end
                    end

                    IDLE :
                    begin
                        if (falling_edge_write)
                        begin
                            if ((Instruct == WRARG_4_1 || Instruct == WRARG_C_1) && WRPGEN == 1)
                            begin
                            // can not execute if WRPGEN bit is zero or Hardware
                            // Protection Mode is entered and SR1NV,SR1V,CR1NV or
                            // CR1V is selected (no error is set)
                                if ((Address == 32'h00000001)  ||
                                   ((Address >  32'h00000006)  &&
                                    (Address <  32'h00000010)) ||
                                   ((Address >  32'h00000011)  &&
                                    (Address <  32'h00000020)) ||
                                   ((Address >  32'h00000027)  &&
                                    (Address <  32'h00000030)) ||
                                   ((Address >  32'h00000031)  &&
                                    (Address <  32'h00000042)) ||
                                   ((Address >  32'h00000045)  &&
                                    (Address <  32'h00800000)) ||
                                   ((Address >  32'h00800006)  &&
                                    (Address <  32'h00800008)) ||
                                   ((Address >  32'h00800008)  &&
                                    (Address <  32'h00800010)) ||
                                   ((Address >  32'h00800011)  &&
                                    (Address <  32'h00800040)) ||
                                   ((Address >  32'h00800045)  &&
                                    (Address < 32'h00800067))  ||
                                   ((Address >  32'h00800068)  &&
                                    (Address < 32'h00800070))  ||
                                   (Address ==  32'h00800078)  ||
                                   ((Address >  32'h00800080)  &&
                                    (Address < 32'h00800089))  ||
                                   (Address ==  32'h00800094)  ||
                                   ((Address >  32'h00800098)  &&
                                    (Address < 32'h0080009B))  ||
                                    (Address >  32'h0080009B))
                                begin
                                    $display ("WARNING: Undefined location ");
                                    $display (" selected. Command is ignored!");
                                end
                                else if ((Address > 32'h00800094) &&
                                         (Address < 32'h00800099)) // CRC
                                begin
                                    $display ("WARNING: CRC register cannot be ");
                                    $display ("written by the WRARG_4_1/C_1 command. ");
                                    $display ("Command is ignored!");
                                end
                                else if (Address == 32'h0080009B) // PPBL
                                begin
                                    $display ("WARNING: PPLV register cannot be ");
                                    $display ("written by the WRARG_4_1/C_1  command. ");
                                    $display ("Command is ignored!");
                                end
                                else if ((Address == 32'h00000002) &&
                                    ((PLPROT_O == 1 && WRAR_reg_in[4] == 1'b0) ))
                                begin
                                    $display ("WARNING: Writing of OTP bits back ");
                                    $display ("to their default state is ignored ");
                                    $display ("and no error is set!");

                                end
                                else if ((~(ASPPWD && ASPPER)) &&
                                        (Address == 32'h00000030  || // ASPO[7:0]
                                        Address == 32'h00000031))    // ASPO[15:8]
                                begin
                                // Once the protection mode is selected,the OTP
                                // bits are permanently protected from programming
                                        next_state = PGERS_ERROR;
                                end
                                else if (~(ASPPER))
                                begin
                                // Once the protection mode is selected,the OTP
                                // bits are permanently protected from programming
                                    if (
                                        Address == 32'h00000020  || // PASS[7:0]
                                        Address == 32'h00000021  || // PASS[15:8]
                                        Address == 32'h00000022  || // PASS[23:16]
                                        Address == 32'h00000023  || // PASS[31:24]
                                        Address == 32'h00000024  || // PASS[39:32]
                                        Address == 32'h00000025  || // PASS[47:40]
                                        Address == 32'h00000026  || // PASS[55:48]
                                        Address == 32'h00000027  || // PASS[63:56]
                                        Address == 32'h00000030  || // ASPR[7:0]
                                        Address == 32'h00000031)    // ASPR[15:8]
                                    begin
                                        next_state = PGERS_ERROR;
                                    end
                                    else
                                        next_state = WRITE_ALL_REG;
                                end
                                else // Protection Mode not selected
                                begin
                                    if ((Address == 32'h00000030) ||
                                        (Address == 32'h00000031))//ASPR
                                    begin
                                        if (WRAR_reg_in[2] == 1'b0 &&
                                            WRAR_reg_in[1] == 1'b0 &&
                                            Address == 32'h00000030)
                                            next_state = PGERS_ERROR;
                                        else
                                            next_state = WRITE_ALL_REG;
                                    end
                                    else
                                        next_state = WRITE_ALL_REG;
                                end
                            end
                            else if ((Instruct==PRPGE_4_1) && WRPGEN == 1)
                            begin
                                ReturnSectorID(sect,Address);

                                if (Sec_Prot[sect]== 0 && PPB_bits[sect]== 1 &&
                                    DYB_bits[sect]== 1)
                                begin
                                    next_state = PAGE_PG;
                                end
                                else
                                    next_state = PGERS_ERROR;
                            end
                            else if (Instruct == PRSSR_4_1 && WRPGEN == 1)
                            begin
                                if (Address + Byte_number <= OTPHiAddr)
                                begin //Program within valid OTP Range
                                    if (((((Address>=16'h0010 && Address<=16'h00FF))
                                        && LOCK_BYTE1[Address/32] == 1) ||
                                        ((Address>=16'h0100 && Address<=16'h01FF)
                                        && LOCK_BYTE2[(Address-16'h0100)/32]==1) ||
                                        ((Address>=16'h0200 && Address<=16'h02FF)
                                        && LOCK_BYTE3[(Address-16'h0200)/32]==1) ||
                                        ((Address>=16'h0300 && Address<=16'h03FF)
                                        && LOCK_BYTE4[(Address-16'h0300)/32] == 1)))
                                    begin
//                                         if (TLPROT == 0)
                                            next_state = OTP_PG;
//                                         else
                                   //rev N, TLPROT no longer protects SSR region(OTP)
                                        //Attempting to program within valid OTP
                                        //range while TLPROT = 1
//                                             next_state = PGERS_ERROR;
                                    end
                                    else if (ZERO_DETECTED)
                                    begin
                                    //Attempting to program any zero in the 16
                                    //lowest bytes or attempting to program any zero
                                    //in locked region
                                        next_state = PGERS_ERROR;
                                    end
                                end
                            end
                            else if ((Instruct==ER256_4_0) && WRPGEN == 1)
                            begin
                                ReturnSectorID(sect,Address);

                                if (UniformSec || (TopBoot && !BottomBoot && (sect < 255)) ||
                                (!TopBoot && BottomBoot && sect > 32) || (TopBoot && BottomBoot
                                && (sect > 16 && sect < 271))) 
                                begin
                                    if (Sec_Prot[sect]== 0 && PPB_bits[sect]== 1
                                        && DYB_bits[sect]== 1)
                                    begin
                                        if (~CFR3V[5])
                                            next_state = SECTOR_ERS;
                                        else
                                            next_state = BLANK_CHECK;
                                    end
                                    else
                                        next_state = PGERS_ERROR;
                                end
                                else if ((TopBoot && !BottomBoot  && sect >= 255) ||
                                        (!TopBoot && BottomBoot && sect <= 32) ||
                                        (TopBoot && BottomBoot && (
                                         sect <= 16 || sect >= 271)))
                                begin
                                    if (Sec_ProtSE == 33 && ASP_ProtSE == 33)
                                    //Sector erase command is applied to a
                                    //256 KB range that includes 4 KB sectors.
                                    begin
                                        if (~CFR3V[5])
                                            next_state = SECTOR_ERS;
                                        else
                                            next_state = BLANK_CHECK;
                                    end
                                    else
                                        next_state = PGERS_ERROR;
                                end
                            end
                            else if ((Instruct == ER004_4_0) && WRPGEN == 1)
                            begin
                                ReturnSectorID(sect,Address);
                                if (UniformSec || (TopBoot && !BottomBoot  && sect < 256) ||
                                (!TopBoot && BottomBoot && sect > 31) || (TopBoot && BottomBoot
                                && (sect >15 && sect < 272)))
                                begin
                                    $display("The instruction is applied to");
                                    $display("a sector that is larger than");
                                    $display("4 KB.");
                                    $display("Instruction is ignored!!!");
                                end
                                else
                                begin
                                    if (Sec_Prot[sect]== 0 &&
                                    PPB_bits[sect]== 1 && DYB_bits[sect]== 1)
                                    begin
                                        if (~CFR3V[5])
                                            next_state = SECTOR_ERS;
                                        else
                                            next_state = BLANK_CHECK;
                                    end
                                    else
                                        next_state = PGERS_ERROR;
                                end
                            end
                            else if (Instruct == ERCHP_0_0 && WRPGEN == 1 &&
                                    (STR1V[4]==0 && STR1V[3]==0 && STR1V[2]==0))
                            begin
                                if (~CFR3V[5])
                                    next_state = BULK_ERS;
                                else
                                    next_state = BLANK_CHECK;
                            end
                            else if ((Instruct == PRPPB_4_0) && WRPGEN)
                                if (ASPPPB && PPBLCK && ASPPRM)
                                    next_state = PPB_PG;
                                else
                                    next_state = PGERS_ERROR;
                            else if (Instruct == ERPPB_0_0 && WRPGEN)
                                if (ASPPPB && PPBLCK && ASPPRM)
                                    next_state = PPB_ERS;
                                else
                                    next_state = PGERS_ERROR;
                            else if ((Instruct == WRPLB_0_0) && WRPGEN == 1)
                                next_state = PLB_PG;
                            else if ((Instruct == WRDYB_4_1) && WRPGEN)
                            begin
                                if (DYAV_in == 8'hFF || DYAV_in == 8'h00)
                                    next_state = DYB_PG;
                                else
                                    next_state = PGERS_ERROR;
                            end
                            else if (Instruct == PWDUL_0_1 && ~RDYBSY)
                                next_state = PASS_UNLOCK;
                            else if (Instruct == EVERS_4_0)
                                next_state = EVAL_ERS_STAT;
                            else if (Instruct == DICHK_4_1)
                            begin
                                if (Address >= CRC_Start_Addr_reg + 3)
                                // Condition for entering CRC_calc state is not complete
                                // it needs to have comparison of Addr to EndAddr
                                // Check datasheet for table of state transitions
                                    next_state = CRC_Calc;
                                else
                                    next_state = IDLE;
                            end
                            else if (Instruct == SPEPD_0_0)
                                next_state = CRC_SUSP;
                            // Reading Sector Erase Count register
                            else if (Instruct == SEERC_4_0 && !RDYBSY)
                            begin
                                ReturnSectorID(sect,Address);
                                next_state = SEERC;
                            end
                            else
                                next_state = IDLE;
                        end
                        else if (DPD_entered)
                            next_state = DP_DOWN;
                    end
                    
                    AUTOBOOT :
                    begin
                        if (rising_edge_CSNeg_ipd)
                            next_state = IDLE;
                    end

                    WRITE_ALL_REG :
                    begin
                        if (rising_edge_WDONE || rising_edge_CSDONE)
                            next_state = IDLE;
                    end

                    PAGE_PG :
                    begin
                        if (PRGSUSP_out_event && PRGSUSP_out == 1)
                            next_state = PG_SUSP;
                        else if (rising_edge_PDONE)
                            next_state = IDLE;
                    end

                    OTP_PG :
                    begin
                        if (rising_edge_PDONE)
                            next_state = IDLE;
                    end

                    PG_SUSP :
                    begin
                        if (falling_edge_write)
                        begin
                            if (Instruct == RSEPD_0_0)
                                next_state = PAGE_PG;
                        end
                    end

                    CRC_Calc :
                    begin
                        if ((Instruct == SPEPD_0_0) || rising_edge_START_T1_in)
                            next_state = CRC_SUSP;
                        if (rising_edge_CRCDONE)
                            next_state = IDLE;
                    end

                    CRC_SUSP :
                    begin
                        if (falling_edge_write)
                        begin
                            if (Instruct == RSEPD_0_0)
                                next_state = CRC_Calc;
                            else if (Instruct == SFRST_0_0)
                                next_state = RESET_STATE;
                        end
                    end

                    SECTOR_ERS :
                    begin
                        if (ERSSUSP_out_event && ERSSUSP_out == 1)
                            next_state = ERS_SUSP;
                        else if (rising_edge_EDONE)
                            next_state = IDLE;
                    end

                    BULK_ERS :
                    begin
                        if (rising_edge_EDONE)
                            next_state = IDLE;
                    end

                    ERS_SUSP :
                    begin
                        if (falling_edge_write)
                        begin
                            if ((Instruct==PRPGE_4_1) && WRPGEN && ~PRGERR)
                            begin
                                ReturnSectorID(sect,Address);

                                if (SectorSuspend != Address/(SecSize256+1))
                                begin
                                    if (Sec_Prot[sect]== 0 && PPB_bits[sect]== 1 &&
                                        DYB_bits[sect]== 1)
                                    begin
                                        next_state = ERS_SUSP_PG;
                                    end
                                end
                            end
                            else if ((Instruct == WRDYB_4_1) && WRPGEN && ~PRGERR)
                            begin
                                if (DYAV_in == 8'hFF || DYAV_in == 8'h00)
                                    next_state = DYB_PG;
                                else
                                    next_state = PGERS_ERROR;
                            end
                            else if ((Instruct == RSEPD_0_0) && ~PRGERR)
                                next_state = SECTOR_ERS;
                        end
                    end

                    ERS_SUSP_PG :
                    begin
                        if (rising_edge_PDONE)
                            next_state = ERS_SUSP;
                        else if (PRGSUSP_out_event && PRGSUSP_out == 1)
                            next_state = ERS_SUSP_PG_SUSP;
                    end

                    ERS_SUSP_PG_SUSP :
                    begin

                        if (falling_edge_write)
                        begin
                            if (Instruct == RSEPD_0_0)
                            begin
                                next_state = ERS_SUSP_PG;
                            end
                        end
                    end

                    PASS_PG :
                    begin
                        if (rising_edge_PDONE)
                            next_state = IDLE;
                    end

                    PASS_UNLOCK :
                    begin
                        if (falling_edge_PASSULCK_in)
                        begin
                            if (~PRGERR)
                                next_state = IDLE;
                            else
                                next_state = PGERS_ERROR;
                        end
                    end

                    PPB_PG :
                    begin
                        if (rising_edge_PDONE)
                            next_state = IDLE;
                    end

                    PPB_ERS :
                    begin
                    if (falling_edge_PPBERASE_in)
                        next_state = IDLE;
                    end

                    PLB_PG :
                    begin
                    if (rising_edge_PDONE)
                        next_state = IDLE;
                    end

                    DYB_PG :
                    begin
                    if (rising_edge_PDONE)
                        if (ERASES)
                            next_state = ERS_SUSP;
                        else
                            next_state = IDLE;
                    end

                    ASP_PG :
                    begin
                    if (rising_edge_PDONE)
                        next_state = IDLE;
                    end

                    PGERS_ERROR :
                    begin
                        if (falling_edge_write)
                        begin
                            if (Instruct == WRDIS_0_0 && ~PRGERR && ~ERSERR)
                            begin
                            // A Clear Status Register (CLPEF_0_0) followed by a Write
                            // Disable (WRDIS_0_0) command must be sent to return the
                            // device to standby state
                                next_state = IDLE;
                            end
                        end
                    end

                    BLANK_CHECK :
                    begin
                        if (rising_edge_BCDONE)
                        begin
                            if (NOT_BLANK)
                                if (Instruct == ERCHP_0_0)
                                    next_state = BULK_ERS;
                                else
                                    next_state = SECTOR_ERS;
                            else
                                next_state = IDLE;
                        end
                    end

                    EVAL_ERS_STAT :
                    begin
                        if (rising_edge_EESDONE)
                            next_state = IDLE;
                    end

                    DP_DOWN:
                    begin
                        if (falling_edge_RST && CFR4N[2] == 1'b0)
                            current_state = RESET_STATE;
                        else if (rising_edge_DPD_out)
                            next_state = IDLE;
                    end

                    SEERC :
                    begin
                        if (rising_edge_SEERC_DONE)
                            next_state = IDLE;
                    end

                endcase
            end
        end
    end

//    /////////////////////////////////////////////////////////////////////////
//    //FSM Output generation and general functionality
//    /////////////////////////////////////////////////////////////////////////
    reg change_addr_event    = 1'b0;
    reg Instruct_event       = 1'b0;
    reg current_state_event  = 1'b0;

    integer WData [0:511];
    integer WOTPData;
    integer Addr;
    integer Addr_tmp;
    integer Addr_idcfi;

    always @(Instruct_event)
    begin
        read_cnt  = 0;
        byte_cnt  = 1;
        rd_fast   = 1'b0;
        rd_slow   = 1'b0;
        dual      = 1'b0;
        ddr       = 1'b0;
        any_read  = 1'b0;
        Addr_idcfi  = 0;
    end

    always @(posedge read_out)
    begin
        if (PoweredUp == 1'b1)
        begin
            oe_z = 1'b1;
            #1000 oe_z = 1'b0;

            if (CSNeg_ipd==1'b0)
            begin
                oe = 1'b1;
                #1000 oe = 1'b0;
            end
        end
    end

    always @(change_addr_event)
    begin
        if (change_addr_event)
        begin
            read_addr = Address;
        end
    end

    always @(posedge PASSACC_out)
    begin
//         STR1V[0] = 1'b0; //RDYBSY
        PASSACC_in = 1'b0;
    end

    always @(rising_edge_PoweredUp or posedge oe or posedge oe_z or rising_edge_CRCDONE or
           posedge WDONE or posedge CSDONE or posedge PDONE or posedge EDONE or falling_edge_RST or
           current_state_event or posedge PRGSUSP_out or posedge ERSSUSP_out or
           posedge PASSULCK_out or posedge PPBERASE_out or rising_edge_BCDONE or
           rising_edge_EESDONE or falling_edge_write or rising_edge_DPD_out or
           posedge start_autoboot or Instruct or Address or INCV or
           rising_edge_CSNeg_ipd or rising_edge_reseted or change_addr_event or
           posedge SEERC_DONE or DPD_in or DPDExt_out or falling_edge_DPD_POR_out)
    begin: Functionality
    integer i,j;
    integer sect;

        if (rising_edge_PoweredUp)
        begin
            // the default condition after power-up
            // During POR,the non-volatile version of the registers is copied to
            // volatile version to provide the default state of the volatile
            // register
            STR1V[4:2] = STR1N[4:2];
            STR1V[7:5] = STR1N[7:5];
            STR1V[1:0] = STR1N[1:0];

            CFR1V = CFR1N;
            CFR2V = CFR2N;
            CFR3V = CFR3N;
            CFR4V = CFR4N;
            CFR5V = CFR5N;

            ICRV = 32'hFFFFFFFF;
            icrc_out = 32'hFFFFFFFF;
            icrc_cnt = 0;
            INTNeg_zd    = 1'b1;
            INCV = 8'hFF;
            INSV = 8'hFF;

            //As shipped from the factory, all devices default ASP to the
            //Persistent Protection mode, with all sectors unprotected,
            //when power is applied. The device programmer or host system must
            //then choose which sector protection method to use.
            //For Persistent Protection mode, PPBLOCK defaults to "1"
            PPLV[0] = 1'b1;
            
            if (ASPDYB)
                DYAV[7:0] = 8'hFF;
            else
                DYAV[7:0] = 8'h00;

            if (~ASPDYB)
                //All the DYB power-up in the protected state
                DYB_bits = {288{1'b0}};
            else
                //All the DYB power-up in the unprotected state
                DYB_bits = {288{1'b1}};

            BP_bits = {STR1V[4],STR1V[3],STR1V[2]};
            change_BP = 1'b1;
            #1 change_BP = 1'b0;

            CRC_ACT = 1'b0;
            CRC_RD_SETUP = 1'b0;
        end

        if (rising_edge_DPD_out)
        begin
            DPD_in        = 1'b0;
            DPD_entered   = 1'b0;
            DPDExt_out    = 1'b0;
            ICRV = 32'hFFFFFFFF;
            icrc_out = 32'hFFFFFFFF;
            icrc_cnt = 0;
            INTNeg_zd       = 1'b1;
            INCV = 8'hFF;
            INSV = 8'hFF; //???
            STR1V[1] = 0;
        end

        case (current_state)
            IDLE :
            begin


                ASP_ProtSE = 0;
                Sec_ProtSE = 0;

                if (BottomBoot == 1'b1 && TopBoot == 1'b0)
                begin
                    for (j=32;j>=0;j=j-1)
                    begin
                        if (PPB_bits[j] == 1 && DYB_bits[j] == 1)
                        begin
                            ASP_ProtSE = ASP_ProtSE + 1;
                        end
                        if (Sec_Prot[j] == 0)
                        begin
                            Sec_ProtSE = Sec_ProtSE + 1;
                        end
                    end
                end
                else if (BottomBoot == 1'b0 && TopBoot == 1'b1)
                begin
                    for (j=287;j>=255;j=j-1)
                    begin
                        if (PPB_bits[j] == 1 && DYB_bits[j] == 1)
                        begin
                            ASP_ProtSE = ASP_ProtSE + 1;
                        end
                        if (Sec_Prot[j] == 0)
                        begin
                            Sec_ProtSE = Sec_ProtSE + 1;
                        end
                    end
                end
                else if (BottomBoot == 1'b1 && TopBoot == 1'b1)
                begin
                    for (j=16;j>=0;j=j-1)
                    begin
                        if (PPB_bits[j] == 1 && DYB_bits[j] == 1)
                        begin
                            ASP_ProtSE = ASP_ProtSE + 1;
                        end
                        if (Sec_Prot[j] == 0)
                        begin
                            Sec_ProtSE = Sec_ProtSE + 1;
                        end
                    end
                    for (j=287;j>=271;j=j-1)
                    begin
                        if (PPB_bits[j] == 1 && DYB_bits[j] == 1)
                        begin
                            ASP_ProtSE = ASP_ProtSE + 1;
                        end
                        if (Sec_Prot[j] == 0)
                        begin
                            Sec_ProtSE = Sec_ProtSE + 1;
                        end
                    end
                    Sec_ProtSE = Sec_ProtSE - 1;
                    ASP_ProtSE = ASP_ProtSE - 1;
                end

                if (falling_edge_write && (DPD_in == 1'b0))
                begin
                    if (Instruct == WRENB_0_0)
                        STR1V[1] = 1'b1;
                    else if (Instruct == WRDIS_0_0)
                        STR1V[1] = 0;
                    else if (Instruct == EVERS_4_0)
                    begin
                        ReturnSectorID(sect,Address);

                        EESSTART = 1'b1;
                        EESSTART <= #5 1'b0;
                        STR1V[0] = 1'b1;  // RDYBSY
                        STR1V[1] = 1'b1;  // WRPGEN
                    end
                    else if ((Instruct == WRARG_4_1 || Instruct == WRARG_C_1) && WRPGEN == 1)
                    begin
                        // can not execute if WRPGEN bit is zero or Hardware
                        // Protection Mode is entered and SR1NV,SR1V,CR1NV or
                        // CR1V is selected (no error is set)
                        Addr = Address;

                        if ((Address == 32'h00000001)  ||
                            ((Address >  32'h00000006)  &&
                            (Address <  32'h00000010)) ||
                            ((Address >  32'h00000011)  &&
                            (Address <  32'h00000020)) ||
                            ((Address >  32'h00000027)  &&
                            (Address <  32'h00000030)) ||
                            ((Address >  32'h00000031)  &&
                                    (Address <  32'h00000042)) ||
                                   ((Address >  32'h00000045)  &&
                                    (Address <  32'h00800000)) ||
                            ((Address >  32'h00800006) &&
                            (Address <  32'h00800008)) ||
                            ((Address >  32'h00800008) &&
                            (Address <  32'h00800010)) ||
                            ((Address >  32'h00800011) &&
                            (Address <  32'h00800067)) ||
                            (Address >  32'h00800068)
                            )
                        begin
                            STR1V[1] = 1'b0; // WRPGEN
                        end
                        else if ((Address == 32'h00000002) &&
                               ((PLPROT_O == 1'b1 && WRAR_reg_in[4] == 1'b0) ))
                        begin
                            STR1V[1] = 1'b0; // WRPGEN
                        end
                        else if ((~(ASPPWD && ASPPER)) &&
                                (Address == 32'h00000030  || // ASPR[7:0]
                                Address == 32'h00000031))   // ASPR[15:8]
                        begin
                                STR1V[6] = 1'b1; // PRGERR
                                STR1V[0] = 1'b1; // RDYBSY
                        end
                        else if ((~( ASPPER)) && (
                                Address == 32'h00000020  || // PASS[7:0]
                                Address == 32'h00000021  || // PASS[15:8]
                                Address == 32'h00000022  || // PASS[23:16]
                                Address == 32'h00000023  || // PASS[31:24]
                                Address == 32'h00000024  || // PASS[39:32]
                                Address == 32'h00000025  || // PASS[47:40]
                                Address == 32'h00000026  || // PASS[55:48]
                                Address == 32'h00000027  || // PASS[63:56]
                                Address == 32'h00000030  || // ASPR[7:0]
                                Address == 32'h00000031))    // ASPR[15:8]
                        begin
                                STR1V[6] = 1'b1; // PRGERR
                                STR1V[0] = 1'b1; // RDYBSY
                        end
                        else // Protection Mode not selected
                        begin
                            if ((Address == 32'h00000030) ||
                                (Address == 32'h00000031))//ASPR
                            begin
                                if (WRAR_reg_in[2] == 1'b0 &&
                                    WRAR_reg_in[1] == 1'b0 &&
                                    Address == 32'h00000030)
                                begin
                                    STR1V[6] = 1'b1; // PRGERR
                                    STR1V[0] = 1'b1; // RDYBSY
                                end
                                else
                                begin
                                    WSTART = 1'b1;
                                    WSTART <= #5 1'b0;
                                    STR1V[0] = 1'b1;  // RDYBSY
                                end
                            end
                            else if ((Address == 32'h00000000) ||
                                        (Address == 32'h00000010) ||
                                        (Address >= 32'h00000002) &&
                                        (Address <= 32'h00000006) ||
                                        (Address >= 32'h00000020) &&
                                        (Address <= 32'h00000027) ||
                                        (Address == 32'h00000042) ||
                                        (Address == 32'h00000043) ||
                                        (Address == 32'h00000044) ||
                                        (Address == 32'h00000045) )
                            begin
                                WSTART = 1'b1;
                                WSTART <= #5 1'b0;
                                STR1V[0] = 1'b1;  // RDYBSY
                            end
                            else
                            begin
                                CSSTART = 1'b1;
                                CSSTART <= #5 1'b0;
                                STR1V[0] = 1'b1;  // RDYBSY
                            end
                        end
                    end
                    else if ((Instruct == PRPGE_4_1) && WRPGEN ==1)
                    begin
                        ReturnSectorID(sect,Address);
                        pgm_page = Address / (PageSize+1);

                        if (Sec_Prot[sect] == 0 &&
                            PPB_bits[sect]== 1 && DYB_bits[sect]== 1)
                        begin
                            PSTART  = 1'b1;
                            PSTART <= #5 1'b0;
                            PGSUSP  = 0;
                            PGRES   = 0;
                            INITIAL_CONFIG = 1;
                            STR1V[0] = 1'b1;  // RDYBSY
                            Addr    = Address;
                            Addr_tmp= Address;
                            wr_cnt  = Byte_number;
                            for (i=wr_cnt;i>=0;i=i-1)
                            begin
                                if (Viol != 0)
                                    WData[i] = -1;
                                else
                                    WData[i] = WByte[i];
                            end
                        end
                        else
                        begin
                        //PRGERR bit will be set when the user attempts to
                        //to program within a protected main memory sector
                            STR1V[6] = 1'b1; //PRGERR
                            STR1V[0] = 1'b1; //RDYBSY
                        end
                    end
                    else if (Instruct == PRSSR_4_1 && WRPGEN == 1)
                    begin
                        if (Address + Byte_number <= OTPHiAddr)
                        begin //Program within valid OTP Range
                            if (((((Address>=16'h0010 && Address<=16'h00FF))
                                && LOCK_BYTE1[Address/32] == 1) ||
                                ((Address>=16'h0100 && Address<=16'h01FF)
                                && LOCK_BYTE2[(Address-16'h0100)/32]==1) ||
                                ((Address>=16'h0200 && Address<=16'h02FF)
                                && LOCK_BYTE3[(Address-16'h0200)/32]==1) ||
                                ((Address>=16'h0300 && Address<=16'h03FF)
                                && LOCK_BYTE4[(Address-16'h0300)/32] == 1)))
                            begin
                            //rev N, TLPROT no longer protects SSR region(OTP)
                            // As long as the TLPROT bit remains cleared to a
                            // logic '0' the OTP address space is programmable.
//                                 if (TLPROT == 0)
//                                 begin
                                    PSTART  = 1'b1;
                                    PSTART <= #5 1'b0;
                                    STR1V[0] = 1'b1; //RDYBSY
                                    Addr    = Address;
                                    Addr_tmp= Address;
                                    wr_cnt  = Byte_number;
                                    for (i=wr_cnt;i>=0;i=i-1)
                                    begin
                                        if (Viol != 0)
                                            WData[i] = -1;
                                        else
                                            WData[i] = WByte[i];
                                    end
//                                 end
//                                 else
                                //rev N, TLPROT no longer protects SSR region(OTP)
                                //Attempting to program within valid OTP
                                //range while TLPROT = 1
//                                 begin
//                                     STR1V[6] = 1'b1; // PRGERR
//                                     STR1V[0] = 1'b1; // RDYBSY
//                                 end
                            end
                            else if (ZERO_DETECTED)
                            begin
                                if (Address > 12'h3FF)
                                begin
                                    $display ("Given address is ");
                                    $display ("out of OTP address range");
                                end
                                else
                                begin
                                //Attempting to program any zero in the 16
                                //lowest bytes or attempting to program any zero
                                //in locked region
                                    STR1V[6] = 1'b1; // PRGERR
                                    STR1V[0] = 1'b1; // RDYBSY
                                end
                            end
                        end
                    end
                    else if ((Instruct==ER256_4_0) && WRPGEN == 1)
                    begin
                        ReturnSectorID(sect,Address);
                        SectorErased  = sect;
                        SectorSuspend = Address/(SecSize256+1);

                        if (UniformSec || (TopBoot && !BottomBoot  && sect <= 255) ||
                           (!TopBoot && BottomBoot && sect >= 32) || (TopBoot && BottomBoot
                                && (sect >=16 && sect <= 271)))
                        begin

                            if (Sec_Prot[sect]== 0 && PPB_bits[sect]== 1
                                 && DYB_bits[sect]== 1)
                            begin
                                Addr = Address;
                                if (~CFR3V[5])
                                begin
                                    bc_done = 1'b0;
                                    ESTART  = 1'b1;
                                    ESTART <= #5 1'b0;
                                    ESUSP     = 0;
                                    ERES      = 0;
                                    INITIAL_CONFIG = 1;
                                    STR1V[0] = 1'b1; //RDYBSY
                                end
                            end
                            else
                            begin
                            //ERSERR bit will be set when the user attempts to
                            //erase an individual protected main memory sector
                                STR1V[5] = 1'b1; //ERSERR
                                STR1V[0] = 1'b1; //RDYBSY
                            end
                        end
                        else if ((TopBoot && !BottomBoot  && sect >= 255) ||
                                (!TopBoot && BottomBoot && sect <= 32) ||
                                (TopBoot && BottomBoot
                                && (sect <= 16 || sect >= 271)))
                        begin
                            if (Sec_ProtSE == 33 && ASP_ProtSE == 33)
                            //Sector erase command is applied to a
                            //256 KB range that includes 4 KB sectors.
                            begin
                                Addr = Address;
                                if (~CFR3V[5])
                                begin
                                    bc_done = 1'b0;
                                    ESTART = 1'b1;
                                    ESTART <= #5 1'b0;
                                    ESUSP     = 0;
                                    ERES      = 0;
                                    INITIAL_CONFIG = 1;
                                    STR1V[0] = 1'b1; //RDYBSY
                                end
                            end
                            else
                            begin
                            //ERSERR bit will be set when the user attempts to
                            //erase an individual protected main memory sector
                                STR1V[5] = 1'b1; //ERSERR
                                STR1V[0] = 1'b1; //RDYBSY
                            end
                        end
                    end
                    else if ((Instruct == ER004_4_0) && WRPGEN == 1)
                    begin
                        ReturnSectorID(sect,Address);

                         if (UniformSec || (TopBoot && !BottomBoot  && sect <= 255) ||
                           (!TopBoot && BottomBoot && sect >= 32) || 
                           (TopBoot && BottomBoot
                                && (sect >=16 && sect <= 271)))
                        begin
                            STR1V[1] = 1'b0;//WRPGEN
                        end
                        else
                        begin
                            if (Sec_Prot[sect] == 0 &&
                                PPB_bits[sect]== 1 && DYB_bits[sect]== 1)
                            //A P4E instruction applied to a sector
                            //that has been Write Protected through the
                            //Block Protect Bits or ASP will not be
                            //executed and will set the ERSERR status
                            begin
                                Addr = Address;
                                if (~CFR3V[5])
                                begin
                                    bc_done = 1'b0;
                                    ESTART = 1'b1;
                                    ESTART <= #5 1'b0;
                                    ESUSP     = 0;
                                    ERES      = 0;
                                    INITIAL_CONFIG = 1;
                                    STR1V[0] = 1'b1; //RDYBSY
                                end
                            end
                            else
                            begin
                            //ERSERR bit will be set when the user attempts to
                            //erase an individual protected main memory sector
                                STR1V[5] = 1'b1; //ERSERR
                                STR1V[0] = 1'b1; //RDYBSY
                            end
                        end
                    end
                    else if (Instruct == ERCHP_0_0 && WRPGEN == 1)
                    begin
                        if (STR1V[4]==0 && STR1V[3]==0 && STR1V[2]==0)
                        begin
                            if (~CFR3V[5])
                            begin
                                bc_done = 1'b0;
                                ESTART = 1'b1;
                                ESTART <= #5 1'b0;
                                ESUSP  = 0;
                                ERES   = 0;
                                INITIAL_CONFIG = 1;
                                STR1V[0] = 1'b1; //RDYBSY
                            end
                        end
                        else
                        begin
                        //The Bulk Erase command will not set ERSERR if a
                        //protected sector is found during the command
                        //execution.
                            STR1V[1] = 1'b0;//WRPGEN
                        end
                    end
                    else if ((Instruct == PRPPB_4_0) && WRPGEN)
                    begin
                        if (ASPPPB && PPBLCK && ASPPRM)
                        begin
                            ReturnSectorID(sect,Address);
                            PSTART = 1'b1;
                            PSTART <= #5 1'b0;
                            STR1V[0] = 1'b1;//RDYBSY
                        end
                        else
                        begin
                            STR1V[6] = 1'b1; // PRGERR
                            STR1V[0] = 1'b1; // RDYBSY
                        end
                    end
                    else if (Instruct == ERPPB_0_0 && WRPGEN)
                    begin
                            if (ASPPPB && PPBLCK && ASPPRM)
                            begin
                                PPBERASE_in = 1'b1;
                                STR1V[0] = 1'b1; // RDYBSY
                            end
                            else
                            begin
                                STR1V[5] = 1'b1; // ERSERR
                                STR1V[0] = 1'b1; // RDYBSY
                            end
//                             STR1V[1] = 1'b0; // WRPGEN ?? secure_opN
                    end
                    else if ((Instruct == WRPLB_0_0) && WRPGEN == 1)
                    begin
                        PSTART = 1'b1;
                        PSTART <= #5 1'b0;
                        STR1V[0] = 1'b1; // RDYBSY
                    end
                    else if ((Instruct == WRDYB_4_1) && WRPGEN)
                    begin
                        if (DYAV_in == 8'hFF || DYAV_in == 8'h00)
                        begin
                            ReturnSectorID(sect,Address);
                            PSTART   = 1'b1;
                            PSTART  <= #5 1'b0;
                            STR1V[0] = 1'b1;// RDYBSY
                        end
                        else
                        begin
                            STR1V[6] = 1'b1;// PRGERR
                            STR1V[0] = 1'b1;// RDYBSY
                        end
                    end
                    else if (Instruct == PWDUL_0_1)
                    begin
                        if (~RDYBSY)
                        begin
                            PASSULCK_in = 1;
                            STR1V[0] = 1'b1; //RDYBSY
                        end
                        else
                        begin
                            $display ("The PWDUL_0_1 command cannot be accepted");
                            $display (" any faster than once every 100us");
                        end
                    end
                    else if (Instruct == DICHK_4_1)
                    begin
                        if (CRC_End_Addr_reg >= CRC_Start_Addr_reg + 3)
                        begin
                            CRCSTART = 1'b1;
                            CRCSTART <= #5 1'b0;
                            STR1V[0] = 1'b1;
                            STR2V[3] = 1'b0; // DICRCA
                            DCRV  = 32'h00000000;
                        end
                        else
                        begin
                            // Abort CRC calculation
                            $display ("CRC EndAddr is not StartAddr+3 ");
                            $display ("or greater; CRC calculation is aborted");
                            STR2V[3] = 1'b1; // DICRCA
                        end
                    end
                    else if (Instruct == SPEPD_0_0 && ~START_T1_in)
                    begin
                        START_T1_in = 1'b1;
                    end
                    else if (Instruct == CLECC_0_0)
                    begin
                        ESCV[4] = 0;// 2 bits ECC detection
                        ESCV[3] = 0;// 1 bit ECC correction
                        INSV[1] = 1;
                        INSV[0] = 1;
                        ECTV = 16'h0000;
                        EATV = 32'h00000000;
                    end
                    else if (Instruct == CLPEF_0_0)
                    begin
                        STR1V[6] = 0;// PRGERR
                        STR1V[5] = 0;// ERSERR
                        STR1V[0] = 0;// RDYBSY
                    end
                    else if (Instruct == ENDPD_0_0)
                    begin
                        DPD_in = 1'b1;
                    end
                    else if (Instruct == SEERC_4_0)
                    begin
                        ReturnSectorID(sect,Address);
                        SectorErased  = sect;
                        SectorSuspend = Address/(SecSize256+1);

                        Addr = Address;

                        SEERC_START  = 1'b1;
                        SEERC_START  <= #5 1'b0;

                        STR1V[0] = 1'b1; //RDYBSY
                    end

                    if (Instruct == SRSTE_0_0)
                    begin
                        RESET_EN = 1;
                    end
                    else
                    begin
                        RESET_EN <= 0;
                    end
                end
                else if (oe_z)
                begin
                    if ((Instruct == RDAY1_C_0) || (Instruct == RDAY2_C_0) ||
                    ((Instruct == RDAY1_4_0) && (~OPI_IT)))
                    begin
                        rd_fast = 1'b0;
                        rd_slow = 1'b1;
                        dual    = 1'b0;
                        ddr     = 1'b0;
                    end
                    else if ((Instruct == RDAY2_4_0) && OPI_IT && SDRDDR)
                    begin
                        rd_fast = 1'b0;
                        rd_slow = 1'b0;
                        dual    = 1'b1;
                        ddr     = 1'b1;
                    end
                    else
                    begin
                        rd_fast = 1'b1;
                        rd_slow = 1'b0;
                        dual    = 1'b0;
                        ddr     = 1'b0;
                    end
                end
                else if (oe)
                begin
                    any_read = 1'b1;
                    if (Instruct == RDSR1)
                    begin
                    //Read Status Register 1
                        if (OPI_IT)
                        begin
                            data_out[7:0] = STR1V;
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            DataDriveOut_SO = data_out[1-read_cnt];
                            DataDriveOut_SI = data_out[0-read_cnt];

                            read_cnt = read_cnt + 1;
                            if (read_cnt == 1)
                            begin
                                read_cnt = 0;
                            end
                        end
                        else
                        begin
                            DataDriveOut_SO = STR1V[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                    else if (Instruct == RDSR2)
                    begin
                        //Read Status Register 2
                        if (OPI_IT)
                        begin
                            data_out[7:0] = STR2V;
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            DataDriveOut_SO = data_out[1-read_cnt];
                            DataDriveOut_SI = data_out[0-read_cnt];

                            read_cnt = read_cnt + 1;
                            if (read_cnt == 1)
                            begin
                                read_cnt = 0;
                            end
                        end
                        else
                        begin
                            DataDriveOut_SO = STR2V[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                    else if (Instruct == RDARG_4_0)
                    begin
                        READ_ALL_REG(read_addr, RDAR_reg);

                        if (OPI_IT)
                        begin
                            data_out[7:0]  = RDAR_reg;
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            DataDriveOut_SO = data_out[1-read_cnt];
                            DataDriveOut_SI = data_out[0-read_cnt];

                            read_cnt = read_cnt + 1;
                            if (read_cnt == 1)
                            begin
                                read_cnt = 0;
                            end
                        end
                        else
                        begin
                            data_out[7:0]  = RDAR_reg;
                            DataDriveOut_SO = data_out[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                    else if ((Instruct == RDAY1_C_0) || ((Instruct == RDAY1_4_0) && (~OPI_IT)))
                    begin
                        //Read Memory array
                        rd_fast = 1'b0;
                        rd_slow = 1'b1;
                        dual    = 1'b0;
                        ddr     = 1'b0;

                        if (Mem[read_addr] !== -1)
                        begin
                            data_out[7:0] = Mem[read_addr];
                            DataDriveOut_SO  = data_out[7-read_cnt];
                        end
                        else
                        begin
                            DataDriveOut_SO  = 8'bx;
                        end

                        read_cnt = read_cnt + 1;
                        if (read_cnt == 8)
                        begin
                            read_cnt = 0;
                            if (read_addr >= AddrRANGE)
                                read_addr = 0;
                            else
                                read_addr = read_addr + 1;
                        end
                    end
                    else if ((Instruct == RDAY2_C_0) && (~OPI_IT))
                    begin

                        rd_fast = 1'b1;
                        rd_slow = 1'b0;
                        dual    = 1'b0;
                        ddr     = 1'b0;
                        

                        if (Mem[read_addr] !== -1)
                        begin
                            data_out[7:0] = Mem[read_addr];
                            DataDriveOut_SO  = data_out[7-read_cnt];
                        end
                        else
                        begin
                            DataDriveOut_SO  = 8'bx;
                        end

                        read_cnt = read_cnt + 1;
                        if (read_cnt == 8)
                        begin
                            read_cnt = 0;

                            if (~CFR4V[4])  //Wrap Disabled
                            begin
                                if (read_addr == AddrRANGE)
                                    read_addr = 0;
                                else
                                    read_addr = read_addr + 1;
                            end
                            else           //Wrap Enabled
                            begin
                                read_addr = read_addr + 1;

                                if (read_addr % WrapLength == 0)
                                    read_addr = read_addr - WrapLength;

                            end
                        end
                    end
                    else if ((Instruct == RDAY1_4_0) && OPI_IT)
                    begin
                        if (Mem[read_addr] !== -1)
                        begin
                            data_out[7:0] = Mem[read_addr];
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            DataDriveOut_SO = data_out[1-read_cnt];
                            DataDriveOut_SI = data_out[0-read_cnt];
                        end
                        else
                        begin
                            DataDriveOut_Dout = 6'bx;
                            DataDriveOut_SO   = 1'bx;
                            DataDriveOut_SI   = 1'bx;
                        end
                        
                        read_cnt = read_cnt + 1;
                        if (read_cnt == 1)
                        begin
                            read_cnt = 0;
                            if (read_addr >= AddrRANGE)
                                read_addr = 0;
                            else
                                read_addr = read_addr + 1;
                        end
                    end
                    else if ((Instruct == RDAY2_4_0) && OPI_IT && SDRDDR)
                    begin
                        //Read Memory array
                        rd_fast = 1'b0;
                        rd_slow = 1'b0;
                        dual    = 1'b1;
                        ddr     = 1'b1;
                            data_out[7:0]  = Mem[read_addr];
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            DataDriveOut_SO = data_out[1-read_cnt];
                            DataDriveOut_SI = data_out[0-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 1)
                            begin
                                read_cnt = 0;

                                if (~CFR4V[4])  //Wrap Disabled
                                begin
                                    if (read_addr == AddrRANGE)
                                        read_addr = 0;
                                    else
                                        read_addr = read_addr + 1;
                                end
                                else           //Wrap Enabled
                                begin
                                    read_addr = read_addr + 1;

                                    if (read_addr % WrapLength == 0)
                                        read_addr = read_addr - WrapLength;
                                end
                            end
                    end
                    else if (Instruct == RDSSR_4_0)
                    begin
                        if(read_addr>=OTPLoAddr && read_addr<=OTPHiAddr)
                        begin
                        //Read OTP Memory array
                            rd_fast = 1'b1;
                            rd_slow = 1'b0;
                            dual    = 1'b0;
                            ddr     = 1'b0;
                            data_out[7:0] = OTPMem[read_addr];
                            if (OPI_IT)
                            begin
                                for (i=0;i<=5;i=i+1)
                                begin
                                    DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                                end
                                DataDriveOut_SO = data_out[1-read_cnt];
                                DataDriveOut_SI = data_out[0-read_cnt];
                                read_cnt = read_cnt + 1;
                                if (read_cnt == 1)
                                begin
                                    read_cnt = 0;
                                    read_addr = read_addr + 1;
                                end
                            end
                            else
                            begin
                                DataDriveOut_SO  = data_out[7-read_cnt];
                                read_cnt = read_cnt + 1;
                                if (read_cnt == 8)
                                begin
                                    read_cnt = 0;
                                    read_addr = read_addr + 1;
                                end
                            end
                        end
                        else if (read_addr > OTPHiAddr)
                        begin
                        //OTP Read operation will not wrap to the
                        //starting address after the OTP address is at
                        //its maximum; instead, the data beyond the
                        //maximum OTP address will be undefined.
                            if (OPI_IT)
                            begin
                                DataDriveOut_Dout = 6'bX;
                                DataDriveOut_SO   = 1'bX;
                                DataDriveOut_SI   = 1'bX;
                                read_cnt = read_cnt + 1;
                                if (read_cnt == 1)
                                    read_cnt = 0;
                            end
                            else
                            begin
                                DataDriveOut_SO = 1'bX;
                                read_cnt = read_cnt + 1;
                                if (read_cnt == 8)
                                    read_cnt = 0;
                            end
                        end
                    end
                    else if (Instruct == RDIDN)
                    begin
                        if (Addr_idcfi <= IDLength)
                        begin
                            data_out[7:0] = MDID_reg[8*Addr_idcfi+7 -: 8];
                            if (OPI_IT)
                            begin
                                for (i=0;i<=5;i=i+1)
                                begin
                                    DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                                end
                                DataDriveOut_SO = data_out[1-read_cnt];
                                DataDriveOut_SI = data_out[0-read_cnt];
                                read_cnt = read_cnt + 1;
                                if (read_cnt == 1)
                                begin
                                    read_cnt = 0;
                                    Addr_idcfi = Addr_idcfi + 1;
                                end
                            end
                            else
                            begin
                                DataDriveOut_SO  = data_out[7-read_cnt];
                                read_cnt  = read_cnt + 1;
                                if (read_cnt == 8)
                                begin
                                    read_cnt = 0;
                                    Addr_idcfi = Addr_idcfi+1;
                                end
                            end
                        end
                    end
                    else if (Instruct == RDUID)
                    begin
                        if (Addr_idcfi <= BYTE-1)
                        begin
                            data_out[7:0] = UID_reg[8*Addr_idcfi+7 -: 8];
                            if (OPI_IT)
                            begin
                                for (i=0;i<=5;i=i+1)
                                begin
                                    DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                                end
                                DataDriveOut_SO = data_out[1-read_cnt];
                                DataDriveOut_SI = data_out[0-read_cnt];
                                read_cnt = read_cnt + 1;
                                if (read_cnt == 1)
                                begin
                                    read_cnt = 0;
                                    Addr_idcfi = Addr_idcfi + 1;
                                end
                            end
                            else
                            begin
                                DataDriveOut_SO  = data_out[7-read_cnt];
                                read_cnt  = read_cnt + 1;
                                if (read_cnt == 8)
                                begin
                                    read_cnt = 0;
                                    Addr_idcfi = Addr_idcfi+1;
                                end
                            end
                        end
                    end
                    else if (Instruct == RSFDP)
                    begin
                        if (addr_bytes <= SFDPHiAddr)
                        begin
                            data_out[7:0]  = SFDP_array[addr_bytes];
                            if (OPI_IT)
                            begin
                                for (i=0;i<=5;i=i+1)
                                begin
                                    DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                                end
                                DataDriveOut_SO = data_out[1-read_cnt];
                                DataDriveOut_SI = data_out[0-read_cnt];
                                read_cnt = read_cnt + 1;
                                if (read_cnt == 1)
                                begin
                                    read_cnt = 0;
                                    addr_bytes = addr_bytes + 1;
                                end
                            end
                            else
                            begin
                                DataDriveOut_SO = data_out[7-read_cnt];
                                read_cnt = read_cnt + 1;
                                if (read_cnt == 8)
                                begin
                                    read_cnt = 0;
                                    addr_bytes = addr_bytes+1;
                                end
                            end
                        end
                        else
                        begin
                        //Continued shifting of output beyond the end of
                        //the defined ID-CFI address space will
                        //provide undefined data.
                            if (OPI_IT)
                            begin
                                DataDriveOut_Dout = 6'bX;
                                DataDriveOut_SO   = 1'bX;
                                DataDriveOut_SI   = 1'bX;
                            end
                            else
                                DataDriveOut_SO = 1'bX;
                        end
                    end
                    else if (Instruct == RDECC_4_0)
                    begin
                        if (OPI_IT)
                        begin
                            DataDriveOut_Dout = ESCV[7:2];
                            DataDriveOut_SO   = ESCV[1];
                            DataDriveOut_SI   = ESCV[0];
                        end
                        else
                        begin
                            DataDriveOut_SO = ESCV[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                    else if (Instruct == RDCRC_4_0)
                    begin
                        if (Addr_idcfi <= 3)
                        begin
                            data_out[7:0] = ICRV[8*Addr_idcfi+7 -: 8];
                            if (OPI_IT)
                            begin
                                for (i=0;i<=5;i=i+1)
                                begin
                                    DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                                end
                                DataDriveOut_SO = data_out[1-read_cnt];
                                DataDriveOut_SI = data_out[0-read_cnt];
                                read_cnt = read_cnt + 1;
                                if (read_cnt == 1)
                                begin
                                    read_cnt = 0;
                                    Addr_idcfi = Addr_idcfi + 1;
                                end
                            end
                        end
                    end
                    else if (Instruct == RDDYB_4_0)
                    begin
                    //Read DYB Access Register
                        ReturnSectorID(sect,Address);

                        if (DYB_bits[sect] == 1)
                            DYAV[7:0] = 8'hFF;
                        else
                        begin
                            DYAV[7:0] = 8'h0;
                        end

                        if (OPI_IT)
                        begin
                            DataDriveOut_Dout = DYAV[7:2];
                            DataDriveOut_SO   = DYAV[1];
                            DataDriveOut_SI   = DYAV[0];
                        end
                        else
                        begin
                            DataDriveOut_SO = DYAV[7-read_cnt];
                            read_cnt  = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                    else if (Instruct == RDPPB_4_0)
                    begin
                    //Read PPB Access Register
                        ReturnSectorID(sect,Address);

                        if (PPB_bits[sect] == 1)
                            PPAV[7:0] = 8'hFF;
                        else
                        begin
                            PPAV[7:0] = 8'h0;
                        end

                        if (OPI_IT)
                        begin
                            DataDriveOut_Dout = PPAV[7:2];
                            DataDriveOut_SO   = PPAV[1];
                            DataDriveOut_SI   = PPAV[0];
                        end
                        else
                        begin
                            DataDriveOut_SO = PPAV[7-read_cnt];
                            read_cnt  = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                    else if (Instruct == RDPLB_4_0)
                    begin
                         DataDriveOut_Dout = PPLV[7:2];
                         DataDriveOut_SO   = PPLV[1];
                         DataDriveOut_SI   = PPLV[0];
                    end
                    else if (Instruct == RDPLB_0_0)
                    begin
                    //Read PPB Lock Register
                        DataDriveOut_SO = PPLV[7-read_cnt];
                        DataDriveOut_Dout = 6'bZ;
                        DataDriveOut_SI   = 1'bZ;
                        read_cnt  = read_cnt + 1;
                        if (read_cnt == 8)
                            read_cnt = 0;
                    end
                end
            end
            
            AUTOBOOT:
            begin
                if (start_autoboot == 1)
                begin

                    if (oe)
                    begin
                        any_read = 1'b1;
                        if (OPI_IT)
                        begin           //max SCK frequency is 100MHz
                            rd_fast = 1'b0;
                            rd_slow = 1'b0;
                            dual    = 1'b1;
                            ddr     = 1'b1;
                            
                            data_out[7:0]  = Mem[read_addr];
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 1)
                            begin
                                read_cnt = 0;
                                read_addr = read_addr + 1;
                            end
                        end
                        else
                        begin 
                            rd_fast = 1'b0;
                            rd_slow = 1'b1;
                            dual    = 1'b0;
                            ddr     = 1'b0;
                            data_out[7:0] = Mem[read_addr];
                            DataDriveOut_SO = data_out[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                            begin
                                read_cnt = 0;
                                read_addr = read_addr + 1;
                            end
                        end
                    end
                end
            end

            WRITE_ALL_REG:
            begin

                if (OPI_IT)
                begin
                    rd_fast = 1'b1;
                    rd_slow = 1'b0;
                    dual    = 1'b1;
                    ddr     = 1'b0;
                end
                else
                begin
                    rd_fast = 1'b1;
                    rd_slow = 1'b0;
                    dual    = 1'b0;
                    ddr     = 1'b0;
                end

                if (oe)
                begin
                    any_read = 1'b1;
                    if (Instruct == RDSR1)
                    begin
                    //Read Status Register 1
                        if (OPI_IT)
                        begin
                            data_out[7:0] = STR1V;
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            DataDriveOut_SO = data_out[1-read_cnt];
                            DataDriveOut_SI = data_out[0-read_cnt];

                            read_cnt = read_cnt + 1;
                            if (read_cnt == 1)
                            begin
                                read_cnt = 0;
                            end
                        end
                        else
                        begin
                            DataDriveOut_SO = STR1V[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                    else if (Instruct == RDSR2)
                    begin
                        //Read Status Register 2
                        if (OPI_IT)
                        begin
                            data_out[7:0] = STR2V;
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            DataDriveOut_SO = data_out[1-read_cnt];
                            DataDriveOut_SI = data_out[0-read_cnt];

                            read_cnt = read_cnt + 1;
                            if (read_cnt == 1)
                            begin
                                read_cnt = 0;
                            end
                        end
                        else
                        begin
                            DataDriveOut_SO = STR2V[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                    else if (Instruct == RDARG_4_0)
                    begin
                          READ_ALL_REG(read_addr, RDAR_reg);

                        if (OPI_IT)
                        begin
                            data_out[7:0]  = RDAR_reg;
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            DataDriveOut_SO = data_out[1-read_cnt];
                            DataDriveOut_SI = data_out[0-read_cnt];

                            read_cnt = read_cnt + 1;
                            if (read_cnt == 1)
                            begin
                                read_cnt = 0;
                            end
                        end
                        else
                        begin
                            data_out[7:0]  = RDAR_reg;
                            DataDriveOut_SO = data_out[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                end

                new_pass_byte = WRAR_reg_in;
                if (Addr == 32'h00000020)
                    old_pass_byte = PWDO[7:0];
                else if (Addr == 32'h00000021)
                    old_pass_byte = PWDO[15:8];
                else if (Addr == 32'h00000022)
                    old_pass_byte = PWDO[23:16];
                else if (Addr == 32'h00000023)
                    old_pass_byte = PWDO[31:24];
                else if (Addr == 32'h00000024)
                    old_pass_byte = PWDO[39:32];
                else if (Addr == 32'h00000025)
                    old_pass_byte = PWDO[47:40];
                else if (Addr == 32'h00000026)
                    old_pass_byte = PWDO[55:48];
                else if (Addr == 32'h00000027)
                    old_pass_byte = PWDO[63:56];

                for (i=0;i<=7;i=i+1)
                begin
                    if (old_pass_byte[j] == 0)
                        new_pass_byte[j] = 0;
                end

                if (WDONE && CSDONE)
                begin
                    STR1V[0] = 1'b0; // RDYBSY
                    STR1V[1] = 1'b0; // WRPGEN

                    if (Addr == 32'h00000000) // SR1_NV;
                    begin
                        if (~PLPROT_O)
                        begin
                            if (TLPROT == 0)
                            //The Freeze Bit, when set to 1, locks the current
                            //state of the LBPROT2-0 bits in Status Register.
                            begin
                                    STR1N[4] = WRAR_reg_in[4];//LBPROT2_NV
                                    STR1N[3] = WRAR_reg_in[3];//LBPROT1_NV
                                    STR1N[2] = WRAR_reg_in[2];//LBPROT0_NV

                                    STR1V[4] = WRAR_reg_in[4];//LBPROT2
                                    STR1V[3] = WRAR_reg_in[3];//LBPROT1
                                    STR1V[2] = WRAR_reg_in[2];//LBPROT0

                                    BP_bits = {STR1V[4],STR1V[3],STR1V[2]};

                                    change_BP    = 1'b1;
                                    #1 change_BP = 1'b0;
                            end
                        end
                    end
                    else if (Addr == 32'h00000002) // CFR1_NV;
                    begin
                        if (PLPROT_O == 1'b0 && ASPPER)
                        begin
                            CFR1N[4] = WRAR_reg_in[4];//PLPROT_O
                            CFR1V[4] = WRAR_reg_in[4];//PLPROT
                            if (~TLPROT)
                            begin
                                CFR1N[6] = WRAR_reg_in[6];// SP4KBS_NV
                                CFR1V[6] = WRAR_reg_in[6];//SP4KBS  
                                CFR1N[5] = WRAR_reg_in[5];//TBPROT_NV
                                CFR1V[5] = WRAR_reg_in[5];//TBPROT 
                                
                                CFR1N[2] = WRAR_reg_in[2];//TB4KBS_NV
                                CFR1V[2] = WRAR_reg_in[2];//TB4KBS
                                change_TBPARM = 1'b1;
                                #1 change_TBPARM = 1'b0;
                            end
                        end
                    end
                    else if (Addr == 32'h00000003) // CFR2_NV
                    begin
                            CFR2N[3:0] = WRAR_reg_in[3:0];// RL_NV[3:0]
                            CFR2V[3:0] = WRAR_reg_in[3:0];// RL[3:0]
                            CFR2N[7]   = WRAR_reg_in[7];  // ADRBYT_NV
                            CFR2V[7]   = WRAR_reg_in[7];  // ADRBYT_V
                    end
                    else if (Addr == 32'h00000004) // CFR3_NV
                    begin
                        CFR3N[7] = WRAR_reg_in[7];// VRGLAT
                        CFR3V[6] = WRAR_reg_in[6];// VRGLAT
                        CFR3N[5] = WRAR_reg_in[5];// BLKCHK_NV
                        CFR3V[5] = WRAR_reg_in[5];// BLKCHK_V

                        CFR3N[4] = WRAR_reg_in[4];// PGMBUF_NV
                        CFR3V[4] = WRAR_reg_in[4];// PGMBUF_V

                        if (CFR3N[4] == 1'b0)
                        begin
                            change_PageSize = 1'b1;
                            #1 change_PageSize = 1'b0;
                        end
                        if (ASPPER)
                        begin
                            CFR3N[3] = WRAR_reg_in[3];// UNHYSA_NV
                            CFR3V[3] = WRAR_reg_in[3];// UNHYSA_V
                        end
                    end
                    else if (Addr == 32'h00000005) // CFR4N
                    begin
//                         if (CFR4N[7:5] == 3'b000)
//                         begin
                            CFR4N[7:5] = WRAR_reg_in[7:5];// IOIMPD_NV[2:0]
                            CFR4V[7:5] = WRAR_reg_in[7:5];// IOIMPD[2:0]
//                         end

//                         if (CFR4N[4] == 1'b0)
//                         begin
                            CFR4N[4] = WRAR_reg_in[4];// RBSTWP_NV
                            CFR4V[4] = WRAR_reg_in[4];// RBSTWP
//                         end
                        
//                         if (CFR4N[3] == 1'b0)
//                         begin
                            CFR4N[3] = WRAR_reg_in[3];// ECC12S
                            CFR4V[3] = WRAR_reg_in[3];// ECC12S
//                         end
                        
                        CFR4N[2] = WRAR_reg_in[2];// DPDPOR_NV
                        CFR4V[2]  = WRAR_reg_in[2];// DPDPOR 

//                         if (CFR4N[1:0] == 2'b00)
//                         begin
                            CFR4N[1:0] = WRAR_reg_in[1:0];// RBSTWL_NV[1:0]
                            CFR4V[1:0] = WRAR_reg_in[1:0];// RBSTWL[1:0]
//                         end
                    end
                    else if (Addr == 32'h00000006) // CFR5N
                    begin

//                             CFR5N[7] = WRAR_reg_in[7];// DSOSDR_NV // new spec
//                             CFR5V[7] = WRAR_reg_in[7];// DSOSDR
// 
// 
// 
//                             CFR5N[6] = WRAR_reg_in[6];// PDSSDR_NV
//                             CFR5V[6] = WRAR_reg_in[6];// PDSSDR


//                         if (CFR5N[1] == 1'b0)
//                         begin
                            CFR5N[1] = WRAR_reg_in[1];// DDR_NV
                            CFR5V[1] = WRAR_reg_in[1];// SDRDDR
//                         end

//                         if (CFR5N[0] == 1'b0)
//                         begin
                            CFR5N[0] = WRAR_reg_in[0];// OPI_NV
                            CFR5V[0] = WRAR_reg_in[0];// OPI_IT
//                         end
                    end
                    else if (Addr == 32'h00000020)
                    // Password_reg[7:0];
                    begin
                        PWDO[7:0] = new_pass_byte;
                    end
                    else if (Addr == 32'h00000021)
                    // Password_reg[15:8];
                    begin
                        PWDO[15:8] = new_pass_byte;
                    end
                    else if (Addr == 32'h00000022)
                    // Password_reg[23:16];
                    begin
                        PWDO[23:16] = new_pass_byte;
                    end
                    else if (Addr == 32'h00000023)
                    // Password_reg[31:24];
                    begin
                        PWDO[31:24] = new_pass_byte;
                    end
                    else if (Addr == 32'h00000024)
                    // Password_reg[39:32];
                    begin
                        PWDO[39:32] = new_pass_byte;
                    end
                    else if (Addr == 32'h00000025)
                    // Password_reg[47:40];
                    begin
                        PWDO[47:40] = new_pass_byte;
                    end
                    else if (Addr == 32'h00000026)
                    // Password_reg[55:48];
                    begin
                        PWDO[55:48] = new_pass_byte;
                    end
                    else if (Addr == 32'h00000027)
                    // Password_reg[63:56];
                    begin
                        PWDO[63:56] = new_pass_byte;
                    end
                    else if (Addr == 32'h00000030) // ASP_reg[7:0]
                    begin
                        if (ASPDYB == 1'b0 && WRAR_reg_in[4] == 1'b1)
                                $display("ASPDYB bit is allready programmed");
                            else
                                ASPO[4] = WRAR_reg_in[4];//ASPDYB

                            if (ASPPPB == 1'b0 && WRAR_reg_in[3] == 1'b1)
                                $display("ASPPPB bit is allready programmed");
                            else
                                ASPO[3] = WRAR_reg_in[3];//ASPPPB

                            if (ASPPRM == 1'b0 && WRAR_reg_in[0] == 1'b1)
                                $display("ASPPRM bit is allready programmed");
                            else
                                ASPO[0] = WRAR_reg_in[0];//ASPPRM

                        ASPO[2] = WRAR_reg_in[2];//ASPPWD
                        ASPO[1] = WRAR_reg_in[1];//ASPPER
                    end
                    else if (Addr == 32'h00000031)
                    // ASP_reg[15:8];
                    begin
                        $display("RFU bits");
                    end
                    else if (Addr == 32'h00000042) // 
                    begin
                        ATBN[7:0] = WRAR_reg_in[7:0];// 
                    end
                    else if (Addr == 32'h00000043) // 
                    begin
                        ATBN[15:8] = WRAR_reg_in[7:0];// 
                    end
                    else if (Addr == 32'h00000044) // 
                    begin
                        ATBN[23:16] = WRAR_reg_in[7:0];// 
                    end
                    else if (Addr == 32'h00000045) // 
                    begin
                        ATBN[31:24] = WRAR_reg_in[7:0];// 
                    end
                    else if (Addr == 32'h00800000) // SR1_V
                    begin
                        if (~PLPROT_O)
                        begin
                            if (TLPROT == 0)
                            //The Freeze Bit, when set to 1, locks the current
                            //state of the LBPROT2-0 bits in Status Register.
                            begin
                                    STR1V[4] = WRAR_reg_in[4];//LBPROT2
                                    STR1V[3] = WRAR_reg_in[3];//LBPROT1
                                    STR1V[2] = WRAR_reg_in[2];//LBPROT0

                                    BP_bits = {STR1V[4],STR1V[3],STR1V[2]};

                                    change_BP    = 1'b1;
                                    #1 change_BP = 1'b0;
                            end
                        end
                    end
                    else if (Addr == 32'h00800001) // SR2_V
                    begin
                        $display("Status Register 2 does not have user ");
                        $display("programmable bits, all defined bits are  ");
                        $display("volatile read only status.");
                    end
                    else if (Addr == 32'h00800002) // CFR1_V
                    begin
                        
                        CFR1V[0] = WRAR_reg_in[0];// TLPROT
     
                    end
                    else if (Addr == 32'h00800003) // CR2_V
                    begin
                        CFR2V[3:0] = WRAR_reg_in[3:0];// MEMLAT[3:0]
                        CFR2V[7]   = WRAR_reg_in[7];  // ADRBYT_V
                    end
                    else if (Addr == 32'h00800004) // CR3_V
                    begin
                        CFR3V[7:6] = WRAR_reg_in[7:6];// VRGLAT
                        CFR3V[5] = WRAR_reg_in[5];// BLKCHK
                        CFR3V[4] = WRAR_reg_in[4];// PGMBUF

                        change_PageSize = 1'b1;
                        #1 change_PageSize = 1'b0;

                    end
                    else if (Addr == 32'h00800005) // CFR4V
                    begin
                        CFR4V[7:5] = WRAR_reg_in[7:5];// OI[2:0]
                        CFR4V[4]   = WRAR_reg_in[4];  // WE
                        CFR4V[3]  = WRAR_reg_in[3];//
                        CFR4V[1:0] = WRAR_reg_in[1:0];// WL[1:0]
                    end
                    else if (Addr == 32'h00800006) // CR5_V
                    begin
//                         CFR5V[7] = WRAR_reg_in[7];// DSOSDR //new spec
//                         CFR5V[6] = WRAR_reg_in[6];// PDSSDR
                        CFR5V[1] = WRAR_reg_in[1];// SDRDDR
                        CFR5V[0] = WRAR_reg_in[0];// OPI_IT
                    end
                    else if (Addr == 32'h00800008) // ICEV
                    begin
                        ICEV[0] = WRAR_reg_in[0]; // ITCRCE
                    end
                    else if (Addr == 32'h00800068 && OPI_IT) // INCV
                    begin
                        INCV[7] = WRAR_reg_in[7];
                        INCV[4] = WRAR_reg_in[4];
                        INCV[1] = WRAR_reg_in[1]; 
                        INCV[0] = WRAR_reg_in[0]; 
                    end
                    else if (Addr == 32'h00800067) // INSV
                    begin
                        INSV[4] = WRAR_reg_in[4];
                        INSV[1] = WRAR_reg_in[1]; 
                        INSV[0] = WRAR_reg_in[0]; 
                    end
                end
            end

            PAGE_PG :
            begin
                if (OPI_IT)
                begin
                    rd_fast = 1'b1;
                    rd_slow = 1'b0;
                    dual    = 1'b1;
                    ddr     = 1'b0;
                end
                else
                begin
                    rd_fast = 1'b1;
                    rd_slow = 1'b0;
                    dual    = 1'b0;
                    ddr     = 1'b0;
                end

                if (oe)
                begin
                    any_read = 1'b1;
                    if (Instruct == RDSR1)
                    begin
                    //Read Status Register 1
                        if (OPI_IT)
                        begin
                            data_out[7:0] = STR1V;
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            DataDriveOut_SO = data_out[1-read_cnt];
                            DataDriveOut_SI = data_out[0-read_cnt];

                            read_cnt = read_cnt + 1;
                            if (read_cnt == 1)
                            begin
                                read_cnt = 0;
                            end
                        end
                        else
                        begin
                            DataDriveOut_SO = STR1V[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                    else if (Instruct == RDSR2)
                    begin
                        //Read Status Register 2
                        if (OPI_IT)
                        begin
                            data_out[7:0] = STR2V;
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            DataDriveOut_SO = data_out[1-read_cnt];
                            DataDriveOut_SI = data_out[0-read_cnt];

                            read_cnt = read_cnt + 1;
                            if (read_cnt == 1)
                            begin
                                read_cnt = 0;
                            end
                        end
                        else
                        begin
                            DataDriveOut_SO = STR2V[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                    else if (Instruct == RDARG_4_0)
                    begin
                        READ_ALL_REG(read_addr, RDAR_reg);

                        if (OPI_IT)
                        begin
                            data_out[7:0]  = RDAR_reg;
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            DataDriveOut_SO = data_out[1-read_cnt];
                            DataDriveOut_SI = data_out[0-read_cnt];

                            read_cnt = read_cnt + 1;
                            if (read_cnt == 1)
                            begin
                                read_cnt = 0;
                            end
                        end
                        else
                        begin
                            data_out[7:0]  = RDAR_reg;
                            DataDriveOut_SO = data_out[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                end

                if(current_state_event && current_state == PAGE_PG)
                begin
                    if (~PDONE)
                    begin
                        ADDRHILO_PG(AddrLo, AddrHi, Addr);
                        cnt = 0;

                        for (i=0;i<=wr_cnt;i=i+1)
                        begin
                            new_int = WData[i];
                            old_int = Mem[Addr + i - cnt];
                            if (new_int > -1)
                            begin
                                new_bit = new_int;
                                if (old_int > -1)
                                begin
                                    old_bit = old_int;
                                    for(j=0;j<=7;j=j+1)
                                    begin
                                        if (~old_bit[j])
                                            new_bit[j]=1'b0;
                                    end
                                    new_int=new_bit;
                                end
                                WData[i]= new_int;
                            end
                            else
                            begin
                                WData[i] = -1;
                            end

                            Mem[Addr + i - cnt] = - 1;
                            if ((Addr + i) == AddrHi)
                            begin
                                Addr = AddrLo;
                                cnt = i + 1;
                            end
                        end
                    end
                    cnt = 0;
                end

                if (PDONE)
                begin
                    
                    if (((CFR4V[3] == 1'b1)  || (non_industrial_temp == 1'b1)) 
                          && (ECC_ERR > 0))
                    begin
                        STR1V[0] = 1'b1; //RDYBSY
                        STR1V[1] = 1'b1; //WRPGEN
                        STR1V[6] = 1'b1; //PRGERR
                        $display ("WARNING: For non-industrial temperatures ");
                        $display ("it is not allowed to have multi-programming ");
                        $display ("without erasing previously the sector!");
                        $display ("multi-pass programming within the same data unit");
                        $display ("will result in a Program Error.");
                        ECC_ERR = 0;
                    end
                    else
                    begin
                        STR1V[0] = 1'b0; //RDYBSY
                        STR1V[1] = 1'b0; //WRPGEN
                        ECC_ERR = 0;
                    end

                    for (i=0;i<=wr_cnt;i=i+1)
                    begin
                        Mem[Addr_tmp + i - cnt] = WData[i];
                        if ((Addr_tmp + i) == AddrHi)
                        begin
                            Addr_tmp = AddrLo;
                            cnt = i + 1;
                        end
                    end
                end

                if (falling_edge_write)
                begin
                    if ((Instruct == SPEPD_0_0) && ~PRGSUSP_in)
                    begin
                        if (~RES_TO_SUSP_TIME)
                        begin
                            PGSUSP = 1'b1;
                            PGSUSP <= #5 1'b0;
                            PRGSUSP_in = 1'b1;
                        end
                        else
                        begin
                            $display("Minimum for tRS is not satisfied! ",
                                     "PGSP command is ignored");
                        end
                    end
                end
            end

            PG_SUSP:
            begin
                if (OPI_IT)
                begin
                    rd_fast = 1'b1;
                    rd_slow = 1'b0;
                    dual    = 1'b1;
                    ddr     = 1'b0;
                end
                else
                begin
                    rd_fast = 1'b1;
                    rd_slow = 1'b0;
                    dual    = 1'b0;
                    ddr     = 1'b0;
                end

                if (PRGSUSP_out && PRGSUSP_in)
                begin
                    PRGSUSP_in = 1'b0;
                    //The RDYBSY bit in the Status Register will indicate that
                    //the device is ready for another operation.
                    STR1V[0] = 1'b0;
                    //The Program Suspend (PROGMS) bit in the Status Register will
                    //be set to the logical “1” state to indicate that the
                    //program operation has been suspended.
                    STR2V[0] = 1'b1;
                end

                if (oe)
                begin
                    any_read = 1'b1;
                    if (Instruct == RDSR1)
                    begin
                    //Read Status Register 1
                        if (OPI_IT)
                        begin
                            data_out[7:0] = STR1V;
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            DataDriveOut_SO = data_out[1-read_cnt];
                            DataDriveOut_SI = data_out[0-read_cnt];

                            read_cnt = read_cnt + 1;
                            if (read_cnt == 1)
                            begin
                                read_cnt = 0;
                            end
                        end
                        else
                        begin
                            DataDriveOut_SO = STR1V[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                    else if (Instruct == RDSR2)
                    begin
                        //Read Status Register 2
                        if (OPI_IT)
                        begin
                            data_out[7:0] = STR2V;
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            DataDriveOut_SO = data_out[1-read_cnt];
                            DataDriveOut_SI = data_out[0-read_cnt];

                            read_cnt = read_cnt + 1;
                            if (read_cnt == 1)
                            begin
                                read_cnt = 0;
                            end
                        end
                        else
                        begin
                            DataDriveOut_SO = STR2V[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                    else if (Instruct == RDARG_4_0)
                    begin
                        READ_ALL_REG(read_addr, RDAR_reg);

                        if (OPI_IT)
                        begin
                            data_out[7:0]  = RDAR_reg;
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            DataDriveOut_SO = data_out[1-read_cnt];
                            DataDriveOut_SI = data_out[0-read_cnt];

                            read_cnt = read_cnt + 1;
                            if (read_cnt == 1)
                            begin
                                read_cnt = 0;
                            end
                        end
                        else
                        begin
                            data_out[7:0]  = RDAR_reg;
                            DataDriveOut_SO = data_out[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                    else if (Instruct == RDCRC_4_0)
                    begin
                        if (Addr_idcfi <= 3)
                        begin
                            data_out[7:0] = ICRV[8*Addr_idcfi+7 -: 8];
                            if (OPI_IT)
                            begin
                                for (i=0;i<=5;i=i+1)
                                begin
                                    DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                                end
                                DataDriveOut_SO = data_out[1-read_cnt];
                                DataDriveOut_SI = data_out[0-read_cnt];
                                read_cnt = read_cnt + 1;
                                if (read_cnt == 1)
                                begin
                                    read_cnt = 0;
                                    Addr_idcfi = Addr_idcfi + 1;
                                end
                            end
                        end
                    end
                    else if ((Instruct == RDAY1_C_0) || ((Instruct == RDAY1_4_0) && (~OPI_IT)))
                    begin
                        //Read Memory array
                        rd_fast = 1'b0;
                        rd_slow = 1'b1;
                        dual    = 1'b0;
                        ddr     = 1'b0;

                        if (pgm_page != read_addr / (PageSize+1))
                        begin
                            data_out[7:0] = Mem[read_addr];
                            DataDriveOut_SO  = data_out[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                            begin
                                read_cnt = 0;
                                if (read_addr >= AddrRANGE)
                                    read_addr = 0;
                                else
                                    read_addr = read_addr + 1;
                            end
                        end
                        else
                        begin
                            DataDriveOut_SO  = 8'bxxxxxxxx;
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                            begin
                                read_cnt = 0;
                                if (read_addr == AddrRANGE)
                                    read_addr = 0;
                                else
                                    read_addr = read_addr + 1;
                            end
                        end
                    end
                    else if ((Instruct == RDAY2_C_0) && (~OPI_IT))
                    begin

                        if (pgm_page != read_addr / (PageSize+1))
                        begin
                            data_out[7:0] = Mem[read_addr];
                            DataDriveOut_SO  = data_out[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                            begin
                                read_cnt = 0;

                                if (~CFR4V[4])  //Wrap Disabled
                                begin
                                    if (read_addr == AddrRANGE)
                                        read_addr = 0;
                                    else
                                        read_addr = read_addr + 1;
                                end
                                else           //Wrap Enabled
                                begin
                                    read_addr = read_addr + 1;

                                    if (read_addr % WrapLength == 0)
                                        read_addr = read_addr - WrapLength;
                                end
                            end
                        end
                        else
                        begin
                            DataDriveOut_SO  = 8'bxxxxxxxx;
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                            begin
                                read_cnt = 0;

                                if (~CFR4V[4])  //Wrap Disabled
                                begin
                                    if (read_addr == AddrRANGE)
                                        read_addr = 0;
                                    else
                                        read_addr = read_addr + 1;
                                end
                                else           //Wrap Enabled
                                begin
                                    read_addr = read_addr + 1;

                                    if (read_addr % WrapLength == 0)
                                        read_addr = read_addr - WrapLength;
                                end
                            end
                        end
                    end
                end
                else if (oe_z)
                begin
                    if ((Instruct == RDAY1_C_0) || ((Instruct == RDAY1_4_0) && (~OPI_IT)))
                    begin
                        rd_fast = 1'b0;
                        rd_slow = 1'b1;
                        dual    = 1'b0;
                        ddr     = 1'b0;
                    end
                    else
                    begin
                        rd_fast = 1'b1;
                        rd_slow = 1'b0;
                        dual    = 1'b0;
                        ddr     = 1'b0;
                    end
                end

                if (falling_edge_write)
                begin
                    if (Instruct == RSEPD_0_0)
                    begin
                        STR2V[0] = 1'b0; // PROGMS
                        STR1V[0] = 1'b1; // RDYBSY
                        PGRES  = 1'b1;
                        PGRES <= #5 1'b0;
                        RES_TO_SUSP_TIME = 1'b1;
                        RES_TO_SUSP_TIME <= #tdevice_RS 1'b0;//100us
                    end
                    else if (Instruct == CLECC_0_0)
                    begin
                        ESCV[4] = 0;// 2 bits ECC detection
                        ESCV[3] = 0;// 1 bit ECC correction
                        INSV[1] = 1;
                        INSV[0] = 1;
                        ECTV = 16'h0000;
                        EATV = 32'h00000000;
                    end
                    else if (Instruct == CLPEF_0_0)
                    begin
                        STR1V[6] = 0;// PRGERR
                        STR1V[5] = 0;// ERSERR
                        STR1V[0] = 0;// RDYBSY
                    end

                    if (Instruct == SRSTE_0_0)
                    begin
                        RESET_EN = 1;
                    end
                    else
                    begin
                        RESET_EN <= 0;
                    end
                end
            end

            OTP_PG:
            begin
                rd_fast = 1'b1;
                rd_slow = 1'b0;
                dual    = 1'b0;
                ddr     = 1'b0;

                if (oe)
                begin
                    any_read = 1'b1;
                    if (Instruct == RDSR1)
                    begin
                    //Read Status Register 1
                        if (OPI_IT)
                        begin
                            data_out[7:0] = STR1V;
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            DataDriveOut_SO = data_out[1-read_cnt];
                            DataDriveOut_SI = data_out[0-read_cnt];

                            read_cnt = read_cnt + 1;
                            if (read_cnt == 1)
                            begin
                                read_cnt = 0;
                            end
                        end
                        else
                        begin
                            DataDriveOut_SO = STR1V[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                    else if (Instruct == RDSR2)
                    begin
                        //Read Status Register 2
                        if (OPI_IT)
                        begin
                            data_out[7:0] = STR2V;
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            DataDriveOut_SO = data_out[1-read_cnt];
                            DataDriveOut_SI = data_out[0-read_cnt];

                            read_cnt = read_cnt + 1;
                            if (read_cnt == 1)
                            begin
                                read_cnt = 0;
                            end
                        end
                        else
                        begin
                            DataDriveOut_SO = STR2V[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                    else if (Instruct == RDARG_4_0)
                    begin
                        READ_ALL_REG(read_addr, RDAR_reg);

                        if (OPI_IT)
                        begin
                            data_out[7:0]  = RDAR_reg;
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            DataDriveOut_SO = data_out[1-read_cnt];
                            DataDriveOut_SI = data_out[0-read_cnt];

                            read_cnt = read_cnt + 1;
                            if (read_cnt == 1)
                            begin
                                read_cnt = 0;
                            end
                        end
                        else
                        begin
                            DataDriveOut_SO = RDAR_reg[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                end

                if(current_state_event && current_state == OTP_PG)
                begin
                    if (~PDONE)
                    begin

                        for (i=0;i<=wr_cnt;i=i+1)
                        begin
                            new_int = WData[i];
                            old_int = OTPMem[Addr + i];
                            if (new_int > -1)
                            begin
                                new_bit = new_int;
                                if (old_int > -1)
                                begin
                                    old_bit = old_int;
                                    for(j=0;j<=7;j=j+1)
                                    begin
                                        if (~old_bit[j])
                                            new_bit[j] = 1'b0;
                                    end
                                    new_int = new_bit;
                                end
                                WData[i] = new_int;
                            end
                            else
                            begin
                                WData[i] = -1;
                            end
                            OTPMem[Addr + i] =  -1;
                        end
                    end
                end

                if (PDONE)
                begin

                    
                    if (((CFR4V[3] == 1'b1)  || (non_industrial_temp == 1'b1)) 
                          && (ECC_ERR > 0) )
                    begin
                        STR1V[0] = 1'b1; //RDYBSY
                        STR1V[1] = 1'b1; //WRPGEN
                        STR1V[6] = 1'b1; //PRGERR
                        ECC_ERR = 0;
                        $display ("WARNING: For non-industrial temperatures ");
                        $display ("it is not allowed to have multi-programming ");
                        $display ("without erasing previously the sector!");
                        $display ("multi-pass programming within the same sector will result in a Program Error.");
                    end
                    else
                    begin
                        STR1V[0] = 1'b0; //RDYBSY
                        STR1V[1] = 1'b0; //WRPGEN
                        ECC_ERR = 0;
                    end

                    for (i=0;i<=wr_cnt;i=i+1)
                    begin
                        OTPMem[Addr + i] = WData[i];
                    end
                    LOCK_BYTE1 = OTPMem[16];
                    LOCK_BYTE2 = OTPMem[17];
                    LOCK_BYTE3 = OTPMem[18];
                    LOCK_BYTE4 = OTPMem[19];
                end
            end

            CRC_Calc:
            begin
                if (OPI_IT)
                begin
                    rd_fast = 1'b1;
                    rd_slow = 1'b0;
                    dual    = 1'b1;
                    ddr     = 1'b0;
                end
                else
                begin
                    rd_fast = 1'b1;
                    rd_slow = 1'b0;
                    dual    = 1'b0;
                    ddr     = 1'b0;
                end

                if (oe)
                begin
                    any_read = 1'b1;
                    if (Instruct == RDSR1)
                    begin
                    //Read Status Register 1
                        DataDriveOut_SO = STR1V[7-read_cnt];
                        read_cnt = read_cnt + 1;
                        if (read_cnt == 8)
                            read_cnt = 0;
                    end
                end

                CRC_ACT      = 1'b1;
                CRC_RD_SETUP =  1'b1;

                if (rising_edge_CRCDONE)
                begin
                    crc_out = 32'h00000000;
                    for (i=CRC_Start_Addr_reg;i<=CRC_End_Addr_reg;i=i+1)
                    begin
                        crc_in = Mem[i];
                        for (j=15;j>=0;j=j-1)
                        begin
                            crc_tmp = crc_out[31] ^ crc_in[j];

                            crc_out[31] = crc_out[30];
                            crc_out[30] = crc_out[29];
                            crc_out[29] = crc_out[28];
                            crc_out[28] = crc_out[27] ^ crc_tmp;
                            crc_out[27] = crc_out[26] ^ crc_tmp;
                            crc_out[26] = crc_out[25] ^ crc_tmp;
                            crc_out[25] = crc_out[24] ^ crc_tmp;
                            crc_out[24] = crc_out[23];
                            crc_out[23] = crc_out[22] ^ crc_tmp;
                            crc_out[22] = crc_out[21] ^ crc_tmp;
                            crc_out[21] = crc_out[20];
                            crc_out[20] = crc_out[19] ^ crc_tmp;
                            crc_out[19] = crc_out[18] ^ crc_tmp;
                            crc_out[18] = crc_out[17] ^ crc_tmp;
                            crc_out[17] = crc_out[16];
                            crc_out[16] = crc_out[15];
                            crc_out[15] = crc_out[14];
                            crc_out[14] = crc_out[13] ^ crc_tmp;
                            crc_out[13] = crc_out[12] ^ crc_tmp;
                            crc_out[12] = crc_out[11];
                            crc_out[11] = crc_out[10] ^ crc_tmp;
                            crc_out[10] = crc_out[9] ^ crc_tmp;
                            crc_out[9] = crc_out[8] ^ crc_tmp;
                            crc_out[8] = crc_out[7] ^ crc_tmp;
                            crc_out[7] = crc_out[6];
                            crc_out[6] = crc_out[5] ^ crc_tmp;
                            crc_out[5] = crc_out[4];
                            crc_out[4] = crc_out[3];
                            crc_out[3] = crc_out[2];
                            crc_out[2] = crc_out[1];
                            crc_out[1] = crc_out[0];
                            crc_out[0] = crc_tmp;
                        end
                    end
                    DCRV = crc_out;
                    STR1V[0] = 1'b0; // RDYBSY
                end
            end

            CRC_SUSP:
            begin
                if (OPI_IT)
                begin
                    rd_fast = 1'b1;
                    rd_slow = 1'b0;
                    dual    = 1'b1;
                    ddr     = 1'b0;
                end
                else
                begin
                    rd_fast = 1'b1;
                    rd_slow = 1'b0;
                    dual    = 1'b0;
                    ddr     = 1'b0;
                end

                if (sSTART_T1 && START_T1_in)
                begin
                    START_T1_in = 1'b0;
                    //The RDYBSY bit in the Status Register will indicate that
                    //the device is ready for another operation.
                    STR1V[0] = 1'b0;
                    //The CRC Suspend (DICRCS) bit in the Status Register will
                    //be set to the logical “1” state to indicate that the
                    //CRC operation has been suspended.
                    STR2V[4] = 1'b1;
                end

                if (oe)
                begin
                    any_read = 1'b1;
                    if (Instruct == RDSR1)
                    begin
                    //Read Status Register 1
                        if (OPI_IT)
                        begin
                            data_out[7:0] = STR1V;
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            DataDriveOut_SO = data_out[1-read_cnt];
                            DataDriveOut_SI = data_out[0-read_cnt];

                            read_cnt = read_cnt + 1;
                            if (read_cnt == 1)
                            begin
                                read_cnt = 0;
                            end
                        end
                        else
                        begin
                            DataDriveOut_SO = STR1V[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                    else if (Instruct == RDSR2)
                    begin
                        //Read Status Register 2
                        if (OPI_IT)
                        begin
                            data_out[7:0] = STR2V;
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            DataDriveOut_SO = data_out[1-read_cnt];
                            DataDriveOut_SI = data_out[0-read_cnt];

                            read_cnt = read_cnt + 1;
                            if (read_cnt == 1)
                            begin
                                read_cnt = 0;
                            end
                        end
                        else
                        begin
                            DataDriveOut_SO = STR2V[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                    else if (Instruct == RDARG_4_0)
                    begin
                        READ_ALL_REG(read_addr, RDAR_reg);

                        if (OPI_IT)
                        begin
                            data_out[7:0]  = RDAR_reg;
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            DataDriveOut_SO = data_out[1-read_cnt];
                            DataDriveOut_SI = data_out[0-read_cnt];

                            read_cnt = read_cnt + 1;
                            if (read_cnt == 1)
                            begin
                                read_cnt = 0;
                            end
                        end
                        else
                        begin
                            data_out[7:0]  = RDAR_reg;
                            DataDriveOut_SO = data_out[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                    else if ((Instruct == RDAY1_C_0) || ((Instruct == RDAY1_4_0) && (~OPI_IT)))
                    begin
                        //Read Memory array
                        rd_fast = 1'b0;
                        rd_slow = 1'b1;
                        dual    = 1'b0;
                        ddr     = 1'b0;

                        if (pgm_page != read_addr / (PageSize+1))
                        begin
                            data_out[7:0] = Mem[read_addr];
                            DataDriveOut_SO  = data_out[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                            begin
                                read_cnt = 0;
                                if (read_addr >= AddrRANGE)
                                    read_addr = 0;
                                else
                                    read_addr = read_addr + 1;
                            end
                        end
                        else
                        begin
                            DataDriveOut_SO  = 8'bxxxxxxxx;
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                            begin
                                read_cnt = 0;
                                if (read_addr == AddrRANGE)
                                    read_addr = 0;
                                else
                                    read_addr = read_addr + 1;
                            end
                        end
                    end
                    else if ((Instruct == RDAY2_C_0) && (~OPI_IT))
                    begin

                        if (pgm_page != read_addr / (PageSize+1))
                        begin
                            data_out[7:0] = Mem[read_addr];
                            DataDriveOut_SO  = data_out[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                            begin
                                read_cnt = 0;

                                if (~CFR4V[4])  //Wrap Disabled
                                begin
                                    if (read_addr == AddrRANGE)
                                        read_addr = 0;
                                    else
                                        read_addr = read_addr + 1;
                                end
                                else           //Wrap Enabled
                                begin
                                    read_addr = read_addr + 1;

                                    if (read_addr % WrapLength == 0)
                                        read_addr = read_addr - WrapLength;
                                end
                            end
                        end
                        else
                        begin
                            DataDriveOut_SO  = 8'bxxxxxxxx;
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                            begin
                                read_cnt = 0;

                                if (~CFR4V[4])  //Wrap Disabled
                                begin
                                    if (read_addr == AddrRANGE)
                                        read_addr = 0;
                                    else
                                        read_addr = read_addr + 1;
                                end
                                else           //Wrap Enabled
                                begin
                                    read_addr = read_addr + 1;

                                    if (read_addr % WrapLength == 0)
                                        read_addr = read_addr - WrapLength;
                                end
                            end
                        end
                    end
                end
                else if (oe_z)
                begin
                    if ((Instruct == RDAY1_C_0) || ((Instruct == RDAY1_4_0) && (~OPI_IT)))
                    begin
                        rd_fast = 1'b0;
                        rd_slow = 1'b1;
                        dual    = 1'b0;
                        ddr     = 1'b0;
                    end
                    else
                    begin
                        rd_fast = 1'b1;
                        rd_slow = 1'b0;
                        dual    = 1'b0;
                        ddr     = 1'b0;
                    end
                end

                if (falling_edge_write)
                begin
                    if (Instruct == RSEPD_0_0)
                    begin
                        STR2V[4] = 1'b0; // DICRCS
                        STR1V[0] = 1'b1; // RDYBSY
                        CRCRES  = 1'b1;
                        CRCRES <= #5 1'b0;
                        RES_TO_SUSP_TIME = 1'b1;
                        RES_TO_SUSP_TIME <= #tdevice_CRCRL 1'b0;// 5us
                    end

                    if (Instruct == SRSTE_0_0)
                    begin
                        RESET_EN = 1;
                    end
                    else
                    begin
                        RESET_EN <= 0;
                    end
                end
            end

            SECTOR_ERS:
            begin
                if (OPI_IT)
                begin
                    rd_fast = 1'b1;
                    rd_slow = 1'b0;
                    dual    = 1'b1;
                    ddr     = 1'b0;
                end
                else
                begin
                    rd_fast = 1'b1;
                    rd_slow = 1'b0;
                    dual    = 1'b0;
                    ddr     = 1'b0;
                end

                if (oe)
                begin
                    any_read = 1'b1;
                    if (Instruct == RDSR1)
                    begin
                    //Read Status Register 1
                        if (OPI_IT)
                        begin
                            data_out[7:0] = STR1V;
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            DataDriveOut_SO = data_out[1-read_cnt];
                            DataDriveOut_SI = data_out[0-read_cnt];

                            read_cnt = read_cnt + 1;
                            if (read_cnt == 1)
                            begin
                                read_cnt = 0;
                            end
                        end
                        else
                        begin
                            DataDriveOut_SO = STR1V[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                    else if (Instruct == RDSR2)
                    begin
                        //Read Status Register 2
                        if (OPI_IT)
                        begin
                            data_out[7:0] = STR2V;
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            DataDriveOut_SO = data_out[1-read_cnt];
                            DataDriveOut_SI = data_out[0-read_cnt];

                            read_cnt = read_cnt + 1;
                            if (read_cnt == 1)
                            begin
                                read_cnt = 0;
                            end
                        end
                        else
                        begin
                            DataDriveOut_SO = STR2V[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                    else if (Instruct == RDARG_4_0)
                    begin
                        READ_ALL_REG(read_addr, RDAR_reg);

                        if (OPI_IT)
                        begin
                            data_out[7:0]  = RDAR_reg;
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            DataDriveOut_SO = data_out[1-read_cnt];
                            DataDriveOut_SI = data_out[0-read_cnt];

                            read_cnt = read_cnt + 1;
                            if (read_cnt == 1)
                            begin
                                read_cnt = 0;
                            end
                        end
                        else
                        begin
                            data_out[7:0]  = RDAR_reg;
                            DataDriveOut_SO = data_out[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                end

                if(current_state_event && current_state == SECTOR_ERS)
                begin
                    if (~EDONE)
                    begin
                        ADDRHILO_SEC(AddrLo, AddrHi, Addr);
                        for (i=AddrLo;i<=AddrHi;i=i+1)
                        begin
                            Mem[i] = -1;
                        end
                    end
                end

                if (EDONE == 1)
                begin
                    STR1V[0] = 1'b0; //RDYBSY
                    STR1V[1] = 1'b0; //WRPGEN
                    ERS_nosucc[SectorErased] = 1'b0;

                    // Increment Sector Erase Count register for a given Sector
                    SECV_in[SectorErased] = SECV_in[SectorErased] + 24'h000001;

                    // Erase multi-pass sector flags register
                    MPASSREG[SectorErased] = 1'b0;

                    for (i=AddrLo;i<=AddrHi;i=i+1)
                    begin
                        Mem[i] = MaxData;
                    end
                end

                if (falling_edge_write)
                begin
                    if ((Instruct == SPEPD_0_0) && ~ERSSUSP_in)
                    begin
                        if (~RES_TO_SUSP_TIME)
                        begin
                            ESUSP      = 1'b1;
                            ESUSP     <= #5 1'b0;
                            ERSSUSP_in = 1'b1;
                        end
                        else
                        begin
                            $display("Minimum for tRS is not satisfied! ",
                                     "PGSP command is ignored");
                        end
                    end
                end
            end

            BULK_ERS:
            begin
                if (OPI_IT)
                begin
                    rd_fast = 1'b1;
                    rd_slow = 1'b0;
                    dual    = 1'b1;
                    ddr     = 1'b0;
                end
                else
                begin
                    rd_fast = 1'b1;
                    rd_slow = 1'b0;
                    dual    = 1'b0;
                    ddr     = 1'b0;
                end

                if (oe)
                begin
                    any_read = 1'b1;
                    if (Instruct == RDSR1)
                    begin
                    //Read Status Register 1
                        if (OPI_IT)
                        begin
                            data_out[7:0] = STR1V;
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            DataDriveOut_SO = data_out[1-read_cnt];
                            DataDriveOut_SI = data_out[0-read_cnt];

                            read_cnt = read_cnt + 1;
                            if (read_cnt == 1)
                            begin
                                read_cnt = 0;
                            end
                        end
                        else
                        begin
                            DataDriveOut_SO = STR1V[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                    else if (Instruct == RDSR2)
                    begin
                        //Read Status Register 2
                        if (OPI_IT)
                        begin
                            data_out[7:0] = STR2V;
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            DataDriveOut_SO = data_out[1-read_cnt];
                            DataDriveOut_SI = data_out[0-read_cnt];

                            read_cnt = read_cnt + 1;
                            if (read_cnt == 1)
                            begin
                                read_cnt = 0;
                            end
                        end
                        else
                        begin
                            DataDriveOut_SO = STR2V[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                    else if (Instruct == RDARG_4_0)
                    begin
                        READ_ALL_REG(read_addr, RDAR_reg);

                        if (OPI_IT)
                        begin
                            data_out[7:0]  = RDAR_reg;
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            DataDriveOut_SO = data_out[1-read_cnt];
                            DataDriveOut_SI = data_out[0-read_cnt];

                            read_cnt = read_cnt + 1;
                            if (read_cnt == 1)
                            begin
                                read_cnt = 0;
                            end
                        end
                        else
                        begin
                            data_out[7:0]  = RDAR_reg;
                            DataDriveOut_SO = data_out[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                end

                if(current_state_event && current_state == BULK_ERS)
                begin
                    if (~EDONE)
                    begin
                        for (i=0;i<=AddrRANGE;i=i+1)
                        begin
                            ReturnSectorID(sect,i);
                            if (PPB_bits[sect] == 1 && DYB_bits[sect] == 1)
                            begin
                                Mem[i] = -1;
                            end
                        end
                    end
                end

                if (EDONE == 1)
                begin
                    STR1V[0] = 1'b0; // RDYBSY
                    STR1V[1] = 1'b0; // WRPGEN
                    for (i=0;i<=AddrRANGE;i=i+1)
                    begin
                        ReturnSectorID(sect,i);
                        if (PPB_bits[sect] == 1 && DYB_bits[sect] == 1)
                        begin
                            Mem[i] = MaxData;
                        end
                    end
                    for (j=0;j<=SecNumHyb;j=j+1)
                    begin
                        // Increment Sector Erase Count register for a given Sector
                        SECV_in[j] = SECV_in[j] + 24'h000001;
                        // Erase multi-pass sector flags register
                        MPASSREG[j] = 1'b0;
                    end
                end
            end

            ERS_SUSP:
            begin
                if (OPI_IT)
                begin
                    rd_fast = 1'b1;
                    rd_slow = 1'b0;
                    dual    = 1'b1;
                    ddr     = 1'b0;
                end
                else
                begin
                    rd_fast = 1'b1;
                    rd_slow = 1'b0;
                    dual    = 1'b0;
                    ddr     = 1'b0;
                end

                if (ERSSUSP_out)
                begin
                    ERSSUSP_in = 0;
                    //The Erase Suspend (ERASES) bit in the Status Register will
                    //be set to the logical “1” state to indicate that the
                    //erase operation has been suspended.
                    STR2V[1] = 1'b1;
                    //The RDYBSY bit in the Status Register will indicate that
                    //the device is ready for another operation.
                    STR1V[0] = 1'b0;
                end

                if (oe)
                begin
                    any_read = 1'b1;
                    if (Instruct == RDSR1)
                    begin
                    //Read Status Register 1
                        if (OPI_IT)
                        begin
                            data_out[7:0] = STR1V;
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            DataDriveOut_SO = data_out[1-read_cnt];
                            DataDriveOut_SI = data_out[0-read_cnt];

                            read_cnt = read_cnt + 1;
                            if (read_cnt == 1)
                            begin
                                read_cnt = 0;
                            end
                        end
                        else
                        begin
                            DataDriveOut_SO = STR1V[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                    else if (Instruct == RDSR2)
                    begin
                        //Read Status Register 2
                        if (OPI_IT)
                        begin
                            data_out[7:0] = STR2V;
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            DataDriveOut_SO = data_out[1-read_cnt];
                            DataDriveOut_SI = data_out[0-read_cnt];

                            read_cnt = read_cnt + 1;
                            if (read_cnt == 1)
                            begin
                                read_cnt = 0;
                            end
                        end
                        else
                        begin
                            DataDriveOut_SO = STR2V[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                    else if (Instruct == RDARG_4_0)
                    begin
                        READ_ALL_REG(read_addr, RDAR_reg);

                        if (OPI_IT)
                        begin
                            data_out[7:0]  = RDAR_reg;
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            DataDriveOut_SO = data_out[1-read_cnt];
                            DataDriveOut_SI = data_out[0-read_cnt];

                            read_cnt = read_cnt + 1;
                            if (read_cnt == 1)
                            begin
                                read_cnt = 0;
                            end
                        end
                        else
                        begin
                            data_out[7:0]  = RDAR_reg;
                            DataDriveOut_SO = data_out[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                    else if (Instruct == RDCRC_4_0)
                    begin
                        if (Addr_idcfi <= 3)
                        begin
                            data_out[7:0] = ICRV[8*Addr_idcfi+7 -: 8];
                            if (OPI_IT)
                            begin
                                for (i=0;i<=5;i=i+1)
                                begin
                                    DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                                end
                                DataDriveOut_SO = data_out[1-read_cnt];
                                DataDriveOut_SI = data_out[0-read_cnt];
                                read_cnt = read_cnt + 1;
                                if (read_cnt == 1)
                                begin
                                    read_cnt = 0;
                                    Addr_idcfi = Addr_idcfi + 1;
                                end
                            end
                        end
                    end
                    else if ((Instruct == RDAY1_C_0) || ((Instruct == RDAY1_4_0) && (~OPI_IT)))
                    begin
                        //Read Memory array
                        rd_fast = 1'b0;
                        rd_slow = 1'b1;
                        dual    = 1'b0;
                        ddr     = 1'b0;

                        if (SectorSuspend != read_addr/(SecSize256+1))
                        begin
                            data_out[7:0] = Mem[read_addr];
                            DataDriveOut_SO  = data_out[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                            begin
                                read_cnt = 0;
                                if (read_addr >= AddrRANGE)
                                    read_addr = 0;
                                else
                                    read_addr = read_addr + 1;
                            end
                        end
                        else
                        begin
                            DataDriveOut_SO  = 8'bxxxxxxxx;
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                            begin
                                read_cnt = 0;
                                if (read_addr == AddrRANGE)
                                    read_addr = 0;
                                else
                                    read_addr = read_addr + 1;
                            end
                        end
                    end
                    else if ((Instruct == RDAY2_C_0) && (~OPI_IT))
                    begin

                        rd_fast = 1'b1;
                        rd_slow = 1'b0;
                        dual    = 1'b0;
                        ddr     = 1'b0;

                        if (SectorSuspend != read_addr/(SecSize256+1))
                        begin
                            data_out[7:0] = Mem[read_addr];
                            DataDriveOut_SO  = data_out[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                            begin
                                read_cnt = 0;

                                if (~CFR4V[4])  //Wrap Disabled
                                begin
                                    if (read_addr == AddrRANGE)
                                        read_addr = 0;
                                    else
                                        read_addr = read_addr + 1;
                                end
                                else           //Wrap Enabled
                                begin
                                    read_addr = read_addr + 1;

                                    if (read_addr % WrapLength == 0)
                                        read_addr = read_addr - WrapLength;
                                end
                            end
                        end
                        else
                        begin
                            DataDriveOut_SO  = 8'bxxxxxxxx;
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                            begin
                                read_cnt = 0;

                                if (~CFR4V[4])  //Wrap Disabled
                                begin
                                    if (read_addr == AddrRANGE)
                                        read_addr = 0;
                                    else
                                        read_addr = read_addr + 1;
                                end
                                else           //Wrap Enabled
                                begin
                                    read_addr = read_addr + 1;

                                    if (read_addr % WrapLength == 0)
                                        read_addr = read_addr - WrapLength;
                                end
                            end
                        end
                    end
                    else if (Instruct == RDDYB_4_0)
                    begin
                    //Read DYB Access Register
                        ReturnSectorID(sect,Address);

                        if (DYB_bits[sect] == 1)
                            DYAV[7:0] = 8'hFF;
                        else
                        begin
                            DYAV[7:0] = 8'h0;
                        end

                        if (OPI_IT)
                        begin
                            DataDriveOut_Dout = DYAV[7:2];
                            DataDriveOut_SO   = DYAV[1];
                            DataDriveOut_SI   = DYAV[0];
                        end
                        else
                        begin
                            DataDriveOut_SO = DYAV[7-read_cnt];
                            read_cnt  = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                    else if (Instruct == RDPPB_4_0)
                    begin
                    //Read PPB Access Register
                        ReturnSectorID(sect,Address);

                        if (PPB_bits[sect] == 1)
                            PPAV[7:0] = 8'hFF;
                        else
                        begin
                            PPAV[7:0] = 8'h0;
                        end

                        if (OPI_IT)
                        begin
                            DataDriveOut_Dout = PPAV[7:2];
                            DataDriveOut_SO   = PPAV[1];
                            DataDriveOut_SI   = PPAV[0];
                        end
                        else
                        begin
                            DataDriveOut_SO = PPAV[7-read_cnt];
                            read_cnt  = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                end
                else if (oe_z)
                begin
                    if ((Instruct == RDAY1_C_0) || ((Instruct == RDAY1_4_0) && (~OPI_IT)))
                    begin
                        rd_fast = 1'b0;
                        rd_slow = 1'b1;
                        dual    = 1'b0;
                        ddr     = 1'b0;
                    end
                    else
                    begin
                        rd_fast = 1'b1;
                        rd_slow = 1'b0;
                        dual    = 1'b0;
                        ddr     = 1'b0;
                    end
                end
                if (falling_edge_write)
                begin
                    if (Instruct == RSEPD_0_0)
                    begin
                        STR2V[1] = 1'b0; // ERASES
                        STR1V[0] = 1'b1; // RDYBSY

                        Addr = SectorSuspend*(SecSize256+1);

                        ADDRHILO_SEC(AddrLo, AddrHi, Addr);
                        ERES = 1'b1;
                        ERES <= #5 1'b0;
                        RES_TO_SUSP_TIME = 1'b1;
                        RES_TO_SUSP_TIME <= #tdevice_RS 1'b0;//100us
                    end
                    else if ((Instruct==PRPGE_4_1) && WRPGEN && ~PRGERR)
                    begin
                        ReturnSectorID(sect,Address);

                        if (SectorSuspend != Address/(SecSize256+1))
                        begin
                            if (Sec_Prot[sect]== 0 && PPB_bits[sect]== 1 &&
                                DYB_bits[sect]== 1)
                            begin
                                PSTART = 1'b1;
                                PSTART <= #5 1'b0;
                                PGSUSP  = 0;
                                PGRES   = 0;
                                STR1V[0] = 1'b1;//RDYBSY
                                Addr     = Address;
                                Addr_tmp = Address;
                                wr_cnt   = Byte_number;
                                for (i=wr_cnt;i>=0;i=i-1)
                                begin
                                    if (Viol != 0)
                                        WData[i] = -1;
                                    else
                                        WData[i] = WByte[i];
                                end
                            end
                            else
                            begin
                                STR1V[0] = 1'b1;// RDYBSY
                                STR1V[6] = 1'b1;// PRGERR
                            end
                        end
                        else
                        begin
                            STR1V[0] = 1'b1;// RDYBSY
                            STR1V[6] = 1'b1;// PRGERR
                        end
                    end
                    else if ((Instruct == WRDYB_4_1) && WRPGEN)
                    begin
                        if (DYAV_in == 8'hFF || DYAV_in == 8'h00)
                        begin
                            ReturnSectorID(sect,Address);
                            PSTART   = 1'b1;
                            PSTART  <= #5 1'b0;
                            STR1V[0] = 1'b1;// RDYBSY
                        end
                        else
                        begin
                            STR1V[6] = 1'b1;// PRGERR
                            STR1V[0] = 1'b1;// RDYBSY
                        end
                    end
                    else if (Instruct == WRENB_0_0)
                        STR1V[1] = 1'b1; //WRPGEN
                    else if (Instruct == CLECC_0_0)
                    begin
                        ESCV[4] = 0;// 2 bits ECC detection
                        ESCV[3] = 0;// 1 bit ECC correction
                        INSV[1] = 1;
                        INSV[0] = 1;
                        ECTV = 16'h0000;
                        EATV = 32'h00000000;
                    end
                    else if (Instruct == CLPEF_0_0)
                    begin
                        STR1V[6] = 0;// PRGERR
                        STR1V[5] = 0;// ERSERR
                        STR1V[0] = 0;// RDYBSY
                    end

                    if (Instruct == SRSTE_0_0)
                    begin
                        RESET_EN = 1;
                    end
                    else
                    begin
                        RESET_EN <= 0;
                    end
                end
            end

            ERS_SUSP_PG:
            begin
                if (OPI_IT)
                begin
                    rd_fast = 1'b1;
                    rd_slow = 1'b0;
                    dual    = 1'b1;
                    ddr     = 1'b0;
                end
                else
                begin
                    rd_fast = 1'b1;
                    rd_slow = 1'b0;
                    dual    = 1'b0;
                    ddr     = 1'b0;
                end

                if (oe)
                begin
                    any_read = 1'b1;
                    if (Instruct == RDSR1)
                    begin
                    //Read Status Register 1
                        if (OPI_IT)
                        begin
                            data_out[7:0] = STR1V;
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            DataDriveOut_SO = data_out[1-read_cnt];
                            DataDriveOut_SI = data_out[0-read_cnt];

                            read_cnt = read_cnt + 1;
                            if (read_cnt == 1)
                            begin
                                read_cnt = 0;
                            end
                        end
                        else
                        begin
                            DataDriveOut_SO = STR1V[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                    else if (Instruct == RDSR2)
                    begin
                        //Read Status Register 2
                        if (OPI_IT)
                        begin
                            data_out[7:0] = STR2V;
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            DataDriveOut_SO = data_out[1-read_cnt];
                            DataDriveOut_SI = data_out[0-read_cnt];

                            read_cnt = read_cnt + 1;
                            if (read_cnt == 1)
                            begin
                                read_cnt = 0;
                            end
                        end
                        else
                        begin
                            DataDriveOut_SO = STR2V[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                    else if (Instruct == RDARG_4_0)
                    begin
                        READ_ALL_REG(read_addr, RDAR_reg);

                        if (OPI_IT)
                        begin
                            data_out[7:0]  = RDAR_reg;
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            DataDriveOut_SO = data_out[1-read_cnt];
                            DataDriveOut_SI = data_out[0-read_cnt];

                            read_cnt = read_cnt + 1;
                            if (read_cnt == 1)
                            begin
                                read_cnt = 0;
                            end
                        end
                        else
                        begin
                            data_out[7:0]  = RDAR_reg;
                            DataDriveOut_SO = data_out[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                end

                if(current_state_event && current_state == ERS_SUSP_PG)
                begin
                    if (~PDONE)
                    begin
                        ADDRHILO_PG(AddrLo, AddrHi, Addr);
                        cnt = 0;
                        for (i=0;i<=wr_cnt;i=i+1)
                        begin
                            new_int = WData[i];
                            old_int = Mem[Addr + i - cnt];
                            if (new_int > -1)
                            begin
                                new_bit = new_int;
                                if (old_int > -1)
                                begin
                                    old_bit = old_int;
                                    for(j=0;j<=7;j=j+1)
                                    begin
                                        if (~old_bit[j])
                                            new_bit[j] = 1'b0;
                                    end
                                    new_int = new_bit;
                                end
                                WData[i] = new_int;
                            end
                            else
                            begin
                                WData[i] = -1;
                            end

                            if ((Addr + i) == AddrHi)
                            begin
                                Addr = AddrLo;
                                cnt = i + 1;
                            end
                        end
                    end
                    cnt =0;
                end

                if (PDONE)
                begin
                    
                    if (((CFR4V[3] == 1'b1)  || (non_industrial_temp == 1'b1)) 
                          && (ECC_ERR > 0) )
                    begin
                        STR1V[0] = 1'b1; //RDYBSY
                        STR1V[1] = 1'b1; //WRPGEN
                        STR1V[6] = 1'b1; //PRGERR
                        ECC_ERR = 0;
                        $display ("WARNING: For non-industrial temperatures ");
                        $display ("it is not allowed to have multi-programming ");
                        $display ("without erasing previously the sector!");
                        $display ("multi-pass programming within the same sector will result in a Program Error.");
                    end
                    else
                    begin
                        STR1V[0] = 1'b0; //RDYBSY
                        STR1V[1] = 1'b0; //WRPGEN
                        ECC_ERR = 0;
                    end

                    for (i=0;i<=wr_cnt;i=i+1)
                    begin
                        Mem[Addr_tmp + i - cnt] = WData[i];
                        if ((Addr_tmp + i) == AddrHi)
                        begin
                            Addr_tmp = AddrLo;
                            cnt = i + 1;
                        end
                    end
                end

                if (falling_edge_write)
                begin
                    if ((Instruct == SPEPD_0_0) && ~PRGSUSP_in)
                    begin
                        if (~RES_TO_SUSP_TIME)
                        begin
                            PGSUSP = 1'b1;
                            PGSUSP <= #5 1'b0;
                            PRGSUSP_in = 1'b1;
                        end
                        else
                        begin
                            $display("Minimum for tRS is not satisfied! ",
                                     "PGSP command is ignored");
                        end
                    end
                end
            end

            ERS_SUSP_PG_SUSP:
            begin
                if (OPI_IT)
                begin
                    rd_fast = 1'b1;
                    rd_slow = 1'b0;
                    dual    = 1'b1;
                    ddr     = 1'b0;
                end
                else
                begin
                    rd_fast = 1'b1;
                    rd_slow = 1'b0;
                    dual    = 1'b0;
                    ddr     = 1'b0;
                end

                if (PRGSUSP_out && PRGSUSP_in)
                begin
                    PRGSUSP_in = 1'b0;
                    //The RDYBSY bit in the Status Register will indicate that
                    //the device is ready for another operation.
                    STR1V[0] = 1'b0;
                    //The Program Suspend (PROGMS) bit in the Status Register will
                    //be set to the logical “1” state to indicate that the
                    //program operation has been suspended.
                    STR2V[0] = 1'b1;
                end

                if (oe)
                begin
                    any_read = 1'b1;
                    if (Instruct == RDSR1)
                    begin
                    //Read Status Register 1
                        if (OPI_IT)
                        begin
                            data_out[7:0] = STR1V;
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            DataDriveOut_SO = data_out[1-read_cnt];
                            DataDriveOut_SI = data_out[0-read_cnt];

                            read_cnt = read_cnt + 1;
                            if (read_cnt == 1)
                            begin
                                read_cnt = 0;
                            end
                        end
                        else
                        begin
                            DataDriveOut_SO = STR1V[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                    else if (Instruct == RDSR2)
                    begin
                        //Read Status Register 2
                        if (OPI_IT)
                        begin
                            data_out[7:0] = STR2V;
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            DataDriveOut_SO = data_out[1-read_cnt];
                            DataDriveOut_SI = data_out[0-read_cnt];

                            read_cnt = read_cnt + 1;
                            if (read_cnt == 1)
                            begin
                                read_cnt = 0;
                            end
                        end
                        else
                        begin
                            DataDriveOut_SO = STR2V[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                    else if (Instruct == RDARG_4_0)
                    begin
                        READ_ALL_REG(read_addr, RDAR_reg);

                        if (OPI_IT)
                        begin
                            data_out[7:0]  = RDAR_reg;
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            DataDriveOut_SO = data_out[1-read_cnt];
                            DataDriveOut_SI = data_out[0-read_cnt];

                            read_cnt = read_cnt + 1;
                            if (read_cnt == 1)
                            begin
                                read_cnt = 0;
                            end
                        end
                        else
                        begin
                            data_out[7:0]  = RDAR_reg;
                            DataDriveOut_SO = data_out[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                    else if (Instruct == RDCRC_4_0)
                    begin
                        if (Addr_idcfi <= 3)
                        begin
                            data_out[7:0] = ICRV[8*Addr_idcfi+7 -: 8];
                            if (OPI_IT)
                            begin
                                for (i=0;i<=5;i=i+1)
                                begin
                                    DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                                end
                                DataDriveOut_SO = data_out[1-read_cnt];
                                DataDriveOut_SI = data_out[0-read_cnt];
                                read_cnt = read_cnt + 1;
                                if (read_cnt == 1)
                                begin
                                    read_cnt = 0;
                                    Addr_idcfi = Addr_idcfi + 1;
                                end
                            end
                        end
                    end
                    else if ((Instruct == RDAY1_C_0) || ((Instruct == RDAY1_4_0) && (~OPI_IT)))
                    begin
                        //Read Memory array
                        rd_fast = 1'b0;
                        rd_slow = 1'b1;
                        dual    = 1'b0;
                        ddr     = 1'b0;

                        if (SectorSuspend != read_addr/(SecSize256+1) &&
                            pgm_page != read_addr / (PageSize+1))
                        begin
                            data_out[7:0] = Mem[read_addr];
                            DataDriveOut_SO  = data_out[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                            begin
                                read_cnt = 0;
                                if (read_addr >= AddrRANGE)
                                    read_addr = 0;
                                else
                                    read_addr = read_addr + 1;
                            end
                        end
                        else
                        begin
                            DataDriveOut_SO  = 8'bxxxxxxxx;
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                            begin
                                read_cnt = 0;
                                if (read_addr == AddrRANGE)
                                    read_addr = 0;
                                else
                                    read_addr = read_addr + 1;
                            end
                        end
                    end
                    else if ((Instruct == RDAY2_C_0) && (~OPI_IT))
                    begin

                        if (SectorSuspend != read_addr/(SecSize256+1) &&
                            pgm_page != read_addr / (PageSize+1))
                        begin
                            data_out[7:0] = Mem[read_addr];
                            DataDriveOut_SO  = data_out[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                            begin
                                read_cnt = 0;

                                if (~CFR4V[4])  //Wrap Disabled
                                begin
                                    if (read_addr == AddrRANGE)
                                        read_addr = 0;
                                    else
                                        read_addr = read_addr + 1;
                                end
                                else           //Wrap Enabled
                                begin
                                    read_addr = read_addr + 1;

                                    if (read_addr % WrapLength == 0)
                                        read_addr = read_addr - WrapLength;
                                end
                            end
                        end
                        else
                        begin
                            DataDriveOut_SO  = 8'bxxxxxxxx;
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                            begin
                                read_cnt = 0;

                                if (~CFR4V[4])  //Wrap Disabled
                                begin
                                    if (read_addr == AddrRANGE)
                                        read_addr = 0;
                                    else
                                        read_addr = read_addr + 1;
                                end
                                else           //Wrap Enabled
                                begin
                                    read_addr = read_addr + 1;

                                    if (read_addr % WrapLength == 0)
                                        read_addr = read_addr - WrapLength;
                                end
                            end
                        end
                    end
                end
                else if (oe_z)
                begin
                    if ((Instruct == RDAY1_C_0) || ((Instruct == RDAY1_4_0) && (~OPI_IT)))
                    begin
                        rd_fast = 1'b0;
                        rd_slow = 1'b1;
                        dual    = 1'b0;
                        ddr     = 1'b0;
                    end
                    else
                    begin
                        rd_fast = 1'b1;
                        rd_slow = 1'b0;
                        dual    = 1'b0;
                        ddr     = 1'b0;
                    end
                end

                if (falling_edge_write)
                begin
                    if (Instruct == RSEPD_0_0)
                    begin
                        STR2V[0] = 1'b0; // PROGMS
                        STR1V[0] = 1'b1; // RDYBSY
                        PGRES  = 1'b1;
                        PGRES <= #5 1'b0;
                        RES_TO_SUSP_TIME = 1'b1;
                        RES_TO_SUSP_TIME <= #tdevice_RS 1'b0;//100us
                    end
                    else if (Instruct == CLECC_0_0)
                    begin
                        ESCV[4] = 0;// 2 bits ECC detection
                        ESCV[3] = 0;// 1 bit ECC correction
                        INSV[1] = 1;
                        INSV[0] = 1;
                        ECTV = 16'h0000;
                        EATV = 32'h00000000;
                    end
                    else if (Instruct == CLPEF_0_0)
                    begin
                        STR1V[6] = 0;// PRGERR
                        STR1V[5] = 0;// ERSERR
                        STR1V[0] = 0;// RDYBSY
                    end

                    if (Instruct == SRSTE_0_0)
                    begin
                        RESET_EN = 1;
                    end
                    else
                    begin
                        RESET_EN <= 0;
                    end
                end
            end

            PASS_PG:
            begin
                rd_fast = 1'b1;
                rd_slow = 1'b0;
                dual    = 1'b0;
                ddr     = 1'b0;

                if (oe)
                begin
                    any_read = 1'b1;
                    if (Instruct == RDSR1)
                    begin
                    //Read Status Register 1
                        if (OPI_IT)
                        begin
                            data_out[7:0] = STR1V;
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            DataDriveOut_SO = data_out[1-read_cnt];
                            DataDriveOut_SI = data_out[0-read_cnt];

                            read_cnt = read_cnt + 1;
                            if (read_cnt == 1)
                            begin
                                read_cnt = 0;
                            end
                        end
                        else
                        begin
                            DataDriveOut_SO = STR1V[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                    else if (Instruct == RDSR2)
                    begin
                        //Read Status Register 2
                        if (OPI_IT)
                        begin
                            data_out[7:0] = STR2V;
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            DataDriveOut_SO = data_out[1-read_cnt];
                            DataDriveOut_SI = data_out[0-read_cnt];

                            read_cnt = read_cnt + 1;
                            if (read_cnt == 1)
                            begin
                                read_cnt = 0;
                            end
                        end
                        else
                        begin
                            DataDriveOut_SO = STR2V[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                    else if (Instruct == RDARG_4_0)
                    begin
                        READ_ALL_REG(read_addr, RDAR_reg);

                        if (OPI_IT)
                        begin
                            data_out[7:0]  = RDAR_reg;
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            DataDriveOut_SO = data_out[1-read_cnt];
                            DataDriveOut_SI = data_out[0-read_cnt];

                            read_cnt = read_cnt + 1;
                            if (read_cnt == 1)
                            begin
                                read_cnt = 0;
                            end
                        end
                        else
                        begin
                            DataDriveOut_SO = RDAR_reg[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                end

                new_pass = PWDO_in;
                old_pass = PWDO;
                for (i=0;i<=63;i=i+1)
                begin
                    if (old_pass[j] == 0)
                        new_pass[j] = 0;
                end

                if (PDONE)
                begin
                    PWDO = new_pass;
                    STR1V[0] = 1'b0; //RDYBSY
                    STR1V[1] = 1'b0; //WRPGEN
                end
            end

            PASS_UNLOCK:
            begin
                rd_fast = 1'b1;
                rd_slow = 1'b0;
                dual    = 1'b0;
                ddr     = 1'b0;

                if (oe)
                begin
                    any_read = 1'b1;
                    if (Instruct == RDSR1)
                    begin
                    //Read Status Register 1
                        if (OPI_IT)
                        begin
                            data_out[7:0] = STR1V;
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            DataDriveOut_SO = data_out[1-read_cnt];
                            DataDriveOut_SI = data_out[0-read_cnt];

                            read_cnt = read_cnt + 1;
                            if (read_cnt == 1)
                            begin
                                read_cnt = 0;
                            end
                        end
                        else
                        begin
                            DataDriveOut_SO = STR1V[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                    else if (Instruct == RDSR2)
                    begin
                        //Read Status Register 2
                        if (OPI_IT)
                        begin
                            data_out[7:0] = STR2V;
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            DataDriveOut_SO = data_out[1-read_cnt];
                            DataDriveOut_SI = data_out[0-read_cnt];

                            read_cnt = read_cnt + 1;
                            if (read_cnt == 1)
                            begin
                                read_cnt = 0;
                            end
                        end
                        else
                        begin
                            DataDriveOut_SO = STR2V[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                    else if (Instruct == RDARG_4_0)
                    begin
                        READ_ALL_REG(read_addr, RDAR_reg);

                        if (OPI_IT)
                        begin
                            data_out[7:0]  = RDAR_reg;
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            DataDriveOut_SO = data_out[1-read_cnt];
                            DataDriveOut_SI = data_out[0-read_cnt];

                            read_cnt = read_cnt + 1;
                            if (read_cnt == 1)
                            begin
                                read_cnt = 0;
                            end
                        end
                        else
                        begin
                            DataDriveOut_SO = RDAR_reg[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                end

                if (PASS_TEMP == PWDO)
                begin
                    PASS_UNLOCKED = 1'b1;
                end
                else
                begin
                    PASS_UNLOCKED = 1'b0;
                end
                if (PASSULCK_out)
                begin
                    if ((PASS_UNLOCKED == 1'b1) && (~ASPPWD))
                    begin
                        PPLV [0] = 1'b1;
                        STR1V[0] = 1'b0; //RDYBSY
                    end
                    else
                    begin
                        STR1V[6] = 1'b1; //PRGERR
                        STR1V[0] = 1'b1; //RDYBSY
                        $display ("Incorrect Password");
                        PASSACC_in = 1'b1;
                    end
                    PASSULCK_in = 1'b0;
                end
            end

            PPB_PG:
            begin
                rd_fast = 1'b1;
                rd_slow = 1'b0;
                dual    = 1'b0;
                ddr     = 1'b0;

                if (oe)
                begin
                    any_read = 1'b1;
                    if (Instruct == RDSR1)
                    begin
                    //Read Status Register 1
                        if (OPI_IT)
                        begin
                            data_out[7:0] = STR1V;
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            DataDriveOut_SO = data_out[1-read_cnt];
                            DataDriveOut_SI = data_out[0-read_cnt];

                            read_cnt = read_cnt + 1;
                            if (read_cnt == 1)
                            begin
                                read_cnt = 0;
                            end
                        end
                        else
                        begin
                            DataDriveOut_SO = STR1V[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                    else if (Instruct == RDSR2)
                    begin
                        //Read Status Register 2
                        if (OPI_IT)
                        begin
                            data_out[7:0] = STR2V;
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            DataDriveOut_SO = data_out[1-read_cnt];
                            DataDriveOut_SI = data_out[0-read_cnt];

                            read_cnt = read_cnt + 1;
                            if (read_cnt == 1)
                            begin
                                read_cnt = 0;
                            end
                        end
                        else
                        begin
                            DataDriveOut_SO = STR2V[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                    else if (Instruct == RDARG_4_0)
                    begin
                        READ_ALL_REG(read_addr, RDAR_reg);

                        if (OPI_IT)
                        begin
                            data_out[7:0]  = RDAR_reg;
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            DataDriveOut_SO = data_out[1-read_cnt];
                            DataDriveOut_SI = data_out[0-read_cnt];

                            read_cnt = read_cnt + 1;
                            if (read_cnt == 1)
                            begin
                                read_cnt = 0;
                            end
                        end
                        else
                        begin
                            DataDriveOut_SO = RDAR_reg[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                end

                if (PDONE)
                begin
                    PPB_bits[sect]= 1'b0;
                    STR1V[0] = 1'b0;
                    STR1V[1] = 1'b0;
                end
            end

            PPB_ERS:
            begin
                rd_fast = 1'b1;
                rd_slow = 1'b0;
                dual    = 1'b0;
                ddr     = 1'b0;

                if (oe)
                begin
                    any_read = 1'b1;
                    if (Instruct == RDSR1)
                    begin
                    //Read Status Register 1
                        if (OPI_IT)
                        begin
                            data_out[7:0] = STR1V;
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            DataDriveOut_SO = data_out[1-read_cnt];
                            DataDriveOut_SI = data_out[0-read_cnt];

                            read_cnt = read_cnt + 1;
                            if (read_cnt == 1)
                            begin
                                read_cnt = 0;
                            end
                        end
                        else
                        begin
                            DataDriveOut_SO = STR1V[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                    else if (Instruct == RDSR2)
                    begin
                        //Read Status Register 2
                        if (OPI_IT)
                        begin
                            data_out[7:0] = STR2V;
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            DataDriveOut_SO = data_out[1-read_cnt];
                            DataDriveOut_SI = data_out[0-read_cnt];

                            read_cnt = read_cnt + 1;
                            if (read_cnt == 1)
                            begin
                                read_cnt = 0;
                            end
                        end
                        else
                        begin
                            DataDriveOut_SO = STR2V[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                    else if (Instruct == RDARG_4_0)
                    begin
                        READ_ALL_REG(read_addr, RDAR_reg);

                        if (OPI_IT)
                        begin
                            data_out[7:0]  = RDAR_reg;
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            DataDriveOut_SO = data_out[1-read_cnt];
                            DataDriveOut_SI = data_out[0-read_cnt];

                            read_cnt = read_cnt + 1;
                            if (read_cnt == 1)
                            begin
                                read_cnt = 0;
                            end
                        end
                        else
                        begin
                            DataDriveOut_SO = RDAR_reg[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                end

                if (PPBERASE_out)
                begin

                    PPB_bits = {288{1'b1}};

                    STR1V[0] = 1'b0;
                    STR1V[1] = 1'b0;
                    PPBERASE_in = 1'b0;
                end
            end

            PLB_PG:
            begin
                rd_fast = 1'b1;
                rd_slow = 1'b0;
                dual    = 1'b0;
                ddr     = 1'b0;

                if (oe)
                begin
                    any_read = 1'b1;
                    if (Instruct == RDSR1)
                    begin
                    //Read Status Register 1
                        if (OPI_IT)
                        begin
                            data_out[7:0] = STR1V;
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            DataDriveOut_SO = data_out[1-read_cnt];
                            DataDriveOut_SI = data_out[0-read_cnt];

                            read_cnt = read_cnt + 1;
                            if (read_cnt == 1)
                            begin
                                read_cnt = 0;
                            end
                        end
                        else
                        begin
                            DataDriveOut_SO = STR1V[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                    else if (Instruct == RDSR2)
                    begin
                        //Read Status Register 2
                        if (OPI_IT)
                        begin
                            data_out[7:0] = STR2V;
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            DataDriveOut_SO = data_out[1-read_cnt];
                            DataDriveOut_SI = data_out[0-read_cnt];

                            read_cnt = read_cnt + 1;
                            if (read_cnt == 1)
                            begin
                                read_cnt = 0;
                            end
                        end
                        else
                        begin
                            DataDriveOut_SO = STR2V[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                    else if (Instruct == RDARG_4_0)
                    begin
                        READ_ALL_REG(read_addr, RDAR_reg);

                        if (OPI_IT)
                        begin
                            data_out[7:0]  = RDAR_reg;
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            DataDriveOut_SO = data_out[1-read_cnt];
                            DataDriveOut_SI = data_out[0-read_cnt];

                            read_cnt = read_cnt + 1;
                            if (read_cnt == 1)
                            begin
                                read_cnt = 0;
                            end
                        end
                        else
                        begin
                            DataDriveOut_SO = RDAR_reg[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                end

                if (PDONE)
                begin
                    PPLV[0] = 1'b0;
                    STR1V[0] = 1'b0; //RDYBSY
                    STR1V[1] = 1'b0; //WRPGEN
                end
            end

            DYB_PG:
            begin
                if (OPI_IT)
                begin
                    rd_fast = 1'b1;
                    rd_slow = 1'b0;
                    dual    = 1'b1;
                    ddr     = 1'b0;
                end
                else
                begin
                    rd_fast = 1'b1;
                    rd_slow = 1'b0;
                    dual    = 1'b0;
                    ddr     = 1'b0;
                end

                if (oe)
                begin
                    any_read = 1'b1;
                    if (Instruct == RDSR1)
                    begin
                    //Read Status Register 1
                        if (OPI_IT)
                        begin
                            data_out[7:0] = STR1V;
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            DataDriveOut_SO = data_out[1-read_cnt];
                            DataDriveOut_SI = data_out[0-read_cnt];

                            read_cnt = read_cnt + 1;
                            if (read_cnt == 1)
                            begin
                                read_cnt = 0;
                            end
                        end
                        else
                        begin
                            DataDriveOut_SO = STR1V[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                    else if (Instruct == RDSR2)
                    begin
                        //Read Status Register 2
                        if (OPI_IT)
                        begin
                            data_out[7:0] = STR2V;
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            DataDriveOut_SO = data_out[1-read_cnt];
                            DataDriveOut_SI = data_out[0-read_cnt];

                            read_cnt = read_cnt + 1;
                            if (read_cnt == 1)
                            begin
                                read_cnt = 0;
                            end
                        end
                        else
                        begin
                            DataDriveOut_SO = STR2V[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                    else if (Instruct == RDARG_4_0)
                    begin
                        READ_ALL_REG(read_addr, RDAR_reg);

                        if (OPI_IT)
                        begin
                            data_out[7:0]  = RDAR_reg;
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            DataDriveOut_SO = data_out[1-read_cnt];
                            DataDriveOut_SI = data_out[0-read_cnt];

                            read_cnt = read_cnt + 1;
                            if (read_cnt == 1)
                            begin
                                read_cnt = 0;
                            end
                        end
                        else
                        begin
                            data_out[7:0]  = RDAR_reg;
                            DataDriveOut_SO = data_out[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                end

                if (PDONE)
                begin
                    DYAV = DYAV_in;
                    if (DYAV == 8'hFF)
                    begin
                        DYB_bits[sect]= 1'b1;
                    end
                    else if (DYAV == 8'h00)
                    begin
                        DYB_bits[sect]= 1'b0;
                    end

                    STR1V[0] = 1'b0;
                    STR1V[1] = 1'b0;
                end
            end

            ASP_PG:
            begin
                rd_fast = 1'b1;
                rd_slow = 1'b0;
                dual    = 1'b0;
                ddr     = 1'b0;

                if (oe)
                begin
                    any_read = 1'b1;
                    if (Instruct == RDSR1)
                    begin
                    //Read Status Register 1
                        if (OPI_IT)
                        begin
                            data_out[7:0] = STR1V;
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            DataDriveOut_SO = data_out[1-read_cnt];
                            DataDriveOut_SI = data_out[0-read_cnt];

                            read_cnt = read_cnt + 1;
                            if (read_cnt == 1)
                            begin
                                read_cnt = 0;
                            end
                        end
                        else
                        begin
                            DataDriveOut_SO = STR1V[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                    else if (Instruct == RDSR2)
                    begin
                        //Read Status Register 2
                        if (OPI_IT)
                        begin
                            data_out[7:0] = STR2V;
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            DataDriveOut_SO = data_out[1-read_cnt];
                            DataDriveOut_SI = data_out[0-read_cnt];

                            read_cnt = read_cnt + 1;
                            if (read_cnt == 1)
                            begin
                                read_cnt = 0;
                            end
                        end
                        else
                        begin
                            DataDriveOut_SO = STR2V[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                    else if (Instruct == RDARG_4_0)
                    begin
                        READ_ALL_REG(read_addr, RDAR_reg);

                        if (OPI_IT)
                        begin
                            data_out[7:0]  = RDAR_reg;
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            DataDriveOut_SO = data_out[1-read_cnt];
                            DataDriveOut_SI = data_out[0-read_cnt];

                            read_cnt = read_cnt + 1;
                            if (read_cnt == 1)
                            begin
                                read_cnt = 0;
                            end
                        end
                        else
                        begin
                            DataDriveOut_SO = RDAR_reg[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                end

                if (PDONE)
                begin
                
                        if (ASPDYB == 1'b0 && ASPO_in[4] == 1'b1)
                            $display("ASPDYB bit is allready programmed");
                        else
                            ASPO[4] = ASPO_in[4];//ASPDYB

                        if (ASPPPB == 1'b0 && ASPO_in[3] == 1'b1)
                            $display("ASPPPB bit is allready programmed");
                        else
                            ASPO[3] = ASPO_in[3];//ASPPPB

                        if (ASPPRM == 1'b0 && ASPO_in[0] == 1'b1)
                            $display("ASPPRM bit is allready programmed");
                        else
                            ASPO[0] = ASPO_in[0];//ASPPRM

                    ASPO[2] = ASPO_in[2];//ASPPWD
                    ASPO[1] = ASPO_in[1];//ASPPER

                    STR1V[0] = 1'b0;
                    STR1V[1] = 1'b0;
                end
            end

 

            DP_DOWN:
            begin
                rd_fast = 1'b1;
                rd_slow = 1'b0;
                dual    = 1'b0;

                if (CSNeg_ipd && DPDExt_out)
                begin
                    $display("Device is in Deep Power Down Mode");
                    $display("No instructions allowed");
                    #1 DPDExt_out = 1'b0;
                end

                if (falling_edge_RST)
                begin
                    RST_in = 1'b1;
                    #1 RST_in = 1'b0;
                    reseted   = 1'b0;
                end
            end

            SEERC :
            begin
                if (OPI_IT)
                begin
                    rd_fast = 1'b1;
                    rd_slow = 1'b0;
                    dual    = 1'b1;
                    ddr     = 1'b0;
                end
                else
                begin
                    rd_fast = 1'b1;
                    rd_slow = 1'b0;
                    dual    = 1'b0;
                    ddr     = 1'b0;
                end

                if (oe)
                begin
                    any_read = 1'b1;
                    if (Instruct == RDSR1)
                    begin
                    //Read Status Register 1
                        if (OPI_IT)
                        begin
                            data_out[7:0] = STR1V;
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            DataDriveOut_SO = data_out[1-read_cnt];
                            DataDriveOut_SI = data_out[0-read_cnt];

                            read_cnt = read_cnt + 1;
                            if (read_cnt == 1)
                            begin
                                read_cnt = 0;
                            end
                        end
                        else
                        begin
                            DataDriveOut_SO = STR1V[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                    else if (Instruct == RDSR2)
                    begin
                        //Read Status Register 2
                        if (OPI_IT)
                        begin
                            data_out[7:0] = STR2V;
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            DataDriveOut_SO = data_out[1-read_cnt];
                            DataDriveOut_SI = data_out[0-read_cnt];

                            read_cnt = read_cnt + 1;
                            if (read_cnt == 1)
                            begin
                                read_cnt = 0;
                            end
                        end
                        else
                        begin
                            DataDriveOut_SO = STR2V[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                    else if (Instruct == RDARG_4_0)
                    begin
                        READ_ALL_REG(read_addr, RDAR_reg);

                        if (OPI_IT)
                        begin
                            data_out[7:0]  = RDAR_reg;
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            DataDriveOut_SO = data_out[1-read_cnt];
                            DataDriveOut_SI = data_out[0-read_cnt];

                            read_cnt = read_cnt + 1;
                            if (read_cnt == 1)
                            begin
                                read_cnt = 0;
                            end
                        end
                        else
                        begin
                            data_out[7:0]  = RDAR_reg;
                            DataDriveOut_SO = data_out[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                end

                if (SEERC_DONE == 1)
                begin
                    STR1V[0] = 1'b0; //RDYBSY

                    // Mirror particular sector erase register to sector erase counter
                    SECV <= SECV_in[SectorErased];
                end
            end

            RESET_STATE:
            begin
            // During Reset,the non-volatile version of the registers is
            // copied to volatile version to provide the default state of
            // the volatile register
                STR1V[7:5] = STR1N[7:5];
                STR1V[1:0] = STR1N[1:0];
                DCRV = 32'h00000000;
                if (RESET_EN)
                begin
                    ICRV = 32'hFFFFFFFF;
                    rd_crc = 0;
                    icrc_out = 32'hFFFFFFFF;
                    icrc_cnt = 0;
                end

                if (Instruct == SFRST_0_0)
                begin
                // The volatile TLPROT bit (CFR1V[0]) and the volatile PPB Lock
                // bit are not changed by the SW RESET
                    CFR1V[7:1] = CFR1N[7:1];
                    STR2V[3] = 1'b0; // DICRCA
                end
                else
                begin
                    CFR1V = CFR1N;
                    
                    if (ASPDYB)
                        DYAV[7:0] = 8'hFF;
                    else
                        DYAV[7:0] = 8'h00;
                   

                    if (~ASPPWD)
                        PPLV[0] = 1'b0;
                    else
                        PPLV[0] = 1'b1;
                end

                CFR2V = CFR2N;
                CFR3V = CFR3N;
                CFR4V = CFR4N;
                CFR5V = CFR5N;
                INCV = 8'hFF;
                INSV = 8'hFF;
                //Loads the Program Buffer with all ones
                for(i=0;i<=511;i=i+1)
                begin
                    WData[i] = MaxData;
                end

                if (TLPROT == 1'b0)
                begin
                //When BPNV is set to '1'. the LBPROT2-0 bits in Status
                //Register are volatile and will be reseted after
                //reset command
                STR1V[4:2] = STR1N[4:2];
                BP_bits = {STR1V[4],STR1V[3],STR1V[2]};
                change_BP = 1'b1;
                #1 change_BP = 1'b0;
                end
            end

            PGERS_ERROR :
            begin
                if (OPI_IT)
                begin
                    rd_fast = 1'b1;
                    rd_slow = 1'b0;
                    dual    = 1'b1;
                    ddr     = 1'b0;
                end
                else
                begin
                    rd_fast = 1'b1;
                    rd_slow = 1'b0;
                    dual    = 1'b0;
                    ddr     = 1'b0;
                end

                if (oe)
                begin
                    any_read = 1'b1;
                    if (Instruct == RDSR1)
                    begin
                    //Read Status Register 1
                        if (OPI_IT)
                        begin
                            data_out[7:0] = STR1V;
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            DataDriveOut_SO = data_out[1-read_cnt];
                            DataDriveOut_SI = data_out[0-read_cnt];

                            read_cnt = read_cnt + 1;
                            if (read_cnt == 1)
                            begin
                                read_cnt = 0;
                            end
                        end
                        else
                        begin
                            DataDriveOut_SO = STR1V[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                    else if (Instruct == RDARG_4_0)
                    begin
                        READ_ALL_REG(read_addr, RDAR_reg);

                        if (OPI_IT)
                        begin
                            data_out[7:0]  = RDAR_reg;
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            DataDriveOut_SO = data_out[1-read_cnt];
                            DataDriveOut_SI = data_out[0-read_cnt];

                            read_cnt = read_cnt + 1;
                            if (read_cnt == 1)
                            begin
                                read_cnt = 0;
                            end
                        end
                        else
                        begin
                            data_out[7:0]  = RDAR_reg;
                            DataDriveOut_SO = data_out[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                end

                if (falling_edge_write)
                begin
                    if (Instruct == WRDIS_0_0 && ~PRGERR && ~ERSERR)
                    begin
                    // A Clear Status Register (CLPEF_0_0) followed by a Write
                    // Disable (WRDIS_0_0) command must be sent to return the
                    // device to standby state
                        STR1V[1] = 1'b0; //WRPGEN
                    end
                    else if (Instruct == CLECC_0_0)
                    begin
                        ESCV[4] = 0;// 2 bits ECC detection
                        ESCV[3] = 0;// 1 bit ECC correction
                        INSV[1] = 1;
                        INSV[0] = 1;
                        ECTV = 16'h0000;
                        EATV = 32'h00000000;
                    end
                    else if (Instruct == CLPEF_0_0)
                    begin
                        STR1V[6] = 0;// PRGERR
                        STR1V[5] = 0;// ERSERR
                        STR1V[0] = 0;// RDYBSY
                    end

                    if (Instruct == SRSTE_0_0)
                    begin
                        RESET_EN = 1;
                    end
                    else
                    begin
                        RESET_EN <= 0;
                    end
                end
            end

            BLANK_CHECK :
            begin
                if (rising_edge_BCDONE)
                begin
                    if (NOT_BLANK)
                    begin
                        //Start Sector Erase
                        ESTART = 1'b1;
                        ESTART <= #5 1'b0;
                        ESUSP     = 0;
                        ERES      = 0;
                        INITIAL_CONFIG = 1;
                        STR1V[0] = 1'b1; //RDYBSY
                        Addr = Address;
                    end
                    else
                        STR1V[1] = 1'b1; //WRPGEN
                end
                else
                begin
                    ADDRHILO_SEC(AddrLo, AddrHi, Addr);
                    for (i=AddrLo;i<=AddrHi;i=i+1)
                    begin
                        if (Mem[i] != MaxData)
                            NOT_BLANK = 1'b1;
                    end
                    bc_done = 1'b1;
                end
            end

            EVAL_ERS_STAT :
            begin
                if (oe)
                begin
                    any_read = 1'b1;
                    if (Instruct == RDSR1)
                    begin
                    //Read Status Register 1
                        if (OPI_IT)
                        begin
                            data_out[7:0] = STR1V;
                            for (i=0;i<=5;i=i+1)
                            begin
                                DataDriveOut_Dout[5-i] = data_out[7-i-read_cnt];
                            end
                            DataDriveOut_SO = data_out[1-read_cnt];
                            DataDriveOut_SI = data_out[0-read_cnt];

                            read_cnt = read_cnt + 1;
                            if (read_cnt == 1)
                            begin
                                read_cnt = 0;
                            end
                        end
                        else
                        begin
                            DataDriveOut_SO = STR1V[7-read_cnt];
                            read_cnt = read_cnt + 1;
                            if (read_cnt == 8)
                                read_cnt = 0;
                        end
                    end
                end

                if (rising_edge_EESDONE)
                begin
                    STR1V[0] = 1'b0;
                    STR1V[1] = 1'b0;

                    if (ERS_nosucc[sect] == 1'b1)
                    begin
                        STR2V[2] = 1'b0;
                    end
                    else
                        STR2V[2] = 1'b1;
                end
            end

        endcase
        if (falling_edge_write)
        begin
            if (Instruct == SRSTE_0_0 && current_state != DP_DOWN)
                RESET_EN <= 1;
            else
                RESET_EN <= 0;
        end
        
        if (INCV[7] == 1'b0 || INCV[4] == 1'b0 || INCV[1] == 1'b0 
           || INCV[0] == 1'b0 ) //rising_edge_status_7 ???
        begin
            if (INCV[7] == 1'b0)
            begin
                if (INCV[4] == 1'b0 && falling_edge_RDYBSY)
                begin
                    INSV[4] = 1'b0;
                end
                if (INCV[1] == 1'b0 && ESCV[1] == 1'b0)
                begin
                    INSV[1] = 1'b0;
                end
                if (INCV[0] == 1'b0 && ESCV[0] == 1'b0)
                begin
                    INSV[0] = 1'b0;
                end
            end
        end
        
        if (ASPO[2]==0 && ASPRDP==0 && PPBLCK==0) //???
            READ_PROTECT = 1'b1;
        else
            READ_PROTECT = 1'b0;

    end
    
    always @(INSV or INSV or rising_edge_RST_out or ESCV or falling_edge_RDYBSY or
          rising_edge_SWRST_out or rising_edge_PoweredUp or rising_edge_DPD_out)
    begin
        if (rising_edge_PoweredUp || (rising_edge_RST_out || rising_edge_SWRST_out)
           || rising_edge_DPD_out)
        begin
            INTNeg_zd = 1'b1;
        end
        else if (INCV[7] == 1'b1)
        begin
            INTNeg_zd = 1'b1;
        end
        else if (INSV == 8'hFF)
        begin
            INTNeg_zd = 1'b1;
        end
        else if (INCV[7] == 1'b0)
        begin
            if (INCV[4] == 1'b0 && falling_edge_RDYBSY)
            begin
                INTNeg_zd = 1'b0;
            end
            if (INCV[1] == 1'b0 && ESCV[4] == 1'b1 )
            begin
                INTNeg_zd = 1'b0;
            end
            if (INCV[0] == 1'b0 && ESCV[3] == 1'b1 )
            begin
                INTNeg_zd = 1'b0;
            end
        end
    
    end
    
    
    always @(posedge CSNeg_ipd)
    begin
        //Output Disable Control
        SOut_zd                = 1'bZ;
        SIOut_zd               = 1'bZ;
        DataDriveOut_SO        = 1'bZ;
        DataDriveOut_SI        = 1'bZ;
        Dout_zd                = 8'bZ;
        DataDriveOut_Dout      = 6'bZ;
        DS_zd                  = 1'bZ;
        DataDriveOut_DS        = 1'bZ;
    end

    always @(change_TBPARM, CFR3V[3], posedge PoweredUp)
    begin
        if (CFR3V[3] == 1'b0)
        begin
            if (CFR1V[6] == 1'b0)  
            begin
               if (TB4KBS_NV == 0)
               begin
                   TopBoot     = 0;
                   BottomBoot  = 1;
                   UniformSec = 0;
               end
               else
               begin
                   TopBoot     = 1;
                   BottomBoot  = 0;
                   UniformSec = 0;
               end
            end
            else if (CFR1V[6] == 1'b1) 
            begin
                 TopBoot     = 1;
                 BottomBoot  = 1;
                 UniformSec = 0;
            end
        end   
        else
        begin
            UniformSec = 1;
        end
    end

    always @(posedge change_BP)
    begin
        case (STR1V[4:2])

            3'b000:
            begin
                Sec_Prot[SecNumHyb:0] = {288{1'b0}};
            end

            3'b001:
            begin
                if (CFR3V[3]) // Uniform Sector Architecture
                begin
                    if (~TBPROT_NV)  // LBPROT starts at Top
                    begin
                        Sec_Prot[SecNumUni:(SecNumUni+1)*63/64] =   {4{1'b1}};
                        Sec_Prot[(SecNumUni+1)*63/64-1 : 0]     = {252{1'b0}};
                    end
                    else
                    begin
                        Sec_Prot[(SecNumUni+1)/64-1 : 0]       =   {4{1'b1}};
                        Sec_Prot[SecNumUni : (SecNumUni+1)/64] = {252{1'b0}};
                    end
                end
                else if (~CFR3V[3] && SP4KBS_NV)// Hybrid Sector Architecture
                begin
                    if (~TBPROT_NV)  // LBPROT starts at Top
                    begin
                        Sec_Prot[SecNumHyb:(SecNumHyb-19)] =   {20{1'b1}};
                        Sec_Prot[(SecNumHyb-20) : 0]     = {268{1'b0}};
                    end
                    else
                    begin
                        Sec_Prot[19 : 0]       =   {20{1'b1}};
                        Sec_Prot[SecNumHyb : (SecNumHyb-20)] = {268{1'b0}};
                    end
                end
                else// Hybrid Sector Architecture
                begin
                    if(TB4KBS_NV)  // 4 KB Physical Sectors at Top
                    begin
                        if (~TBPROT_NV)  // LBPROT starts at Top
                        begin
                            Sec_Prot[SecNumHyb:(SecNumHyb-31)*63/64]= {36{1'b1}};
                            Sec_Prot[(SecNumHyb-31)*63/64-1 : 0]   = {252{1'b0}};
                        end
                        else
                        begin
                            Sec_Prot[(SecNumHyb-31)/64-1 : 0]      =   {4{1'b1}};
                            Sec_Prot[SecNumHyb :(SecNumHyb-31)/64] = {284{1'b0}};
                        end
                    end
                    else          // 4 KB Physical Sectors at Bottom
                    begin
                        if (~TBPROT_NV)  // LBPROT starts at Top
                        begin
                            Sec_Prot[SecNumHyb:(SecNumHyb-31)*63/64+8] =
                                                                      {28{1'b1}};
                            Sec_Prot[(SecNumHyb-31)*63/64+7 : 0]   = {260{1'b0}};
                        end
                        else            // LBPROT starts at Bottom
                        begin
                            Sec_Prot[(SecNumHyb-31)/64+7 : 0]      =  {12{1'b1}};
                            Sec_Prot[SecNumHyb:(SecNumHyb-31)/64+8]= {276{1'b0}};
                        end
                    end
                end
            end

            3'b010:
            begin
                if (CFR3V[3]) // Uniform Sector Architecture
                begin
                    if (~TBPROT_NV)  // LBPROT starts at Top
                    begin
                        Sec_Prot[SecNumUni : (SecNumUni+1)*31/32] = {8{1'b1}};
                        Sec_Prot[(SecNumUni+1)*31/32-1 : 0]       = {248{1'b0}};
                    end
                    else            // LBPROT starts at Bottom
                    begin
                        Sec_Prot[(SecNumUni+1)/32-1 : 0]       = {8{1'b1}};
                        Sec_Prot[SecNumUni : (SecNumUni+1)/32] = {248{1'b0}};
                    end
                end
                else if (~CFR3V[3] &&  SP4KBS_NV)// Hybrid Sector Architecture
                begin
                    if (~TBPROT_NV)  // LBPROT starts at Top
                    begin
                        Sec_Prot[SecNumHyb:(SecNumHyb-23)]= {24{1'b1}};
                        Sec_Prot[(SecNumHyb-24) : 0]   = {264{1'b0}};
                    end
                    else
                    begin
                        Sec_Prot[23 : 0]      =   {24{1'b1}};
                        Sec_Prot[SecNumHyb : 24] = {264{1'b0}};
                    end
                end
                else// Hybrid Sector Architecture
                begin
                    if(TB4KBS_NV)  // 4 KB Physical Sectors at Top
                    begin
                        if (~TBPROT_NV)  // LBPROT starts at Top
                        begin
                            Sec_Prot[SecNumHyb:(SecNumHyb-31)*31/32]= {40{1'b1}};
                            Sec_Prot[(SecNumHyb-31)*31/32-1 : 0]   = {248{1'b0}};
                        end
                        else
                        begin
                            Sec_Prot[(SecNumHyb-31)/32-1 : 0]      =   {8{1'b1}};
                            Sec_Prot[SecNumHyb :(SecNumHyb-31)/32] = {280{1'b0}};
                        end
                    end
                    else          // 4 KB Physical Sectors at Bottom
                    begin
                        if (~TBPROT_NV)  // LBPROT starts at Top
                        begin
                            Sec_Prot[SecNumHyb:(SecNumHyb-31)*31/32+8] =
                                                                      {32{1'b1}};
                            Sec_Prot[(SecNumHyb-31)*31/32+7 : 0]   = {256{1'b0}};
                        end
                        else            // LBPROT starts at Bottom
                        begin
                            Sec_Prot[(SecNumHyb-31)/32+7 : 0]      =  {16{1'b1}};
                            Sec_Prot[SecNumHyb:(SecNumHyb-31)/32+8]= {272{1'b0}};
                        end
                    end
                end
            end

            3'b011:
            begin
                if (CFR3V[3]) // Uniform Sector Architecture
                begin
                    if (~TBPROT_NV)  // LBPROT starts at Top
                    begin
                        Sec_Prot[SecNumUni : (SecNumUni+1)*15/16] = {16{1'b1}};
                        Sec_Prot[(SecNumUni+1)*15/16-1 : 0]       = {240{1'b0}};
                    end
                    else            // LBPROT starts at Bottom
                    begin
                        Sec_Prot[(SecNumUni+1)/16-1 : 0]       = {16{1'b1}};
                        Sec_Prot[SecNumUni : (SecNumUni+1)/16] = {240{1'b0}};
                    end
                end
                else if (~CFR3V[3] &&  SP4KBS_NV)// Hybrid Sector Architecture
                begin
                    if (~TBPROT_NV)  // LBPROT starts at Top
                    begin
                        Sec_Prot[SecNumHyb:(SecNumHyb-31)]= {32{1'b1}};
                        Sec_Prot[(SecNumHyb-32) : 0]   = {256{1'b0}};
                    end
                    else
                    begin
                        Sec_Prot[31 : 0]      =  {32{1'b1}};
                        Sec_Prot[SecNumHyb : 32] = {256{1'b0}};
                    end
                end
                else// Hybrid Sector Architecture
                begin
                    if(TB4KBS_NV)  // 4 KB Physical Sectors at Top
                    begin
                        if (~TBPROT_NV)  // LBPROT starts at Top
                        begin
                            Sec_Prot[SecNumHyb:(SecNumHyb-31)*15/16]= {48{1'b1}};
                            Sec_Prot[(SecNumHyb-31)*15/16-1 : 0]   = {240{1'b0}};
                        end
                        else
                        begin
                            Sec_Prot[(SecNumHyb-31)/16-1 : 0]      =  {16{1'b1}};
                            Sec_Prot[SecNumHyb :(SecNumHyb-31)/16] = {272{1'b0}};
                        end
                    end
                    else          // 4 KB Physical Sectors at Bottom
                    begin
                        if (~TBPROT_NV)  // LBPROT starts at Top
                        begin
                            Sec_Prot[SecNumHyb:(SecNumHyb-31)*15/16+8] =
                                                                     {40{1'b1}};
                            Sec_Prot[(SecNumHyb-31)*15/16+7 : 0]   = {248{1'b0}};
                        end
                        else            // LBPROT starts at Bottom
                        begin
                            Sec_Prot[(SecNumHyb-31)/16+7 : 0]      =  {24{1'b1}};
                            Sec_Prot[SecNumHyb:(SecNumHyb-31)/16+8]= {264{1'b0}};
                        end
                    end
                end
            end

            3'b100:
            begin
                if (CFR3V[3]) // Uniform Sector Architecture
                begin
                    if (~TBPROT_NV)  // LBPROT starts at Top
                    begin
                        Sec_Prot[SecNumUni : (SecNumUni+1)*7/8] = {32{1'b1}};
                        Sec_Prot[(SecNumUni+1)*7/8-1 : 0]       = {224{1'b0}};
                    end
                    else            // LBPROT starts at Bottom
                    begin
                        Sec_Prot[(SecNumUni+1)/8-1 : 0]       = {32{1'b1}};
                        Sec_Prot[SecNumUni : (SecNumUni+1)/8] = {224{1'b0}};
                    end
                end
                else if (~CFR3V[3] &&  SP4KBS_NV)// Hybrid Sector Architecture
                begin
                    if (~TBPROT_NV)  // LBPROT starts at Top
                    begin
                        Sec_Prot[SecNumHyb:(SecNumHyb-47)]= {48{1'b1}};
                        Sec_Prot[(SecNumHyb-48):0]   = {240{1'b0}};
                    end
                    else
                    begin
                        Sec_Prot[47 : 0]      =  {48{1'b1}};
                        Sec_Prot[SecNumHyb : 47] = {240{1'b0}};
                    end
                end
                else// Hybrid Sector Architecture
                begin
                    if(TB4KBS_NV)  // 4 KB Physical Sectors at Top
                    begin
                        if (~TBPROT_NV)  // LBPROT starts at Top
                        begin
                            Sec_Prot[SecNumHyb:(SecNumHyb-31)*7/8]= {64{1'b1}};
                            Sec_Prot[(SecNumHyb-31)*7/8-1 : 0]   = {224{1'b0}};
                        end
                        else
                        begin
                            Sec_Prot[(SecNumHyb-31)/8-1 : 0]      =  {32{1'b1}};
                            Sec_Prot[SecNumHyb :(SecNumHyb-31)/8] = {256{1'b0}};
                        end
                    end
                    else          // 4 KB Physical Sectors at Bottom
                    begin
                        if (~TBPROT_NV)  // LBPROT starts at Top
                        begin
                            Sec_Prot[SecNumHyb:(SecNumHyb-31)*7/8+8] =
                                                                     {56{1'b1}};
                            Sec_Prot[(SecNumHyb-31)*7/8+7 : 0]     = {232{1'b0}};
                        end
                        else            // LBPROT starts at Bottom
                        begin
                            Sec_Prot[(SecNumHyb-31)/8+7 : 0]       =  {40{1'b1}};
                            Sec_Prot[SecNumHyb:(SecNumHyb-31)/8+8] = {248{1'b0}};
                        end
                    end
                end
            end

            3'b101:
            begin
                if (CFR3V[3]) // Uniform Sector Architecture
                begin
                    if (~TBPROT_NV)  // LBPROT starts at Top
                    begin
                        Sec_Prot[SecNumUni : (SecNumUni+1)*3/4] = {64{1'b1}};
                        Sec_Prot[(SecNumUni+1)*3/4-1 : 0]       = {192{1'b0}};
                    end
                    else            // LBPROT starts at Bottom
                    begin
                        Sec_Prot[(SecNumUni+1)/4-1 : 0]       = {64{1'b1}};
                        Sec_Prot[SecNumUni : (SecNumUni+1)/4] = {192{1'b0}};
                    end
                end
                else if (~CFR3V[3] &&  SP4KBS_NV)// Hybrid Sector Architecture
                begin
                    if (~TBPROT_NV)  // LBPROT starts at Top
                    begin
                        Sec_Prot[SecNumHyb:(SecNumHyb-79)]= {80{1'b1}};
                        Sec_Prot[(SecNumHyb-80): 0]   = {208{1'b0}};
                    end
                    else
                    begin
                        Sec_Prot[79 : 0]      =  {80{1'b1}};
                        Sec_Prot[SecNumHyb :80] = {208{1'b0}};
                    end
                end
                else// Hybrid Sector Architecture
                begin
                    if(TB4KBS_NV)  // 4 KB Physical Sectors at Top
                    begin
                        if (~TBPROT_NV)  // LBPROT starts at Top
                        begin
                            Sec_Prot[SecNumHyb:(SecNumHyb-31)*3/4]= {96{1'b1}};
                            Sec_Prot[(SecNumHyb-31)*3/4-1 : 0]   = {192{1'b0}};
                        end
                        else
                        begin
                            Sec_Prot[(SecNumHyb-31)/4-1 : 0]      =  {64{1'b1}};
                            Sec_Prot[SecNumHyb :(SecNumHyb-31)/4] = {224{1'b0}};
                        end
                    end
                    else          // 4 KB Physical Sectors at Bottom
                    begin
                        if (~TBPROT_NV)  // LBPROT starts at Top
                        begin
                            Sec_Prot[SecNumHyb:(SecNumHyb-31)*3/4+8] =
                                                                     {88{1'b1}};
                            Sec_Prot[(SecNumHyb-31)*3/4+7 : 0]     = {200{1'b0}};
                        end
                        else            // LBPROT starts at Bottom
                        begin
                            Sec_Prot[(SecNumHyb-31)/4+7 : 0]       =  {72{1'b1}};
                            Sec_Prot[SecNumHyb:(SecNumHyb-31)/4+8] = {216{1'b0}};
                        end
                    end
                end
            end

            3'b110:
            begin
                if (CFR3V[3]) // Uniform Sector Architecture
                begin
                    if (~TBPROT_NV)  // LBPROT starts at Top
                    begin
                        Sec_Prot[SecNumUni : (SecNumUni+1)/2] = {128{1'b1}};
                        Sec_Prot[(SecNumUni+1)/2-1 : 0]       = {128{1'b0}};
                    end
                    else            // LBPROT starts at Bottom
                    begin
                        Sec_Prot[(SecNumUni+1)/2-1 : 0]       = {128{1'b1}};
                        Sec_Prot[SecNumUni : (SecNumUni+1)/2] = {128{1'b0}};
                    end
                end
                else if (~CFR3V[3] &&  SP4KBS_NV)// Hybrid Sector Architecture
                begin
                    if (~TBPROT_NV)  // LBPROT starts at Top
                    begin
                        Sec_Prot[SecNumHyb:(SecNumHyb-143)] = {144{1'b1}};
                        Sec_Prot[(SecNumHyb-144) : 0]     = {144{1'b0}};
                    end
                    else
                    begin
                        Sec_Prot[143 : 0]      = {144{1'b1}};
                        Sec_Prot[SecNumHyb : 144] = {144{1'b0}};
                    end
                end
                else// Hybrid Sector Architecture
                begin
                    if(TB4KBS_NV)  // 4 KB Physical Sectors at Top
                    begin
                        if (~TBPROT_NV)  // LBPROT starts at Top
                        begin
                            Sec_Prot[SecNumHyb:(SecNumHyb-31)/2] = {160{1'b1}};
                            Sec_Prot[(SecNumHyb-31)/2-1 : 0]     = {128{1'b0}};
                        end
                        else
                        begin
                            Sec_Prot[(SecNumHyb-31)/2-1 : 0]      = {128{1'b1}};
                            Sec_Prot[SecNumHyb :(SecNumHyb-31)/2] = {160{1'b0}};
                        end
                    end
                    else          // 4 KB Physical Sectors at Bottom
                    begin
                        if (~TBPROT_NV)  // LBPROT starts at Top
                        begin
                            Sec_Prot[SecNumHyb:(SecNumHyb-31)/2+8] = {152{1'b1}};
                            Sec_Prot[(SecNumHyb-31)/2+7 : 0]       = {136{1'b0}};
                        end
                        else            // LBPROT starts at Bottom
                        begin
                            Sec_Prot[(SecNumHyb-31)/2+7 : 0]       = {136{1'b1}};
                            Sec_Prot[SecNumHyb:(SecNumHyb-31)/2+8] = {152{1'b0}};
                        end
                    end
                end
            end

            3'b111:
            begin
                Sec_Prot[SecNumHyb:0] =  {288{1'b1}};
            end
        endcase
    end

    always @(CFR3V[4])
    begin
        if (CFR3V[4] == 1'b0)
        begin
            PageSize = 255;
            PageNum  = PageNum256;
        end
        else
        begin
            PageSize = 511;
            PageNum  = PageNum512;
        end
    end
    
    ////////////////////////////////////////////////////////////////////////
    // autoboot control logic
    ////////////////////////////////////////////////////////////////////////
    always @(rising_edge_SCK_ipd or current_state_event)
    begin
        if(current_state == AUTOBOOT)
        begin
            if (rising_edge_SCK_ipd)
            begin
                if (start_delay > 0)
                    start_delay = start_delay - 1;
            end

            if (start_delay == 0)
            begin
                start_autoboot = 1;
            end
        end
    end



    // Procedure ADDRHILO_SEC
    task ADDRHILO_SEC;
    inout   AddrLOW;
    inout   AddrHIGH;
    input   Addr;
    integer AddrLOW;
    integer AddrHIGH;
    integer Addr;
    integer sector;
    begin
        if (CFR3V[3] == 1'b0) //Hybrid Sector Architecture
        begin
            if ( SP4KBS_NV == 0)//Top or Botton
            begin
                if (TB4KBS_NV == 0) //4KB Sectors at Bottom
                begin
                    if (Addr/(SecSize256+1) == 0)
                    begin
                        if (Addr/(SecSize4+1) < 32 &&
                           ( Instruct == ER004_4_0))  //4KB Sectors
                        begin
                            sector   = Addr/(SecSize4+1);
                            AddrLOW  = sector*(SecSize4+1);
                            AddrHIGH = sector*(SecSize4+1) + SecSize4;
                        end
                        else
                        begin
                            AddrLOW  = 32*(SecSize4+1);
                            AddrHIGH = SecSize256;
                        end
                    end
                    else
                    begin
                        sector   = Addr/(SecSize256+1);
                        AddrLOW  = sector*(SecSize256+1);
                        AddrHIGH = sector*(SecSize256+1) + SecSize256;
                    end
                end
                else  //4KB Sectors at Top
                begin
                    if (Addr/(SecSize256+1) == 255)
                    begin
                        if (Addr >  (AddrRANGE - 32*(SecSize4+1))&&
                           (Instruct == ER004_4_0)) //4KB Sectors
                        begin
                            sector   = 256 +
                               (Addr-(AddrRANGE + 1 - 32*(SecSize4+1)))/(SecSize4+1);
                            AddrLOW  = AddrRANGE + 1 - 32*(SecSize4+1) +
                               (sector-256)*(SecSize4+1);
                            AddrHIGH = AddrRANGE + 1 - 32*(SecSize4+1) +
                                       (sector-256)*(SecSize4+1) + SecSize4;
                        end
                        else
                        begin
                            AddrLOW  = 255*(SecSize256+1);
                            AddrHIGH = AddrRANGE - 32*(SecSize4+1);
                        end
                    end
                    else
                    begin
                        sector   = Addr/(SecSize256+1);
                        AddrLOW  = sector*(SecSize256+1);
                        AddrHIGH = sector*(SecSize256+1) + SecSize256;
                    end
                end
            end
            else if ( SP4KBS_NV == 1'b1) //Top and Botton
            begin
                if (Addr/(SecSize256+1) == 0)
                    begin
                        if (Addr/(SecSize4+1) < 16 &&
                           (Instruct == ER004_4_0))  //4KB Sectors
                        begin
                            sector   = Addr/(SecSize4+1);
                            AddrLOW  = sector*(SecSize4+1);
                            AddrHIGH = sector*(SecSize4+1) + SecSize4;
                        end
                        else
                        begin
                            AddrLOW  = 16*(SecSize4+1);
                            AddrHIGH = SecSize256;
                        end
                    end
                    else if (Addr/(SecSize256+1) == 272)
                    begin
                        if (Addr >  (AddrRANGE - 16*(SecSize4+1))&&
                           (Instruct == ER004_4_0)) //4KB Sectors
                        begin
                            sector   = 256 +
                               (Addr-(AddrRANGE + 1 - 16*(SecSize4+1)))/(SecSize4+1);
                            AddrLOW  = AddrRANGE + 1 - 16*(SecSize4+1) +
                               (sector-256)*(SecSize4+1);
                            AddrHIGH = AddrRANGE + 1 - 16*(SecSize4+1) +
                                       (sector-256)*(SecSize4+1) + SecSize4;
                        end
                        else
                        begin
                            AddrLOW  = 255*(SecSize256+1);
                            AddrHIGH = AddrRANGE - 16*(SecSize4+1);
                        end
                    end
                    else
                    begin
                        sector   = Addr/(SecSize256+1);
                        AddrLOW  = sector*(SecSize256+1);
                        AddrHIGH = sector*(SecSize256+1) + SecSize256;
                    end
            end
        end
        else   //Uniform Sector Architecture
        begin
            sector   = Addr/(SecSize256+1);
            AddrLOW  = sector*(SecSize256+1);
            AddrHIGH = sector*(SecSize256+1) + SecSize256;
        end
    end
    endtask

    // Procedure ADDRHILO_PG
    task ADDRHILO_PG;
    inout  AddrLOW;
    inout  AddrHIGH;
    input   Addr;
    integer AddrLOW;
    integer AddrHIGH;
    integer Addr;
    integer page;
    begin
        page = Addr / (PageSize + 1);
        AddrLOW = page * (PageSize + 1);
        AddrHIGH = page * (PageSize + 1) + PageSize;
    end
    endtask

    // Procedure ReturnSectorID
    task ReturnSectorID;
    inout   sect;
    input   Address;
    integer sect;
    integer Address;
    integer conv;
    integer HybAddrHi;
    integer HybAddrLow;
    begin
        if (CFR3V[3] == 1'b0) //Hybrid Sector Architecture 
        begin
            if  (CFR1V[6] == 1'b0) 
            begin
                conv = Address / (SecSize256+1);
                if (!TopBoot && BottomBoot)
                begin
                    if (conv == 0)  //4KB Sectors
                    begin
                        param_sec_write_time = 1'b0;
                        HybAddrHi = 32*(SecSize4+1) - 1;
                
                        if (Address <= HybAddrHi)
                            sect = Address/(SecSize4+1);
                        else
                            sect = 32;
                    end
                    else
                    begin
                        sect = conv + 32;
                        param_sec_write_time = 1'b1;
                    end
                end
                else if (TopBoot && !BottomBoot)
                begin
                    if (conv == 255)       //4KB Sectors
                    begin
                        param_sec_write_time = 1'b0;
                        HybAddrLow = AddrRANGE + 1 - 32*(SecSize4+1);
                
                        if (Address < HybAddrLow)
                            sect = 255;
                        else
                            sect = 256 + (Address - HybAddrLow) / (SecSize4+1);
                    end
                    else
                    begin
                        sect = conv;
                        param_sec_write_time = 1'b1;
                    end
                end
             end
             else if  (CFR1V[6] == 1'b1) 
             begin
                 conv = Address / (SecSize256+1);
                 if (conv == 0)  //4KB Sectors
                 begin
                    param_sec_write_time = 1'b0;
                    HybAddrHi = 16*(SecSize4+1) - 1;
                    if (Address <= HybAddrHi)
                      sect = Address/(SecSize4+1);
                    else
                      sect = 17;
                 end
                 else if (conv == 255)       //4KB Sectors
                 begin
                    param_sec_write_time = 1'b0;
                      HybAddrLow = AddrRANGE + 1 - 16*(SecSize4+1);
                    if (Address < HybAddrLow)
                      sect = 271;
                    else
                      sect = 272 + (Address - HybAddrLow) / (SecSize4+1);
                 end
                 else if (conv > 0 && conv < 255)
                 begin
                      sect = conv + 16;
                      param_sec_write_time = 1'b1;
                 end
             end
        end
        else  //Uniform Sector Architecture
        begin
            sect = Address/(SecSize256+1);
            param_sec_write_time = 1'b1;
        end
    end
    endtask

    task READ_ALL_REG;
        input integer Addr;
        inout integer RDAR_reg;
    begin

        if (Addr == 32'h00000000)
            RDAR_reg = STR1N;
        else if (Addr == 32'h00000002)
            RDAR_reg = CFR1N;
        else if (Addr == 32'h00000003)
            RDAR_reg = CFR2N;
        else if (Addr == 32'h00000004)
            RDAR_reg = CFR3N;
        else if (Addr == 32'h00000005)
            RDAR_reg = CFR4N;
        else if (Addr == 32'h00000006)
            RDAR_reg = CFR5N;
        else if (Addr == 32'h00000020)
        begin
            if (ASPPWD)
                RDAR_reg = PWDO[7:0];
            else
                RDAR_reg = 8'bXX;
        end
        else if (Addr == 32'h00000021)
        begin
            if (ASPPWD)
                RDAR_reg = PWDO[15:8];
            else
                RDAR_reg = 8'bXX;
        end
        else if (Addr == 32'h00000022)
        begin
            if (ASPPWD)
                RDAR_reg = PWDO[23:16];
            else
                RDAR_reg = 8'bXX;
        end
        else if (Addr == 32'h00000023)
        begin
            if (ASPPWD)
                RDAR_reg = PWDO[31:24];
            else
                RDAR_reg = 8'bXX;
        end
        else if (Addr == 32'h00000024)
        begin
            if (ASPPWD)
                RDAR_reg = PWDO[39:32];
            else
                RDAR_reg = 8'bXX;
        end
        else if (Addr == 32'h00000025)
        begin
            if (ASPPWD)
                RDAR_reg = PWDO[47:40];
            else
                RDAR_reg = 8'bXX;
        end
        else if (Addr == 32'h00000026)
        begin
            if (ASPPWD)
                RDAR_reg = PWDO[55:48];
            else
                RDAR_reg = 8'bXX;
        end
        else if (Addr == 32'h00000027)
        begin
            if (ASPPWD)
                RDAR_reg = PWDO[63:56];
            else
                RDAR_reg = 8'bXX;
        end
        else if (Addr == 32'h00000030)
            RDAR_reg = ASPO[7:0];
        else if (Addr == 32'h00000031)
            RDAR_reg = ASPO[15:8];
        else if (Addr == 32'h00000042)
            RDAR_reg = ATBN[7:0];
        else if (Addr == 32'h00000043)
            RDAR_reg = ATBN[15:8];
        else if (Addr == 32'h00000044)
            RDAR_reg = ATBN[23:16];
        else if (Addr == 32'h00000045)
            RDAR_reg = ATBN[31:24];
        else if (Addr == 32'h00000050)
            RDAR_reg = EFX0O[7:0];
        else if (Addr == 32'h00000051)
            RDAR_reg = EFX0O[15:8];
        else if (Addr == 32'h00000052)
            RDAR_reg = EFX1O[7:0];
        else if (Addr == 32'h00000053)
            RDAR_reg = EFX1O[15:8];
        else if (Addr == 32'h00000054)
            RDAR_reg = EFX2O[7:0];
        else if (Addr == 32'h00000055)
            RDAR_reg = EFX2O[15:8];
        else if (Addr == 32'h00000056)
            RDAR_reg = EFX3O[7:0];
        else if (Addr == 32'h00000057)
            RDAR_reg = EFX3O[15:8];
        else if (Addr == 32'h00000058)
            RDAR_reg = EFX4O[7:0];
        else if (Addr == 32'h00000059)
            RDAR_reg = EFX4O[15:8];
        else if (Addr == 32'h00000079)
            RDAR_reg = UID_reg[7:0];
        else if (Addr == 32'h0000007A)
            RDAR_reg = UID_reg[15:8];
        else if (Addr == 32'h0000007B)
            RDAR_reg = UID_reg[23:16];
        else if (Addr == 32'h0000007C)
            RDAR_reg = UID_reg[31:24];
        else if (Addr == 32'h0000007D)
            RDAR_reg = UID_reg[39:32];
        else if (Addr == 32'h0000007E)
            RDAR_reg = UID_reg[47:40];
        else if (Addr == 32'h0000007F)
            RDAR_reg = UID_reg[55:48];
        else if (Addr == 32'h00000080)
            RDAR_reg = UID_reg[63:56];
        else if (Addr == 32'h00800000)
            RDAR_reg = STR1V;
        else if (Addr == 32'h00800001)
            RDAR_reg = STR2V;
        else if (Addr == 32'h00800002)
            RDAR_reg = CFR1V;
        else if (Addr == 32'h00800003)
            RDAR_reg = CFR2V;
        else if (Addr == 32'h00800004)
            RDAR_reg = CFR3V;
        else if (Addr == 32'h00800005)
            RDAR_reg = CFR4V;
        else if (Addr == 32'h00800006)
            RDAR_reg = CFR5V;
        else if (Addr == 32'h00800008)
            RDAR_reg = ICEV;
        else if (Addr == 32'h00800067)
            RDAR_reg = INSV;
        else if (Addr == 32'h00800068)
            RDAR_reg = INCV;
        else if (Addr == 32'h00800089)
            RDAR_reg = ESCV;
        else if (Addr == 32'h0080008A)
            RDAR_reg = ECTV[7:0];
        else if (Addr == 32'h0080008B)
            RDAR_reg = ECTV[15:8];
        else if (Addr == 32'h0080008E)
            RDAR_reg = EATV[7:0];
        else if (Addr == 32'h0080008F)
            RDAR_reg = EATV[15:8];
        else if (Addr == 32'h00800040)
            RDAR_reg = EATV[23:16];
        else if (Addr == 32'h00800041)
            RDAR_reg = EATV[31:24];
        else if (Addr == 32'h00800091)
            RDAR_reg = SECV[7:0];
        else if (Addr == 32'h00800092)
            RDAR_reg = SECV[15:8];
        else if (Addr == 32'h00800093)
            RDAR_reg = SECV[23:16];
        else if (Addr == 32'h00800095)
            RDAR_reg = DCRV[7:0];
        else if (Addr == 32'h00800096)
            RDAR_reg = DCRV[15:8];
        else if (Addr == 32'h00800097)
            RDAR_reg = DCRV[23:16];
        else if (Addr == 32'h00800098)
            RDAR_reg = DCRV[31:24];
        else if (Addr == 32'h0080009B)
            RDAR_reg = PPLV;
        else
            RDAR_reg = 8'bXX;//N/A

    end
    endtask

    ///////////////////////////////////////////////////////////////////////////
    // edge controll processes
    ///////////////////////////////////////////////////////////////////////////

    always @(posedge PoweredUp)
    begin
        rising_edge_PoweredUp = 1;
        #1 rising_edge_PoweredUp = 0;
    end

    always @(posedge SCK_ipd)
    begin
       rising_edge_SCK_ipd = 1'b1;
       #1 rising_edge_SCK_ipd = 1'b0;
    end

    always @(negedge SCK_ipd)
    begin
       falling_edge_SCK_ipd = 1'b1;
       #1 falling_edge_SCK_ipd = 1'b0;
    end

    always @(posedge CSNeg_ipd)
    begin
        rising_edge_CSNeg_ipd = 1'b1;
        #1 rising_edge_CSNeg_ipd = 1'b0;
    end

    always @(negedge CSNeg_ipd)
    begin
        falling_edge_CSNeg_ipd = 1'b1;
        #1 falling_edge_CSNeg_ipd = 1'b0;
    end

    always @(negedge write)
    begin
        falling_edge_write = 1;
        #1 falling_edge_write = 0;
    end

    always @(posedge reseted)
    begin
        rising_edge_reseted = 1;
        #1 rising_edge_reseted = 0;
    end

    always @(negedge RESETNeg)
    begin
        falling_edge_RESETNeg = 1;
        #1 falling_edge_RESETNeg = 0;
    end

    always @(posedge RESETNeg)
    begin
        rising_edge_RESETNeg = 1;
        #1 rising_edge_RESETNeg = 0;
    end

    always @(posedge PSTART)
    begin
        rising_edge_PSTART = 1'b1;
        #1 rising_edge_PSTART = 1'b0;
    end

    always @(posedge PDONE)
    begin
        rising_edge_PDONE = 1'b1;
        #1 rising_edge_PDONE = 1'b0;
    end

    always @(posedge WSTART)
    begin
        rising_edge_WSTART = 1;
        #1 rising_edge_WSTART = 0;
    end

    always @(posedge WDONE)
    begin
        rising_edge_WDONE = 1'b1;
        #1 rising_edge_WDONE = 1'b0;
    end

    always @(posedge CSDONE)
    begin
        rising_edge_CSDONE = 1'b1;
        #1 rising_edge_CSDONE = 1'b0;
    end

    always @(posedge EESSTART)
    begin
        rising_edge_EESSTART = 1;
        #1 rising_edge_EESSTART = 0;
    end

    always @(posedge EESDONE)
    begin
        rising_edge_EESDONE = 1'b1;
        #1 rising_edge_EESDONE = 1'b0;
    end

    always @(posedge bc_done)
    begin
        rising_edge_BCDONE = 1'b1;
        #1 rising_edge_BCDONE = 1'b0;
    end

    always @(posedge ESTART)
    begin
        rising_edge_ESTART = 1'b1;
        #1 rising_edge_ESTART = 1'b0;
    end

    always @(posedge EDONE)
    begin
        rising_edge_EDONE = 1'b1;
        #1 rising_edge_EDONE = 1'b0;
    end

    always @(posedge SEERC_START)
    begin
        rising_edge_SEERC_START = 1'b1;
        #1 rising_edge_SEERC_START = 1'b0;
    end

    always @(posedge SEERC_DONE)
    begin
        rising_edge_SEERC_DONE = 1'b1;
        #1 rising_edge_SEERC_DONE = 1'b0;
    end

    always @(posedge PRGSUSP_out)
    begin
        PRGSUSP_out_event = 1;
        #1 PRGSUSP_out_event = 0;
    end

    always @(posedge ERSSUSP_out)
    begin
        ERSSUSP_out_event = 1;
        #1 ERSSUSP_out_event = 0;
    end

    always @(posedge START_T1_in)
    begin
        rising_edge_START_T1_in = 1'b1;
        #1 rising_edge_START_T1_in = 1'b0;
    end

    always @(posedge CRCSTART)
    begin
        rising_edge_CRCSTART = 1'b1;
        #1 rising_edge_CRCSTART = 1'b0;
    end

    always @(posedge CRCDONE)
    begin
        rising_edge_CRCDONE = 1'b1;
        #1 rising_edge_CRCDONE = 1'b0;
    end

    always @(change_addr)
    begin
        change_addr_event = 1'b1;
        #1 change_addr_event = 1'b0;
    end
    
    always @(negedge RDYBSY)
    begin
        falling_edge_RDYBSY = 1;
        #1 falling_edge_RDYBSY = 0;
    end

    always @(current_state)
    begin
        current_state_event = 1'b1;
        #1 current_state_event = 1'b0;
    end

    always @(Instruct)
    begin
        Instruct_event = 1'b1;
        #1 Instruct_event = 1'b0;
    end

    always @(posedge DPD_out)
    begin
        rising_edge_DPD_out = 1'b1;
        #1 rising_edge_DPD_out = 1'b0;
    end
    
    always @(negedge DPD_POR_out)
    begin
        falling_edge_DPD_POR_out = 1'b1;
        #1 falling_edge_DPD_POR_out = 1'b0;
    end

    always @(posedge RST_out)
    begin
        rising_edge_RST_out = 1'b1;
        #1 rising_edge_RST_out = 1'b0;
    end

    always @(negedge RST)
    begin
        falling_edge_RST = 1'b1;
        #1 falling_edge_RST = 1'b0;
    end

    always @(posedge SWRST_out)
    begin
        rising_edge_SWRST_out = 1'b1;
        #1 rising_edge_SWRST_out = 1'b0;
    end

    always @(negedge PASSULCK_in)
    begin
        falling_edge_PASSULCK_in = 1'b1;
        #1 falling_edge_PASSULCK_in = 1'b0;
    end

    always @(negedge PPBERASE_in)
    begin
        falling_edge_PPBERASE_in = 1'b1;
        #1 falling_edge_PPBERASE_in = 1'b0;
    end

    integer IOt_01;
    integer IOt_0Z;
    integer DSt_01;
    integer SEERCIOt;
    integer SEERCIOt_dly;

    reg  BuffInIO;
    wire BuffOutIO;

    reg  BuffInIOZ;
    wire BuffOutIOZ;

    reg  BuffInDS;
    wire BuffOutDS;

    reg  SEERCSInIO;
    wire SEERCOutIO;

    BUFFER    BUF_DOut   (BuffOutIO, BuffInIO);
    BUFFER    BUF_DOutZ  (BuffOutIOZ, BuffInIOZ);
    BUFFER    BUF_DS     (BuffOutDS, BuffInDS);
    BUFFER    BUF_SEERC  (SEERCOutIO, SEERCSInIO);

    initial
    begin
        BuffInIO   = 1'b1;
        BuffInIOZ  = 1'b1;
        BuffInDS   = 1'b1;
        SEERCSInIO = 1'b0;
    end

    always @(posedge BuffOutIO)
    begin
        IOt_01 = $time;
    end

    always @(posedge BuffOutIOZ)
    begin
        IOt_0Z = $time;
    end

    always @(posedge BuffOutDS)
    begin
        DSt_01 = $time;
    end

    // For SEECR time
    // Use always block to have some functionality in case user doesn't use SDF
    // Default delay will be #10
    always @(negedge SEERCOutIO)
    begin
        SEERCIOt      <= $time;
    end

    always @(SEERCIOt)
    begin
        SEERCIOt_dly  <= SEERCIOt;
    end

    always @(SEERCIOt_dly)
    begin
        if (SEERCIOt == 63e6)
            tdevice_SEERC = tdevice_SEERC_max;
        else if (SEERCIOt == 55e6)
            tdevice_SEERC = tdevice_SEERC_typ;
        else if (SEERCIOt == 55e6)
            tdevice_SEERC = tdevice_SEERC_min;
        else
            tdevice_SEERC = 63e6;
    end
    // end SEECR time

    always @(DataDriveOut_SO,DataDriveOut_SI,DataDriveOut_Dout)
    begin
        if ((IOt_01 > SCK_cycle/2) && DOUBLE)
        begin
            glitch = 1;
            SOut_zd        <= #(IOt_01-1000) DataDriveOut_SO;
            SIOut_zd       <= #(IOt_01-1000) DataDriveOut_SI;
            Dout_zd[7:2]   <= #(IOt_01-1000) DataDriveOut_Dout;
            Dout_zd[1]     <= #(IOt_01-1000) DataDriveOut_SO;
            Dout_zd[0]     <= #(IOt_01-1000) DataDriveOut_SI;
        end
        else
        begin
            glitch = 0;
            SOut_zd        <= DataDriveOut_SO;
            SIOut_zd       <= DataDriveOut_SI;
            Dout_zd[7:2]   <= DataDriveOut_Dout;
            Dout_zd[1]     <= DataDriveOut_SO;
            Dout_zd[0]     <= DataDriveOut_SI;
        end
    end

    always @(rising_edge_SCK_ipd, falling_edge_SCK_ipd)
    begin
        if (~CSNeg_ipd)
        begin
      // In DPD mode DS will not toggle during an attempted read transaction
            if (DPD_in == 1'b1)
            begin
                glitch_ds = 0;
                DS_zd  <= 1'b0;
            end
      // Detect glitch
            else if ((DSt_01 > SCK_cycle/2)  && DATA_STROBE)
            begin
                glitch_ds = 1;
                DS_zd  <= #DSt_01 DataDriveOut_DS;
            end
//       Read/Write transactions
            else if (DATA_STROBE)
            begin
                glitch_ds = 0;
                DS_zd  <=  #DSt_01 DataDriveOut_DS;
            end
        end
    end

endmodule

module BUFFER (OUT,IN);
    input IN;
    output OUT;
    buf   ( OUT, IN);
endmodule

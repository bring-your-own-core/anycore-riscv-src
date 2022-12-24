/*******************************************************************************
#                        NORTH CAROLINA STATE UNIVERSITY
#
#                              AnyCore Project
# 
# AnyCore written by NCSU authors Rangeen Basu Roy Chowdhury and Eric Rotenberg.
# 
# AnyCore is based on FabScalar which was written by NCSU authors Niket K. 
# Choudhary, Brandon H. Dwiel, and Eric Rotenberg.
# 
# AnyCore also includes contributions by NCSU authors Elliott Forbes, Jayneel 
# Gandhi, Anil Kumar Kannepalli, Sungkwan Ku, Hiran Mayukh, Hashem Hashemi 
# Najaf-abadi, Sandeep Navada, Tanmay Shah, Ashlesha Shastri, Vinesh Srinivasan, 
# and Salil Wadhavkar.
# 
# AnyCore is distributed under the BSD license.
*******************************************************************************/

`timescale 1ns/100ps

module AnyCore_Piton(

	input                            clk,
	input                            rst_n,
    output                           spc_grst_l,

	//input                            resetFetch_i,
	//input                            cacheModeOverride_i,

    input [63:0]                     startPC_i,

  // Debug interface - separate address space, read-write from outside
  // or loopback from core pipeline.
  // Operates at ioClk
  input  [5:0]                     regAddr_i,     //64 registers
  input  [`REG_DATA_WIDTH-1:0]     regWrData_i,
  input                            regWrEn_i,
  output logic [`REG_DATA_WIDTH-1:0] regRdData_o,

`ifdef DYNAMIC_CONFIG
  input                            stallFetch_i,
  input                            reconfigureCore_i,
`endif


  input  [1:0]                        irq_i,      // level sensitive IR lines, mip & sip (async)
  input                               ipi_i,      // software interrupt (a.k.a inter-process-interrupt)
  input                               time_irq_i, // Timer interrupts

  input        [`CSR_WIDTH-1:0]     hartId_i, // hart id in multicore environment

  // TRI inputs
  input                                  l15_transducer_val,
  input   [3:0]                          l15_transducer_returntype,
  input                                  l15_transducer_l2miss,
  input   [1:0]                          l15_transducer_error,
  input                                  l15_transducer_noncacheable,
  input                                  l15_transducer_atomic,
  input   [`L15_THREADID_MASK]           l15_transducer_threadid,
  input                                  l15_transducer_prefetch,
  input                                  l15_transducer_f4b,
  input   [63:0]                         l15_transducer_data_0,
  input   [63:0]                         l15_transducer_data_1,
  input   [63:0]                         l15_transducer_data_2,
  input   [63:0]                         l15_transducer_data_3,
  input                                  l15_transducer_inval_icache_all_way,
  input                                  l15_transducer_inval_dcache_all_way,
  input   [`L15_PADDR_MASK]              l15_transducer_address,
  input   [15:4]                         l15_transducer_inval_address_15_4,
  input                                  l15_transducer_cross_invalidate,
  input   [1:0]                          l15_transducer_cross_invalidate_way,
  input                                  l15_transducer_inval_dcache_inval,
  input                                  l15_transducer_inval_icache_inval,
  input   [1:0]                          l15_transducer_inval_way,
  input                                  l15_transducer_blockinitstore,

  input                                  l15_transducer_ack,
  input                                  l15_transducer_header_ack,


  // TRI outputs
  output                                 transducer_l15_req_ack,
  output  [`PCX_REQTYPE_WIDTH-1:0]       transducer_l15_rqtype,
  output  [`L15_AMO_OP_WIDTH-1:0]        transducer_l15_amo_op,

  output                                 transducer_l15_nc,
  output  [`PCX_SIZE_FIELD_WIDTH-1:0]    transducer_l15_size,
  output  [`L15_THREADID_MASK]           transducer_l15_threadid,
  output                                 transducer_l15_prefetch,
  output                                 transducer_l15_invalidate_cacheline,
  output                                 transducer_l15_blockstore,
  output                                 transducer_l15_blockinitstore,
  output  [1:0]                          transducer_l15_l1rplway,
  output                                 transducer_l15_val,
  output  [`L15_PADDR_HI:0]              transducer_l15_address,
  output  [32:0]                         transducer_l15_csm_data,
  output  [63:0]                         transducer_l15_data,
  output  [63:0]                         transducer_l15_data_next_entry
	);


/*****************************Wire Declaration**********************************/

wire [`ICACHE_BLOCK_ADDR_BITS-1:0] ic2memReqAddr;    // memory read address
wire                               ic2memReqValid;   // memory read enable
wire [`ICACHE_NUM_WAYS_LOG-1:0]                        ic2memReqWay;     // memory way 
wire [`ICACHE_TAG_BITS-1:0]        mem2icTag;        // tag of the incoming data
wire [`ICACHE_INDEX_BITS-1:0]      mem2icIndex;      // index of the incoming data
wire [`ICACHE_BITS_IN_LINE-1:0]    mem2icData;       // requested data
wire                               mem2icRespValid;  // requested data is ready

wire                               mem2icInv;        // icache invalidation
wire  [`ICACHE_INDEX_BITS-1:0]     mem2icInvInd;     // icache invalidation index
wire  [`ICACHE_NUM_WAYS_LOG-1:0]                        mem2icInvWay;     // icache invalidation way (unused)

// cache-to-memory interface for Loads
wire [`DCACHE_BLOCK_ADDR_BITS-1:0] dc2memLdAddr;  // memory read address
wire                               dc2memLdValid; // memory read enable
wire [1:0]                         dc2memReqWay;  // memory way

// memory-to-cache interface for Loads
wire [`DCACHE_TAG_BITS-1:0]     mem2dcLdTag;       // tag of the incoming datadetermine
wire [`DCACHE_INDEX_BITS-1:0]   mem2dcLdIndex;     // index of the incoming data
wire [`DCACHE_BITS_IN_LINE-1:0] mem2dcLdData;      // requested data
wire                            mem2dcLdValid;     // indicates the requested data is ready

// cache-to-memory interface for stores
wire [`DCACHE_ST_ADDR_BITS-1:0]  dc2memStAddr;
wire [`SIZE_DATA-1:0]            dc2memStData;
wire [2:0]                       dc2memStSize;
wire                             dc2memStValid;

wire                               mem2dcInv;     // dcache invalidation
wire  [`DCACHE_INDEX_BITS-1:0]     mem2dcInvInd;  // dcache invalidation index
wire  [1:0]                        mem2dcInvWay;  // dcache invalidation way (unused)

wire                            mem2dcStComplete;
wire                            mem2dcStStall;

wire                             anycore_int;

wire reset;
reg reset_l;

assign spc_grst_l = rst_n;
assign reset = ~reset_l;

always @ (posedge clk) begin
    if(!rst_n) begin
        reset_l <= 1'b0;
    end
    else if (anycore_int) begin
        reset_l <= 1'b1;
    end
end

wire [`SIZE_PC-1:0]                ldAddr;
wire [`SIZE_DATA-1:0]              ldData;
wire                               ldEn;

wire [`SIZE_PC-1:0]                stAddr;
wire [`SIZE_DATA-1:0]              stData;
wire [3:0]                         stEn;

reg  [`SIZE_PC-1:0]                instPC[0:`FETCH_WIDTH-1];

assign ldData     = 32'h0;

logic [`SIZE_PC-1:0]  currentInstPC;
assign currentInstPC = instPC[0];

logic [`SIZE_PC-1:0] prevInstPC;

always @(posedge clk) begin
    prevInstPC <= currentInstPC;
end

always @(posedge clk) begin
    if (prevInstPC != currentInstPC) begin
        $display("currentInstPC changed from 0x%x to 0x%x", prevInstPC, currentInstPC);
    end
end

logic [`SIZE_INSTRUCTION-1:0]      inst   [0:`FETCH_WIDTH-1];
logic                              instValid;
logic [2:0]                        cancelCurrentFetch;

assign instValid = 1'b0;
assign cancelCurrentFetch = 3'h0;

`ifdef DYNAMIC_CONFIG
    logic                             stallFetch_sync; 
    logic                             reconfigureCore_sync;
    logic [`FETCH_WIDTH-1:0]          fetchLaneActive;
    logic [`DISPATCH_WIDTH-1:0]       dispatchLaneActive;
    logic [`ISSUE_WIDTH-1:0]          issueLaneActive;         
    logic [`EXEC_WIDTH-1:0]           execLaneActive;
    logic [`EXEC_WIDTH-1:0]           saluLaneActive;
    logic [`EXEC_WIDTH-1:0]           caluLaneActive;
    logic [`COMMIT_WIDTH-1:0]         commitLaneActive;
    logic [`NUM_PARTS_RF-1:0]         rfPartitionActive;
    logic [`NUM_PARTS_RF-1:0]         alPartitionActive;
    logic [`STRUCT_PARTS_LSQ-1:0]     lsqPartitionActive;
    logic [`STRUCT_PARTS-1:0]         iqPartitionActive;
    logic [`STRUCT_PARTS-1:0]         ibuffPartitionActive;
`endif    

`ifdef SCRATCH_PAD
    logic [`DEBUG_INST_RAM_LOG+`DEBUG_INST_RAM_WIDTH_LOG-1:0] instScratchAddr;
    logic [7:0]                       instScratchWrData;  
    logic                             instScratchWrEn ;  
    logic [7:0]                       instScratchRdData;  
    logic [`DEBUG_DATA_RAM_LOG+`DEBUG_DATA_RAM_WIDTH_LOG-1:0] dataScratchAddr;
    logic [7:0]                       dataScratchWrData;
    logic                             dataScratchWrEn;  
    logic [7:0]                       dataScratchRdData; 
    logic [1:0]                       scratchPadEn;
`endif


`ifdef INST_CACHE
    logic                             instCacheBypass;

    logic                             icScratchModeEn;
    logic [`ICACHE_INDEX_BITS+`ICACHE_BYTES_IN_LINE_LOG-1:0]  icScratchWrAddr;
    logic                                                     icScratchWrEn;
    logic [7:0]                                               icScratchWrData;
    logic [7:0]                                               icScratchRdData;
`endif  

`ifdef DATA_CACHE
    logic                             dataCacheBypass;
    logic                             dcScratchModeEn;

    logic [`DCACHE_INDEX_BITS+`DCACHE_BYTES_IN_LINE_LOG-1:0]  dcScratchWrAddr;
    logic                                                     dcScratchWrEn;
    logic [7:0]                                               dcScratchWrData;
    logic [7:0]                                               dcScratchRdData;
`endif

    logic [`SIZE_PHYSICAL_LOG+`SIZE_DATA_BYTE_OFFSET-1:0]     debugPRFAddr; 
    logic [`SRAM_DATA_WIDTH-1:0]      debugPRFRdData;    
    logic [`SRAM_DATA_WIDTH-1:0]      debugPRFWrData;
    logic                             debugPRFWrEn;

	  logic [`SIZE_RMT_LOG-1:0]         debugAMTAddr;
	  logic [`SIZE_PHYSICAL_LOG-1:0]    debugAMTRdData;

`ifdef PERF_MON
    logic [31:0]                      perfMonRegData;
    logic [`REG_DATA_WIDTH-1:0]       perfMonRegAddr;
    logic                             perfMonRegGlobalClr;
    logic                             perfMonRegClr;
    logic 		                        perfMonRegRun;
`endif

    logic                             reconfigDone;
    logic                             pipeDrained;
    logic                             fetchReq;
    logic                             fetchRecoverFlag;
    logic                             instPC_push_af;
    logic                             instPC_packet_req;
    logic                             cpx_depacket_af;
    logic                             pcx_packet_af;
    logic                             ldAddr_packet_req;
    logic                             ldData_depacket_af;
    logic                             st_packet_req;

logic   coreClk;
logic   ioClk;
logic   resetFetch_sync;
logic   reset_sync;

assign ioClk    = clk;
assign coreClk  = clk;
assign reset_sync = reset;

//DebugConfig debCon(
//    .ioClk                    (ioClk                  ),
//    .coreClk                  (coreClk                ),
//    .reset                    (reset                  ),
//    .resetFetch_i             (1'b0),//resetFetch_i           ),
//    .cacheModeOverride_i      (1'b0),//cacheModeOverride_i    ),
//                                                      
//    .reset_sync_o             (reset_sync             ),
//    .resetFetch_sync_o        (resetFetch_sync        ),
//                                                      
//    .regAddr_i                (regAddr_i              ), 
//    .regWrData_i              (regWrData_i            ),
//    .regWrEn_i                (regWrEn_i              ),
//    .regRdData_o              (regRdData_o            ),
//
//    .currentInstPC_i          (currentInstPC          ),
//                                                        
//`ifdef DYNAMIC_CONFIG          
//    .stallFetch_i             (stallFetch_i           ), 
//    .reconfigureCore_i        (reconfigureCore_i      ),
//    .stallFetch_sync_o        (stallFetch_sync        ), 
//    .reconfigureCore_sync_o   (reconfigureCore_sync   ),
//    .fetchLaneActive_o        (fetchLaneActive        ),
//    .dispatchLaneActive_o     (dispatchLaneActive     ),
//    .issueLaneActive_o        (issueLaneActive        ),         
//    .execLaneActive_o         (execLaneActive         ),
//    .saluLaneActive_o         (saluLaneActive         ),
//    .caluLaneActive_o         (caluLaneActive         ),
//    .commitLaneActive_o       (commitLaneActive       ),
//    .rfPartitionActive_o      (rfPartitionActive      ),
//    .alPartitionActive_o      (alPartitionActive      ),
//    .lsqPartitionActive_o     (lsqPartitionActive     ),
//    .iqPartitionActive_o      (iqPartitionActive      ),
//    .ibuffPartitionActive_o   (ibuffPartitionActive   ),
//    .reconfigDone_i           (reconfigDone           ),
//    .pipeDrained_i            (pipeDrained            ),
//`endif                         
//                                                        
//`ifdef SCRATCH_PAD            
//    .instScratchAddr_o        (instScratchAddr        ),
//    .instScratchWrData_o      (instScratchWrData      ),    
//    .instScratchWrEn_o        (instScratchWrEn        ),  
//    .instScratchRdData_i      (instScratchRdData      ),  
//    .dataScratchAddr_o        (dataScratchAddr        ),
//    .dataScratchWrData_o      (dataScratchWrData      ),
//    .dataScratchWrEn_o        (dataScratchWrEn        ),  
//    .dataScratchRdData_i      (dataScratchRdData      ), 
//    .scratchPadEn_o           (scratchPadEn           ),
//`endif                       
//                                                        
//`ifdef INST_CACHE           
//    .instCacheBypass_o        (instCacheBypass        ),
//    .icScratchModeEn_o        (icScratchModeEn        ),
//    .icScratchWrAddr_o        (icScratchWrAddr        ),
//    .icScratchWrEn_o          (icScratchWrEn          ),
//    .icScratchWrData_o        (icScratchWrData        ),
//    .icScratchRdData_i        (icScratchRdData        ),
//`endif                     
//                                                        
//`ifdef DATA_CACHE         
//    .dataCacheBypass_o        (dataCacheBypass        ),
//    .dcScratchModeEn_o        (dcScratchModeEn        ),
//    .dcScratchWrAddr_o        (dcScratchWrAddr        ),
//    .dcScratchWrEn_o          (dcScratchWrEn          ),
//    .dcScratchWrData_o        (dcScratchWrData        ),
//    .dcScratchRdData_i        (dcScratchRdData        ),
//`endif                   
//                                                        
//                                                       
//`ifdef PERF_MON         
//    .perfMonRegData_i         (perfMonRegData         ),
//    .perfMonRegAddr_o         (perfMonRegAddr         ),
//    .perfMonRegGlobalClr_o    (perfMonRegGlobalClr    ),
//    .perfMonRegClr_o          (perfMonRegClr          ),
//    .perfMonRegRun_o          (perfMonRegRun          ),
//`endif
//
//    .debugPRFAddr_o           (debugPRFAddr           ), 
//    .debugPRFRdData_i         (debugPRFRdData         ),    
//    .debugPRFWrData_o         (debugPRFWrData         ),
//    .debugPRFWrEn_o           (debugPRFWrEn           ),
//
//	  .debugAMTAddr_o           (debugAMTAddr           ),
//	  .debugAMTRdData_i         (debugAMTRdData         )
//
//  );

assign icScratchModeEn = 1'b0;
assign icScratchWrEn = 1'b0;
assign icScratchWrAddr = {(`ICACHE_INDEX_BITS+`ICACHE_BYTES_IN_LINE_LOG){1'b0}};
assign icScratchWrData = 8'b0;

assign dcScratchModeEn = 1'b0;
assign dcScratchWrEn = 1'b0;
assign dcScratchWrAddr = {(`DCACHE_INDEX_BITS+`DCACHE_BYTES_IN_LINE_LOG){1'b0}};
assign dcScratchWrData = 8'b0;

assign debugPRFWrEn = 1'b0;
assign debugPRFAddr = {(`SIZE_PHYSICAL_LOG+`SIZE_DATA_BYTE_OFFSET){1'b0}};
assign debugPRFWrData = {`SRAM_DATA_WIDTH{1'b0}};

Core_OOO coreTop(

    .clk                                 (coreClk),
    .reset                               (reset_sync),
    .resetFetch_i                        (resetFetch_sync),
    .toggleFlag_o                        (),

    .irq_i                               ( irq_i ),
    .ipi_i                               ( ipi_i ),
    .time_irq_i                          ( time_irq_i ),
    .hartId_i                                          , //constant

`ifdef SCRATCH_PAD
    .instScratchAddr_i                   (instScratchAddr),
    .instScratchWrData_i                 (instScratchWrData),
    .instScratchWrEn_i                   (instScratchWrEn),
    .instScratchRdData_o                 (instScratchRdData),
    .dataScratchAddr_i                   (dataScratchAddr),
    .dataScratchWrData_i                 (dataScratchWrData),
    .dataScratchWrEn_i                   (dataScratchWrEn),
    .dataScratchRdData_o                 (dataScratchRdData),
    .instScratchPadEn_i                  (scratchPadEn[0]),
    .dataScratchPadEn_i                  (scratchPadEn[1]),
`endif

`ifdef DYNAMIC_CONFIG
    .stallFetch_i                        (stallFetch_sync), 
    .reconfigureCore_i                   (reconfigureCore_sync),
    .fetchLaneActive_i                   (fetchLaneActive), 
    .dispatchLaneActive_i                (dispatchLaneActive), 
    .issueLaneActive_i                   (issueLaneActive), 
    .execLaneActive_i                    (issueLaneActive),
    .saluLaneActive_i                    (saluLaneActive),
    .caluLaneActive_i                    (caluLaneActive),
    .commitLaneActive_i                  (commitLaneActive), 
    .rfPartitionActive_i                 (rfPartitionActive),
    .alPartitionActive_i                 (alPartitionActive),
    .lsqPartitionActive_i                (lsqPartitionActive),
    .iqPartitionActive_i                 (iqPartitionActive),
    .ibuffPartitionActive_i              (ibuffPartitionActive),
    .reconfigDone_o                      (reconfigDone),
    .pipeDrained_o                       (pipeDrained),
`endif
`ifdef PERF_MON
    .perfMonRegAddr_i                    (perfMonRegAddr),
    .perfMonRegData_o                    (perfMonRegData),
    .perfMonRegRun_i                     (perfMonRegRun),
    .perfMonRegClr_i                     (perfMonRegClr),
    .perfMonRegGlobalClr_i               (perfMonRegGlobalClr),                    
`endif

    .startPC_i                           (startPC_i),
    //.startPC_i                           (64'h00000000800000b4), //vvad
    //.startPC_i                           (64'h00000000800001fc), //masked-filter

    .instPC_o                            (instPC),
    .fetchReq_o                          (fetchReq),
    .fetchRecoverFlag_o                  (fetchRecoverFlag),
    .inst_i                              (inst),
    .instValid_i                         (instValid & ~(|cancelCurrentFetch)),
    .instException_i                     (),

    .ldAddr_o                            (ldAddr),
    .ldData_i                            (ldData),
    .ldDataValid_i                       (ldEn),  //Loopback
    .ldEn_o                              (ldEn),

    .stAddr_o                            (stAddr),
    .stData_o                            (stData),
    .stEn_o                              (stEn),

  `ifdef INST_CACHE
    .ic2memReqAddr_o                     (ic2memReqAddr  ),      // memory read address
    .ic2memReqValid_o                    (ic2memReqValid ),     // memory read enable
    .ic2memReqWay_o                      (ic2memReqWay),
    .mem2icTag_i                         (mem2icTag      ),          // tag of the incoming data
    .mem2icIndex_i                       (mem2icIndex    ),        // index of the incoming data
    .mem2icData_i                        (mem2icData     ),         // requested data
    .mem2icRespValid_i                   (mem2icRespValid),    // requested data is ready

    .mem2icInv_i                         (mem2icInv),
    .mem2icInvInd_i                      (mem2icInvInd),
    .mem2icInvWay_i                      (mem2icInvWay),

    //.instCacheBypass_i                   (instCacheBypass  ),
    .icScratchModeEn_i                   (icScratchModeEn  ),

    .icScratchWrAddr_i                   (icScratchWrAddr  ),
    .icScratchWrEn_i                     (icScratchWrEn    ),
    .icScratchWrData_i                   (icScratchWrData  ),
    .icScratchRdData_o                   (icScratchRdData  ),
  `endif  

  `ifdef DATA_CACHE
    .dataCacheBypass_i                   (dataCacheBypass    ),
    .dcScratchModeEn_i                   (dcScratchModeEn    ),
  
    .dc2memLdAddr_o                      (dc2memLdAddr     ), // memory read address
    .dc2memLdValid_o                     (dc2memLdValid    ), // memory read enable
    .dc2memReqWay_o                      (dc2memReqWay     ),
                                                            
    .mem2dcLdTag_i                       (mem2dcLdTag      ), // tag of the incoming datadetermine
    .mem2dcLdIndex_i                     (mem2dcLdIndex    ), // index of the incoming data
    .mem2dcLdData_i                      (mem2dcLdData     ), // requested data
    .mem2dcLdValid_i                     (mem2dcLdValid    ), // indicates the requested data is ready
                                                            
    .dc2memStAddr_o                      (dc2memStAddr     ), // memory read address
    .dc2memStData_o                      (dc2memStData     ), // memory read address
    .dc2memStSize_o                      (dc2memStSize     ), // memory read address
    .dc2memStValid_o                     (dc2memStValid    ), // memory read enable
                                                            
    .mem2dcInv_i                         (mem2dcInv        ),     // dcache invalidation
    .mem2dcInvInd_i                      (mem2dcInvInd     ),  // dcache invalidation index
    .mem2dcInvWay_i                      (mem2dcInvWay     ),  // dcache invalidation way (unusedndex

    .mem2dcStComplete_i                  (mem2dcStComplete ),
    .mem2dcStStall_i                     (mem2dcStStall    ),

    .dcScratchWrAddr_i                   (dcScratchWrAddr    ),
    .dcScratchWrEn_i                     (dcScratchWrEn      ),
    .dcScratchWrData_i                   (dcScratchWrData    ),
    .dcScratchRdData_o                   (dcScratchRdData    ),
    .dcFlush_i                           (),
    .dcFlushDone_o                       (),
  `endif    

    /* Initialize the PRF from top */
    // These are not used
    .dbAddr_i                            ({`SIZE_PHYSICAL_LOG{1'b0}}),
    .dbData_i                            ({`SIZE_DATA{1'b0}}),
    .dbWe_i                              (1'b0),
   
    .debugPRFAddr_i                      (debugPRFAddr       ), 
    .debugPRFRdData_o                    (debugPRFRdData     ),
    .debugPRFWrEn_i                      (debugPRFWrEn       ),
    .debugPRFWrData_i                    (debugPRFWrData     ),

	  .debugAMTAddr_i                      (debugAMTAddr       ),
	  .debugAMTRdData_o                    (debugAMTRdData     )

 );


`ifdef INST_CACHE
  
`endif //ifdef INST_CACHE

//`ifdef DATA_CACHE
//  logic [32-`DCACHE_BLOCK_ADDR_BITS-1:0] ldPktDummy;
//  assign ldPktDummy = {(32-`DCACHE_BLOCK_ADDR_BITS){1'b0}};
//  
//  Packetizer_Piton #(
//      .PAYLOAD_WIDTH          (32),
//      .PACKET_WIDTH           (`DCACHE_LD_ADDR_PKT_BITS),
//      .ID                     (0),  // This should macth the ID of depacketizer in the TB
//      .DEPTH                  (4),  // Only one outstanding load miss at a time
//      .DEPTH_LOG              (2),
//      .N_PKTS_BITS            (2),
//      .THROTTLE               (0) // Throttling is disabled
//  )
//      pcx_packetizer (
//  
//      .reset                  (reset),
//  
//      .clk_payload            (coreClk),
//      .ic_req_i               (ic2memReqValid_o),
//      .ic_payload_i           ({instPktDummy,ic2memReqAddr_o}),
//      .dc_ld_req_i            (dc2memLdValid_o),
//      .dc_st_req_i            (dc2memStValid_o),
//      .dc_payload_i           ({dc2memLdAddr_o,dc2memStAddr_o,dc2memStData_o,dc2memStByteEn_o}),
//      .payload_grant_o        (),
//      .push_af_o              (pcx_packet_af),
//  
//      .clk_packet             (ioClk),
//      .packet_req_o           (spc0_pcx_req_pq),
//      .lock_o                 (),
//      .packet_o               (spc0_pcx_data_pa),
//      .packet_grant_i         (ldAddr_packet_req), // Request is looped back in
//      .packet_received_i      (pcx_spc0_grant_px)
//  );
//  
//  
//  
//  
//  logic [32-`DCACHE_BLOCK_ADDR_BITS-1:0] ldDePktDummy;
//  
//  Depacketizer_Piton #(
//      .PAYLOAD_WIDTH      (32+`DCACHE_BITS_IN_LINE),
//      .PACKET_WIDTH       (`DCACHE_LD_DATA_PKT_BITS),
//      .ID                 (1), // This should macth the ID of packetizer in the TB
//      .DEPTH              (4), // Only one outstanding load miss at a time
//      .DEPTH_LOG          (2),
//      .N_PKTS_BITS        (2),
//      .INST_NAME          ("cpx_depkt")
//  )
//      cpx_depacketizer (
//  
//      .reset              (reset),
//  
//      .clk_packet         (ioClk),
//      .cpx_packet_i       (cpx_spc0_data_cx2),
//      .cpx_packet_af_o    (cpx_depacket_af),
//  
//      .clk_payload        (coreClk),
//      .ic_payload_o       ({mem2icTag_i,mem2icIndex_i,mem2icData_i}),
//      .ic_payload_valid_o (mem2icRespValid_i),
//      .dc_payload_o       ({mem2dcLdTag_i,mem2dcLdIndex_i,mem2dcLdData_i}),
//      .dc_payload_valid_o (mem2dcLdValid_i),
//      .cpx_packet_received_o  ()
//  );
//  
//`endif


    //DO WE EVEN NEED TO ADD STUFF HERE?
    // not supported at the moment
    assign transducer_l15_amo_op = `L15_AMO_OP_NONE;
    anycore_tri_transducer tri_transducer(
        .clk                               (clk),
        .rst_n                             (rst_n),

        .l15_transducer_ack_i              (l15_transducer_ack),
        .l15_transducer_header_ack_i       (l15_transducer_header_ack),

        .ic2mem_reqaddr_i                  (ic2memReqAddr),
        .ic2mem_reqvalid_i                 (ic2memReqValid),
        .ic2memReqWay_o                    (ic2memReqWay),
        .dc2memReqWay_o                    (dc2memReqWay),
        

        .dc2mem_ldaddr_i                   (dc2memLdAddr),
        .dc2mem_ldvalid_i                  (dc2memLdValid),

        .dc2mem_staddr_i                   (dc2memStAddr),
        .dc2mem_stdata_i                   (dc2memStData),
        .dc2mem_stsize_i                   (dc2memStSize),
        .dc2mem_stvalid_i                  (dc2memStValid),

        .transducer_l15_rqtype_o               (transducer_l15_rqtype),
        .transducer_l15_nc_o                   (transducer_l15_nc),
        .transducer_l15_size_o                 (transducer_l15_size),
        .transducer_l15_threadid_o             (transducer_l15_threadid),
        .transducer_l15_prefetch_o             (transducer_l15_prefetch),
        .transducer_l15_blockstore_o           (transducer_l15_blockstore),
        .transducer_l15_blockinitstore_o       (transducer_l15_blockinitstore),
        .transducer_l15_l1rplway_o             (transducer_l15_l1rplway),
        .transducer_l15_val_o                  (transducer_l15_val),
        .transducer_l15_invalidate_cacheline_o (transducer_l15_invalidate_cacheline),
        .transducer_l15_address_o              (transducer_l15_address),
        .transducer_l15_csm_data_o             (transducer_l15_csm_data),
        .transducer_l15_data_o                 (transducer_l15_data),
        .transducer_l15_data_next_entry_o      (transducer_l15_data_next_entry),

        .l15_transducer_val_i                   (l15_transducer_val),
        .l15_transducer_returntype_i            (l15_transducer_returntype),
        .l15_transducer_l2miss_i                (l15_transducer_l2miss),
        .l15_transducer_error_i                 (l15_transducer_error),
        .l15_transducer_noncacheable_i          (l15_transducer_noncacheable),
        .l15_transducer_atomic_i                (l15_transducer_atomic),
        .l15_transducer_threadid_i              (l15_transducer_threadid),
        .l15_transducer_prefetch_i              (l15_transducer_prefetch),
        .l15_transducer_f4b_i                   (l15_transducer_f4b),
        .l15_transducer_data_0_i                (l15_transducer_data_0),
        .l15_transducer_data_1_i                (l15_transducer_data_1),
        .l15_transducer_data_2_i                (l15_transducer_data_2),
        .l15_transducer_data_3_i                (l15_transducer_data_3),
        .l15_transducer_inval_icache_all_way_i  (l15_transducer_inval_icache_all_way),
        .l15_transducer_inval_dcache_all_way_i  (l15_transducer_inval_dcache_all_way),
        .l15_transducer_address_i               (l15_transducer_address),
        .l15_transducer_inval_address_15_4_i    (l15_transducer_inval_address_15_4),
        .l15_transducer_cross_invalidate_i      (l15_transducer_cross_invalidate),
        .l15_transducer_cross_invalidate_way_i  (l15_transducer_cross_invalidate_way),
        .l15_transducer_inval_dcache_inval_i    (l15_transducer_inval_dcache_inval),
        .l15_transducer_inval_icache_inval_i    (l15_transducer_inval_icache_inval),
        .l15_transducer_inval_way_i             (l15_transducer_inval_way),
        .l15_transducer_blockinitstore_i        (l15_transducer_blockinitstore),

        .transducer_l15_req_ack_o               (transducer_l15_req_ack),

        .mem2ic_tag_o                     (mem2icTag),
        .mem2ic_index_o                   (mem2icIndex),
        .mem2ic_data_o                    (mem2icData),
        .mem2ic_respvalid_o               (mem2icRespValid),

        .mem2ic_invvalid_o                (mem2icInv),
        .mem2ic_invindex_o                (mem2icInvInd),
        .mem2ic_invway_o                  (mem2icInvWay),

        .mem2dc_ldtag_o                   (mem2dcLdTag),
        .mem2dc_ldindex_o                 (mem2dcLdIndex),
        .mem2dc_lddata_o                  (mem2dcLdData),
        .mem2dc_ldvalid_o                 (mem2dcLdValid),

        .mem2dc_invvalid_o                (mem2dcInv),
        .mem2dc_invindex_o                (mem2dcInvInd),
        .mem2dc_invway_o                  (mem2dcInvWay),

        .mem2dc_stcomplete_o              (mem2dcStComplete),
        .mem2dc_ststall_o                 (mem2dcStStall),

        .anycore_int_o                    (anycore_int)
    );

endmodule

`include "iop.h"
`include "CommonConfig.h"
module anycore_tri_transducer(
    //decoder interface
    input wire         clk,
    input wire         rst_n,

    input l15_transducer_ack_i,
    input l15_transducer_header_ack_i,

    input [`ICACHE_BLOCK_ADDR_BITS-1:0] ic2mem_reqaddr_i,
    input                               ic2mem_reqvalid_i,
    output [`ICACHE_NUM_WAYS_LOG-1:0]                        ic2memReqWay_o,

    input [`DCACHE_BLOCK_ADDR_BITS-1:0] dc2mem_ldaddr_i,

    input [`DCACHE_ST_ADDR_BITS-1:0]    dc2mem_staddr_i,
    input [`SIZE_DATA-1:0]              dc2mem_stdata_i,
    input [2:0]                         dc2mem_stsize_i,

    // outputs anycore uses
    output reg  [4:0]  transducer_l15_rqtype_o,
    output reg  [2:0]  transducer_l15_size_o,
    output reg         transducer_l15_val_o,
    output reg  [`PHY_ADDR_WIDTH-1:0] transducer_l15_address_o,
    output reg  [63:0] transducer_l15_data_o,
    output wire        transducer_l15_nc_o,


    // outputs anycore doesn't use
    output wire [0:0]  transducer_l15_threadid_o,
    output wire        transducer_l15_prefetch_o,
    output wire        transducer_l15_invalidate_cacheline_o,
    output wire        transducer_l15_blockstore_o,
    output wire        transducer_l15_blockinitstore_o,
    output reg  [1:0]  transducer_l15_l1rplway_o,
    output wire [63:0] transducer_l15_data_next_entry_o,
    output wire [32:0] transducer_l15_csm_data_o,

    //encoder interface
    input wire          l15_transducer_val_i,
    input wire [3:0]    l15_transducer_returntype_i,
    input wire          l15_transducer_l2miss_i,
    input wire [1:0]    l15_transducer_error_i,
    input wire          l15_transducer_noncacheable_i,
    input wire          l15_transducer_atomic_i,
    input wire [`L15_THREADID_MASK]    l15_transducer_threadid_i,
    input wire          l15_transducer_prefetch_i,
    input wire          l15_transducer_f4b_i,
    input wire [63:0]   l15_transducer_data_0_i,
    input wire [63:0]   l15_transducer_data_1_i,
    input wire [63:0]   l15_transducer_data_2_i,
    input wire [63:0]   l15_transducer_data_3_i,
    input wire          l15_transducer_inval_icache_all_way_i,
    input wire          l15_transducer_inval_dcache_all_way_i,
    input wire [`L15_PADDR_MASK]   l15_transducer_address_i,
    input wire [15:4]   l15_transducer_inval_address_15_4_i,
    input wire          l15_transducer_cross_invalidate_i,
    input wire [1:0]    l15_transducer_cross_invalidate_way_i,
    input wire          l15_transducer_inval_dcache_inval_i,
    input wire          l15_transducer_inval_icache_inval_i,
    //said something about this wire
    input wire [1:0]    l15_transducer_inval_way_i,
    input wire          l15_transducer_blockinitstore_i,

    output              transducer_l15_req_ack_o,

    output [`ICACHE_TAG_BITS-1:0]       mem2ic_tag_o,
    output [`ICACHE_INDEX_BITS-1:0]     mem2ic_index_o,
    output [`ICACHE_BITS_IN_LINE-1:0]   mem2ic_data_o,
    output reg                          mem2ic_respvalid_o,

    input                               dc2mem_ldvalid_i,
    output [`DCACHE_TAG_BITS-1:0]       mem2dc_ldtag_o,
    output [`DCACHE_INDEX_BITS-1:0]     mem2dc_ldindex_o,
    output [`DCACHE_BITS_IN_LINE-1:0]   mem2dc_lddata_o,
    output reg                          mem2dc_ldvalid_o,

    output                              mem2dc_invvalid_o,
    output [`DCACHE_INDEX_BITS-1:0]     mem2dc_invindex_o,
    output [0:0]                        mem2dc_invway_o,

    output                              mem2ic_invvalid_o,
    output [`ICACHE_INDEX_BITS-1:0]     mem2ic_invindex_o,
    output [`ICACHE_NUM_WAYS_LOG-1:0]                        mem2ic_invway_o,

    input                               dc2mem_stvalid_i,
    output reg                          mem2dc_stcomplete_o,
    output                              mem2dc_ststall_o,

    output reg                          anycore_int_o

);

reg current_val;
reg prev_val;
reg header_ack_seen_next;
reg header_ack_seen_reg;

// Get full address that's 64 bits long since it's otherwise to icache
// block alignment
wire [63:0] anycore_imiss_full_addr = ic2mem_reqaddr_i << (64-`ICACHE_BLOCK_ADDR_BITS);
//CHANGES
//wire [1:0] anycore_imiss_way = ic2mem_reqaddr_i[`ICACHE_INDEX_BITS-1:`ICACHE_INDEX_BITS-2-1];
wire [`ICACHE_NUM_WAYS_LOG-1:0] anycore_imiss_way = ic2memReqWay_o;
// Sign extend to 64 bits
//wire [63:0] anycore_store_full_addr = {{((64-`DCACHE_ST_ADDR_BITS)-3){dc2mem_staddr_i[`DCACHE_ST_ADDR_BITS-1]}}, (dc2mem_staddr_i << 3)};
wire [63:0] anycore_store_full_addr = {{((64-`DCACHE_ST_ADDR_BITS)-3){dc2mem_staddr_i[`DCACHE_ST_ADDR_BITS-1]}}, (dc2mem_staddr_i)};
wire [1:0] anycore_store_way = dc2mem_staddr_i[`DCACHE_INDEX_BITS-1:`DCACHE_INDEX_BITS-2-1];
// Sign extend to 64 bits
wire [63:0] anycore_load_full_addr = {{((64-`DCACHE_BLOCK_ADDR_BITS)-4){dc2mem_ldaddr_i[`DCACHE_BLOCK_ADDR_BITS-1]}}, (dc2mem_ldaddr_i << 4)};
wire [1:0] anycore_load_way = dc2mem_ldaddr_i[`DCACHE_INDEX_BITS-1:`DCACHE_INDEX_BITS-2-1];

wire [63:0] anycore_dc2mem_stdata_flipped = {dc2mem_stdata_i[7:0], dc2mem_stdata_i[15:8], dc2mem_stdata_i[23:16], dc2mem_stdata_i[31:24], dc2mem_stdata_i[39:32], dc2mem_stdata_i[47:40], dc2mem_stdata_i[55:48], dc2mem_stdata_i[63:56]};
//wire [63:0] anycore_dc2mem_stdata_flipped = dc2mem_stdata_i;

// Status of different requests
localparam IDLE = 2'd0;
localparam ARRIVE = 2'd1;
localparam ISSUE = 2'd2;

// "next" is wire
reg [1:0] decoder_store_reg;
reg [1:0] decoder_store_next;
reg [63:0]    			  anycore_store_full_addr_buf;
reg [63:0]    			  anycore_store_full_addr_buf_next;
reg [`SIZE_DATA-1:0]              anycore_dc2mem_stdata_flipped_buf;
reg [`SIZE_DATA-1:0]              anycore_dc2mem_stdata_flipped_buf_next;
reg [2:0]                         anycore_dc2mem_stsize_buf;
reg [2:0]                         anycore_dc2mem_stsize_buf_next;

reg [1:0] decoder_load_reg;
reg [1:0] decoder_load_next;
reg [63:0] 			  anycore_load_full_addr_buf;
reg [63:0] 			  anycore_load_full_addr_buf_next;

reg [1:0] imiss_reg;
reg [1:0] imiss_next;
reg [63:0] 			  anycore_imiss_full_addr_buf;
reg [63:0] 			  anycore_imiss_full_addr_buf_next;

reg  [`PHY_ADDR_WIDTH-1:0] transducer_l15_address_next;
reg  [63:0] transducer_l15_data_next;
reg  [4:0]  transducer_l15_rqtype_next;
reg  [2:0]  transducer_l15_size_next;

// internal states
always @ (posedge clk) begin
    if (!rst_n) begin
        decoder_store_reg <= IDLE;
        decoder_load_reg <= IDLE;
        imiss_reg <= IDLE;
        header_ack_seen_reg <= 1'b0;
        anycore_store_full_addr_buf <= 64'b0;
        anycore_dc2mem_stdata_flipped_buf   <= {`SIZE_DATA{1'b0}};
        anycore_dc2mem_stsize_buf   <= 3'b0;
        anycore_load_full_addr_buf  <= 64'b0;
        anycore_imiss_full_addr_buf  <= 64'b0;
    end
    else begin
        decoder_store_reg <= decoder_store_next;
        decoder_load_reg <= decoder_load_next;
        imiss_reg <= imiss_next;
        header_ack_seen_reg <= header_ack_seen_next;
        anycore_store_full_addr_buf <= anycore_store_full_addr_buf_next;
        anycore_dc2mem_stdata_flipped_buf   <= anycore_dc2mem_stdata_flipped_buf_next;
        anycore_dc2mem_stsize_buf   <= anycore_dc2mem_stsize_buf_next;
        anycore_load_full_addr_buf  <= anycore_load_full_addr_buf_next;
        anycore_imiss_full_addr_buf  <= anycore_imiss_full_addr_buf_next;
    end
end

always @ * begin
    decoder_store_next = decoder_store_reg;
    decoder_load_next = decoder_load_reg;
    imiss_next = imiss_reg;
    header_ack_seen_next = header_ack_seen_reg;
    anycore_store_full_addr_buf_next = anycore_store_full_addr_buf;
    anycore_dc2mem_stdata_flipped_buf_next   = anycore_dc2mem_stdata_flipped_buf;
    anycore_dc2mem_stsize_buf_next   = anycore_dc2mem_stsize_buf;
    anycore_load_full_addr_buf_next  = anycore_load_full_addr_buf;
    anycore_imiss_full_addr_buf_next  = anycore_imiss_full_addr_buf;
    // L15 gets a request
    if (l15_transducer_ack_i) begin
        decoder_store_next = (decoder_store_reg == ISSUE) ? IDLE : decoder_store_reg;
        decoder_load_next = (decoder_load_reg == ISSUE) ? IDLE: decoder_load_reg;
        imiss_next = (imiss_reg == ISSUE) ? IDLE: imiss_reg;
        header_ack_seen_next = 1'b0;
    end
    else if (l15_transducer_header_ack_i) begin
        header_ack_seen_next = 1'b1;
    end
    // New requests arrive
    if (dc2mem_stvalid_i) begin
        decoder_store_next = ARRIVE;
	anycore_store_full_addr_buf_next = anycore_store_full_addr;
        anycore_dc2mem_stdata_flipped_buf_next   = anycore_dc2mem_stdata_flipped;
        anycore_dc2mem_stsize_buf_next   = dc2mem_stsize_i;
    end
    if (dc2mem_ldvalid_i) begin
        decoder_load_next = ARRIVE;
        anycore_load_full_addr_buf_next  = anycore_load_full_addr;
    end
    if (ic2mem_reqvalid_i) begin
        imiss_next = ARRIVE;
        anycore_imiss_full_addr_buf_next  = anycore_imiss_full_addr;
    end
    // Issue and deal with arrive at the same time
    // Imiss > Load > Store
    if (imiss_next == ARRIVE) begin
        imiss_next = ((decoder_store_reg != ISSUE) && (decoder_load_reg != ISSUE)) ? ISSUE : ARRIVE;
    end
    else begin
	if (decoder_load_next == ARRIVE) begin
            decoder_load_next = ((decoder_store_reg != ISSUE) && (imiss_reg != ISSUE)) ? ISSUE : ARRIVE;
	end
	else begin
	    if (decoder_store_next == ARRIVE) begin
                decoder_store_next = ((decoder_load_reg != ISSUE) && (imiss_reg != ISSUE)) ? ISSUE : ARRIVE;
	    end
	end
    end

    // set rqtype specific data
    if (imiss_next == ISSUE) begin
        // ifill operation
        // need bypass if reg == IDLE
        transducer_l15_address_next = (imiss_reg == IDLE) ? anycore_imiss_full_addr_buf_next[`PHY_ADDR_WIDTH-1:0]
							      : anycore_imiss_full_addr_buf[`PHY_ADDR_WIDTH-1:0];
        transducer_l15_data_next = 64'b0;
        transducer_l15_rqtype_next = `IMISS_RQ;
        transducer_l15_size_next = `PCX_SZ_4B;
        transducer_l15_l1rplway_o = anycore_imiss_way;
    end
    else if (decoder_load_next == ISSUE) begin
        transducer_l15_address_next = (decoder_load_reg == IDLE) ? anycore_load_full_addr_buf_next[`PHY_ADDR_WIDTH-1:0]
							     : anycore_load_full_addr_buf[`PHY_ADDR_WIDTH-1:0];
        transducer_l15_data_next = 64'b0;
        transducer_l15_rqtype_next = `LOAD_RQ;
        transducer_l15_size_next = `PCX_SZ_16B;
        transducer_l15_l1rplway_o = anycore_load_way;
    end
    else if(decoder_store_next == ISSUE) begin
        transducer_l15_address_next = (decoder_store_reg == IDLE) ? anycore_store_full_addr_buf_next[`PHY_ADDR_WIDTH-1:0]
							      : anycore_store_full_addr_buf[`PHY_ADDR_WIDTH-1:0];
        transducer_l15_data_next = (decoder_store_reg == IDLE) ? anycore_dc2mem_stdata_flipped_buf_next  //anycore_dc2mem_stdata;
							   : anycore_dc2mem_stdata_flipped_buf;
        transducer_l15_rqtype_next = `STORE_RQ;
        transducer_l15_size_next = (decoder_store_reg == IDLE) ? anycore_dc2mem_stsize_buf_next
							   : anycore_dc2mem_stsize_buf;
        transducer_l15_l1rplway_o = anycore_store_way;
    end
    else  begin
        transducer_l15_address_next = `PHY_ADDR_WIDTH'b0;
        transducer_l15_data_next = 64'b0;
        transducer_l15_rqtype_next = 5'b0;
        transducer_l15_size_next = 3'b0;
        transducer_l15_l1rplway_o = 2'b0;
    end


end

// outputs
always @ (posedge clk)
begin
    if (!rst_n) begin
        current_val <= 0;
        prev_val <= 0;
        transducer_l15_val_o <= 1'b0;
        transducer_l15_address_o <= `PHY_ADDR_WIDTH'b0;
        transducer_l15_data_o <= 64'b0;
        transducer_l15_rqtype_o <= 5'b0;
        transducer_l15_size_o <= 3'b0;
    end
    else begin
        current_val <= ic2mem_reqvalid_i | dc2mem_stvalid_i | dc2mem_ldvalid_i;
        prev_val <= current_val;
        transducer_l15_val_o <= ((imiss_next == ISSUE) | (decoder_load_next == ISSUE) | (decoder_store_next == ISSUE)) & ~header_ack_seen_next;
	//ic2mem_reqvalid_i | dc2mem_ldvalid_i | dc2mem_stvalid_i | decoder_store_next;//dc2mem_stvalid_i | dc2mem_ldvalid_i | decoder_store_reg;// | decoder_load_reg;
        transducer_l15_address_o <= transducer_l15_address_next;
        transducer_l15_data_o <= transducer_l15_data_next;
        transducer_l15_rqtype_o <= transducer_l15_rqtype_next;
        transducer_l15_size_o <= transducer_l15_size_next;
    end
end

// unused wires tie to zero
assign transducer_l15_threadid_o = 1'b0;
assign transducer_l15_prefetch_o = 1'b0;
assign transducer_l15_csm_data_o = 33'b0;
assign transducer_l15_data_next_entry_o = 64'b0;

assign transducer_l15_blockstore_o = 1'b0;
assign transducer_l15_blockinitstore_o = 1'b0;
// will anycore ever need to invalidate cachelines?
assign transducer_l15_invalidate_cacheline_o = 1'b0;

//assign transducer_l15_val_o = current_val && !prev_val;
//assign transducer_l15_val_o = ic2mem_reqvalid_i | dc2mem_stvalid_i | decoder_store_reg;

assign transducer_l15_nc_o = transducer_l15_address_o[`PHY_ADDR_WIDTH-1];

//`define STATE_NORMAL 1'b0
//`define STATE_SECONDHALF 1'b1
//
localparam STORE_IDLE = 1'b0;
localparam STORE_ACTIVE = 1'b1;
localparam LOAD_IDLE = 1'b0;
localparam LOAD_ACTIVE = 1'b1;

//reg state;
//reg state_next;

reg encoder_store_reg;
reg encoder_store_next;

reg encoder_load_reg;
reg encoder_load_next;

reg dinvalrst_reg;
reg dinvalrst_next;
reg iinvalrst_reg;
reg iinvalrst_next;

reg signal_dcache_inval;
reg signal_icache_inval;

wire [63:0] l15_transducer_address_sext;
wire [63:0] l15_transducer_address_zext;

wire [63:0] l15_transducer_data_0_swap = {l15_transducer_data_0_i[7:0], l15_transducer_data_0_i[15:8], l15_transducer_data_0_i[23:16], l15_transducer_data_0_i[31:24], l15_transducer_data_0_i[39:32], l15_transducer_data_0_i[47:40], l15_transducer_data_0_i[55:48], l15_transducer_data_0_i[63:56]};
wire [63:0] l15_transducer_data_1_swap = {l15_transducer_data_1_i[7:0], l15_transducer_data_1_i[15:8], l15_transducer_data_1_i[23:16], l15_transducer_data_1_i[31:24], l15_transducer_data_1_i[39:32], l15_transducer_data_1_i[47:40], l15_transducer_data_1_i[55:48], l15_transducer_data_1_i[63:56]};
wire [63:0] l15_transducer_data_2_swap = {l15_transducer_data_2_i[7:0], l15_transducer_data_2_i[15:8], l15_transducer_data_2_i[23:16], l15_transducer_data_2_i[31:24], l15_transducer_data_2_i[39:32], l15_transducer_data_2_i[47:40], l15_transducer_data_2_i[55:48], l15_transducer_data_2_i[63:56]};
wire [63:0] l15_transducer_data_3_swap = {l15_transducer_data_3_i[7:0], l15_transducer_data_3_i[15:8], l15_transducer_data_3_i[23:16], l15_transducer_data_3_i[31:24], l15_transducer_data_3_i[39:32], l15_transducer_data_3_i[47:40], l15_transducer_data_3_i[55:48], l15_transducer_data_3_i[63:56]};

//always @ (posedge clk) begin
//    if (!rst_n) begin
//        state <= `STATE_NORMAL;
//    end
//    else begin
//        state <= state_next;
//    end
//end

always @ (posedge clk) begin
    if (!rst_n) begin
        encoder_store_reg <= STORE_IDLE;
        encoder_load_reg <= LOAD_IDLE;
        dinvalrst_reg <= 1'b0;
        iinvalrst_reg <= 1'b0;
    end
    else begin
        encoder_store_reg <= encoder_store_next;
        encoder_load_reg <= encoder_load_next;
        dinvalrst_reg <= dinvalrst_next;
        iinvalrst_reg <= iinvalrst_next;
    end
end

assign mem2dc_ststall_o = (encoder_store_reg == STORE_ACTIVE) | dc2mem_stvalid_i;

assign l15_transducer_address_sext = {{24{l15_transducer_address_i[`PHY_ADDR_WIDTH-1]}}, l15_transducer_address_i};
assign l15_transducer_address_zext = {{24{1'b0}}, l15_transducer_address_i};
assign transducer_l15_req_ack_o = l15_transducer_val_i;

assign mem2ic_tag_o = l15_transducer_address_zext[63:64-`ICACHE_TAG_BITS];
assign mem2ic_index_o = l15_transducer_address_zext[64-`ICACHE_TAG_BITS-1:64-`ICACHE_TAG_BITS-`ICACHE_INDEX_BITS];
assign mem2ic_data_o[`ICACHE_BITS_IN_LINE-1:0] = {l15_transducer_data_3_swap, l15_transducer_data_2_swap, l15_transducer_data_1_swap, l15_transducer_data_0_swap};

assign mem2dc_ldtag_o = l15_transducer_address_zext[63:64-`DCACHE_TAG_BITS];
assign mem2dc_ldindex_o = l15_transducer_address_zext[64-`DCACHE_TAG_BITS-1:64-`DCACHE_TAG_BITS-`DCACHE_INDEX_BITS];
//assign mem2dc_lddata_o[`DCACHE_BITS_IN_LINE-1:0] = {{l15_transducer_data_3_swap, l15_transducer_data_2_swap, l15_transducer_data_1_swap, l15_transducer_data_0_swap}, {l15_transducer_data_3_swap, l15_transducer_data_2_swap, l15_transducer_data_1_swap, l15_transducer_data_0_swap}};
//assign mem2dc_lddata_o[`DCACHE_BITS_IN_LINE-1:0] = {l15_transducer_data_3_swap, l15_transducer_data_2_swap, l15_transducer_data_1_swap, l15_transducer_data_0_swap};
assign mem2dc_lddata_o[`DCACHE_BITS_IN_LINE-1:0] = {l15_transducer_data_1_swap, l15_transducer_data_0_swap};

// keep track of whether we have received the wakeup interrupt
reg int_recv;
always @ (posedge clk) begin
    if (!rst_n) begin
        anycore_int_o <= 1'b0;
    end
    else if (int_recv) begin
        anycore_int_o <= 1'b1;
    end
    else if (anycore_int_o) begin
        anycore_int_o <= 1'b0;
    end
end

always @ * begin
    encoder_store_next = encoder_store_reg;
    encoder_load_next = encoder_load_reg;
    dinvalrst_next = 1'b0;
    //iinvalrst_next = 1'b0;
    if (dc2mem_stvalid_i) begin
        encoder_store_next = STORE_ACTIVE;
    end
    if (mem2dc_stcomplete_o) begin
        encoder_store_next = STORE_IDLE;
    end
    if (dc2mem_ldvalid_i) begin
        encoder_load_next = LOAD_ACTIVE;
    end
    if (mem2dc_ldvalid_o) begin
        encoder_load_next = LOAD_IDLE;
    end
    if (mem2dc_invvalid_o) begin
        dinvalrst_next = 1'b1;
    end
    if (mem2ic_invvalid_o) begin
        iinvalrst_next = 1'b1;
    end
end

assign mem2dc_invvalid_o = signal_dcache_inval & ~dinvalrst_reg;
assign mem2ic_invvalid_o = signal_icache_inval & ~iinvalrst_reg;
//CHANGES
assign mem2dc_invway_o = l15_transducer_inval_way_i;
//assign mem2dc_invway_o = ic2memReqWay_o;
//assign mem2dc_invway_o = mem2icInvWay_i;
assign mem2dc_invindex_o = l15_transducer_inval_address_15_4_i[`DCACHE_INDEX_BITS+4-1:4];
//assign mem2ic_invway_o = 1; //l15_transducer_inval_way_i;
assign mem2ic_invway_o = ic2memReqWay_o;
//assign mem2ic_invway_o = mem2icInvWay_i;
assign mem2ic_invindex_o = l15_transducer_inval_address_15_4_i[`DCACHE_INDEX_BITS+4-1:4];

always @ * begin
    //state_next = `STATE_NORMAL;
    mem2ic_respvalid_o = 1'b0;
    mem2dc_stcomplete_o = 1'b0;
    mem2dc_ldvalid_o = 1'b0;
    signal_dcache_inval = 1'b0;
    signal_icache_inval = 1'b0;
    int_recv = 1'b0;
    if (l15_transducer_val_i) begin
        case(l15_transducer_returntype_i)
        `INT_RET: begin
            int_recv = 1'b1;
        end
        `IFILL_RET: begin
            mem2ic_respvalid_o = 1'b1;
        end
        `ST_ACK: begin
            mem2dc_stcomplete_o = 1'b1;
            //TODO: st_ack can have an invalidation
            signal_dcache_inval = l15_transducer_inval_dcache_inval_i;
            signal_icache_inval = l15_transducer_inval_icache_inval_i;
        end
        `LOAD_RET: begin
            mem2dc_ldvalid_o = 1'b1;
        end
        `EVICT_REQ: begin
            signal_dcache_inval = l15_transducer_inval_dcache_inval_i;
            signal_icache_inval = l15_transducer_inval_icache_inval_i;
        end
        default: begin
            int_recv = 1'b0;
        end
        endcase
    end
end

`ifdef SIM
always @(posedge clk) begin
    if (mem2ic_respvalid_o) begin
        $display("anycore_mem2ic_data: %h", mem2ic_data_o);
        $display("l15_transducer_data_3: %h", l15_transducer_data_3_i);
        $display("l15_transducer_data_2: %h", l15_transducer_data_2_i);
        $display("l15_transducer_data_1: %h", l15_transducer_data_1_i);
        $display("l15_transducer_data_0: %h", l15_transducer_data_0_i);
    end
end
`endif

endmodule

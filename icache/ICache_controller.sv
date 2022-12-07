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

/*
questions
1) Where would the MSHR in the diagram provided from the CS154 s22 slides?
2) What exactly is scratch mode? I think it is A temporary location in memory that allows for something to be saved, what is its purpose however?
  mode to not use it as cache but just use it as memory. Benefit for embedded class applications to access it in 1 cycle
3) Don't completely understand what the assign part is doing in terms of syntax around line 128-130 
4) What are all the MSHR miss signals and what do they do? (like missd1, missd2, miss pulse)
5) can you explain a little bit about what's going on in lines 213 to 280
6) Don't really understand the declaration in line 353-355
7) what is the assign BIST parts in lines 406-409
8) 
*/

/*
CHANGES I'VE MADE SO FAR IN THE CODE

1) I've changed the size of ICACHE_NUM_LINES and ICACHE_NUM_LINES_LOG to be 4 times smaller.
This is because the amount of tags will now quadruple and ICACHE_TAG_BITS depends on the size of
ICACHE_NUM_LINES.
2) quadrupled the amount of data_array, valid_array, and tag_array
3) also duplicated the cache_data, cache_tag, cache_valid, we will need to add a replacement policy
to figure out what to evict from each subcache
*/

`timescale 1ns/100ps


module ICache_controller#(
    parameter FETCH_WIDTH = `FETCH_WIDTH
) (

    // processor/cache interface
    input                               fetchReq_i,
    input  [`SIZE_PC-1:0]               pc_i,
    output [`SIZE_INSTRUCTION-1:0]      inst_o      [0:FETCH_WIDTH-1],
    output [0:FETCH_WIDTH-1]            instValid_o,

  `ifdef INST_CACHE
    // cache-to-memory interface
    output [`ICACHE_BLOCK_ADDR_BITS-1:0]  ic2memReqAddr_o,  // memory read address
    output reg                            ic2memReqValid_o, // memory read enable

    //wire this into the tri transducer
    //that value comes from roundRobin logic
    //tri transducer line 101, replace with ic2memReqWay after adding to module
    output logic [`ICACHE_NUM_WAYS_LOG-1:0]  ic2memReqWay_o,  // memory way

    // memory-to-cache interface
    input  [`ICACHE_TAG_BITS-1:0]       mem2icTag_i,       // tag of the incoming datadetermine
    input  [`ICACHE_INDEX_BITS-1:0]     mem2icIndex_i,     // index of the incoming data

    input  [`ICACHE_BITS_IN_LINE-1:0]      mem2icData_i,      // requested data
    input                               mem2icRespValid_i, // indicates the requested data is ready

    input                               mem2icInv_i,     // icache invalidation
    input  [`ICACHE_INDEX_BITS-1:0]     mem2icInvInd_i,  // icache invalidation index

    //now this is supposed to be 2 bits wide
    input  [`ICACHE_NUM_WAYS_LOG-1:0]                        mem2icInvWay_i,  // icache invalidation way (unused)

    input [`ICACHE_INDEX_BITS+`ICACHE_BYTES_IN_LINE_LOG-1:0]  icScratchWrAddr_i,
    input                                                     icScratchWrEn_i,
    input [7:0]                                               icScratchWrData_i,
    output [7:0]                                              icScratchRdData_o,

    input                               icFlush_i,
    output reg                          icFlushDone_o,
  `endif

    input                               mmuException_i,
    output                              icMiss_o,

    input                               clk,
    input                               reset,
    input                               icScratchModeEn_i // Should ideally be disabled by default
);

`ifdef INST_CACHE

  // breakdown of pc bits
  // 32      24      16       8       0
  //  |-------|-------|-------|-------|
  //           ttttttttttiiiiiiiiioo
  //           ttttttttttttiiiiiiioo
  //
  // note: the tag is only 10 bits because the pc will never be higher 
  // than 32'h007fffff for CPU2000 benchmarks

  //we now want to have more tag, and less index bits so 12 tag bits and 7 index bits.
  
  
  ////////////////////////////////////////////////////////////
  // processor/cache interface ///////////////////////////////
  ////////////////////////////////////////////////////////////
  
  // SCRATCH Mode related signals - Pipelined once for better timing and fanout
  logic                                 icScratchModeEn_d1;
  logic [`ICACHE_INDEX_BITS-1:0]        icScratchWrIndex_d1;
  logic [`ICACHE_BYTES_IN_LINE_LOG-1:0] icScratchWrByte_d1;
  logic [7:0]                           icScratchWrData_d1;
  logic                                 icScratchWrEn_d1;
  logic [`ICACHE_NUM_WAYS_LOG-1:0]      RoundRobin [`ICACHE_NUM_LINES-1:0];
  logic [`ICACHE_NUM_WAYS_LOG-1:0]      lru [`ICACHE_NUM_WAYS-1:0][`ICACHE_NUM_LINES-1:0];
  int misses = 0;
  int hits = 0;

  always_ff @(posedge clk or posedge reset)
  begin
    if(reset)
    begin
      icScratchModeEn_d1   <=  1'b0;    // Default is SCRATCH mode on reset
      icScratchWrIndex_d1  <=  {`ICACHE_INDEX_BITS{1'b0}};
      icScratchWrByte_d1   <=  {`ICACHE_BYTES_IN_LINE_LOG{1'b0}};
      icScratchWrData_d1   <=  8'h0;
      icScratchWrEn_d1     <=  1'b0;
    end
    else
    begin
      icScratchModeEn_d1   <=  icScratchModeEn_i;
      icScratchWrIndex_d1  <=  icScratchWrAddr_i[`ICACHE_INDEX_BITS+`ICACHE_BYTES_IN_LINE_LOG-1:`ICACHE_BYTES_IN_LINE_LOG];
      icScratchWrByte_d1   <=  icScratchWrAddr_i[`ICACHE_BYTES_IN_LINE_LOG-1:0];
      icScratchWrData_d1   <=  icScratchWrData_i;
      icScratchWrEn_d1     <=  icScratchWrEn_i;
     end
  end
   

  // pc segments /////////////////////////////////////////////
  //PROBABLY NEED TO MODIFY THE SIZE OF THIS WITH THE MACROS
  //logic [`SIZE_PC-1:0]               pc_i4;
  logic [`ICACHE_OFFSET_BITS-1:0]    pc_offset;
  logic [`ICACHE_INDEX_BITS-1:0]     pc_index;
  logic [`ICACHE_TAG_BITS-1:0]       pc_tag;
  logic [`ICACHE_OFFSET_BITS-1:0]    pc_offset_reg;
  logic [`ICACHE_INDEX_BITS-1:0]     pc_index_reg;
  logic [`ICACHE_TAG_BITS-1:0]       pc_tag_reg;
  logic                              fetchReq_reg;
  
  // the unregistered index is for reading the tag/data array
  //DONT REALLY UNDERSTAND THIS PART --> DONT NEED TO WORRY ABOUT THIS
  //indexing into the vector to pull certain number of bits, will follow if you modify the macros
  //assign pc_i4                    = pc_i + 5'b10000;
  assign pc_offset                = pc_i[`ICACHE_OFFSET_BITS+`ICACHE_INST_BYTE_OFFSET_LOG-1 : `ICACHE_INST_BYTE_OFFSET_LOG];
  assign pc_index                 = pc_i[`ICACHE_OFFSET_BITS+`ICACHE_INDEX_BITS+`ICACHE_INST_BYTE_OFFSET_LOG-1 : `ICACHE_OFFSET_BITS+`ICACHE_INST_BYTE_OFFSET_LOG];
  assign pc_tag                   = pc_i[`SIZE_PC-1 : `ICACHE_OFFSET_BITS+`ICACHE_INDEX_BITS+`ICACHE_INST_BYTE_OFFSET_LOG];
  
  // the registered signals are for miss handling
  always_ff @(posedge clk)
  begin
    pc_tag_reg              <= pc_tag;
    pc_index_reg            <= pc_index;
    pc_offset_reg           <= pc_offset;
    fetchReq_reg            <= fetchReq_i;
  end
  
  // tag, valid and data read from cache /////////////////////
  //PROBABLY NEED TO MODIFY THE SIZE OF THIS
  logic [`ICACHE_TAG_BITS-1:0]    cache_tag [`ICACHE_NUM_WAYS-1:0];
  logic [`ICACHE_BITS_IN_LINE-1:0]   cache_data [`ICACHE_NUM_WAYS-1:0];
  logic                           cache_valid [`ICACHE_NUM_WAYS-1:0];

  // hit detection logic. hits are detected the cycle after fetchReq_i goes high.
  // hit can stay high for multiple cycles if no new request comes (e.g. fetch
  // stalls)
  logic   [0:`FETCH_WIDTH-1]      instValid;
  logic   [`SIZE_INSTRUCTION-1:0] inst [0:`FETCH_WIDTH-1];

  logic [`ICACHE_NUM_WAYS-1:0]   hit;       
  logic                           totalHit;
  
  
  assign inst_o = inst;
  assign instValid_o = instValid;
  
  ///////////////////////////////////////////////
  // MSHR / FILL  Logic /////////////////////
  ///////////////////////////////////////////////
  
  logic                             fillValid;
  logic   [`ICACHE_OFFSET_BITS-1:0] fillOffset;
  logic   [`ICACHE_INDEX_BITS-1:0]  fillIndex;
  logic   [`ICACHE_TAG_BITS-1:0]    fillTag;
  logic   [`ICACHE_BITS_IN_LINE-1:0]   fillData;
  
  // MHSR 0 
  logic                             mshr0Valid;
  logic   [`ICACHE_OFFSET_BITS-1:0] mshr0Offset;
  logic   [`ICACHE_INDEX_BITS-1:0]  mshr0Index;
  logic   [`ICACHE_TAG_BITS-1:0]    mshr0Tag;
  
  // Misc signals
  logic                             miss;
  logic                             miss_d1;
  logic                             miss_d2;
  logic                             miss_pulse;
  logic                             missUnderMiss;
  
  assign miss = ~totalHit;

  assign icMiss_o = ic2memReqValid_o;
  
  always_ff @(posedge clk or posedge reset)
  begin
    if(reset)
    begin
      miss_d1 <= 1'b0;
      miss_d2 <= 1'b0;
    end
    else
    begin
      // Clear on a fillValid so that a pulse is generated for a pending miss
      miss_d1 <= miss & fetchReq_i & ~fillValid;
      miss_d2 <= miss_d1 & ~fillValid;
    end
  end

  //new roundRobin logic here, we want to do roundRobin for each cache line as well, not just the cache block  
  always_ff @(posedge clk)
  begin
    if (reset) 
    begin
      int i;
      int j;
      for (i = 0; i < `ICACHE_NUM_LINES; i++) 
      begin
        RoundRobin[i] <= '0;
        for (j = 0; j < `ICACHE_NUM_WAYS; j++)
        begin
          lru[j][i] = j;
        end
      end
    end 
    //in case of a miss, should we just implement this by 1 as well so instead of lru[0][pc_index] we have something else?
    else if (miss) 
    begin
        int i;
        int x;
        misses <= misses + 1;
        $display("MISSES: %d", misses);
        RoundRobin[pc_index] <= RoundRobin[pc_index] + 1'b1;
        //need to check if there is a fill valid or else we cannot actually 
        //add anything to the cache
        //find which one of the ways is the one being invalidated
        for (i = 0; i < `ICACHE_NUM_WAYS; i++)
        begin
          if (lru[i][pc_index] == mem2icInvWay_i)
          begin
            x = i;
            break;
          end
        end
        //now do the same process of moving it to the the most recently used
        //this is because whatever was in it was evicted and the newest entry 
        //being put in now counts as the most recently used
        for (i = x; i < `ICACHE_NUM_WAYS - 1; i++)
        begin
          //$display("lru");
          lru[i][pc_index] = lru[i+1][pc_index];
        end
        lru[`ICACHE_NUM_WAYS - 1][pc_index] = mem2icInvWay_i;
        // for (i = 0; i < `ICACHE_NUM_WAYS; i++)
        // begin
        //   $display("lru: %d", lru[i][pc_index]);
        // end
    end
    else if (totalHit) 
    begin
      int i;
      int hitnum;
      int x;
      hits <= hits + 1;
      $display("HITS: %d", hits);
      //figure out which way there was a hit in the first place
      //this is to figure out which way in the lru do we need to move to most recently used
      for (hitnum = 0; hitnum < `ICACHE_NUM_WAYS; hitnum++)
      begin
        if(hit[hitnum])
        begin
          i = hitnum;
          break;
        end
      end
      //$display("value of i: %d", i);
      //$display("value of hitnum: %d", hitnum);
      //need to figure out where in the lru is that hit way
      //because it could have been moved around
      for (i = 0; i < `ICACHE_NUM_WAYS; i++)
      begin
        if (lru[i][pc_index] == hitnum)
        begin
          x = i;
          break;
        end
      end
      //now we have to shift all elements down and add the way to the end
      //which counts as it being the most recently used
      //on the way out, the way at lru[0] which is the least recently used will be the
      //one that will be evicted and replaced.
      for (i = x; i < `ICACHE_NUM_WAYS - 1; i++)
      begin
        //$display("lru");
        lru[i][pc_index] = lru[i+1][pc_index];
      end
      lru[`ICACHE_NUM_WAYS - 1][pc_index] = hitnum;
      // for (i = 0; i < `ICACHE_NUM_WAYS; i++)
      // begin
      //   $display("lru: %d", lru[i][pc_index]);
      // end
    end
  end

  assign miss_pulse = miss_d1 & ~miss_d2;
  //assign miss_pulse = fetchReq_i & miss & ~miss_d1;
  
  // send a request the cycle after fetchReq_i goes high is hit is low.
  assign ic2memReqAddr_o        = {pc_tag_reg, pc_index_reg};
  // 1) Load only once per read miss and only one miss at a time.
  // 2) Load only is MSHR is not already locked up 
  //    OR a previous miss is completing in this cycle, which makes the MSHR free
  // 3) If MSHR is not free, let the reader replay the read.
  assign ic2memReqValid_o       = miss_pulse & (~mshr0Valid | fillValid); 
  
  
  /* The following block currently implements a single MSHR.
     It can be easily extended to support a fully associative
     file of MSHRs */
  always_ff @(posedge clk or posedge reset)
  begin
    if(reset)
    begin
      fillValid <= 1'b0;
      fillIndex <= {`ICACHE_INDEX_BITS{1'b0}};
      fillTag   <= {`ICACHE_TAG_BITS{1'b0}};
    end
    else
    begin
      //NOTE: SCRATCH MODE
      // Pull fillValid low when in scratch mode.
      fillValid <= ~icScratchModeEn_d1 & (mem2icRespValid_i & mshr0Valid & (mshr0Index == mem2icIndex_i) & (mshr0Tag == mem2icTag_i));
      fillIndex <= mshr0Index;
      fillTag   <= mshr0Tag;
      
      fillData  <= mem2icData_i;
    end
  end
  
  always_ff @(posedge clk or posedge reset)
  begin
    if(reset)
    begin
      missUnderMiss <= 1'b0;
      mshr0Valid <= 1'b0;
      mshr0Index <= 9'b0;
      mshr0Offset<= 3'b0;
      mshr0Tag   <= 10'b0;
    end
    else
    begin
      // Clear on fill valid and set on L2 read request
      case({fillValid,miss_pulse})
        2'b00: begin
          missUnderMiss <= missUnderMiss;
          mshr0Valid <= mshr0Valid;
        end
        2'b01: begin 
          mshr0Valid <= 1'b1; 
          if(mshr0Valid) 
            missUnderMiss <= 1'b1;
          else // if not already handling a miss, record the address
          begin
            mshr0Index  <= pc_index_reg;
            mshr0Offset <= pc_offset_reg;
            mshr0Tag    <= pc_tag_reg;
          end
        end
        2'b10: begin
          missUnderMiss <= 1'b0;
          mshr0Valid <= 1'b0;
        end
        2'b11: begin // If completing a miss handling in the same cycle
          missUnderMiss <= 1'b0;
          mshr0Valid  <= 1'b1;
          mshr0Index  <= pc_index_reg;
          mshr0Offset <= pc_offset_reg;
          mshr0Tag    <= pc_tag_reg;
        end
        default: begin
          missUnderMiss <= 1'b0;
          mshr0Valid  <= mshr0Valid;
          mshr0Index  <= mshr0Index;
          mshr0Offset <= mshr0Offset; 
          mshr0Tag    <= mshr0Tag; 
        end
      endcase
    end
  end
  
  
  ////////////////////////////////////////////////////////////
  
  //can probably ignore this part for the purposes of this project or double check the config
  always_comb
  begin
      int i;
      for (i = 0; i < `FETCH_WIDTH; i++)
          instValid[i]          = 1'b0;
  
      if (totalHit)
      begin
        instValid[0]  = 1'b1;  // First slot is always valid irrespective of the offset
  
        `ifdef FETCH_TWO_WIDE
          // Second slot is valid when pc is less than the total number of slots
          if(pc_offset < `ICACHE_INSTS_IN_LINE-1)
            instValid[1] = 1'b1;
        `endif
  
        `ifdef FETCH_THREE_WIDE
          if(pc_offset < `ICACHE_INSTS_IN_LINE-2)
            instValid[2] = 1'b1;
        `endif
  
        `ifdef FETCH_FOUR_WIDE
          if(pc_offset < `ICACHE_INSTS_IN_LINE-3)
            instValid[3] = 1'b1;
        `endif
  
        `ifdef FETCH_FIVE_WIDE
          if(pc_offset < `ICACHE_INSTS_IN_LINE-4)
            instValid[4] = 1'b1;
        `endif
  
        `ifdef FETCH_SIX_WIDE
          if(pc_offset < `ICACHE_INSTS_IN_LINE-5)
            instValid[5] = 1'b1;
        `endif
  
        `ifdef FETCH_SEVEN_WIDE
          if(pc_offset < `ICACHE_INSTS_IN_LINE-6)
            instValid[6] = 1'b1;
        `endif
  
        `ifdef FETCH_EIGHT_WIDE
          if(pc_offset < `ICACHE_INSTS_IN_LINE-7)
            instValid[7] = 1'b1;
        `endif
  
      end
  end
  
  //DO WE NEED TO MODIFY THE SIZE OF THIS AS WELL?
  logic [(2*`ICACHE_BITS_IN_LINE)-1 : 0] cache_data_extended [`ICACHE_NUM_WAYS-1:0];
  // extract the instruction from the cache block
  always_comb
  begin
    int i;
    for(i = 0; i < `ICACHE_NUM_WAYS; i++)
    begin
      cache_data_extended[i] = {{`ICACHE_BITS_IN_LINE{1'b0}},cache_data[i]};
    end

    for(i = 0;i < `FETCH_WIDTH;i++)
    begin
      //Instructions going to the pipeline is still 64 bit but in the cache, its 40 bits. Padding with 0s.
      int j;
      for(j = 0; j < `ICACHE_NUM_WAYS; j++)
      begin
        if (hit[j])
        begin
          inst[i] = {24'b0,cache_data_extended[j][((pc_offset+i)*`SIZE_INSTRUCTION)+`SIZE_INSTRUCTION-1 -: `SIZE_INSTRUCTION]};
          break;
        end
      end
    end
  end
  
  
  /* Cache data and tag arrays */ 
  //this is what we duplicate to add associativity
  //start here make everything 0-3
  logic [`ICACHE_BITS_IN_LINE-1:0]                       data_array [`ICACHE_NUM_WAYS-1:0] [`ICACHE_NUM_LINES-1:0];
  logic [(`ICACHE_TAG_BITS*`ICACHE_INSTS_IN_LINE)-1:0] tag_array [`ICACHE_NUM_WAYS-1:0] [`ICACHE_NUM_LINES-1:0];
  logic [`ICACHE_NUM_LINES-1:0]                       valid_array [`ICACHE_NUM_WAYS-1:0];
  
  //look into if how we're implementing round robin here is correct/ works and doesn't break the code
  
  //duplicate as well and then use cache replacement policy to figure out which ones to extract from 0-3
  //do we also need to duplicate the pc_index or is that fine?
  //NEED TO ADD CACHE REPLACEMENT POLICY LET'S START WITH ROUND ROBIN
   
  always_comb
  begin
      int i;
      ic2memReqWay_o = RoundRobin[pc_index];
      //should this be the hit way instead? as in the way that is the least recently used up next?
      //we probably need the actual value in there instead of the index?
      //don't we also care about the miss? in a miss, we need to add to the cache so if its full we
      //also need to evict a cache line?
      //ic2memReqWay_o = lru[0][pc_index];
      
      for(i = 0;i < `ICACHE_NUM_WAYS;i++)
      begin
        cache_data[i]  = data_array[i][pc_index];
        cache_tag[i]   = tag_array[i][pc_index];
        cache_valid[i] = valid_array[i][pc_index];
      end
      for(i = 0;i < `ICACHE_NUM_WAYS;i++)
      begin
        hit[i]                      = icScratchModeEn_d1 
                                        ? fetchReq_i 
                                        : ((cache_tag[i] == pc_tag) & cache_valid[i] & fetchReq_i) | mmuException_i;
      end


  end
  
  // A fetch only generates a hit if fetchReq_i is high
  // An instruction is not bypassed from fill buffer, the pipeline
  // is responsible for replaying a cache access as long as it does
  // not hit. This makes the fill pipeline simpler and also allows
  // hit under miss if need be.
  // NOTE: SCRATCH MODE
  // Always hits when in scratch mode.
  // NOTE: When not in scratch mode, force a hit if MMU indicates an exception.
  // This is to avoid incorrect fills from the next level. If we do not mask
  // the incorrect fill, garbage data can get filled in the icache and remain
  // there. Fetch will hit on this garbage data later. Eventually, the exception
  // will be handled at retirement and cause will be fixed. Fetch can happen normally
  // thereafter.

  //needs to be modified you can do like hit 0-3 and then see how it falls into place from how the hit is structured
  //for the direct cache below

  //PROBLEM WITH HIT, THEY ARE ALL 1 AT THE SAME TIME FOR SOME REASON, ONLY ONE OF THEM SHOULD HIT AT A TIME
  //you can also make this 4 bits wise and do an or reduction but this is fine as well


  //I'm assuming that we're going to need a variable to see if there was a hit in any of the 4 subcaches
  //add a mux here to find out which way the hit came from 

  assign totalHit = (hit == '0) ? 1'b0 : 1'b1;

  // Initializes the first 4 lines of the data array to the following BIST sequence.
  // This is only useful in scratch pad mode cause in cache mode, these lines are invalid.
  // The idea is to start the core in scratch pad mode after reset so that this BIST pattern
  // can run automatically and indicate successful completion by toggling an output.
  localparam INIT_REG_1    =  64'b0;//{16'h0000,`ADDI,8'h00,8'h01,16'h0000};  //  Initializes register 1 to 0 
  localparam INIT_REG_2    =  64'b0;//{16'h0000,`ADDI,8'h00,8'h02,16'h0000};  //  Initializes register 2 to 0 
  localparam INIT_REG_3    =  64'b0;//{16'h0000,`ADDI,8'h00,8'h03,16'h0004};  //  Initializes register 2 to 4 
  localparam INIT_REG_4    =  64'b0;//{16'h0000,`ADDI,8'h00,8'h04,16'h0002};  //  Initializes register 2 to 4 
  localparam ADD_INST_1    =  64'b0;//{16'h0000,`ADDI,8'h01,8'h01,16'h0005};  //  Accumulates 5 to register 1 
  localparam ADD_INST_2    =  64'b0;//{16'h0000,`ADDI,8'h02,8'h02,16'h000a};  //  Accumulates 10 to register 2
  localparam ADD_INST_3    =  64'b0;//{16'h0000,`ADDI,8'h03,8'h03,16'h0004};  //  Increments base address for loads and stores - word aligned
  localparam ADD_INST_4    =  64'b0;//{16'h0000,`ADDI,8'h04,8'h04,16'h0002};  //  Increments register 4 by 2
  localparam TOGGLE_INST_S =  64'b0;//{16'h0000,`TOGGLE_S,32'h00000000}    ;  //  Simple ALU Toggle
  localparam TOGGLE_INST_C =  64'b0;//{16'h0000,`TOGGLE_C,32'h00000000}    ;  //  Complex ALU Toggle
  localparam JUMP_INST     =  64'b0;//{16'h0000,`JUMP,32'h00000010}        ;  //  Jump to 0x00000040 and continue the loop
  localparam NOP_INST      =  64'b0;//{16'h0000,`NOP,32'h00000000}         ;  //  NOP
  localparam ST_INST       =  64'b0;//{16'h0000,`SW,8'h03,8'h04,16'h0000}  ;  //  Uses register 3 as base
  localparam LD_INST       =  64'b0;//{16'h0000,`LW,8'h03,8'h04,16'h0000}  ;  //  Uses register 3 as base

  logic [`ICACHE_BITS_IN_LINE-1:0] BIST [3:0];

  // Following microcode works both in case of 8 instruction line size and 4 instruction line size.
  // Note the JMP has been placed as the 4th instruction in the last line. The MSB 4 instructions are naturally NOPs.
  assign BIST[0]  = {NOP_INST[39:0]  ,NOP_INST[39:0]  ,NOP_INST[39:0]  ,TOGGLE_INST_S[39:0], INIT_REG_4[39:0],INIT_REG_3[39:0],INIT_REG_2[39:0],INIT_REG_1[39:0] };
  assign BIST[1]  = {ADD_INST_1[39:0],ADD_INST_2[39:0],ADD_INST_1[39:0],TOGGLE_INST_S[39:0], ADD_INST_2[39:0],ADD_INST_1[39:0],ADD_INST_2[39:0],ST_INST[39:0]    };
  assign BIST[2]  = {ADD_INST_3[39:0],ADD_INST_4[39:0],ADD_INST_2[39:0],TOGGLE_INST_C[39:0], ADD_INST_2[39:0],ADD_INST_1[39:0],LD_INST   [39:0],INIT_REG_4[39:0] };
  assign BIST[3]  = {NOP_INST  [39:0],NOP_INST  [39:0],NOP_INST  [39:0],NOP_INST[39:0]     , JUMP_INST [39:0],ADD_INST_1[39:0],ADD_INST_1[39:0],ADD_INST_2[39:0] };
  //assign BIST[0]  = {`NOP_INST  ,`ADD_INST_2,`ADD_INST_1,`TOGGLE_INST_S,`ADD_INST_2   ,`ADD_INST_1,`INIT_REG_2,`INIT_REG_1 };
  //assign BIST[1]  = {`ADD_INST_2,`ADD_INST_1,`NOP_INST  ,`TOGGLE_INST_S,`ADD_INST_1   ,`ADD_INST_2,`ADD_INST_1,`ADD_INST_2 };
  //assign BIST[2]  = {`ADD_INST_1,`NOP_INST  ,`ADD_INST_2,`TOGGLE_INST_C,`ADD_INST_2   ,`ADD_INST_1,`ADD_INST_2,`ADD_INST_1 };
  //assign BIST[3]  = {`NOP_INST  ,`NOP_INST  ,`JUMP_INST ,`ADD_INST_1   ,`TOGGLE_INST_C,`ADD_INST_2,`ADD_INST_1,`ADD_INST_2 };
  
  //modify with data array 0-3 
  //don't have to worry about the case with scratch data
  //make sure here that we have a way to keep track of what data_array and tag_array are being handled?
  //this is true for fillValid I believe, for resetting, we can just reset any cache? need to ask more details

  //chip top -> anycore TRI transducer
  //line 61 invalidate way --> tell you which way to replace so wire this out
  //line 414-415 get wired this into icache
  //line 63, change that to be 4 bits for 4 way associativity
  //top level --> anycorePiton.sv mem2icInvWay --> change the size of that as well, it is instantiated it
  //instead of roundrobin here you use mem2icinvway
  always_ff @(posedge clk or posedge reset)
  begin
    int i;
    int j;
    int x;
    //maybe change this to be <= j'b0, instead of double for-loop to make the code cleaner
    if(reset)
    begin
      for(i = 0;i < `ICACHE_NUM_WAYS;i++)
      begin
        for(j=0 ; j < `ICACHE_NUM_LINES; j++)
        begin
          data_array[i][j]          <=  '0;
        end
      end
    end
    else if(fillValid)
    begin
      data_array[mem2icInvWay_i][fillIndex]   <=  fillData;
      tag_array[mem2icInvWay_i][fillIndex]    <=  fillTag;
      //need to also redirect this information in order for it to work?
    end
    // Load scratch pad from outside
    else if(icScratchWrEn_d1 & icScratchModeEn_d1)
    begin
      data_array[0][icScratchWrIndex_d1][(icScratchWrByte_d1*8) +: 8]  <= icScratchWrData_d1; 
    end
  end
  
  // Reading the bytes through the SCRATCH interface
  assign icScratchRdData_o  = data_array[0][icScratchWrIndex_d1][(icScratchWrByte_d1*8) +: 8];

//which hit you have so will probably need to have a case here or if/else
// THIS IS WHERE ALL OF THOSE DIFFERENT HITS WILL COME INTO PLAY, RIGHT HERE
// WILL NEED TO TEST THIS WITH A REGISTER STORE/LOAD INTENSIVE PROGRAM
//make sure you always flush all of the ways (0-3) which ever cache falls under this category
  always_ff @(posedge clk or posedge reset)
  begin
    if(reset | icFlush_i)
    begin
      int i;
      int j;
      for(i = 0;i < `ICACHE_NUM_WAYS;i++)
      begin
        for(j = 0; j < `ICACHE_NUM_LINES;j++)
        begin
          valid_array[i][j]  <= 1'b0;
        end
      end
    end
    //change this to avoid the for loop.
    else if(mem2icInv_i)
    begin
      int i;
      for(i = 0;i < `ICACHE_NUM_WAYS;i++)
      begin
        if (mem2icInvWay_i == i)
        begin
          valid_array[i][fillIndex] <= 1'b0;
          break;
        end
      end
    end
    //change this to avoid the for loop.
    else if(fillValid)
    begin
      int i;
      for(i = 0;i < `ICACHE_NUM_WAYS;i++)
      begin
        if (mem2icInvWay_i == i)
        begin
          valid_array[i][fillIndex] <= 1'b1;
          break;
        end
      end
    end
  end

  always_ff @(posedge clk)
  begin
    icFlushDone_o <= icFlush_i;
  end
`endif //`ifdef INST_CACHE
endmodule
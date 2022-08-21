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


module SupRegFile (

	input                               clk,
	input                               reset,
  input                               flush_i,

  input        [`CSR_WIDTH_LOG-1:0]   regWrAddr_i,  
  input        [`CSR_WIDTH-1:0]       regWrData_i,
  input                               regWrEn_i,
  input                               commitReg_i,

  input        [`CSR_WIDTH_LOG-1:0]   regRdAddr_i,  
  input                               regRdEn_i,
  output logic [`CSR_WIDTH-1:0]       regRdData_o,

  input        [`COMMIT_WIDTH_LOG:0]  totalCommit_i,
  input                               exceptionFlag_i,
  input        [`SIZE_PC-1:0]         exceptionPC_i,
  input        [`EXCEPTION_CAUSE_LOG-1:0]  exceptionCause_i,
  input        [`SIZE_VIRT_ADDR-1:0]  stCommitAddr_i,
  input        [`SIZE_VIRT_ADDR-1:0]  ldCommitAddr_i,
  input                               sretFlag_i,
  input                               mretFlag_i,
  input        [`CSR_WIDTH-1:0]	      csr_fflags_i,

  input  [1:0]                        irq_i,      // level sensitive IR lines, mip & sip (async)
  input                               ipi_i,      // software interrupt (a.k.a inter-process-interrupt)
  input                               time_irq_i, // Timer interrupts

  input        [`CSR_WIDTH-1:0]       hartId_i, // hart id in multicore environment
  input        [`CSR_WIDTH-1:0]       startPC_i,// default PC after reset, saved at mtvec

  output logic                        atomicRdVioFlag_o,
  output logic                        interruptPending_o,
  output reg   [`CSR_WIDTH-1:0]       csr_epc_o,
  output reg   [`CSR_WIDTH-1:0]       csr_evec_o,
  //Changes: Mohit (Status output goes to Instruction Buffer used for checking FP_DISABLED status)	
  output       [`CSR_WIDTH-1:0]       csr_status_o,
  //Changes: Mohit (FRM register used for dynamic rounding mode)	
  output       [`CSR_WIDTH-1:0]       csr_frm_o,
  output privilege_t                  priv_lvl_o
	);

//`define SR_S              64'h0000000000000001
//`define SR_PS             64'h0000000000000002
//`define SR_EI             64'h0000000000000004
//`define SR_PEI            64'h0000000000000008
//`define SR_EF             64'h0000000000000010
//`define SR_U64            64'h0000000000000020
//`define SR_S64            64'h0000000000000040
//`define SR_VM             64'h0000000000000080
//`define SR_EA             64'h0000000000000100
//`define SR_IM             64'h0000000000FF0000
//`define SR_IP             64'h00000000FF000000
//`define SR_IM_SHIFT       16
//`define SR_IP_SHIFT       24
//localparam SR_ZERO   =         ~(`SR_S|`SR_PS|`SR_EI|`SR_PEI|`SR_EF|`SR_U64|`SR_S64|`SR_VM|`SR_EA|`SR_IM|`SR_IP);

//`define IRQ_COP           2
//`define IRQ_IPI           5
//`define IRQ_HOST          6
//`define IRQ_TIMER         7
//
//`define IMPL_SPIKE        1
//`define IMPL_ROCKET       2

//// page table entry (PTE) fields
//`define PTE_V             64'h0000000000000001 // Entry is a page Table descriptor
//`define PTE_T             64'h0000000000000002 // Entry is a page Table, not a terminal node
//`define PTE_G             64'h0000000000000004 // Global
//`define PTE_UR            64'h0000000000000008 // User Write permission
//`define PTE_UW            64'h0000000000000010 // User Read permission
//`define PTE_UX            64'h0000000000000020 // User eXecute permission
//`define PTE_SR            64'h0000000000000040 // Supervisor Read permission
//`define PTE_SW            64'h0000000000000080 // Supervisor Write permission
//`define PTE_SX            64'h0000000000000100 // Supervisor eXecute permission
//`define PTE_PERM          (`PTE_SR | `PTE_SW | `PTE_SX | `PTE_UR | `PTE_UW | `PTE_UX)
//
//`define RISCV_PGLEVELS      3
//`define RISCV_PGSHIFT       13
//`define RISCV_PGLEVEL_BITS  10
//`define RISCV_PGSIZE        (1 << `RISCV_PGSHIFT)




/*Original CSRs*/
logic [`CSR_WIDTH-1:0]  csr_fcsr;
logic [`CSR_WIDTH-1:0]  csr_stats;
logic [`CSR_WIDTH-1:0]  csr_sup0; 
logic [`CSR_WIDTH-1:0]  csr_sup1; 
logic [`CSR_WIDTH-1:0]  csr_epc; 
logic [`CSR_WIDTH-1:0]  csr_badvaddr; 
logic [`CSR_WIDTH-1:0]  csr_ptbr; 
logic [`CSR_WIDTH-1:0]  csr_asid; 
logic [`CSR_WIDTH-1:0]  csr_count;
logic [`CSR_WIDTH-1:0]  csr_compare;
logic [`CSR_WIDTH-1:0]  csr_evec; 
logic [`CSR_WIDTH-1:0]  csr_cause;
logic [`CSR_WIDTH-1:0]  csr_status; 
logic [`CSR_WIDTH-1:0]  csr_hartid; 
logic [`CSR_WIDTH-1:0]  csr_impl; 
logic [`CSR_WIDTH-1:0]  csr_fatc; 
logic [`CSR_WIDTH-1:0]  csr_send_ipi; 
logic [`CSR_WIDTH-1:0]  csr_clear_ipi;
logic [`CSR_WIDTH-1:0]  csr_reset; 
logic [`CSR_WIDTH-1:0]  csr_tohost;
logic [`CSR_WIDTH-1:0]  csr_fromhost; 
logic [`CSR_WIDTH-1:0]  csr_cycle;
logic [`CSR_WIDTH-1:0]  csr_time; 
logic [`CSR_WIDTH-1:0]  csr_instret;
logic [`CSR_WIDTH-1:0]  csr_cycleh;
logic [`CSR_WIDTH-1:0]  csr_timeh; 
logic [`CSR_WIDTH-1:0]  csr_instreth;

logic [`CSR_WIDTH-1:0]  csr_epc_next;
logic [`CSR_WIDTH-1:0]  csr_badvaddr_next;
logic [`CSR_WIDTH-1:0]  csr_count_next;
logic [`CSR_WIDTH-1:0]  csr_cause_next;
logic [`CSR_WIDTH-1:0]  csr_scause_next;
logic [`CSR_WIDTH-1:0]  csr_status_next;
logic [`CSR_WIDTH-1:0]  irq_vector_next;
logic [`CSR_WIDTH-1:0]  set_irq_vector;
logic [`CSR_WIDTH-1:0]  clear_irq_vector;
/* New CSRs */
logic [`CSR_WIDTH-1:0]  csr_mcycle;
logic [`CSR_WIDTH-1:0]  csr_minstret;
status_t                csr_mstatus;
logic [`CSR_WIDTH-1:0]  csr_medeleg;
logic [`CSR_WIDTH-1:0]  csr_mideleg;
logic [`CSR_WIDTH-1:0]  csr_mie;
logic [`CSR_WIDTH-1:0]  csr_mip;
logic [`CSR_WIDTH-1:0]  csr_mepc;
logic [`CSR_WIDTH-1:0]  csr_mcause;
logic [`CSR_WIDTH-1:0]  csr_mtval;
logic [`CSR_WIDTH-1:0]  csr_mtvec;
logic [`CSR_WIDTH-1:0]  csr_mscratch;
logic [`CSR_WIDTH-1:0]  csr_stvec;
logic [`CSR_WIDTH-1:0]  csr_sscratch;
logic [`CSR_WIDTH-1:0]  csr_scause;
logic [`CSR_WIDTH-1:0]  csr_stval;
logic [`CSR_WIDTH-1:0]  csr_satp;
logic [`CSR_WIDTH-1:0]  csr_sepc;

logic [`CSR_WIDTH-1:0]  csr_mcycle_next;
logic [`CSR_WIDTH-1:0]  csr_minstret_next;
status_t                csr_mstatus_next;
logic [`CSR_WIDTH-1:0]  csr_mepc_next;
logic [`CSR_WIDTH-1:0]  csr_mcause_next;
logic [`CSR_WIDTH-1:0]  csr_mtval_next;
logic [`CSR_WIDTH-1:0]  csr_stval_next;
logic [`CSR_WIDTH-1:0]  csr_sepc_next;

privilege_t priv_lvl;
privilege_t priv_lvl_next;
privilege_t trap_priv_lvl;
assign priv_lvl_o = priv_lvl;

logic                        wr_csr_fflags    ;
logic                        wr_csr_frm       ;
logic                        wr_csr_fcsr      ;
logic                        wr_csr_stats     ;
logic                        wr_csr_sup0      ;
logic                        wr_csr_sup1      ;
logic                        wr_csr_epc       ;
logic                        wr_csr_badvaddr  ;
logic                        wr_csr_ptbr      ;
logic                        wr_csr_asid      ;
logic                        wr_csr_count     ;
logic                        wr_csr_compare   ;
logic                        wr_csr_evec      ;
logic                        wr_csr_cause     ;
logic                        wr_csr_status    ;
logic                        wr_csr_hartid    ;
logic                        wr_csr_impl      ;
logic                        wr_csr_fatc      ;
logic                        wr_csr_send_ipi  ;
logic                        wr_csr_clear_ipi ;
logic                        wr_csr_reset     ;
logic                        wr_csr_tohost    ;
logic                        wr_csr_fromhost  ;
logic                        wr_csr_cycle     ;
logic                        wr_csr_time      ;
logic                        wr_csr_instret   ;
logic                        wr_csr_cycleh    ;
logic                        wr_csr_timeh     ;
logic                        wr_csr_instreth  ;

logic                        wr_csr_mcycle    ;
logic                        wr_csr_minstret  ;
logic                        wr_csr_mstatus   ;
logic                        wr_csr_medeleg   ;
logic                        wr_csr_mideleg   ;
logic                        wr_csr_mie       ;
logic                        wr_csr_mip       ;
logic                        wr_csr_mcause    ;
logic                        wr_csr_mtval     ;
logic                        wr_csr_mtvec     ;
logic                        wr_csr_mscratch  ;
logic                        wr_csr_mepc      ;
logic                        wr_csr_sstatus   ;
logic                        wr_csr_stvec     ;
logic                        wr_csr_sscratch  ;
logic                        wr_csr_scause    ;
logic                        wr_csr_stval     ;
logic                        wr_csr_satp  ;
logic                        wr_csr_sepc      ;
logic                        wr_csr_sie       ;
logic                        wr_csr_sip       ;


logic                        regRdChkptValid;
logic [`CSR_WIDTH_LOG-1:0]    regRdAddrChkpt;  
logic [`CSR_WIDTH-1:0]  regRdDataChkpt;
logic [`CSR_WIDTH_LOG-1:0]    regWrAddrCommit;  
logic [`CSR_WIDTH-1:0]  regWrDataCommit;
logic 			regWrValid; //Changes: Mohit (Ensures correct regWrite irrespective of flush)
logic                        atomicRdVioFlag;
logic [7:0]                  interrupts;


// IRQ pending logic
// if any irq is enabled, and pending and irqs are enabled globally
always_comb begin
  if (priv_lvl == MACHINE_PRIVILEGE) begin
    interruptPending_o = (|(csr_mie & csr_mip)) && (csr_mstatus.mie);
  end

  // in S and U mode, if the irq needs to be delegated with mideleg
  else if (priv_lvl == SUPERVISOR_PRIVILEGE) begin
    interruptPending_o = (|(csr_mie & csr_mip & csr_mideleg)) && (csr_mstatus.sie);
  end

  else begin // USER_PRIVILEGE
    interruptPending_o = (|(csr_mie & csr_mip & csr_mideleg)); // no UIE bit in mstatus
  end
end


always_comb begin
if (trap_priv_lvl == MACHINE_PRIVILEGE)
  //only output the BASE part of xtvec
  csr_evec_o = {csr_mtvec[`CSR_WIDTH-1:2], 2'b0};
else // SUPERVISOR_PRIVILEGE
  csr_evec_o = {csr_stvec[`CSR_WIDTH-1:2], 2'b0};
end

assign csr_status_o  = csr_status;	//Changes: Mohit
assign csr_frm_o  = {{`CSR_WIDTH-3{1'b0}}, csr_fcsr[7:5]};

// Checkpoint the CSR address and Data read
// by a CSR instruction to verify the atomic
// execution of the CSR instruction. The logic
// continuously checks for a difference in the
// value read by CSR instruction and the current
// value of the CSR. If it finds a difference, it 
// asserts a signal to indicate non-atomic read.
// This signal is used by the retire logic to raise
// an exception and reexecute the CSR if atomicity has
// been violated.
always_ff @(posedge clk or posedge reset)
begin
  if(reset)
  begin
    regRdChkptValid   <=  1'b0;
  end
  else if(regRdEn_i)
  begin
    regRdAddrChkpt <=  regRdAddr_i;
    regRdDataChkpt <=  regRdData_o;
    regRdChkptValid   <=  1'b1;
  end
  else if(flush_i | commitReg_i)
  begin
    regRdChkptValid   <=  1'b0;
  end
end


// Hold the CSR writes in a temporary register until the
// CSR write instruction commits. The architecture guarantees
// that only on CSR will be dispatched to the backend at any 
// given time making renaming of CSR registers unnecessary. Even
// with this guarantee, CSR writes still remain a problem since
// branch mispredicts or other exceptions might squash the CSR
// instruction after it has completed and waiting in the ActiveList
// to be committed. Hence, the effect of the CSR write can not be
// made permanent until it commits. This way, we can provide and
// illusion of atomic execution of the CSR instruction. No instruction
// prior to the CSR instruction commit will see the effect of the CSR
// instruction and all instructions after the CSR instruction commit will
// see the effect immediately. Note that the instructions after
// the CSR instruction will not be dispatched until the CSR instruction
// has committed.
always_ff @(posedge clk)
begin
  if(regWrEn_i)
  begin
    regWrAddrCommit <=  regWrAddr_i;
    regWrDataCommit <=  regWrData_i;
  end 
end


//Changes: Mohit (Block added to handle flush, after which CSR 
// write should be disabled)
always_ff @(posedge clk or posedge reset)
begin
  if(reset)
  begin
    regWrValid <= 1'b0;
  end
  else if(regWrEn_i)
  begin
    regWrValid <= 1'b1;
  end
  else if(flush_i)
  begin
    regWrValid <= 1'b0;
  end
end


// Register Write operation
always_comb
begin
  wr_csr_fflags    =  1'b0;
  wr_csr_frm       =  1'b0;
  wr_csr_fcsr      =  1'b0;
  wr_csr_stats     =  1'b0;
  wr_csr_sup0      =  1'b0;
  wr_csr_sup1      =  1'b0;
  wr_csr_epc       =  1'b0;
  wr_csr_badvaddr  =  1'b0;
  wr_csr_ptbr      =  1'b0;
  wr_csr_asid      =  1'b0;
  wr_csr_count     =  1'b0;
  wr_csr_compare   =  1'b0;
  wr_csr_evec      =  1'b0;
  wr_csr_cause     =  1'b0;
  wr_csr_status    =  1'b0;
  wr_csr_hartid    =  1'b0;
  wr_csr_impl      =  1'b0;
  wr_csr_fatc      =  1'b0;
  wr_csr_send_ipi  =  1'b0;
  wr_csr_clear_ipi =  1'b0;
  wr_csr_reset     =  1'b0;
  wr_csr_tohost    =  1'b0;
  wr_csr_fromhost  =  1'b0;
  wr_csr_cycle     =  1'b0;
  wr_csr_time      =  1'b0;
  wr_csr_instret   =  1'b0;
  wr_csr_cycleh    =  1'b0;
  wr_csr_timeh     =  1'b0;
  wr_csr_instreth  =  1'b0;
  clear_irq_vector =  64'b0;

  wr_csr_mcycle    =  1'b0;
  wr_csr_minstret  =  1'b0;
  wr_csr_mstatus   =  1'b0;
  wr_csr_medeleg   =  1'b0;
  wr_csr_mideleg   =  1'b0;
  wr_csr_mie       =  1'b0;
  wr_csr_mip       =  1'b0;
  wr_csr_mcause    =  1'b0;
  wr_csr_mtval     =  1'b0;
  wr_csr_mtvec     =  1'b0;
  wr_csr_mscratch  =  1'b0;
  wr_csr_mepc      =  1'b0;
  wr_csr_sstatus   =  1'b0;
  wr_csr_stvec     =  1'b0;
  wr_csr_sscratch  =  1'b0;
  wr_csr_scause    =  1'b0;
  wr_csr_stval     =  1'b0;
  wr_csr_satp      =  1'b0;
  wr_csr_sepc      =  1'b0;
  wr_csr_sie       =  1'b0;
  wr_csr_sip       =  1'b0;

  // Write the register when the CSR instruction commits
  if(commitReg_i && regWrValid) //Changes: Mohit Disables reg commit write after flush
  begin
    case(regWrAddrCommit)
      `CSR_FFLAGS      :wr_csr_fflags    = 1'b1;
      `CSR_FRM         :wr_csr_frm       = 1'b1;
      `CSR_FCSR        :wr_csr_fcsr      = 1'b1;
      12'h0c0:wr_csr_stats     = 1'b1; 
      12'h500:wr_csr_sup0      = 1'b1; 
      12'h501:wr_csr_sup1      = 1'b1; 
      12'h502:wr_csr_epc       = 1'b1; 
      12'h503:wr_csr_badvaddr  = 1'b1; 
      12'h504:wr_csr_ptbr      = 1'b1; 
      12'h505:wr_csr_asid      = 1'b1; 
      12'h506:wr_csr_count     = 1'b1; 
      12'h507:wr_csr_compare   = 1'b1; 
      12'h508:wr_csr_evec      = 1'b1;
      12'h509:wr_csr_cause     = 1'b1; 
      12'h50a:wr_csr_status    = 1'b1; 
      12'h50b:wr_csr_hartid    = 1'b1; 
      12'h50c:wr_csr_impl      = 1'b1; 
      12'h50d:wr_csr_fatc      = 1'b1; 
      12'h50e:wr_csr_send_ipi  = 1'b1; 
      12'h50f:wr_csr_clear_ipi = 1'b1; 
      12'h51d:wr_csr_reset     = 1'b1; 
      12'h51e:wr_csr_tohost    = 1'b1; 
      12'h51f:begin
        wr_csr_fromhost    = 1'b1; 
        clear_irq_vector[`IRQ_HOST+`SR_IP_SHIFT]   = 1'b1;
      end
      //12'hc00:wr_csr_cycle     = 1'b1;
      12'hc01:wr_csr_time      = 1'b1; 
      //12'hc02:wr_csr_instret   = 1'b1;
      12'hc80:wr_csr_cycleh    = 1'b1; 
      12'hc81:wr_csr_timeh     = 1'b1; 
      12'hc82:wr_csr_instreth  = 1'b1; 

      `CSR_MCYCLE     : wr_csr_mcycle     = 1'b1;
      `CSR_MINSTRET   : wr_csr_instret    = 1'b1;
      `CSR_MSTATUS    : wr_csr_mstatus    = 1'b1;
      `CSR_MEDELEG: wr_csr_medeleg = 1'b1;
      `CSR_MIDELEG: wr_csr_mideleg = 1'b1;
      `CSR_MIE: wr_csr_mie     = 1'b1;
      `CSR_MIP        : wr_csr_mip        = 1'b1;
      `CSR_MCAUSE     : wr_csr_mcause     = 1'b1;
      `CSR_MTVAL      : wr_csr_mtval      = 1'b1;
      `CSR_MTVEC      : wr_csr_mtvec      = 1'b1;
      `CSR_MSCRATCH   : wr_csr_mscratch   = 1'b1;
      `CSR_MEPC       : wr_csr_mepc       = 1'b1;
      `CSR_SSTATUS    : wr_csr_sstatus    = 1'b1;
      `CSR_STVEC      : wr_csr_stvec      = 1'b1;
      `CSR_SSCRATCH   : wr_csr_sscratch   = 1'b1;
      `CSR_SCAUSE     : wr_csr_scause     = 1'b1;
      `CSR_STVAL      : wr_csr_stval      = 1'b1;
      `CSR_SATP:wr_csr_satp  = 1'b1;
      `CSR_SEPC       : wr_csr_sepc       = 1'b1;
      `CSR_SIE        : wr_csr_sie        = 1'b1;
      `CSR_SIP        : wr_csr_sip        = 1'b1;
    endcase
  end
end

// Register Write operation
always_ff @(posedge clk or posedge reset)
begin
  if(reset)
  begin
    csr_fcsr      <=  `CSR_WIDTH'b0;
    csr_stats     <=  `CSR_WIDTH'b0;
    csr_sup0      <=  `CSR_WIDTH'b0;
    csr_sup1      <=  `CSR_WIDTH'b0;
    csr_epc       <=  `CSR_WIDTH'b0;
    csr_badvaddr  <=  `CSR_WIDTH'b0;
    csr_ptbr      <=  `CSR_WIDTH'b0;
    csr_asid      <=  `CSR_WIDTH'b0;
    csr_count     <=  `CSR_WIDTH'b0;
    csr_compare   <=  `CSR_WIDTH'b0;
    csr_evec      <=  `CSR_WIDTH'b0;
    csr_cause     <=  `CSR_WIDTH'b0;
    csr_status    <=  (`SR_S | `SR_S64 | `SR_U64);
    csr_hartid    <=  `CSR_WIDTH'b0;
    csr_impl      <=  `CSR_WIDTH'b0;
    csr_fatc      <=  `CSR_WIDTH'b0;
    csr_send_ipi  <=  `CSR_WIDTH'b0;
    csr_clear_ipi <=  `CSR_WIDTH'b0;
    csr_reset     <=  `CSR_WIDTH'b0;
    csr_tohost    <=  `CSR_WIDTH'b0;
    csr_fromhost  <=  `CSR_WIDTH'b0;
    csr_cycle     <=  `CSR_WIDTH'b0;
    csr_time      <=  `CSR_WIDTH'b0;
    csr_instret   <=  `CSR_WIDTH'b0;
    csr_cycleh    <=  `CSR_WIDTH'b0;
    csr_timeh     <=  `CSR_WIDTH'b0;
    csr_instreth  <=  `CSR_WIDTH'b0;

    csr_mcycle     <=  `CSR_WIDTH'b0;
    csr_minstret   <=  `CSR_WIDTH'b0;
    csr_mstatus    <=  (`MSTATUS_SXL_64 | `MSTATUS_UXL_64 ); // only set up the base ISA after reset
    csr_medeleg   <=  `CSR_WIDTH'b0;
    csr_mideleg   <=  `CSR_WIDTH'b0;
    csr_mie       <=  `CSR_WIDTH'b0;
    csr_mcause    <=  `CSR_WIDTH'b0;
    csr_mtval     <=  `CSR_WIDTH'b0;
    csr_mtvec     <=   startPC_i;
    csr_mscratch  <=  `CSR_WIDTH'b0;
    csr_mepc      <=  `CSR_WIDTH'b0;
    csr_mip       <=  `CSR_WIDTH'b0;
    csr_stvec     <=  `CSR_WIDTH'b0;
    csr_sscratch  <=  `CSR_WIDTH'b0;
    csr_scause    <=  `CSR_WIDTH'b0;
    csr_stval     <=  `CSR_WIDTH'b0;
    csr_satp      <=  `CSR_WIDTH'b0;
    csr_sepc      <=  `CSR_WIDTH'b0;

    priv_lvl      <= MACHINE_PRIVILEGE;
  end
  // Write the register when the CSR instruction commits
  else
  begin
    //Changes: Mohit (Update CSR_FFLAGS when floating-point instruction retire)
    csr_fcsr      <=  wr_csr_fflags    ? {{`CSR_WIDTH-5{1'b1}},regWrDataCommit[4:0]} & csr_fcsr : (csr_fcsr | (csr_fflags_i & `CSR_FFLAGS_MASK));;
    csr_fcsr      <=  wr_csr_frm       ? {{`CSR_WIDTH-8{1'b1}},regWrDataCommit[2:0], 5'b1} & csr_fcsr : csr_fcsr;
    //Changes: Mohit (FFLAGS is also part of FCSR register according to ISA)
    csr_fcsr      <=  wr_csr_fcsr      ? {{`CSR_WIDTH-8{1'b1}},regWrDataCommit[7:0]} & csr_fcsr : (csr_fcsr | (csr_fflags_i & `CSR_FFLAGS_MASK));
    csr_stats     <=  wr_csr_stats     ? regWrDataCommit : csr_stats; 
    csr_sup0      <=  wr_csr_sup0      ? regWrDataCommit : csr_sup0; 
    csr_sup1      <=  wr_csr_sup1      ? regWrDataCommit : csr_sup1; 
    csr_epc       <=  wr_csr_epc       ? regWrDataCommit : csr_epc_next; 
    csr_badvaddr  <=  wr_csr_badvaddr  ? regWrDataCommit : csr_badvaddr_next;
    csr_ptbr      <=  wr_csr_ptbr      ? regWrDataCommit : csr_ptbr; 
    csr_asid      <=  wr_csr_asid      ? regWrDataCommit : csr_asid;
    csr_count     <=  wr_csr_count     ? regWrDataCommit : csr_count_next;
    csr_compare   <=  wr_csr_compare   ? regWrDataCommit & `CSR_COMPARE_MASK : csr_compare; 
    csr_evec      <=  wr_csr_evec      ? regWrDataCommit : csr_evec; 
    csr_cause     <=  wr_csr_cause     ? regWrDataCommit : csr_cause_next;  
    csr_status    <=  wr_csr_status    ? ((regWrDataCommit & ~`SR_IP) | (csr_status & `SR_IP)) & `CSR_STATUS_MASK : csr_status_next;
    csr_hartid    <=  wr_csr_hartid    ? regWrDataCommit : csr_hartid;   
    csr_impl      <=  wr_csr_impl      ? regWrDataCommit : csr_impl;   
    csr_fatc      <=  wr_csr_fatc      ? regWrDataCommit : csr_fatc;   
    csr_send_ipi  <=  wr_csr_send_ipi  ? regWrDataCommit : csr_send_ipi;   
    csr_clear_ipi <=  wr_csr_clear_ipi ? regWrDataCommit : csr_clear_ipi;
    csr_reset     <=  wr_csr_reset     ? regWrDataCommit : csr_reset;
    csr_tohost    <=  wr_csr_tohost    ? regWrDataCommit : csr_tohost;
    csr_fromhost  <=  wr_csr_fromhost  ? regWrDataCommit : csr_fromhost;
    csr_cycle     <=  wr_csr_cycle     ? regWrDataCommit : csr_count_next; //csr_cycle;
    csr_time      <=  wr_csr_time      ? regWrDataCommit : csr_count_next; //csr_time;
    csr_instret   <=  wr_csr_instret   ? regWrDataCommit : csr_count_next; //csr_instret;
    csr_cycleh    <=  wr_csr_cycleh    ? regWrDataCommit : csr_cycleh;
    csr_timeh     <=  wr_csr_timeh     ? regWrDataCommit : csr_timeh;
    csr_instreth  <=  wr_csr_instreth  ? regWrDataCommit : csr_instreth;

    csr_mcycle    <=  wr_csr_mcycle    ? regWrDataCommit : csr_mcycle_next;
    csr_minstret  <=  wr_csr_minstret  ? regWrDataCommit : csr_minstret_next;
    csr_mstatus   <= wr_csr_mstatus ? regWrDataCommit : csr_mstatus_next;
    csr_mstatus   <= wr_csr_sstatus ? (regWrDataCommit & SSTATUS_WRITE_MASK) & (csr_mstatus & ~SSTATUS_WRITE_MASK) : csr_mstatus_next;
    if (wr_csr_medeleg) begin
      csr_medeleg <= (regWrDataCommit & MEDELEG_MASK) | (csr_medeleg & ~MEDELEG_MASK);
    end
    if (wr_csr_mideleg) begin
      csr_mideleg <= (regWrDataCommit & MIDELEG_MASK) | (csr_mideleg & ~MIDELEG_MASK);
    end
    if (wr_csr_mie) begin
      csr_mie <= (regWrDataCommit & MIE_MASK) | (csr_mie & ~MIE_MASK);
    end
    if (wr_csr_mip) begin
      csr_mip <= (regWrDataCommit & MIP_MASK) | (csr_mip & ~MIP_MASK);
    end
    csr_mcause    <=  wr_csr_mcause    ? regWrDataCommit : csr_mcause_next;
    csr_mtval     <=  wr_csr_mtval     ? regWrDataCommit : csr_mtval_next;
    csr_mtvec     <=  wr_csr_mtvec     ? {regWrDataCommit[`CSR_WIDTH-1:2], 1'b0, regWrDataCommit[0]}: csr_mtvec;
    csr_mscratch  <=  wr_csr_mscratch  ? regWrDataCommit : csr_mscratch;
    csr_mepc      <=  wr_csr_mepc      ? {regWrDataCommit[`CSR_WIDTH-1:1], 1'b0} : csr_mepc_next;
    csr_scause    <=  wr_csr_scause    ? regWrDataCommit : csr_scause_next;
    csr_stval     <=  wr_csr_stval     ? regWrDataCommit : csr_stval_next;
    csr_stvec     <=  wr_csr_stvec     ? {regWrDataCommit[`CSR_WIDTH-1:2], 1'b0, regWrDataCommit[0]}: csr_stvec;
    csr_sscratch  <=  wr_csr_sscratch  ? regWrDataCommit : csr_sscratch;
    if (wr_csr_satp) begin
      //TODO
      //if(priv == S && (csr_mstatus & MSTATUS_TVM)) begin
      //   write access exception
      //end else begin
          csr_satp <= regWrDataCommit;
      //end
    end
    csr_sepc      <=  wr_csr_sepc      ? {regWrDataCommit[`CSR_WIDTH-1:1], 1'b0} : csr_sepc_next;

    // MIE and MIP bits can be set by Supervisor mode, if they are set in MIDELEG
    if (wr_csr_sie) begin
      csr_mie <= (regWrDataCommit & csr_mideleg) | (csr_mie & ~csr_mideleg);
    end
    if (wr_csr_sip) begin
      // STIP and SEIP are read only in SIP
      csr_mip <= (regWrDataCommit & (`MIP_SSIP & csr_mideleg))
        | (csr_mip & ~(`MIP_SSIP & csr_mideleg));
    end

    priv_lvl <= priv_lvl_next;
  end
end

assign set_irq_vector  = 0;

// Interrupt bits in MIP
always_comb begin
  csr_mip[`IRQ_M_EXT]   = irq_i[0];    // external irq pending
  csr_mip[`IRQ_M_SOFT]  = ipi_i;       // software irq
  csr_mip[`IRQ_M_TIMER] = time_irq_i;  // external timer irq
end


assign csr_count_next     = csr_count + totalCommit_i + exceptionFlag_i;
assign csr_epc_next       = exceptionFlag_i ? exceptionPC_i    : csr_epc;
assign csr_cause_next     = exceptionFlag_i ? exceptionCause_i : csr_cause;

// totalCommit_i is the number of instructions commiting each cycle
always_comb begin
  csr_minstret_next = csr_minstret + totalCommit_i;
  csr_mcycle_next   = csr_mcycle + 1'b1;
end

always_comb begin
  //default cases
  csr_mstatus_next = csr_mstatus;
  csr_mtval_next   = csr_mtval;
  csr_stval_next   = csr_stval;
  csr_mcause_next  = csr_mcause;
  csr_scause_next  = csr_scause;
  csr_mepc_next    = csr_mepc;
  csr_sepc_next    = csr_sepc;
  priv_lvl_next    = priv_lvl;

  // default: all traps handled at M level
  trap_priv_lvl = MACHINE_PRIVILEGE;

  // Taking a trap
  if (exceptionFlag_i) begin
    //TODO: mideleg for interrupts
    if (csr_medeleg[ 1 << exceptionCause_i ]) begin
      if (priv_lvl == MACHINE_PRIVILEGE)
       // traps cannot be delegated to a
       // less privileged mode
       trap_priv_lvl = MACHINE_PRIVILEGE;
      else
        // traps in S and U mode are delegated to S mode
        trap_priv_lvl = SUPERVISOR_PRIVILEGE;
    end

    priv_lvl_next = trap_priv_lvl;

    if (trap_priv_lvl == MACHINE_PRIVILEGE) begin
      csr_mstatus_next.mpie = csr_mstatus.mie;
      csr_mstatus_next.mie  = 1'b0; // disable interrupts
      csr_mstatus_next.mpp  = priv_lvl;
      csr_mcause_next       = exceptionCause_i;
      csr_mepc_next         = exceptionPC_i;
      case(exceptionCause_i)
        `CAUSE_MISALIGNED_FETCH: csr_mtval_next = exceptionPC_i;
        `CAUSE_FAULT_FETCH     : csr_mtval_next = exceptionPC_i;
        `CAUSE_MISALIGNED_LOAD : csr_mtval_next = ldCommitAddr_i;
        `CAUSE_MISALIGNED_STORE: csr_mtval_next = stCommitAddr_i;
        `CAUSE_FAULT_LOAD      : csr_mtval_next = ldCommitAddr_i;
        `CAUSE_FAULT_STORE     : csr_mtval_next = stCommitAddr_i;
        default                : csr_mtval_next = csr_mtval;
      endcase
    end

    else if (trap_priv_lvl == SUPERVISOR_PRIVILEGE) begin
      csr_mstatus_next.spie = csr_mstatus.sie;
      csr_mstatus_next.sie  = 0; // disable interrupts
      csr_mstatus_next.spp  = priv_lvl[0];
      csr_scause_next       = exceptionCause_i;
      csr_sepc_next         = exceptionPC_i;
      case(exceptionCause_i)
        `CAUSE_MISALIGNED_FETCH: csr_stval_next = exceptionPC_i;
        `CAUSE_FAULT_FETCH     : csr_stval_next = exceptionPC_i;
        `CAUSE_MISALIGNED_LOAD : csr_stval_next = ldCommitAddr_i;
        `CAUSE_MISALIGNED_STORE: csr_stval_next = stCommitAddr_i;
        `CAUSE_FAULT_LOAD      : csr_stval_next = ldCommitAddr_i;
        `CAUSE_FAULT_STORE     : csr_stval_next = stCommitAddr_i;
        default                : csr_stval_next = csr_stval;
      endcase
    end
  end // if exceptionFlag_i
  else begin
// Returning from a trap
    if (mretFlag_i) begin
    // get the previous machine interrupt enable flag
    csr_mstatus_next.mie  = csr_mstatus.mpie;
    // restore the previous privilege level
    priv_lvl_next  = csr_mstatus.mpp;
    // set mpp to user mode
    csr_mstatus_next.mpp  = USER_PRIVILEGE;
    csr_mstatus_next.mpie = 1'b1;
  end
  else if (sretFlag_i) begin
    // return the previous supervisor interrupt enable flag
    csr_mstatus_next.sie  = csr_mstatus.spie;
    // restore the previous privilege level
    priv_lvl_next = {1'b0, csr_mstatus.spp}; //spp is 1 bit
    // set spp to user mode
    csr_mstatus_next.spp  = 1'b0;
    csr_mstatus_next.spie = 1'b1;
  end
  end
end

always_comb begin
  // mepc, sepc used as recoverPC
  if (sretFlag_i)
      csr_epc_o = csr_sepc;
  else
      csr_epc_o = csr_mepc;
end

always_comb
begin
  if(sretFlag_i)
  begin
    csr_status_next    = (csr_status & ~(`SR_S | `SR_EI)) | 
                         ((csr_status & `SR_PS) ? `SR_S : 64'b0) |
                         ((csr_status & `SR_PEI) ? `SR_EI : 64'b0);
  end
  else
  begin
    irq_vector_next    = set_irq_vector | (~clear_irq_vector & csr_status & `SR_IP);
    csr_status_next    = (csr_status & ~`SR_IP) | irq_vector_next;
  end
end

always_comb
begin
  csr_badvaddr_next = csr_badvaddr;
  if(exceptionFlag_i)
  begin
    case(exceptionCause_i)
      `CAUSE_MISALIGNED_FETCH: csr_badvaddr_next = exceptionPC_i;
      `CAUSE_FAULT_FETCH     : csr_badvaddr_next = exceptionPC_i;
      `CAUSE_MISALIGNED_LOAD : csr_badvaddr_next = ldCommitAddr_i;
      `CAUSE_MISALIGNED_STORE: csr_badvaddr_next = stCommitAddr_i;
      `CAUSE_FAULT_LOAD      : csr_badvaddr_next = ldCommitAddr_i;
      `CAUSE_FAULT_STORE     : csr_badvaddr_next = stCommitAddr_i;
      default                : csr_badvaddr_next = csr_badvaddr; 
    endcase
  end
end

// Register Read operation
always_comb
begin
  case(regRdAddr_i)
    `CSR_FFLAGS     : regRdData_o = {{`CSR_WIDTH-5{1'b0}}, csr_fcsr[4:0]};
    `CSR_FRM        : regRdData_o = {{`CSR_WIDTH-3{1'b0}}, csr_fcsr[7:5]};
    `CSR_FCSR       : regRdData_o = {{`CSR_WIDTH-8{1'b0}}, csr_fcsr[7:0]};
    12'h0c0:regRdData_o   =  csr_stats     ; 
    12'h500:regRdData_o   =  csr_sup0      ; 
    12'h501:regRdData_o   =  csr_sup1      ; 
    12'h502:regRdData_o   =  csr_epc       ; 
    12'h503:regRdData_o   =  csr_badvaddr  ; 
    12'h504:regRdData_o   =  csr_ptbr      ; 
    12'h505:regRdData_o   =  csr_asid      ; 
    12'h506:regRdData_o   =  csr_count     ; 
    12'h507:regRdData_o   =  csr_compare   ; 
    12'h508:regRdData_o   =  csr_evec      ;
    12'h509:regRdData_o   =  csr_cause     ;  
    12'h50a:regRdData_o   =  csr_status    ;   
    12'h50b:regRdData_o   =  csr_hartid    ;   
    12'h50c:regRdData_o   =  csr_impl      ;   
    12'h50d:regRdData_o   =  csr_fatc      ;   
    12'h50e:regRdData_o   =  csr_send_ipi  ;   
    12'h50f:regRdData_o   =  csr_clear_ipi ;
    12'h51d:regRdData_o   =  csr_reset     ;
    12'h51e:regRdData_o   =  csr_tohost    ;
    12'h51f:regRdData_o   =  csr_fromhost  ;
    //12'hc00:regRdData_o   =  csr_cycle     ;
    12'hc01:regRdData_o   =  csr_time      ;
    //12'hc02:regRdData_o   =  csr_instret   ;
    12'hc80:regRdData_o   =  csr_cycleh    ;
    12'hc81:regRdData_o   =  csr_timeh     ;
    12'hc82:regRdData_o   =  csr_instreth  ;
    `CSR_CYCLE      : regRdData_o = csr_mcycle;
    `CSR_INSTRET    : regRdData_o = csr_minstret;
    `CSR_MCYCLE     : regRdData_o = csr_mcycle;
    `CSR_MINSTRET   : regRdData_o = csr_minstret;
    `CSR_MVENDORID  : regRdData_o = `CSR_WIDTH'b0; // open source
    `CSR_MARCHID    : regRdData_o = `CSR_WIDTH'b0; // should change later
    `CSR_MIMPID     : regRdData_o = `CSR_WIDTH'b0; // version id
    `CSR_MCONFIGPTR : regRdData_o = `CSR_WIDTH'b0; // config data structure does not exist
    `CSR_MENVCFG    : regRdData_o = `CSR_WIDTH'b0; // fence handling, TODO
    `CSR_MHARTID:regRdData_o = hartId_i;
    `CSR_MSTATUS    : regRdData_o = csr_mstatus    ;
    `CSR_MISA       : regRdData_o = MISA_VAL;
    `CSR_MEDELEG   : regRdData_o = csr_medeleg;
    `CSR_MIDELEG   : regRdData_o = csr_mideleg;
    `CSR_MIE       : regRdData_o = csr_mie;
    // "When MIP is read with a CSR instruction,
    // the value of the SEIP bit returned (...) is the logical-OR
    // of the software-writable bit and the interrupt signal from the
    // interrupt controller "
    `CSR_MIP        : regRdData_o = csr_mip | (irq_i[1] << `IRQ_S_EXT);
    `CSR_MCAUSE     : regRdData_o = csr_mcause;
    `CSR_MTVAL      : regRdData_o = csr_mtval;
    `CSR_MTVEC      : regRdData_o = csr_mtvec;
    `CSR_MSCRATCH   : regRdData_o = csr_mscratch;
    `CSR_MEPC       : regRdData_o = csr_mepc;
    `CSR_SSTATUS    : regRdData_o = csr_mstatus & SSTATUS_READ_MASK;
    `CSR_STVEC      : regRdData_o = csr_stvec;
    `CSR_SENVCFG    : regRdData_o = `CSR_WIDTH'b0;
    `CSR_SSCRATCH   : regRdData_o = csr_sscratch;
    `CSR_SCAUSE     : regRdData_o = csr_scause;
    `CSR_STVAL      : regRdData_o = csr_stval;
    `CSR_SATP      : begin
      //TODO:
      //if(priv == S && (csr_mstatus & MSTATUS_TVM))
      //   read access exception
      //else
      regRdData_o   =  csr_satp;
    end
    `CSR_SEPC       : regRdData_o = csr_sepc;
    `CSR_SIE        : regRdData_o = csr_mie & csr_mideleg;
    // same as MIP, but the delegation needs to be checked
    `CSR_SIP        : regRdData_o = (csr_mip & csr_mideleg)
        | ((irq_i[1] & csr_mideleg[`IRQ_S_EXT]) << `IRQ_S_EXT);
    default:regRdData_o   =  `CSR_WIDTH'bx;
  endcase  
end

// Atomicity Violation Check
always_comb
begin
  case(regRdAddrChkpt)
    `CSR_FFLAGS     :atomicRdVioFlag = (regRdDataChkpt   != {{`CSR_WIDTH-5{1'b0}}, csr_fcsr[4:0]});
    `CSR_FRM        :atomicRdVioFlag = (regRdDataChkpt   != {{`CSR_WIDTH-3{1'b0}}, csr_fcsr[7:5]});
    `CSR_FCSR       :atomicRdVioFlag = (regRdDataChkpt   != {{`CSR_WIDTH-8{1'b0}}, csr_fcsr[7:0]});
    12'h0c0:atomicRdVioFlag = (regRdDataChkpt   !=  csr_stats     ); 
    12'h500:atomicRdVioFlag = (regRdDataChkpt   !=  csr_sup0      ); 
    12'h501:atomicRdVioFlag = (regRdDataChkpt   !=  csr_sup1      ); 
    12'h502:atomicRdVioFlag = (regRdDataChkpt   !=  csr_epc       ); 
    12'h503:atomicRdVioFlag = (regRdDataChkpt   !=  csr_badvaddr  ); 
    12'h504:atomicRdVioFlag = (regRdDataChkpt   !=  csr_ptbr      ); 
    12'h505:atomicRdVioFlag = (regRdDataChkpt   !=  csr_asid      ); 
    12'h506:atomicRdVioFlag = (regRdDataChkpt   !=  csr_count     ); 
    12'h507:atomicRdVioFlag = (regRdDataChkpt   !=  csr_compare   ); 
    12'h508:atomicRdVioFlag = (regRdDataChkpt   !=  csr_evec      );
    12'h509:atomicRdVioFlag = (regRdDataChkpt   !=  csr_cause     );  
    12'h50a:atomicRdVioFlag = (regRdDataChkpt   !=  csr_status    );   
    12'h50b:atomicRdVioFlag = (regRdDataChkpt   !=  csr_hartid    );   
    12'h50c:atomicRdVioFlag = (regRdDataChkpt   !=  csr_impl      );   
    12'h50d:atomicRdVioFlag = (regRdDataChkpt   !=  csr_fatc      );   
    12'h50e:atomicRdVioFlag = (regRdDataChkpt   !=  csr_send_ipi  );   
    12'h50f:atomicRdVioFlag = (regRdDataChkpt   !=  csr_clear_ipi );
    12'h51d:atomicRdVioFlag = (regRdDataChkpt   !=  csr_reset     );
    12'h51e:atomicRdVioFlag = (regRdDataChkpt   !=  csr_tohost    );
    12'h51f:atomicRdVioFlag = (regRdDataChkpt   !=  csr_fromhost  );
    //12'hc00:atomicRdVioFlag = (regRdDataChkpt   !=  csr_cycle     );
    12'hc01:atomicRdVioFlag = (regRdDataChkpt   !=  csr_time      );
    //12'hc02:atomicRdVioFlag = (regRdDataChkpt   !=  csr_instret   );
    12'hc80:atomicRdVioFlag = (regRdDataChkpt   !=  csr_cycleh    );
    12'hc81:atomicRdVioFlag = (regRdDataChkpt   !=  csr_timeh     );
    12'hc82:atomicRdVioFlag = (regRdDataChkpt   !=  csr_instreth  );
    `CSR_CYCLE     : atomicRdVioFlag = (regRdDataChkpt  !=  csr_mcycle    );
    `CSR_INSTRET   : atomicRdVioFlag = (regRdDataChkpt  !=  csr_minstret  );
    `CSR_MCYCLE    : atomicRdVioFlag = (regRdDataChkpt  !=  csr_mcycle    );
    `CSR_MINSTRET  : atomicRdVioFlag = (regRdDataChkpt  !=  csr_minstret  );
    `CSR_MVENDORID : atomicRdVioFlag = (regRdDataChkpt  !=  `CSR_WIDTH'b0 );
    `CSR_MARCHID   : atomicRdVioFlag = (regRdDataChkpt  !=  `CSR_WIDTH'b0 );
    `CSR_MIMPID    : atomicRdVioFlag = (regRdDataChkpt  !=  `CSR_WIDTH'b0 );
    `CSR_MCONFIGPTR: atomicRdVioFlag = (regRdDataChkpt  !=  `CSR_WIDTH'b0 );
    `CSR_MENVCFG   : atomicRdVioFlag = (regRdDataChkpt  !=  `CSR_WIDTH'b0 );
    `CSR_MSTATUS   : atomicRdVioFlag = (regRdDataChkpt  !=  csr_mstatus   );
    `CSR_MISA      : atomicRdVioFlag = (regRdDataChkpt  !=  MISA_VAL      );
    `CSR_MEDELEG   :atomicRdVioFlag = (regRdDataChkpt   !=  csr_medeleg   );
    `CSR_MIDELEG   :atomicRdVioFlag = (regRdDataChkpt   !=  csr_mideleg   );
    `CSR_MIE       :atomicRdVioFlag = (regRdDataChkpt   !=  csr_mie       );
    `CSR_MIP       : atomicRdVioFlag = (regRdDataChkpt  !=  csr_mip       );
    `CSR_MCAUSE    : atomicRdVioFlag = (regRdDataChkpt  !=  csr_mcause    );
    `CSR_MTVAL     : atomicRdVioFlag = (regRdDataChkpt  !=  csr_mtval     );
    `CSR_MTVEC     : atomicRdVioFlag = (regRdDataChkpt  !=  csr_mtvec     );
    `CSR_MSCRATCH  : atomicRdVioFlag = (regRdDataChkpt  !=  csr_mscratch  );
    `CSR_MEPC      : atomicRdVioFlag = (regRdDataChkpt  !=  csr_mepc      );
    `CSR_SSTATUS   : atomicRdVioFlag = (regRdDataChkpt  != (csr_mstatus & SSTATUS_READ_MASK));
    `CSR_STVEC     : atomicRdVioFlag = (regRdDataChkpt  !=  csr_stvec     );
    `CSR_SENVCFG   : atomicRdVioFlag = (regRdDataChkpt  !=  `CSR_WIDTH'b0 );
    `CSR_SSCRATCH  : atomicRdVioFlag = (regRdDataChkpt  !=  csr_sscratch  );
    `CSR_SCAUSE    : atomicRdVioFlag = (regRdDataChkpt  !=  csr_scause    );
    `CSR_STVAL     : atomicRdVioFlag = (regRdDataChkpt  !=  csr_stval     );
    `CSR_SATP      :atomicRdVioFlag = (regRdDataChkpt   !=  csr_satp      );
    `CSR_SEPC      : atomicRdVioFlag = (regRdDataChkpt  !=  csr_sepc      );
    `CSR_SIE       : atomicRdVioFlag = (regRdDataChkpt  !=  (csr_mie & csr_mideleg));
    `CSR_SIP       : atomicRdVioFlag = (regRdDataChkpt  !=  (csr_mip & csr_mideleg));
    default:atomicRdVioFlag = 1'b0;
  endcase  
end

assign atomicRdVioFlag_o = atomicRdVioFlag & regRdChkptValid;

endmodule


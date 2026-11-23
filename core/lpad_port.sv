// Copyright 2023 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.
//
// Author: Emanuele Parisi, University of Bologna
// Date: 17.04.2024
// Description: Implements landing pad enforcement.


module lpad_port
  import ariane_pkg::*;
#(
    parameter config_pkg::cva6_cfg_t CVA6Cfg = config_pkg::cva6_cfg_empty,
    parameter type scoreboard_entry_t = logic,
    parameter type elp_t = logic,
    parameter type lpl_t = logic
) (
    // Landing pad enable
    input logic lpe_i,
    // Landing pad expected
    input elp_t elp_i,
    // Landing pad label: x7[31:12] before this instruction
    input lpl_t lpl_i,
    // Current committing instruction
    input scoreboard_entry_t sbe_i,
    // Current committing instruction is cancelled
    input logic drop_i,
    // Bypass checks
    input logic bypass_i,
    // Landing pad expected
    output elp_t elp_o,
    // Landing pad label: x7[31:12] after this instruction
    output lpl_t lpl_o,
    // Current committing instruction
    output scoreboard_entry_t sbe_o,
    // Bypass checks
    output logic bypass_o
);

  logic is_sbe_valid;
  logic is_sbe_lpad;
  logic is_sbe_lplmismatch;
  logic is_sbe_lplwrite;
  logic is_sbe_jalr_lpad;

  // The LPAD label is the U-immediate, i.e. result[31:12] (the ALU puts the
  // immediate in result), and it is compared with x7[31:12] (lpl_i).
  assign is_sbe_valid       = sbe_i.valid && ~sbe_i.ex.valid && lpe_i;
  assign is_sbe_lpad        = sbe_i.pc[1:0] == 2'b0 && sbe_i.op == ZICFI_LPAD;
  assign is_sbe_lplmismatch = sbe_i.result[LPAD_LABEL_LSB+:LPAD_LABEL_BITS] != '0 &&
                              sbe_i.result[LPAD_LABEL_LSB+:LPAD_LABEL_BITS] != lpl_i;
  // Integer write to x7. Only used to forward the new x7 label to the younger
  // commit ports of this cycle; the registered copy is updated from the
  // register file write port in lpad_unit.
  assign is_sbe_lplwrite    = sbe_i.valid && ~sbe_i.ex.valid && ~drop_i && sbe_i.rd == 'd7 &&
                              ~(CVA6Cfg.FpPresent && is_rd_fpr(sbe_i.op));
  assign is_sbe_jalr_lpad   = sbe_i.op == JALR && ~(sbe_i.rs1 inside {'d1, 'd5, 'd7});

  // x7 tracking is independent of the landing pad enable and of the checks
  assign lpl_o = is_sbe_lplwrite ? sbe_i.result[LPAD_LABEL_LSB+:LPAD_LABEL_BITS] : lpl_i;

  always_comb begin : control_flow_check
    elp_o = elp_i;
    sbe_o = sbe_i;
    bypass_o = bypass_i;
    if (is_sbe_valid) begin
      // The core is committing a valid scoreboard entry.
      if (~bypass_i && ~drop_i) begin
        // All preceeding commit ports are valid, and all preceeding landing
        // pad ports do not containg CFI violations.
        if (elp_i == LPAD_EXPECTED) begin
          // A landing pad is expected, any instruction except for a valid
          // LPAD issues an exception.
          if (~is_sbe_lpad || is_sbe_lplmismatch) begin
            sbe_o.ex.cause = riscv::SOFTWARE_CHECK;
            sbe_o.ex.tval = {{CVA6Cfg.XLEN - 2{1'b0}}, 2'b10};
            sbe_o.ex.valid = 1'b1;
            bypass_o = 1'b1;
          end else begin
            elp_o = NO_LPAD_EXPECTED;
          end
        end else begin
          // If a landing pad is not expected, but we have an indirect jump, the
          // next instruction committed should be a landing pad.
          if (is_sbe_jalr_lpad) begin
            elp_o = LPAD_EXPECTED;
          end
        end
      end
    end else begin
      bypass_o = 1'b1;
    end
  end

endmodule

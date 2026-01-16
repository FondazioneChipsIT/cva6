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


module lpad_unit
  import ariane_pkg::*;
#(
    parameter config_pkg::cva6_cfg_t CVA6Cfg = config_pkg::cva6_cfg_empty,
    parameter type scoreboard_entry_t = logic,
    parameter type elp_t = logic,
    parameter type lpl_t = logic
) (
    // Subsystem Clock - SUBSYSTEM
    input logic clk_i,
    // Asynchronous reset active low - SUBSYSTEM
    input logic rst_ni,
    // Landing pad enable - CSR_REGFILE
    input logic lpe_i,
    // Landing pad expected - CSR_REGFILE
    input elp_t elp_i,
    // Current committing instruction - ISSUE_STAGE
    input scoreboard_entry_t [CVA6Cfg.NrCommitPorts-1:0] commit_instr_i,
    // Current committing instruction is cancelled - ISSUE_STAGE
    input logic [CVA6Cfg.NrCommitPorts-1:0] commit_drop_i,
    // Landing pad expected - CSR_REGFILE
    output elp_t elp_o,
    // Current committing instruction - COMMIT_STAGE
    output scoreboard_entry_t [CVA6Cfg.NrCommitPorts-1:0] commit_instr_o
);

  lpl_t lpl_d, lpl_q;

  elp_t [CVA6Cfg.NrCommitPorts:0] tmp_elp;
  lpl_t [CVA6Cfg.NrCommitPorts:0] tmp_lpl;
  logic [CVA6Cfg.NrCommitPorts:0] tmp_bypass;

  generate
    for (genvar i = 0; i < CVA6Cfg.NrCommitPorts; i++) begin : gen_ports
      lpad_port #(
          .CVA6Cfg(CVA6Cfg),
          .scoreboard_entry_t(scoreboard_entry_t),
          .elp_t(elp_t),
          .lpl_t(lpl_t)
      ) lpad_port_i (
          .lpe_i   (lpe_i),
          .elp_i   (tmp_elp[i]),
          .lpl_i   (tmp_lpl[i]),
          .sbe_i   (commit_instr_i[i]),
          .drop_i  (commit_drop_i[i]),
          .bypass_i(tmp_bypass[i]),
          .elp_o   (tmp_elp[i+1]),
          .lpl_o   (tmp_lpl[i+1]),
          .sbe_o   (commit_instr_o[i]),
          .bypass_o(tmp_bypass[i+1])
      );
    end
  endgenerate

  assign tmp_elp[0]    = elp_i;
  assign tmp_lpl[0]    = lpl_q;
  assign tmp_bypass[0] = 1'b0;
  assign elp_o         = tmp_elp[CVA6Cfg.NrCommitPorts];
  assign lpl_d         = tmp_lpl[CVA6Cfg.NrCommitPorts];

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (~rst_ni) begin
      lpl_q <= 'b0;
    end else begin
      lpl_q <= lpl_d;
    end
  end

endmodule

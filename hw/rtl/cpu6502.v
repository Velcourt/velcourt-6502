// cpu6502.v - an NMOS 6502 written as one readable state machine.
//
// Build Your Own 6502 Computer on an FPGA - Adrian Velcourt
// License: MIT (see LICENSE in the book repository)
//
// Bus model
//   Every state is exactly one bus cycle of the real 6502.
//   During a cycle the CPU drives `ab` (and `we`/`dout` for a write).
//   The memory answers on `din` before the end of the same cycle,
//   and the CPU latches what it needs on the rising edge where ce=1.
//   On the FPGA the system clock runs at twice the CPU rate: ce is high
//   on every second clock, so the block RAM gets one full system clock
//   to answer, just as the real chip gives memory the whole of phi2.
//
// What is modelled
//   All 151 documented opcodes, binary and NMOS decimal arithmetic,
//   the cycle counts of the real chip (page-crossing and branch penalties
//   included), RESET, IRQ, NMI and BRK. Undocumented opcodes run as
//   two-cycle NOPs; chapter 29 discusses adding the 65C02 instructions.

module cpu6502 (
    input  wire        clk,
    input  wire        ce,        // clock enable: one CPU cycle per ce pulse
    input  wire        rst,       // synchronous, active high
    output reg  [15:0] ab,        // address bus
    output reg  [7:0]  dout,      // data written by the CPU
    output reg         we,        // 1 = this cycle is a write
    input  wire [7:0]  din,       // data read from memory this cycle
    input  wire        irq_n,     // level-sensitive interrupt request
    input  wire        nmi_n,     // edge-sensitive (falling) interrupt
    output wire        sync       // 1 during an opcode fetch
);

// --------------------------------------------------------------------
// Programmer-visible registers
// --------------------------------------------------------------------
reg [15:0] pc;
reg [7:0]  a, x, y, s;
reg        fn, fv, fd, fi, fz, fc;   // flags N V D I Z C

// --------------------------------------------------------------------
// Internal registers
// --------------------------------------------------------------------
reg [7:0]  ir;        // instruction register
reg [7:0]  adl, adh;  // effective address being built
reg [7:0]  bal;       // zero-page pointer for (zp,X) and (zp),Y
reg [7:0]  data;      // operand latch for read-modify-write and branches
reg        cry;       // carry out of an index addition
reg        forced;    // current BRK was forced by an interrupt
reg        rst_seq;   // current BRK sequence is a reset
reg        int_pend;  // an interrupt will be taken at the next fetch
reg        nmi_old, nmi_flag;
reg [5:0]  state;
reg [1:0]  vec;       // vector: 10=FFFC reset, 01=FFFA NMI, 11=FFFE IRQ/BRK

// --------------------------------------------------------------------
// States: one per bus cycle
// --------------------------------------------------------------------
localparam
    S_FETCH  = 6'd0,  S_T1     = 6'd1,  S_ZPI    = 6'd2,  S_ABSHI  = 6'd3,
    S_FIX    = 6'd4,  S_INDX0  = 6'd5,  S_INDXL  = 6'd6,  S_INDXH  = 6'd7,
    S_INDYL  = 6'd8,  S_INDYH  = 6'd9,  S_RD     = 6'd10, S_WR     = 6'd11,
    S_RMWRD  = 6'd12, S_RMWDW  = 6'd13, S_RMWWR  = 6'd14, S_BRT    = 6'd15,
    S_BRF    = 6'd16, S_PUSH   = 6'd17, S_PLINC  = 6'd18, S_PLRD   = 6'd19,
    S_JSRD   = 6'd20, S_JSRH   = 6'd21, S_JSRL   = 6'd22, S_JSRA   = 6'd23,
    S_RTSINC = 6'd24, S_RTSL   = 6'd25, S_RTSH   = 6'd26, S_RTSPC  = 6'd27,
    S_RTIINC = 6'd28, S_RTIP   = 6'd29, S_RTIL   = 6'd30, S_RTIH   = 6'd31,
    S_INTH   = 6'd32, S_INTL   = 6'd33, S_INTP   = 6'd34, S_VECL   = 6'd35,
    S_VECH   = 6'd36, S_INDL   = 6'd37, S_INDH   = 6'd38;

assign sync = (state == S_FETCH);

// --------------------------------------------------------------------
// Decoder: what does the opcode in IR ask for?
// --------------------------------------------------------------------
// Addressing modes
localparam M_IMP=4'd0, M_ACC=4'd1, M_IMM=4'd2, M_ZP=4'd3, M_ZPX=4'd4,
           M_ZPY=4'd5, M_ABS=4'd6, M_ABSX=4'd7, M_ABSY=4'd8, M_INDX=4'd9,
           M_INDY=4'd10, M_REL=4'd11, M_CTL=4'd12;   // CTL: stack/jump ops
// Kinds of memory access
localparam K_NONE=2'd0, K_READ=2'd1, K_WRITE=2'd2, K_RMW=2'd3;
// Operations
localparam
    OP_NOP=6'd0,  OP_LDA=6'd1,  OP_LDX=6'd2,  OP_LDY=6'd3,  OP_STA=6'd4,
    OP_STX=6'd5,  OP_STY=6'd6,  OP_ADC=6'd7,  OP_SBC=6'd8,  OP_AND=6'd9,
    OP_ORA=6'd10, OP_EOR=6'd11, OP_CMP=6'd12, OP_CPX=6'd13, OP_CPY=6'd14,
    OP_BIT=6'd15, OP_ASL=6'd16, OP_LSR=6'd17, OP_ROL=6'd18, OP_ROR=6'd19,
    OP_INC=6'd20, OP_DEC=6'd21, OP_INX=6'd22, OP_INY=6'd23, OP_DEX=6'd24,
    OP_DEY=6'd25, OP_TAX=6'd26, OP_TAY=6'd27, OP_TXA=6'd28, OP_TYA=6'd29,
    OP_TSX=6'd30, OP_TXS=6'd31, OP_CLC=6'd32, OP_SEC=6'd33, OP_CLI=6'd34,
    OP_SEI=6'd35, OP_CLV=6'd36, OP_CLD=6'd37, OP_SED=6'd38, OP_PLA=6'd39;

reg [3:0] mode;
reg [1:0] kind;
reg [5:0] op;

always @* begin
    mode = M_IMP; kind = K_NONE; op = OP_NOP;   // undocumented: 2-cycle NOP
    casez (ir)
    // ---- group 1: eight operations x eight addressing modes ----
    8'b???_???_01: begin
        case (ir[7:5])
            3'd0: op = OP_ORA;  3'd1: op = OP_AND;
            3'd2: op = OP_EOR;  3'd3: op = OP_ADC;
            3'd4: op = OP_STA;  3'd5: op = OP_LDA;
            3'd6: op = OP_CMP;  3'd7: op = OP_SBC;
        endcase
        case (ir[4:2])
            3'd0: mode = M_INDX; 3'd1: mode = M_ZP;
            3'd2: mode = M_IMM;  3'd3: mode = M_ABS;
            3'd4: mode = M_INDY; 3'd5: mode = M_ZPX;
            3'd6: mode = M_ABSY; 3'd7: mode = M_ABSX;
        endcase
        kind = (op == OP_STA) ? K_WRITE : K_READ;
        if (ir == 8'h89) begin op = OP_NOP; kind = K_NONE; end // no STA #imm
    end
    // ---- shifts and rotates ----
    8'h0A: begin op = OP_ASL; mode = M_ACC; end
    8'h2A: begin op = OP_ROL; mode = M_ACC; end
    8'h4A: begin op = OP_LSR; mode = M_ACC; end
    8'h6A: begin op = OP_ROR; mode = M_ACC; end
    8'h06, 8'h16, 8'h0E, 8'h1E,
    8'h26, 8'h36, 8'h2E, 8'h3E,
    8'h46, 8'h56, 8'h4E, 8'h5E,
    8'h66, 8'h76, 8'h6E, 8'h7E,
    8'hC6, 8'hD6, 8'hCE, 8'hDE,
    8'hE6, 8'hF6, 8'hEE, 8'hFE: begin
        kind = K_RMW;
        case (ir[7:5])
            3'd0: op = OP_ASL;  3'd1: op = OP_ROL;
            3'd2: op = OP_LSR;  3'd3: op = OP_ROR;
            3'd6: op = OP_DEC;  default: op = OP_INC;
        endcase
        case (ir[4:3])
            2'd0: mode = M_ZP;   2'd1: mode = M_ABS;
            2'd2: mode = M_ZPX;  2'd3: mode = M_ABSX;
        endcase
    end
    // ---- X and Y loads, stores and compares ----
    8'hA2: begin op = OP_LDX; mode = M_IMM;  kind = K_READ; end
    8'hA6: begin op = OP_LDX; mode = M_ZP;   kind = K_READ; end
    8'hB6: begin op = OP_LDX; mode = M_ZPY;  kind = K_READ; end
    8'hAE: begin op = OP_LDX; mode = M_ABS;  kind = K_READ; end
    8'hBE: begin op = OP_LDX; mode = M_ABSY; kind = K_READ; end
    8'hA0: begin op = OP_LDY; mode = M_IMM;  kind = K_READ; end
    8'hA4: begin op = OP_LDY; mode = M_ZP;   kind = K_READ; end
    8'hB4: begin op = OP_LDY; mode = M_ZPX;  kind = K_READ; end
    8'hAC: begin op = OP_LDY; mode = M_ABS;  kind = K_READ; end
    8'hBC: begin op = OP_LDY; mode = M_ABSX; kind = K_READ; end
    8'h86: begin op = OP_STX; mode = M_ZP;   kind = K_WRITE; end
    8'h96: begin op = OP_STX; mode = M_ZPY;  kind = K_WRITE; end
    8'h8E: begin op = OP_STX; mode = M_ABS;  kind = K_WRITE; end
    8'h84: begin op = OP_STY; mode = M_ZP;   kind = K_WRITE; end
    8'h94: begin op = OP_STY; mode = M_ZPX;  kind = K_WRITE; end
    8'h8C: begin op = OP_STY; mode = M_ABS;  kind = K_WRITE; end
    8'hE0: begin op = OP_CPX; mode = M_IMM;  kind = K_READ; end
    8'hE4: begin op = OP_CPX; mode = M_ZP;   kind = K_READ; end
    8'hEC: begin op = OP_CPX; mode = M_ABS;  kind = K_READ; end
    8'hC0: begin op = OP_CPY; mode = M_IMM;  kind = K_READ; end
    8'hC4: begin op = OP_CPY; mode = M_ZP;   kind = K_READ; end
    8'hCC: begin op = OP_CPY; mode = M_ABS;  kind = K_READ; end
    8'h24: begin op = OP_BIT; mode = M_ZP;   kind = K_READ; end
    8'h2C: begin op = OP_BIT; mode = M_ABS;  kind = K_READ; end
    // ---- branches: xxy10000 ----
    8'b???1_0000: mode = M_REL;
    // ---- one-byte instructions ----
    8'h18: op = OP_CLC;  8'h38: op = OP_SEC;  8'h58: op = OP_CLI;
    8'h78: op = OP_SEI;  8'hB8: op = OP_CLV;  8'hD8: op = OP_CLD;
    8'hF8: op = OP_SED;  8'hAA: op = OP_TAX;  8'hA8: op = OP_TAY;
    8'h8A: op = OP_TXA;  8'h98: op = OP_TYA;  8'hBA: op = OP_TSX;
    8'h9A: op = OP_TXS;  8'hE8: op = OP_INX;  8'hC8: op = OP_INY;
    8'hCA: op = OP_DEX;  8'h88: op = OP_DEY;  8'hEA: op = OP_NOP;
    // ---- stack, jumps and interrupts ----
    8'h00, 8'h20, 8'h40, 8'h60, 8'h08, 8'h28, 8'h48, 8'h68:
        mode = M_CTL;
    8'h4C, 8'h6C: mode = M_CTL;
    default: ;
    endcase
end

// Index register used by this addressing mode
wire [7:0] idx = (mode == M_ZPY || mode == M_ABSY || mode == M_INDY) ? y : x;

// Status register as a byte; bit 5 always reads 1, bit 4 is B
wire [7:0] p_byte = {fn, fv, 1'b1, 1'b0, fd, fi, fz, fc};

// The first state of the execute phase for this kind of access
function [5:0] exec_state(input [1:0] k);
    case (k)
        K_WRITE: exec_state = S_WR;
        K_RMW:   exec_state = S_RMWRD;
        default: exec_state = S_RD;
    endcase
endfunction

// Branch condition: bits 7:6 pick the flag, bit 5 the value wanted
reg br_flag;
always @* begin
    case (ir[7:6])
        2'd0: br_flag = fn;
        2'd1: br_flag = fv;
        2'd2: br_flag = fc;
        2'd3: br_flag = fz;
    endcase
end
wire br_take = (br_flag == ir[5]);

// --------------------------------------------------------------------
// The ALU: computes new register and flag values for `op`
// --------------------------------------------------------------------
wire [7:0] alu_m = (state == S_RMWDW) ? data : din;  // the operand
wire [7:0] na, nx, ny, ns, nm;
wire       nn, nv, nd, ni, nz, nc;

alu6502 u_alu (
    .op(op), .acc_mode(mode == M_ACC),
    .a(a), .x(x), .y(y), .s(s), .m(alu_m),
    .fn(fn), .fv(fv), .fd(fd), .fi(fi), .fz(fz), .fc(fc),
    .na(na), .nx(nx), .ny(ny), .ns(ns), .nm(nm),
    .nn(nn), .nv(nv), .nd(nd), .ni(ni), .nz(nz), .nc(nc)
);

// Apply the ALU result in the cycle that completes the operation
wire exec_now = (state == S_T1 && (mode == M_IMP || mode == M_ACC || mode == M_IMM))
             || (state == S_RD)
             || (state == S_RMWDW);

// --------------------------------------------------------------------
// Bus outputs for the current cycle (combinational)
// --------------------------------------------------------------------
always @* begin
    we   = 1'b0;
    dout = 8'h00;
    ab   = pc;
    case (state)
        S_FETCH, S_T1, S_ABSHI, S_BRT, S_JSRA, S_RTSPC: ab = pc;
        S_ZPI:   ab = {8'h00, adl};
        S_FIX:   ab = {adh, adl};
        S_INDX0, S_INDXL, S_INDXH, S_INDYL, S_INDYH: ab = {8'h00, bal};
        S_RD, S_RMWRD: ab = {adh, adl};
        S_WR: begin
            ab = {adh, adl}; we = 1'b1;
            dout = (op == OP_STX) ? x : (op == OP_STY) ? y : a;
        end
        S_RMWDW, S_RMWWR: begin ab = {adh, adl}; we = 1'b1; dout = data; end
        S_BRF:   ab = {pc[15:8], pc[7:0]};
        S_PUSH: begin
            ab = {8'h01, s}; we = 1'b1;
            dout = (ir == 8'h48) ? a : (p_byte | 8'h10);   // PHP pushes B=1
        end
        S_PLINC, S_PLRD, S_JSRD, S_RTSINC, S_RTSL, S_RTSH,
        S_RTIINC, S_RTIP, S_RTIL, S_RTIH: ab = {8'h01, s};
        S_JSRH: begin ab = {8'h01, s}; we = 1'b1; dout = pc[15:8]; end
        S_JSRL: begin ab = {8'h01, s}; we = 1'b1; dout = pc[7:0];  end
        S_INTH: begin ab = {8'h01, s}; we = !rst_seq; dout = pc[15:8]; end
        S_INTL: begin ab = {8'h01, s}; we = !rst_seq; dout = pc[7:0];  end
        S_INTP: begin
            ab = {8'h01, s}; we = !rst_seq;
            dout = p_byte | (forced ? 8'h00 : 8'h10);   // B=1 only for BRK
        end
        S_VECL:  ab = {13'h1FFF, vec, 1'b0};
        S_VECH:  ab = {13'h1FFF, vec, 1'b1};
        S_INDL:  ab = {adh, adl};
        S_INDH:  ab = {adh, adl + 8'd1};  // the famous page-wrap bug
        default: ab = pc;
    endcase
end

// Index addition with carry, used by the absolute indexed modes
wire [8:0] adl_idx = {1'b0, adl} + {1'b0, idx};
wire [8:0] din_idx = {1'b0, din} + {1'b0, idx};
// Branch target, low byte
wire [8:0] br_sum  = {1'b0, pc[7:0]} + {1'b0, data};
// The polled interrupt request at the end of an instruction
wire want_int = nmi_flag | (!irq_n && !fi);

// --------------------------------------------------------------------
// The state machine
// --------------------------------------------------------------------
reg [5:0] next;

always @(posedge clk) begin
    if (rst) begin
        state    <= S_FETCH;
        int_pend <= 1'b1;
        rst_seq  <= 1'b1;
        forced   <= 1'b0;
        fi       <= 1'b1;
        s        <= 8'h00;
        nmi_old  <= 1'b1;
        nmi_flag <= 1'b0;
        pc       <= 16'h0000;
        ir       <= 8'h00;
    end else if (ce) begin
        // NMI is edge-triggered: remember a falling edge until it is served
        nmi_old <= nmi_n;
        if (nmi_old && !nmi_n) nmi_flag <= 1'b1;

        // Registers and flags from the ALU
        if (exec_now) begin
            a <= na; x <= nx; y <= ny; s <= ns;
            fn <= nn; fv <= nv; fd <= nd; fi <= ni; fz <= nz; fc <= nc;
        end

        next = S_FETCH;
        case (state)
        // ---------------- cycle 1: fetch the opcode ----------------
        S_FETCH: begin
            if (int_pend) begin
                ir <= 8'h00;          // run BRK's sequence for the interrupt
                forced <= 1'b1;
            end else begin
                ir <= din;
                forced <= 1'b0;
                pc <= pc + 16'd1;
            end
            next = S_T1;
        end
        // ---------------- cycle 2: read the byte after the opcode ---
        S_T1: begin
            case (mode)
            M_IMP, M_ACC: next = S_FETCH;
            M_IMM: begin pc <= pc + 16'd1; next = S_FETCH; end
            M_ZP:  begin adl <= din; adh <= 8'h00; pc <= pc + 16'd1;
                         next = exec_state(kind); end
            M_ZPX, M_ZPY: begin adl <= din; adh <= 8'h00; pc <= pc + 16'd1;
                         next = S_ZPI; end
            M_ABS, M_ABSX, M_ABSY: begin adl <= din; pc <= pc + 16'd1;
                         next = S_ABSHI; end
            M_INDX: begin bal <= din; pc <= pc + 16'd1; next = S_INDX0; end
            M_INDY: begin bal <= din; pc <= pc + 16'd1; next = S_INDYL; end
            M_REL: begin
                data <= din; pc <= pc + 16'd1;
                next = br_take ? S_BRT : S_FETCH;
            end
            M_CTL: case (ir)
                8'h00: begin                         // BRK / interrupt
                    if (!forced) pc <= pc + 16'd1;   // skip the signature byte
                    next = S_INTH;
                end
                8'h20: begin adl <= din; pc <= pc + 16'd1; next = S_JSRD; end
                8'h40: next = S_RTIINC;
                8'h60: next = S_RTSINC;
                8'h08, 8'h48: next = S_PUSH;
                8'h28, 8'h68: next = S_PLINC;
                default: begin adl <= din; pc <= pc + 16'd1; next = S_ABSHI; end // JMP
            endcase
            default: next = S_FETCH;
            endcase
        end
        // ---------------- address building ----------------
        S_ZPI: begin adl <= adl + idx; next = exec_state(kind); end
        S_ABSHI: begin
            pc <= pc + 16'd1;
            if (ir == 8'h4C) begin                    // JMP abs
                pc <= {din, adl}; next = S_FETCH;
            end else if (ir == 8'h6C) begin           // JMP (ind)
                adh <= din; next = S_INDL;
            end else if (mode == M_ABS) begin
                adh <= din; next = exec_state(kind);
            end else begin                            // abs,X / abs,Y
                adh <= din;
                adl <= adl_idx[7:0];
                cry <= adl_idx[8];
                next = (adl_idx[8] || kind != K_READ) ? S_FIX : exec_state(kind);
            end
        end
        S_FIX:   begin adh <= adh + {7'd0, cry}; next = exec_state(kind); end
        S_INDX0: begin bal <= bal + x; next = S_INDXL; end
        S_INDXL: begin adl <= din; bal <= bal + 8'd1; next = S_INDXH; end
        S_INDXH: begin adh <= din; next = exec_state(kind); end
        S_INDYL: begin adl <= din; bal <= bal + 8'd1; next = S_INDYH; end
        S_INDYH: begin
            adh <= din;
            adl <= adl_idx[7:0];
            cry <= adl_idx[8];
            next = (adl_idx[8] || kind != K_READ) ? S_FIX : exec_state(kind);
        end
        // ---------------- execute ----------------
        S_RD:    next = S_FETCH;                      // ALU applied above
        S_WR:    next = S_FETCH;
        S_RMWRD: begin data <= din; next = S_RMWDW; end
        S_RMWDW: begin data <= nm;  next = S_RMWWR; end  // writes old value back
        S_RMWWR: next = S_FETCH;
        // ---------------- branches ----------------
        S_BRT: begin
            pc[7:0] <= br_sum[7:0];
            // crossing a page costs one more cycle
            if (br_sum[8] != data[7]) next = S_BRF;
            else next = S_FETCH;
        end
        S_BRF: begin
            pc[15:8] <= data[7] ? pc[15:8] - 8'd1 : pc[15:8] + 8'd1;
            next = S_FETCH;
        end
        // ---------------- stack ----------------
        S_PUSH:  begin s <= s - 8'd1; next = S_FETCH; end
        S_PLINC: begin s <= s + 8'd1; next = S_PLRD; end
        S_PLRD: begin
            if (ir == 8'h68) begin
                a <= din; fn <= din[7]; fz <= (din == 8'h00);
            end else begin
                {fn, fv} <= din[7:6]; {fd, fi, fz, fc} <= din[3:0];
            end
            next = S_FETCH;
        end
        S_JSRD:  next = S_JSRH;
        S_JSRH:  begin s <= s - 8'd1; next = S_JSRL; end
        S_JSRL:  begin s <= s - 8'd1; next = S_JSRA; end
        S_JSRA:  begin pc <= {din, adl}; next = S_FETCH; end
        S_RTSINC: begin s <= s + 8'd1; next = S_RTSL; end
        S_RTSL:  begin adl <= din; s <= s + 8'd1; next = S_RTSH; end
        S_RTSH:  begin pc <= {din, adl}; next = S_RTSPC; end
        S_RTSPC: begin pc <= pc + 16'd1; next = S_FETCH; end
        S_RTIINC: begin s <= s + 8'd1; next = S_RTIP; end
        S_RTIP: begin
            {fn, fv} <= din[7:6]; {fd, fi, fz, fc} <= din[3:0];
            s <= s + 8'd1; next = S_RTIL;
        end
        S_RTIL:  begin adl <= din; s <= s + 8'd1; next = S_RTIH; end
        S_RTIH:  begin pc <= {din, adl}; next = S_FETCH; end
        S_INDL:  begin data <= din; next = S_INDH; end
        S_INDH:  begin pc <= {din, data}; next = S_FETCH; end
        // ---------------- BRK, IRQ, NMI and RESET ----------------
        S_INTH:  begin s <= s - 8'd1; next = S_INTL; end
        S_INTL:  begin s <= s - 8'd1; next = S_INTP; end
        S_INTP: begin
            s <= s - 8'd1;
            // choose the vector; a pending NMI wins over IRQ and BRK
            if (rst_seq)       vec <= 2'b10;          // FFFC
            else if (nmi_flag) begin vec <= 2'b01; nmi_flag <= 1'b0; end // FFFA
            else               vec <= 2'b11;          // FFFE
            next = S_VECL;
        end
        S_VECL:  begin adl <= din; fi <= 1'b1; next = S_VECH; end
        S_VECH:  begin pc <= {din, adl}; rst_seq <= 1'b0; next = S_FETCH; end
        default: next = S_FETCH;
        endcase

        // Poll interrupts during the last cycle of every instruction,
        // using the I flag as it was before this cycle.
        if (next == S_FETCH && state != S_FETCH)
            int_pend <= want_int;
        else if (state == S_FETCH)
            int_pend <= 1'b0;

        state <= next;
    end
end

endmodule

// alu6502.v - the arithmetic and logic of the 6502, as pure combinational logic.
//
// Build Your Own 6502 Computer on an FPGA - Adrian Velcourt
// License: MIT
//
// Given an operation, the registers, the flags and an operand byte `m`,
// it computes what the registers and flags become. The CPU decides when
// to keep the answer. `nm` is the result for read-modify-write
// instructions (shifts, INC and DEC on memory).

module alu6502 (
    input  wire [5:0] op,
    input  wire       acc_mode,    // shift the accumulator, not memory
    input  wire [7:0] a, x, y, s, m,
    input  wire       fn, fv, fd, fi, fz, fc,
    output reg  [7:0] na, nx, ny, ns, nm,
    output reg        nn, nv, nd, ni, nz, nc
);

// Same numbering as the decoder in cpu6502.v
localparam
    OP_NOP=6'd0,  OP_LDA=6'd1,  OP_LDX=6'd2,  OP_LDY=6'd3,  OP_STA=6'd4,
    OP_STX=6'd5,  OP_STY=6'd6,  OP_ADC=6'd7,  OP_SBC=6'd8,  OP_AND=6'd9,
    OP_ORA=6'd10, OP_EOR=6'd11, OP_CMP=6'd12, OP_CPX=6'd13, OP_CPY=6'd14,
    OP_BIT=6'd15, OP_ASL=6'd16, OP_LSR=6'd17, OP_ROL=6'd18, OP_ROR=6'd19,
    OP_INC=6'd20, OP_DEC=6'd21, OP_INX=6'd22, OP_INY=6'd23, OP_DEX=6'd24,
    OP_DEY=6'd25, OP_TAX=6'd26, OP_TAY=6'd27, OP_TXA=6'd28, OP_TYA=6'd29,
    OP_TSX=6'd30, OP_TXS=6'd31, OP_CLC=6'd32, OP_SEC=6'd33, OP_CLI=6'd34,
    OP_SEI=6'd35, OP_CLV=6'd36, OP_CLD=6'd37, OP_SED=6'd38;

// ---------------- binary add, used by ADC and SBC ----------------
// SBC is ADC of the inverted operand: A - M = A + ~M + 1 (C=1 means no borrow)
wire       is_sbc = (op == OP_SBC);
wire [7:0] addend = is_sbc ? ~m : m;
wire [8:0] bin    = {1'b0, a} + {1'b0, addend} + {8'd0, fc};
wire       bin_v  = (~(a[7] ^ addend[7])) & (a[7] ^ bin[7]);

// ---------------- decimal add (NMOS 6502) ----------------
// Low digit first; a digit above 9 is corrected by adding 6.
reg  [4:0] dal;        // low digit sum
reg  [8:0] dsum;       // sum before the high-digit correction
reg  [9:0] dadj;       // after the high-digit correction
always @* begin
    dal = {1'b0, a[3:0]} + {1'b0, m[3:0]} + {4'd0, fc};
    if (dal >= 5'd10) dal = ((dal + 5'd6) & 5'h0F) + 5'h10;
    dsum = {1'b0, a[7:4], 4'd0} + {1'b0, m[7:4], 4'd0} + {4'd0, dal};
    dadj = (dsum >= 9'h0A0) ? {1'b0, dsum} + 10'h060 : {1'b0, dsum};
end
// On the NMOS chip N and V come from the half-corrected sum
wire dadd_v = (~(a[7] ^ m[7])) & (a[7] ^ dsum[7]);

// ---------------- decimal subtract (NMOS 6502) ----------------
// Flags come from the binary subtraction; only the value is corrected.
integer sl, sh;
reg [7:0] dsub;
always @* begin
    sl = {28'd0, a[3:0]} - {28'd0, m[3:0]} + {31'd0, fc} - 1;
    if (sl < 0) sl = ((sl - 6) & 32'h0F) - 32'h10;
    sh = {24'd0, a[7:4], 4'd0} - {24'd0, m[7:4], 4'd0} + sl;
    if (sh < 0) sh = sh - 32'h60;
    dsub = sh[7:0];
end

// ---------------- compare: register minus operand ----------------
reg  [7:0] creg;
always @* case (op)
    OP_CPX:  creg = x;
    OP_CPY:  creg = y;
    default: creg = a;
endcase
wire [8:0] cmp = {1'b0, creg} - {1'b0, m};

// ---------------- the operation itself ----------------
reg [7:0] sh_in;   // what a shift works on
always @* begin
    // by default nothing changes
    na = a; nx = x; ny = y; ns = s; nm = m;
    nn = fn; nv = fv; nd = fd; ni = fi; nz = fz; nc = fc;
    sh_in = acc_mode ? a : m;

    case (op)
    OP_LDA: begin na = m; nn = m[7]; nz = (m == 8'd0); end
    OP_LDX: begin nx = m; nn = m[7]; nz = (m == 8'd0); end
    OP_LDY: begin ny = m; nn = m[7]; nz = (m == 8'd0); end
    OP_AND: begin na = a & m; nn = na[7]; nz = (na == 8'd0); end
    OP_ORA: begin na = a | m; nn = na[7]; nz = (na == 8'd0); end
    OP_EOR: begin na = a ^ m; nn = na[7]; nz = (na == 8'd0); end
    OP_ADC: begin
        if (fd) begin
            na = dadj[7:0];
            nc = (dadj > 10'h0FF);
            nn = dsum[7];
            nv = dadd_v;
            nz = (bin[7:0] == 8'd0);
        end else begin
            na = bin[7:0]; nc = bin[8]; nv = bin_v;
            nn = bin[7]; nz = (bin[7:0] == 8'd0);
        end
    end
    OP_SBC: begin
        na = fd ? dsub : bin[7:0];
        nc = bin[8]; nv = bin_v;
        nn = bin[7]; nz = (bin[7:0] == 8'd0);
    end
    OP_CMP, OP_CPX, OP_CPY: begin
        nc = ~cmp[8]; nn = cmp[7]; nz = (cmp[7:0] == 8'd0);
    end
    OP_BIT: begin nz = ((a & m) == 8'd0); nn = m[7]; nv = m[6]; end
    OP_ASL: begin
        nc = sh_in[7];
        if (acc_mode) na = {sh_in[6:0], 1'b0}; else nm = {sh_in[6:0], 1'b0};
    end
    OP_LSR: begin
        nc = sh_in[0];
        if (acc_mode) na = {1'b0, sh_in[7:1]}; else nm = {1'b0, sh_in[7:1]};
    end
    OP_ROL: begin
        nc = sh_in[7];
        if (acc_mode) na = {sh_in[6:0], fc}; else nm = {sh_in[6:0], fc};
    end
    OP_ROR: begin
        nc = sh_in[0];
        if (acc_mode) na = {fc, sh_in[7:1]}; else nm = {fc, sh_in[7:1]};
    end
    OP_INC: nm = m + 8'd1;
    OP_DEC: nm = m - 8'd1;
    OP_INX: nx = x + 8'd1;
    OP_INY: ny = y + 8'd1;
    OP_DEX: nx = x - 8'd1;
    OP_DEY: ny = y - 8'd1;
    OP_TAX: nx = a;
    OP_TAY: ny = a;
    OP_TXA: na = x;
    OP_TYA: na = y;
    OP_TSX: nx = s;
    OP_TXS: ns = x;              // the only transfer that leaves N and Z alone
    OP_CLC: nc = 1'b0;
    OP_SEC: nc = 1'b1;
    OP_CLI: ni = 1'b0;
    OP_SEI: ni = 1'b1;
    OP_CLV: nv = 1'b0;
    OP_CLD: nd = 1'b0;
    OP_SED: nd = 1'b1;
    default: ;
    endcase

    // N and Z follow the result for shifts, INC/DEC and transfers
    case (op)
    OP_ASL, OP_LSR, OP_ROL, OP_ROR: begin
        nn = acc_mode ? na[7] : nm[7];
        nz = acc_mode ? (na == 8'd0) : (nm == 8'd0);
    end
    OP_INC, OP_DEC: begin nn = nm[7]; nz = (nm == 8'd0); end
    OP_INX, OP_DEX, OP_TAX, OP_TSX: begin nn = nx[7]; nz = (nx == 8'd0); end
    OP_INY, OP_DEY, OP_TAY: begin nn = ny[7]; nz = (ny == 8'd0); end
    OP_TXA, OP_TYA: begin nn = na[7]; nz = (na == 8'd0); end
    default: ;
    endcase
end

endmodule

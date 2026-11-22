// sim_soc.cpp - the whole computer in Verilator, with a screen, a serial
// terminal, a PS/2 keyboard, an SD card and a speaker made of C++.
//
// Build Your Own 6502 Computer on an FPGA - Adrian Velcourt.  MIT licence.
//
// Usage: sim_soc SCRIPT [SDIMAGE]
// The script is a list of commands, one per line:
//   expect TEXT       run until the serial output contains TEXT
//   send TEXT         type TEXT on the serial line (\r = Return)
//   ps2 TEXT          type TEXT on the PS/2 keyboard
//   wait MS           run for MS milliseconds
//   frame FILE.ppm    save the next complete video frame
//   wav FILE.wav MS   record MS milliseconds of sound
//   button MS         hold the S2 button for MS milliseconds
//   reset [S2]        reset the computer (holding S2 starts the monitor)
//   quit
#include "Vsoc.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include <deque>

static Vsoc* top;
static unsigned long long clk_count = 0;
static const double CLK_HZ = 25.2e6;
static const int UART_DIV = 219;

// ------------------------------------------------------------ serial
static std::string serial_out;          // everything the computer sent
static size_t expect_from = 0;
static int tx_state = 0, tx_cnt = 0, tx_bits = 0, tx_byte = 0, tx_prev = 1;
static std::deque<int> rx_queue;        // bytes waiting to be typed
static std::vector<int> rx_wave;        // pin levels, one per clock, being sent
static size_t rx_pos = 0;

static void serial_clock() {
    // receive what the computer transmits, sampling in the middle of each bit
    int tx = top->uart_tx;
    if (tx_state == 0) {                                  // idle: wait for a start bit
        if (tx_prev == 1 && tx == 0) { tx_state = 1; tx_cnt = UART_DIV / 2; }
    } else if (--tx_cnt == 0) {
        tx_cnt = UART_DIV;
        if (tx_state == 1) { tx_state = tx == 0 ? 2 : 0; tx_bits = 0; tx_byte = 0; }   // middle of start bit
        else if (tx_bits < 8) { tx_byte |= tx << tx_bits; tx_bits++; }
        else {                                            // stop bit: the byte is complete
            tx_state = 0; serial_out += (char)tx_byte;
            if (tx_byte != '\n') putchar(tx_byte == '\r' ? '\n' : tx_byte); fflush(stdout);
        }
    }
    tx_prev = tx;
    // send what the script types: a byte every 12 bit times
    if (rx_pos >= rx_wave.size() && !rx_queue.empty()) {
        int b = rx_queue.front(); rx_queue.pop_front();
        if (getenv("DBG_UART")) printf("{SEND %02X @%.6f}", b, clk_count / CLK_HZ);
        rx_wave.clear(); rx_pos = 0;
        int bits[12] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1};
        for (int i = 0; i < 8; i++) bits[1 + i] = (b >> i) & 1;
        for (int i = 0; i < 12; i++) for (int k = 0; k < UART_DIV; k++) rx_wave.push_back(bits[i]);
    }
    top->uart_rx = rx_pos < rx_wave.size() ? rx_wave[rx_pos++] : 1;
}

// ------------------------------------------------------------ PS/2 keyboard
static std::vector<std::pair<int,int>> ps2_wave;  // (clk, dat) per system clock
static size_t ps2_pos = 0;
static std::deque<int> ps2_codes;
static void ps2_frame(int code) {
    // 11 bits, ~12.5 kHz keyboard clock: 1000 system clocks per half period
    int bits[11]; bits[0] = 0; int par = 1;
    for (int i = 0; i < 8; i++) { bits[1 + i] = (code >> i) & 1; par ^= bits[1 + i]; }
    bits[9] = par; bits[10] = 1;
    for (int i = 0; i < 11; i++) {
        for (int k = 0; k < 1000; k++) ps2_wave.push_back({1, bits[i]});   // clock high, data set
        for (int k = 0; k < 1000; k++) ps2_wave.push_back({0, bits[i]});   // falling edge: keyboard's bit
    }
    for (int k = 0; k < 20000; k++) ps2_wave.push_back({1, 1});           // gap between codes
}
static void ps2_type(const std::string& s) {
    static const char* lower = "abcdefghijklmnopqrstuvwxyz";
    static const int letters[26] = {0x1C,0x32,0x21,0x23,0x24,0x2B,0x34,0x33,0x43,0x3B,0x42,0x4B,0x3A,
                                    0x31,0x44,0x4D,0x15,0x2D,0x1B,0x2C,0x3C,0x2A,0x1D,0x22,0x35,0x1A};
    static const int digits[10] = {0x45,0x16,0x1E,0x26,0x25,0x2E,0x36,0x3D,0x3E,0x46};
    for (char c : s) {
        int code = -1, shift = 0;
        if (c >= 'a' && c <= 'z') code = letters[c - 'a'];
        else if (c >= 'A' && c <= 'Z') { code = letters[c - 'A']; shift = 1; }
        else if (c >= '0' && c <= '9') code = digits[c - '0'];
        else switch (c) {
            case ' ': code = 0x29; break;  case '\r': code = 0x5A; break;
            case '"': code = 0x52; shift = 1; break;  case ',': code = 0x41; break;
            case '=': code = 0x55; break;  case '+': code = 0x55; shift = 1; break;
            case ':': code = 0x4C; shift = 1; break;  case ';': code = 0x4C; break;
            case '(': code = 0x46; shift = 1; break;  case ')': code = 0x45; shift = 1; break;
            case '*': code = 0x3E; shift = 1; break;  case '-': code = 0x4E; break;
            case '/': code = 0x4A; break;  case '.': code = 0x49; break;
            case '$': code = 0x25; shift = 1; break;  case '<': code = 0x41; shift = 1; break;
            case '>': code = 0x49; shift = 1; break;  case '\b': code = 0x66; break;
        }
        if (code < 0) continue;
        if (shift) ps2_codes.push_back(0x12);
        ps2_codes.push_back(code); ps2_codes.push_back(0xF0); ps2_codes.push_back(code);
        if (shift) { ps2_codes.push_back(0xF0); ps2_codes.push_back(0x12); }
    }
}
static void ps2_clock() {
    if (ps2_pos >= ps2_wave.size()) {
        ps2_wave.clear(); ps2_pos = 0;
        if (!ps2_codes.empty()) { ps2_frame(ps2_codes.front()); ps2_codes.pop_front(); }
    }
    if (ps2_pos < ps2_wave.size()) { top->ps2_clk = ps2_wave[ps2_pos].first; top->ps2_dat = ps2_wave[ps2_pos].second; ps2_pos++; }
    else { top->ps2_clk = 1; top->ps2_dat = 1; }
}

// ------------------------------------------------------------ SD card (SDHC, SPI mode)
static FILE* sd_file = nullptr;
static int sd_prev_sck = 0, sd_bitcnt = 0, sd_in = 0, sd_out = 0xFF;
static std::deque<int> sd_reply;
static std::vector<int> sd_cmdbuf;
static bool sd_idle = true, sd_app = false;
static int sd_wr_state = 0; static long sd_wr_lba = 0; static std::vector<unsigned char> sd_wr_buf;
static void sd_byte_received(int b) {
    if (sd_wr_state == 1) {                    // waiting for the data token
        if (b == 0xFE) { sd_wr_state = 2; sd_wr_buf.clear(); }
        return;
    }
    if (sd_wr_state == 2) {
        sd_wr_buf.push_back(b);
        if (sd_wr_buf.size() == 514) {          // 512 data + 2 CRC
            fseek(sd_file, sd_wr_lba * 512, SEEK_SET); fwrite(sd_wr_buf.data(), 1, 512, sd_file); fflush(sd_file);
            sd_reply.push_back(0x05);           // data accepted
            for (int i = 0; i < 8; i++) sd_reply.push_back(0x00);   // busy for a while
            sd_wr_state = 0;
        }
        return;
    }
    if (sd_cmdbuf.empty() && (b & 0xC0) != 0x40) return;
    sd_cmdbuf.push_back(b);
    if (sd_cmdbuf.size() < 6) return;
    int cmd = sd_cmdbuf[0] & 0x3F;
    unsigned long arg = (unsigned long)sd_cmdbuf[1] << 24 | sd_cmdbuf[2] << 16 | sd_cmdbuf[3] << 8 | sd_cmdbuf[4];
    sd_cmdbuf.clear();
    sd_reply.push_back(0xFF);                   // one byte of delay, like real cards
    int r1 = sd_idle ? 1 : 0;
    if (sd_app && cmd == 41) { sd_idle = false; sd_reply.push_back(0); sd_app = false; return; }
    sd_app = false;
    switch (cmd) {
        case 0:  sd_idle = true; sd_reply.push_back(1); break;
        case 8:  sd_reply.push_back(r1); sd_reply.push_back(0); sd_reply.push_back(0);
                 sd_reply.push_back(1); sd_reply.push_back(arg & 0xFF); break;
        case 55: sd_app = true; sd_reply.push_back(r1); break;
        case 58: sd_reply.push_back(r1); sd_reply.push_back(0xC0); sd_reply.push_back(0xFF);
                 sd_reply.push_back(0x80); sd_reply.push_back(0x00); break;   // CCS=1: SDHC
        case 16: sd_reply.push_back(r1); break;
        case 17: {
            unsigned char buf[512] = {0};
            fseek(sd_file, arg * 512, SEEK_SET); fread(buf, 1, 512, sd_file);
            sd_reply.push_back(0); sd_reply.push_back(0xFF); sd_reply.push_back(0xFE);
            for (int i = 0; i < 512; i++) sd_reply.push_back(buf[i]);
            sd_reply.push_back(0x12); sd_reply.push_back(0x34); break;
        }
        case 24: sd_reply.push_back(0); sd_wr_state = 1; sd_wr_lba = arg; break;
        default: sd_reply.push_back(0x04); break;               // illegal command
    }
}
static void sd_clock() {
    if (!sd_file) { top->sd_miso = 1; return; }
    int sck = top->sd_sck;
    if (top->sd_cs_n) { sd_bitcnt = 0; sd_prev_sck = sck; top->sd_miso = 1; return; }
    if (!sd_prev_sck && sck) {                  // rising edge: sample MOSI
        sd_in = (sd_in << 1) | top->sd_mosi;
        if (++sd_bitcnt == 8) { sd_bitcnt = 0; sd_byte_received(sd_in & 0xFF); }
    }
    if (sd_prev_sck && !sck) {                  // falling edge: next MISO bit
        if (sd_bitcnt == 0) { sd_out = sd_reply.empty() ? 0xFF : sd_reply.front(); if (!sd_reply.empty()) sd_reply.pop_front(); }
    }
    top->sd_miso = (sd_out >> (7 - sd_bitcnt)) & 1;
    sd_prev_sck = sck;
}

// ------------------------------------------------------------ video
static std::vector<unsigned char> frame(640 * 480 * 3);
static int vx = 0, vy = 0, prev_hs = 1, prev_vs = 1, prev_de = 0;
static bool want_frame = false, capturing = false; static std::string frame_name;
static void video_clock() {
    if (top->de) {
        if (vx < 640 && vy < 480) {
            unsigned char* p = &frame[(vy * 640 + vx) * 3];
            p[0] = top->r; p[1] = top->g; p[2] = top->b;
        }
        vx++;
    }
    if (prev_de && !top->de) { vx = 0; vy++; }
    if (prev_vs && !top->vs) {                  // start of vertical sync: frame done
        if (capturing) {
            FILE* f = fopen(frame_name.c_str(), "wb");
            fprintf(f, "P6\n640 480\n255\n"); fwrite(frame.data(), 1, frame.size(), f); fclose(f);
            printf("\n[saved %s]\n", frame_name.c_str()); capturing = false; want_frame = false;
        }
        if (want_frame) capturing = true;
        vy = 0; vx = 0;
    }
    prev_de = top->de; prev_hs = top->hs; prev_vs = top->vs;
}

// ------------------------------------------------------------ sound
static FILE* wav = nullptr; static long wav_samples = 0, wav_left = 0;
static void wav_header(FILE* f, long n) {
    long rate = 49219, bytes = n * 2;
    fseek(f, 0, SEEK_SET);
    fwrite("RIFF", 1, 4, f); int v = 36 + bytes; fwrite(&v, 4, 1, f); fwrite("WAVEfmt ", 1, 8, f);
    v = 16; fwrite(&v, 4, 1, f); short s = 1; fwrite(&s, 2, 1, f); fwrite(&s, 2, 1, f);
    v = rate; fwrite(&v, 4, 1, f); v = rate * 2; fwrite(&v, 4, 1, f); s = 2; fwrite(&s, 2, 1, f);
    s = 16; fwrite(&s, 2, 1, f); fwrite("data", 1, 4, f); v = bytes; fwrite(&v, 4, 1, f);
}
static void audio_clock() {
    if (wav && top->sample_tick) {
        short s = (short)top->sample; fwrite(&s, 2, 1, wav); wav_samples++;
        if (--wav_left == 0) { wav_header(wav, wav_samples); fclose(wav); wav = nullptr; printf("\n[wav saved]\n"); }
    }
}

// ------------------------------------------------------------ the clock
static void tick() {
    top->clk = 0; top->eval();
    serial_clock(); ps2_clock(); sd_clock();
    static int dbg = getenv("DBG_UART") != nullptr;
    if (dbg && top->dbg_ce && ((top->dbg_ab & 0xFFF0) == 0xBF00 || top->dbg_ab == 0xBF11))
        printf("{%04X we=%d din=%02X @%.6f}", top->dbg_ab, top->dbg_we, top->dbg_din, clk_count / CLK_HZ);
    top->clk = 1; top->eval();
    video_clock(); audio_clock();
    clk_count++;
}
static void run_ms(double ms) { unsigned long long n = (unsigned long long)(ms * CLK_HZ / 1000); for (unsigned long long i = 0; i < n; i++) tick(); }

static std::string unescape(const std::string& s) {
    std::string o;
    for (size_t i = 0; i < s.size(); i++) {
        if (s[i] == '\\' && i + 1 < s.size()) { char n = s[++i]; o += n == 'r' ? '\r' : n == 'n' ? '\n' : n == 'b' ? '\b' : n == 'q' ? '"' : n; }
        else o += s[i];
    }
    return o;
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    top = new Vsoc;
    if (argc > 2) { sd_file = fopen(argv[2], "r+b"); if (!sd_file) { sd_file = fopen(argv[2], "w+b"); } }
    top->button = 0; top->uart_rx = 1; top->ps2_clk = 1; top->ps2_dat = 1; top->sd_miso = 1;
    top->rst = 1; for (int i = 0; i < 10; i++) tick(); top->rst = 0;
    FILE* sc = fopen(argv[1], "r");
    char line[1024];
    while (fgets(line, sizeof line, sc)) {
        std::string l(line); while (!l.empty() && (l.back() == '\n' || l.back() == '\r')) l.pop_back();
        if (l.empty() || l[0] == '#') continue;
        std::string cmd = l.substr(0, l.find(' ')), arg = l.find(' ') == std::string::npos ? "" : l.substr(l.find(' ') + 1);
        if (cmd == "expect") {
            std::string want = unescape(arg); double t0 = clk_count / CLK_HZ;
            while (serial_out.find(want, expect_from) == std::string::npos) {
                tick();
                if (clk_count / CLK_HZ - t0 > 60) { printf("\n[TIMEOUT waiting for '%s']\n", arg.c_str()); return 1; }
            }
            expect_from = serial_out.find(want, expect_from) + want.size();
        } else if (cmd == "send") { for (char c : unescape(arg)) rx_queue.push_back((unsigned char)c);
            while (!rx_queue.empty() || rx_pos < rx_wave.size()) tick();
        } else if (cmd == "ps2") { ps2_type(unescape(arg)); while (!ps2_codes.empty() || ps2_pos < ps2_wave.size()) tick();
        } else if (cmd == "wait") run_ms(atof(arg.c_str()));
        else if (cmd == "frame") { frame_name = arg; want_frame = true; while (want_frame) tick();
        } else if (cmd == "wav") {
            char name[512]; double ms; sscanf(arg.c_str(), "%511s %lf", name, &ms);
            wav = fopen(name, "wb"); wav_header(wav, 0); wav_samples = 0; wav_left = (long)(ms * 49.219);
            while (wav) tick();
        } else if (cmd == "button") { top->button = 1; run_ms(atof(arg.c_str())); top->button = 0;
        } else if (cmd == "reset") {           // press the reset button (S2 may be held too)
            top->button = arg == "S2" ? 1 : 0;
            top->rst = 1; for (int i = 0; i < 10; i++) tick(); top->rst = 0;
            run_ms(50); top->button = 0;
        } else if (cmd == "quit") break;
        else printf("unknown script command %s\n", cmd.c_str());
    }
    printf("\n[simulated %.3f s]\n", clk_count / CLK_HZ);
    if (sd_file) fclose(sd_file);
    delete top;
    return 0;
}

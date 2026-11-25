// sim_ocean: the Ocean-240.2 machine (tb_ocean, verilator) with a terminal on its 8251 and frames as PPM.
//   --rom0 F[:patch,..]  ROM0 (DD1, E000) image, 8 KB repeated to 32 KB; patches OFF=XX (hex, offset in the file)
//   --rom1 F             ROM1 (DD2, C000)
//   --ms N               run time
//   --frames PREFIX      PREFIX_N.ppm: 768 x 320 of the raster as the schematic model writes them (src/sim/schem)
//   --rxkey MS:XX        a byte to the RS-232 input at MS
//   --type MS:TEXT       keys from MS on (PS/2 scancodes into ocean_kbd, a key every 100 ms; letters, digits, space;
//                        '\\n' or '|' = Enter)
//   --model N            0 240.2, 1 Turbo, 2 test (the ROMs still from --rom0 / --rom1)
//   --mpss               the colours of MPSS
//   --frame2x PREFIX     PREFIX_N.ppm: the HDMI frames of ocean_scan2x (640 x 576, de)
//   --expect-tx TEXT     fail unless the terminal output has TEXT
//   --peek ADDR          print the SRAM byte at the end (hex address)
//   --iotrace N          print the first N port accesses (OUT always, IN except the polls of 41 / 80 / A1)
//   --vram               at the end: the non-zero bytes of the video RAM (C000-FFFF of pages 0 / 1)
#include "Vtb_ocean.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

static const double CLK_HZ = 49152000.0;

// PS/2 set 2 scancodes of the keys --type knows
static int scancode(char c) {
	const char *L = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
	static const int SL[26] = {0x1C,0x32,0x21,0x23,0x24,0x2B,0x34,0x33,0x43,0x3B,0x42,0x4B,0x3A,0x31,0x44,0x4D,0x15,0x2D,0x1B,0x2C,0x3C,0x2A,0x1D,0x22,0x35,0x1A};
	static const int SD[10] = {0x45,0x16,0x1E,0x26,0x25,0x2E,0x36,0x3D,0x3E,0x46};
	if (c >= 'a' && c <= 'z') c -= 32;
	const char *p = strchr(L, c);
	if (c && p) return SL[p - L];
	if (c >= '0' && c <= '9') return SD[c - '0'];
	if (c == ' ') return 0x29;
	if (c == '|' || c == '\n') return 0x5A;
	if (c == '.') return 0x49;
	return -1;
}

struct Ev { long long t; int b; };

static std::vector<unsigned char> load(const char *spec, std::vector<std::pair<int, int>> &patches) {
	std::string s(spec);
	size_t c = s.find(':');
	std::string fn = s.substr(0, c);
	if (c != std::string::npos) {
		std::string p = s.substr(c + 1);
		size_t pos = 0;
		while (pos < p.size()) {
			size_t e = p.find(',', pos);
			std::string one = p.substr(pos, e == std::string::npos ? std::string::npos : e - pos);
			size_t eq = one.find('=');
			patches.push_back({(int)strtol(one.substr(0, eq).c_str(), 0, 16), (int)strtol(one.substr(eq + 1).c_str(), 0, 16)});
			if (e == std::string::npos) break;
			pos = e + 1;
		}
	}
	FILE *f = fopen(fn.c_str(), "rb");
	if (!f) { fprintf(stderr, "no %s\n", fn.c_str()); exit(2); }
	std::vector<unsigned char> d(65536);
	size_t n = fread(d.data(), 1, d.size(), f);
	fclose(f);
	d.resize(n);
	return d;
}

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	Vtb_ocean *t = new Vtb_ocean;
	const char *rom0 = 0, *rom1 = 0, *frames = 0, *expect = 0;
	double ms = 20;
	std::vector<Ev> rx, kb;
	std::vector<long> peeks;
	int iotrace = 0, vram = 0, model = 0, mpss = 0;
	const char *frame2x = 0;
	for (int i = 1; i < argc; i++) {
		std::string a(argv[i]);
		if (a == "--rom0") rom0 = argv[++i];
		else if (a == "--rom1") rom1 = argv[++i];
		else if (a == "--ms") ms = atof(argv[++i]);
		else if (a == "--frames") frames = argv[++i];
		else if (a == "--expect-tx") expect = argv[++i];
		else if (a == "--peek") peeks.push_back(strtol(argv[++i], 0, 16));
		else if (a == "--iotrace") iotrace = atoi(argv[++i]);
		else if (a == "--vram") vram = 1;
		else if (a == "--rxkey") {
			const char *v = argv[++i];
			Ev e; e.t = (long long)(atof(v) * CLK_HZ / 1000.0); e.b = (int)strtol(strchr(v, ':') + 1, 0, 16);
			rx.push_back(e);
		}
		else if (a == "--type") {
			const char *v = argv[++i];
			double t0 = atof(v);
			const char *txt = strchr(v, ':') + 1;
			for (int j = 0; txt[j]; j++) {
				int sc = scancode(txt[j]);
				if (sc < 0) { fprintf(stderr, "no key for '%c'\n", txt[j]); exit(2); }
				long long t = (long long)((t0 + 100.0 * j) * CLK_HZ / 1000.0);
				kb.push_back({t, sc}); kb.push_back({t + 20000, 0xF0}); kb.push_back({t + 40000, sc});
			}
		}
		else if (a == "--model") model = atoi(argv[++i]);
		else if (a == "--mpss") mpss = 1;
		else if (a == "--frame2x") frame2x = argv[++i];
	}
	// preload the SRAM: ROM0 / ROM1 into the images the model takes (ocean_system: 080000 + 2000 * image), 8 KB each
	t->reset = 1; t->rxd = 1; t->ps2_wr = 0; t->ps2_code = 0; t->pl_we = 0; t->model = model; t->colour_mpss = mpss;
	auto tick = [&]() { t->clk = 0; t->eval(); t->clk = 1; t->eval(); };
	for (int r = 0; r < 2; r++) {
		const char *spec = r ? rom1 : rom0;
		if (!spec) continue;
		std::vector<std::pair<int, int>> patches;
		std::vector<unsigned char> d = load(spec, patches);
		for (auto &p : patches) d[p.first] = p.second;
		for (int a = 0; a < 8192; a++) {
			static const int img[3][2] = {{0, 1}, {2, 3}, {4, 1}};   // the images of each model (ocean_system)
			t->pl_we = 1; t->pl_addr = 0x080000 + img[model % 3][r] * 0x2000 + a; t->pl_data = d[a % d.size()];
			tick();
		}
	}
	t->pl_we = 0;
	for (int i = 0; i < 100; i++) tick();
	t->reset = 0;

	long long total = (long long)(ms * CLK_HZ / 1000.0);
	const int BIT = (int)(CLK_HZ / 4800.0 + 0.5);
	// terminal receiver (TXD) and transmitter (RXD)
	int rx_state = -1; long long rx_t = 0; int rx_byte = 0; int last_txd = 1;
	std::string term;
	size_t rx_i = 0; long long tx_start = -1; int tx_byte = 0;
	size_t kb_i = 0;
	// frames
	FILE *fd = 0; int nfr = 0, x = 0, y = 0, last_vs = 0, last_hs = 0;
	int last_iow = 0, last_ior = 0;
	FILE *f2 = 0; int n2 = 0, n2px = 0, last_ovs = 1;
	for (long long c = 0; c < total; c++) {
		tick();
		// RS-232 to the machine
		if (rx_i < rx.size() && c >= rx[rx_i].t && tx_start < 0) { tx_start = c; tx_byte = rx[rx_i].b; }
		if (tx_start >= 0) {
			long long k = (c - tx_start) / BIT;
			if (k == 0) t->rxd = 0;
			else if (k <= 8) t->rxd = (tx_byte >> (k - 1)) & 1;
			else t->rxd = 1;
			if (k >= 11) { tx_start = -1; printf("\n[sim] sent %02x at %.1f ms\n", tx_byte, rx[rx_i].t * 1000.0 / CLK_HZ); rx_i++; }
		}
		// the PS/2 bytes into ocean_kbd
		t->ps2_wr = 0;
		if (kb_i < kb.size() && c >= kb[kb_i].t) { t->ps2_code = kb[kb_i].b; t->ps2_wr = 1; kb_i++; }
		// the HDMI frames of ocean_scan2x: a file per falling vs, the de pixels
		if (frame2x && t->o_ce) {
			if (!t->o_vs && last_ovs) {
				if (f2) fclose(f2);
				char fn[512]; snprintf(fn, sizeof fn, "%s_%d.ppm", frame2x, n2++);
				f2 = fopen(fn, "wb"); fprintf(f2, "P6\n640 576\n255\n"); n2px = 0;
			}
			if (t->o_de && f2 && n2px < 640 * 576) {
				unsigned char px[3] = {(unsigned char)(t->o_rgb >> 16), (unsigned char)(t->o_rgb >> 8), (unsigned char)t->o_rgb};
				fwrite(px, 1, 3, f2); n2px++;
			}
			last_ovs = t->o_vs;
		}
		// RS-232 from the machine
		int txd = t->txd;
		if (rx_state < 0) { if (last_txd && !txd) { rx_state = 0; rx_t = c + BIT + BIT / 2; rx_byte = 0; } }
		else if (c == rx_t) {
			rx_byte |= txd << rx_state; rx_state++; rx_t += BIT;
			if (rx_state == 8) {
				rx_state = -1;
				if (rx_byte == 0x0D) { putchar('\n'); term += '\n'; }
				else if (rx_byte >= 0x20 && rx_byte < 0x7F) { putchar(rx_byte); term += (char)rx_byte; }
				else if (rx_byte != 0x0A) printf("<%02x>", rx_byte);
				fflush(stdout);
			}
		}
		last_txd = txd;
		if (iotrace > 0) {
			int p = t->cpu_addr & 0xFF;
			if (t->dbg_io_wr && !last_iow) { printf("%.3f ms OUT %02x,%02x\n", c * 1000.0 / CLK_HZ, p, t->dbg_dout); iotrace--; }
			if (!t->dbg_io_rd && last_ior && p != 0x41 && p != 0x80 && p != 0xA1) { printf("%.3f ms IN  %02x = %02x\n", c * 1000.0 / CLK_HZ, p, t->dbg_din); iotrace--; }
			last_iow = t->dbg_io_wr; last_ior = t->dbg_io_rd;
		}
		// frames: a file per rising vsync, x from the end of hsync, samples at ce_pix (as tb_schem)
		if (frames) {
			if (t->vsync && !last_vs) {
				if (fd) fclose(fd);
				char fn[512]; snprintf(fn, sizeof fn, "%s_%d.ppm", frames, nfr++);
				fd = fopen(fn, "wb"); fprintf(fd, "P6\n768 320\n255\n"); y = 0;
			}
			if (!t->hsync && last_hs) { x = 0; y++; }
			if (t->ce_pix && fd && x < 768 && y < 320) {
				int g = (t->gc_raw || t->gk_raw) ? 40 : 0;
				unsigned char px[3] = {(unsigned char)((t->rgb & 4) ? 255 : g), (unsigned char)((t->rgb & 2) ? 255 : g), (unsigned char)((t->rgb & 1) ? 255 : 0)};
				fwrite(px, 1, 3, fd); x++;
			}
			last_vs = t->vsync; last_hs = t->hsync;
		}
	}
	if (fd) fclose(fd);
	if (f2) fclose(f2);
	printf("\n[sim] %.1f ms, PC %04x, C1 %02x\n", ms, t->cpu_addr, t->dbg_c1);
	if (vram) for (int pg = 0; pg < 2; pg++) {
		int nz = 0;
		for (long a = 0xC000; a < 0x10000; a++) { t->dbg_addr = pg * 0x10000 + a; t->eval(); if (t->dbg_q) nz++; }
		printf("video RAM page %d: %d non-zero bytes\n", pg, nz);
	}
	for (long a : peeks) { t->dbg_addr = a; t->eval(); printf("peek %06lx = %02x\n", a, t->dbg_q); }
	int ok = 1;
	if (expect && term.find(expect) == std::string::npos) { printf("FAIL: no \"%s\" on the terminal\n", expect); ok = 0; }
	delete t;
	return ok ? 0 : 1;
}

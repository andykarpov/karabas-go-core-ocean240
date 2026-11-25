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
//   --load ADDR:FILE     a file into the SRAM at ADDR (hex) before the start (a RAM disk image: 010000)
//   --poke ADDR:XX       a byte into the SRAM before the start
//   --wav-in MS:FILE     a .wav as the FL item of the tape (slot 6) at MS, a byte every 400 clocks; it plays at its end
//   --wav-out FILE       the tape line out (TAPE_OUT) as a .wav, 8 bits, 48 kHz
//   --fdd N:FILE         a floppy image (.okd) in drive N (0 / 1: the F item of slot 4 / 5), mounted at 1 ms
//   --fdd-out N:FILE     the image of drive N at the end (with the writes of the machine)
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
	if (c == ':') return 0x52;     // the ' key: ':' on the positional keyboard (MONITOR+)
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
	std::vector<unsigned char> fdd[2];
	const char *fdd_out[2] = {0, 0};
	Vtb_ocean *t = new Vtb_ocean;
	const char *rom0 = 0, *rom1 = 0, *frames = 0, *expect = 0;
	double ms = 20;
	std::vector<Ev> rx, kb;
	std::vector<long> peeks;
	std::vector<std::pair<long, unsigned char>> pre;
	int iotrace = 0, vram = 0, model = 0, mpss = 0;
	const char *frame2x = 0, *wav_out = 0;
	std::vector<unsigned char> wav, wout;
	long long wav_t = -1;
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
		else if (a == "--wav-out") wav_out = argv[++i];
		else if (a == "--wav-in") {
			const char *v = argv[++i];
			wav_t = (long long)(atof(v) * CLK_HZ / 1000.0);
			FILE *f = fopen(strchr(v, ':') + 1, "rb");
			if (!f) { fprintf(stderr, "no wav\n"); exit(2); }
			int ch; while ((ch = fgetc(f)) != EOF) wav.push_back((unsigned char)ch);
			fclose(f);
		}
		else if (a == "--load" || a == "--poke") {
			const char *v = argv[++i];
			long ad = strtol(v, 0, 16);
			const char *rest = strchr(v, ':') + 1;
			if (a == "--poke") pre.push_back({ad, (unsigned char)strtol(rest, 0, 16)});
			else {
				FILE *f = fopen(rest, "rb");
				if (!f) { fprintf(stderr, "no %s\n", rest); exit(2); }
				int ch; while ((ch = fgetc(f)) != EOF) pre.push_back({ad++, (unsigned char)ch});
				fclose(f);
			}
		}
		else if (a == "--mpss") mpss = 1;
		else if (a == "--fdd" || a == "--fdd-out") {
			const char *v = argv[++i];
			int n = atoi(v) & 1; const char *f = strchr(v, ':') + 1;
			if (a == "--fdd-out") fdd_out[n] = f;
			else {
				FILE *ff = fopen(f, "rb"); if (!ff) { fprintf(stderr, "no %s\n", f); return 1; }
				fseek(ff, 0, SEEK_END); fdd[n].resize(ftell(ff)); fseek(ff, 0, SEEK_SET);
				if (fread(fdd[n].data(), 1, fdd[n].size(), ff) != fdd[n].size()) return 1;
				fclose(ff);
			}
		}
		else if (a == "--frame2x") frame2x = argv[++i];
	}
	// preload the SRAM: ROM0 / ROM1 into the images the model takes (ocean_system: 080000 + 2000 * image), 8 KB each
	t->file_active = 0; t->file_wr = 0;
	t->sdc_img_mounted = 0; t->sdc_img_size = 0; t->sdc_busy = 0; t->sdc_done = 0; t->sdc_slot = 0;
	t->sdc_byte_in_strobe = 0; t->sdc_byte_addr = 0; t->sdc_byte_in_data = 0; t->img_wp = 0;
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
	for (auto &p : pre) { t->pl_we = 1; t->pl_addr = p.first; t->pl_data = p.second; tick(); }
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
	// the mounter of kg_mcu2 (kg_l2_img as the sdc_* side sees it): one request at a time, the lowest slot first,
	// a sector some 0.2 ms after the request; a read streams 512 bytes, a write takes sdc_byte_out_data two clocks
	// after sdc_byte_addr
	int m_st = 0, m_slot = 0, m_pos = 0, m_wr = 0; long long m_t = 0; unsigned m_lba = 0;
	int fdd_reads = 0, fdd_writes = 0;
	for (long long c = 0; c < total; c++) {
		tick();
		t->sdc_img_mounted = 0; t->sdc_done = 0; t->sdc_byte_in_strobe = 0;
		for (int n = 0; n < 2; n++) if (c == CLK_HZ / 1000 + n && fdd[n].size()) {
			t->sdc_img_mounted = 1 << (4 + n); t->sdc_img_size = fdd[n].size();
		}
		if (m_st == 0) {
			int req = (t->sdc_rd | t->sdc_wr) & 0x30;
			if (req) {
				m_slot = (req & 0x10) ? 4 : 5; m_wr = (t->sdc_wr >> m_slot) & 1; m_lba = t->sdc_sector;
				t->sdc_busy = 1; t->sdc_slot = m_slot; m_st = 1; m_t = c + 10000; m_pos = 0;
			}
		} else if (m_st == 1 && c >= m_t) {
			std::vector<unsigned char> &d = fdd[m_slot - 4];
			size_t o = (size_t)m_lba * 512 + m_pos;
			if (!m_wr) {
				if ((c - m_t) % 4 == 0) {
					t->sdc_byte_addr = m_pos; t->sdc_byte_in_data = o < d.size() ? d[o] : 0; t->sdc_byte_in_strobe = 1;
					if (++m_pos == 512) { m_st = 2; fdd_reads++; }
				}
			} else {
				int k = (c - m_t) % 4;
				if (k == 0) t->sdc_byte_addr = m_pos;
				if (k == 3) { if (o < d.size()) d[o] = t->sdc_byte_out_data; if (++m_pos == 512) { m_st = 2; fdd_writes++; } }
			}
		} else if (m_st == 2) { t->sdc_busy = 0; t->sdc_done = 1; m_st = 0; }
		// RS-232 to the machine
		if (rx_i < rx.size() && c >= rx[rx_i].t && tx_start < 0) { tx_start = c; tx_byte = rx[rx_i].b; }
		if (tx_start >= 0) {
			long long k = (c - tx_start) / BIT;
			if (k == 0) t->rxd = 0;
			else if (k <= 8) t->rxd = (tx_byte >> (k - 1)) & 1;
			else t->rxd = 1;
			if (k >= 11) { tx_start = -1; printf("\n[sim] sent %02x at %.1f ms\n", tx_byte, rx[rx_i].t * 1000.0 / CLK_HZ); rx_i++; }
		}
		// the tape file as the mcu sends an FL item, then the line out as samples
		t->file_wr = 0;
		if (wav_t >= 0 && c >= wav_t) {
			long long k = (c - wav_t) / 400;
			if (k < (long long)wav.size()) {
				t->file_active = 1;
				if ((c - wav_t) % 400 == 0) { t->file_addr = k; t->file_data = wav[k]; t->file_wr = 1; }
			} else if (t->file_active) { t->file_active = 0; printf("[sim] tape file loaded at %.1f ms\n", c * 1000.0 / CLK_HZ); }
		}
		if (wav_out && c % 1024 == 0) wout.push_back(t->tape_out ? 0xC0 : 0x40);
		// the PS/2 bytes into ocean_kbd
		t->ps2_wr = 0;
		if (kb_i < kb.size() && c >= kb[kb_i].t) { t->ps2_code = kb[kb_i].b; t->ps2_wr = 1; kb_i++; }
		// the HDMI frames of ocean_scan2x: a file per falling vs, the de pixels
		if (frame2x && t->o_ce) {
			if (!t->o_vs && last_ovs) {
				if (f2) fclose(f2);
	if (wav_out) {
		FILE *f = fopen(wav_out, "wb");
		unsigned n = wout.size(), rate = 48000;
		unsigned char h[44] = {'R','I','F','F',0,0,0,0,'W','A','V','E','f','m','t',' ',16,0,0,0,1,0,1,0,0,0,0,0,0,0,0,0,1,0,8,0,'d','a','t','a',0,0,0,0};
		unsigned r = 36 + n; memcpy(h + 4, &r, 4); memcpy(h + 24, &rate, 4); memcpy(h + 28, &rate, 4); memcpy(h + 40, &n, 4);
		fwrite(h, 1, 44, f); fwrite(wout.data(), 1, n, f); fclose(f);
		printf("[sim] tape out: %u samples\n", n);
	}
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
	if (wav_out) {
		FILE *f = fopen(wav_out, "wb");
		unsigned n = wout.size(), rate = 48000;
		unsigned char h[44] = {'R','I','F','F',0,0,0,0,'W','A','V','E','f','m','t',' ',16,0,0,0,1,0,1,0,0,0,0,0,0,0,0,0,1,0,8,0,'d','a','t','a',0,0,0,0};
		unsigned r = 36 + n; memcpy(h + 4, &r, 4); memcpy(h + 24, &rate, 4); memcpy(h + 28, &rate, 4); memcpy(h + 40, &n, 4);
		fwrite(h, 1, 44, f); fwrite(wout.data(), 1, n, f); fclose(f);
		printf("[sim] tape out: %u samples\n", n);
	}
	printf("\n[sim] %.1f ms, PC %04x, C1 %02x\n", ms, t->cpu_addr, t->dbg_c1);
	if (fdd[0].size() || fdd[1].size()) printf("[sim] floppy: %d sectors read, %d written\n", fdd_reads, fdd_writes);
	for (int n = 0; n < 2; n++) if (fdd_out[n]) {
		FILE *ff = fopen(fdd_out[n], "wb"); fwrite(fdd[n].data(), 1, fdd[n].size(), ff); fclose(ff);
	}
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

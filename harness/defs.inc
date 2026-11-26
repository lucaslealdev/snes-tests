; Constants shared by the harness. The check kinds must match cputest/make_cpu_tests.py and
; spctest/make_tests.py; the tags too. tools/check_tables.py verifies them.

; Kinds of failures (the `kind` byte of a failure entry). Bit 7 of the stored byte is set for SPC tests.
CHK_CTRL  = 0   ; a branch or jump went the wrong way
CHK_X     = 1
CHK_Y     = 2
CHK_P     = 3
CHK_A     = 4
CHK_S     = 5   ; S (CPU) or SP (SPC)
CHK_DBR   = 6
CHK_D     = 7
CHK_MEM   = 8
CHK_ORDER = 9   ; test entered out of order (errant jump)
CHK_BRK   = 10  ; unexpected BRK
CHK_COP   = 11  ; unexpected COP
CHK_HANG  = 12  ; the test never finished
CHK_UNRESP = 13 ; the SPC-700 stopped responding. `expected` = number of tests not run
FAIL_SPC  = $80

; Test tags
TAG_EMULATION    = $01
TAG_UNDOCUMENTED = $02
TAG_DECIMAL      = $04
HAS_S            = $08
HAS_D            = $10
HAS_DBR          = $20

; Filters (bit set = tests of that kind are run)
FILT_EMULATION = $01
FILT_UNDOC     = $02
FILT_DECIMAL   = $04

; Phases of the runner (rsv_phase)
PHASE_MENU   = 0
PHASE_SPC    = 1
PHASE_CPU    = 2
PHASE_REPORT = 3

; SPC protocol, see spc_proto.inc
SPC_MSG_FAIL = 1
SPC_MSG_DONE = 2
SPC_CMD_RUN  = $10
SPC_CMD_EXIT = $20
SPC_BOOT_SIGNATURE = $5C00     ; O0=$00, O1=$5C
SPC_HANG_FRAMES = 120          ; frames without progress before a test is considered hung
SPC_WAIT_FRAMES = 180          ; timeout of IPL handshakes

; Limits
FAIL_MAX    = 1000
FAIL_SIZE   = 12
MAX_GROUPS  = 64   ; per CPU type
MAX_TESTS   = 4096

; Joypad bits ($4218/$4219 as a 16 bit value)
PAD_B = $8000
PAD_Y = $4000
PAD_SELECT = $2000
PAD_START = $1000
PAD_UP = $0800
PAD_DOWN = $0400
PAD_LEFT = $0200
PAD_RIGHT = $0100
PAD_A = $0080
PAD_X = $0040
PAD_L = $0020
PAD_R = $0010

; UI shadow buffers (WRAM $7E:2000-$7E:4FFF; the tests don't touch it)
BG1_SHADOW = $7E2000
BG3_SHADOW = $7E2800
OAM_SHADOW = $7E3000
UI_WORK    = $7E3400

; Text styles (palette number of BG1 tiles)
ST_NORMAL = 1
ST_DIM    = 2
ST_ACCENT = 3
ST_PASS   = 4
ST_FAIL   = 5
ST_WARN   = 6
ST_CAT    = 7

; Special tiles
T_BOX_OFF   = 128
T_BOX_ON    = 129
T_POINTER   = 130
T_EXPANDED  = 131
T_COLLAPSED = 132
T_BAR0      = 134
T_BAR8      = 142

; Fixed addresses the tests rely on
native_brk_handler = $1000
native_cop_handler = $1004
emulation_brk_handler = $1008
emulation_cop_handler = $100C

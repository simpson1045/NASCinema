/// Theater pref keys — a pure-Dart file (no dart:ffi/dart:io) so the settings
/// UI can be compiled for web without dragging in the Windows-only control
/// stack. The hooks themselves live in theater_control.dart (renderer only).
library;

const kDenonEnabledPref = 'theater_denon_enabled';
const kDenonHostPref = 'theater_denon_host';
const kDenonInputPref = 'theater_denon_input'; // SOURCE name, e.g. 8K
const kDenonPowerPref = 'theater_denon_power'; // also send ZMON

const kTvEnabledPref = 'theater_tv_enabled';
const kTvHostPref = 'theater_tv_host';
const kTvKeyPref = 'theater_tv_key'; // SSAP client-key from pairing
const kTvInputPref = 'theater_tv_input'; // input carrying the Denon, e.g. HDMI_2
const kTvLabelPref = 'theater_tv_label'; // label to force when it flips to PC
const kTvSwitchInputPref = 'theater_tv_switch'; // also switch the TV on play

const kRefreshMatchPref = 'theater_refresh_match';

const kDefaultTvInput = 'HDMI_2';
const kDefaultTvLabel = 'Denon AVR';

/// Renderer prefs (shared shape: pure constants, UI-safe on any platform).
const kMpvPathPref = 'mpv_path';
const kMpvDefaultPath = r'C:\Program Files\MPV Player\mpv.exe';

/// TrueHD bitstream is OFF by default (decode to lossless multichannel LPCM
/// instead): ffmpeg's spdif TrueHD MAT packer dies at seamless-branching
/// splices (ROTS crashes at ~2:20; trac #9569/#10948), and the 2026-07-26
/// upstream rework regressed on real receivers ("PCM ZERO" — our report on
/// mpv-player/mpv#13943). Flip this on once a fixed mpv/ffmpeg build lands.
/// DTS-HD/EAC3/AC3 bitstream are unaffected and stay on.
const kTruehdBitstreamPref = 'truehd_bitstream';

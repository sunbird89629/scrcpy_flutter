import 'dart:typed_data';

/// Packs H.264 Annex-B access units into MPEG-TS 188-byte packets.
///
/// Single-program, video-only (stream type 0x1B). PTS is derived from a
/// monotonic wall-clock at 90 kHz. Callers should emit PAT + PMT before
/// each keyframe so late joiners can decode.
class MpegTsMuxer {
  static const int _tsSize = 188;
  static const int _sync = 0x47;
  static const int _patPid = 0x0000;
  static const int _pmtPid = 0x1000;
  static const int _videoPid = 0x0100;
  static const int _streamTypeH264 = 0x1B;
  static const int _pesStreamIdVideo = 0xE0;

  int _ccPat = 0;
  int _ccPmt = 0;
  int _ccVideo = 0;

  final Stopwatch _clock = Stopwatch()..start();

  /// 188-byte TS packet carrying PAT.
  Uint8List buildPat() =>
      _wrapPsi(_patSection(), _patPid, _advancePatCc());

  /// 188-byte TS packet carrying PMT.
  Uint8List buildPmt() =>
      _wrapPsi(_pmtSection(), _pmtPid, _advancePmtCc());

  /// Wraps a complete H.264 access unit (Annex-B bytes) into one or more
  /// TS packets. When [isKey] is true, a PCR and random-access indicator
  /// are inserted in the first packet's adaptation field.
  Uint8List wrapAccessUnit(Uint8List auBytes, {required bool isKey}) {
    final pts90k = _pts90kNow();
    final pes = _buildPes(auBytes, pts90k);

    final out = BytesBuilder();
    var offset = 0;
    var first = true;

    while (offset < pes.length) {
      final remaining = pes.length - offset;
      final needPcr = first && isKey;

      var maxPayload = _tsSize - 4;
      if (needPcr) maxPayload -= 8; // AF length+flags (2) + PCR (6)

      Uint8List? af;
      int chunkLen;

      if (remaining <= maxPayload) {
        chunkLen = remaining;
        final stuff = maxPayload - remaining;
        if (needPcr) {
          af = _afPcr(pts90k, randomAccess: true, extraStuff: stuff);
        } else if (stuff > 0) {
          af = _afStuffingOnly(stuff);
        }
      } else {
        chunkLen = maxPayload;
        if (needPcr) {
          af = _afPcr(pts90k, randomAccess: true);
        }
      }

      out.add(
        _buildTsPacket(
          pid: _videoPid,
          pusi: first,
          af: af,
          payload: Uint8List.sublistView(pes, offset, offset + chunkLen),
          cc: _advanceVideoCc(),
        ),
      );

      offset += chunkLen;
      first = false;
    }

    return out.takeBytes();
  }

  int _advancePatCc() {
    final c = _ccPat;
    _ccPat = (_ccPat + 1) & 0x0F;
    return c;
  }

  int _advancePmtCc() {
    final c = _ccPmt;
    _ccPmt = (_ccPmt + 1) & 0x0F;
    return c;
  }

  int _advanceVideoCc() {
    final c = _ccVideo;
    _ccVideo = (_ccVideo + 1) & 0x0F;
    return c;
  }

  int _pts90kNow() {
    final us = _clock.elapsedMicroseconds;
    return ((us * 9) ~/ 100) & 0x1FFFFFFFF;
  }

  Uint8List _buildPes(Uint8List payload, int pts90k) {
    final b = BytesBuilder()
      ..add([
        0x00, 0x00, 0x01, _pesStreamIdVideo,
        0x00, 0x00, // PES_packet_length = 0 (unbounded, allowed for video)
        0x80, // '10' + zeros
        0x80, // PTS_flags=10
        0x05, // PES_header_data_length = 5
      ]);
    _writePts(b, pts90k, marker: 0x21); // '0010' prefix for PTS-only
    b.add(payload);
    return b.takeBytes();
  }

  void _writePts(BytesBuilder b, int pts, {required int marker}) {
    final p = pts & 0x1FFFFFFFF;
    b.add([
      marker | (((p >> 30) & 0x07) << 1),
      (p >> 22) & 0xFF,
      ((p >> 14) & 0xFE) | 0x01,
      (p >> 7) & 0xFF,
      ((p << 1) & 0xFE) | 0x01,
    ]);
  }

  Uint8List _afPcr(int pts, {required bool randomAccess, int extraStuff = 0}) {
    final total = 8 + extraStuff;
    final out = Uint8List(total);
    out[0] = total - 1; // adaptation_field_length
    out[1] = 0x10 | (randomAccess ? 0x40 : 0x00); // PCR_flag (+ RAI)
    final base = pts & 0x1FFFFFFFF;
    out[2] = (base >> 25) & 0xFF;
    out[3] = (base >> 17) & 0xFF;
    out[4] = (base >> 9) & 0xFF;
    out[5] = (base >> 1) & 0xFF;
    out[6] = ((base & 0x01) << 7) | 0x7E; // reserved '111111' + PCR_ext[8]=0
    out[7] = 0x00; // PCR_ext[7..0]
    for (var i = 8; i < total; i++) {
      out[i] = 0xFF;
    }
    return out;
  }

  Uint8List _afStuffingOnly(int stuff) {
    if (stuff == 1) return Uint8List.fromList([0x00]);
    final out = Uint8List(stuff);
    out[0] = stuff - 1;
    out[1] = 0x00;
    for (var i = 2; i < stuff; i++) {
      out[i] = 0xFF;
    }
    return out;
  }

  Uint8List _buildTsPacket({
    required int pid,
    required bool pusi,
    required Uint8List payload,
    required int cc,
    Uint8List? af,
  }) {
    final out = Uint8List(_tsSize);
    out[0] = _sync;
    out[1] = (pusi ? 0x40 : 0x00) | ((pid >> 8) & 0x1F);
    out[2] = pid & 0xFF;

    final int afc;
    if (af != null && payload.isNotEmpty) {
      afc = 0x30;
    } else if (af != null) {
      afc = 0x20;
    } else {
      afc = 0x10;
    }
    out[3] = afc | (cc & 0x0F);

    var cursor = 4;
    if (af != null) {
      out.setRange(cursor, cursor + af.length, af);
      cursor += af.length;
    }
    if (payload.isNotEmpty) {
      out.setRange(cursor, cursor + payload.length, payload);
      cursor += payload.length;
    }
    for (var i = cursor; i < _tsSize; i++) {
      out[i] = 0xFF;
    }
    return out;
  }

  Uint8List _wrapPsi(Uint8List section, int pid, int cc) {
    assert(section.length <= _tsSize - 4);
    final out = Uint8List(_tsSize);
    out[0] = _sync;
    out[1] = 0x40 | ((pid >> 8) & 0x1F); // PUSI=1
    out[2] = pid & 0xFF;
    out[3] = 0x10 | (cc & 0x0F); // payload only
    out.setRange(4, 4 + section.length, section);
    for (var i = 4 + section.length; i < _tsSize; i++) {
      out[i] = 0xFF;
    }
    return out;
  }

  Uint8List _patSection() {
    // section_length = 13 for 1 program
    final body = Uint8List.fromList([
      0x00, // pointer_field
      0x00, // table_id
      0xB0, 0x0D, // section_syntax=1 + '0' + '11' + length=13
      0x00, 0x01, // transport_stream_id
      0xC1, // version=0, current_next=1
      0x00, 0x00,
      0x00, 0x01, // program_number
      0xE0 | ((_pmtPid >> 8) & 0x1F),
      _pmtPid & 0xFF,
    ]);
    final crc = _crc32Mpeg2(Uint8List.sublistView(body, 1));
    final out = Uint8List(body.length + 4);
    out.setRange(0, body.length, body);
    out[body.length] = (crc >> 24) & 0xFF;
    out[body.length + 1] = (crc >> 16) & 0xFF;
    out[body.length + 2] = (crc >> 8) & 0xFF;
    out[body.length + 3] = crc & 0xFF;
    return out;
  }

  Uint8List _pmtSection() {
    // section_length = 18 for 1 ES with no descriptors
    final body = Uint8List.fromList([
      0x00, // pointer_field
      0x02, // table_id
      0xB0, 0x12, // section_length=18
      0x00, 0x01, // program_number
      0xC1,
      0x00, 0x00,
      0xE0 | ((_videoPid >> 8) & 0x1F),
      _videoPid & 0xFF, // PCR_PID = video PID
      0xF0, 0x00, // program_info_length=0
      _streamTypeH264,
      0xE0 | ((_videoPid >> 8) & 0x1F),
      _videoPid & 0xFF, // elementary_PID
      0xF0, 0x00, // ES_info_length=0
    ]);
    final crc = _crc32Mpeg2(Uint8List.sublistView(body, 1));
    final out = Uint8List(body.length + 4);
    out.setRange(0, body.length, body);
    out[body.length] = (crc >> 24) & 0xFF;
    out[body.length + 1] = (crc >> 16) & 0xFF;
    out[body.length + 2] = (crc >> 8) & 0xFF;
    out[body.length + 3] = crc & 0xFF;
    return out;
  }

  static int _crc32Mpeg2(Uint8List data) {
    var crc = 0xFFFFFFFF;
    for (final b in data) {
      crc ^= b << 24;
      for (var i = 0; i < 8; i++) {
        if ((crc & 0x80000000) != 0) {
          crc = ((crc << 1) ^ 0x04C11DB7) & 0xFFFFFFFF;
        } else {
          crc = (crc << 1) & 0xFFFFFFFF;
        }
      }
    }
    return crc;
  }
}

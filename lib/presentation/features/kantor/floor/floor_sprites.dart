// Furniture sprites, ported 1:1 from the web office renderer (office-canvas.js).
// Each is drawn once into a small outlined image and reused every frame.
// ignore_for_file: curly_braces_in_flow_control_structures, prefer_single_quotes, unnecessary_parenthesis, prefer_const_declarations, prefer_final_locals, omit_local_variable_types

import 'floor_pixel.dart';

Sprite bookshelf() => sprite('shelf', 32, 42, (p) {
  p.r(0, 0, 32, 42, '#6E4B2E');
  p.r(2, 2, 28, 38, '#4A321F');
  final cols = [
    '#B64A3D',
    '#3E6BA8',
    '#D9A441',
    '#4F8F5B',
    '#7A4F96',
    '#D8D2C2',
    '#2F5D6E',
  ];
  for (var s = 0; s < 4; s++) {
    final y0 = 3 + s * 10;
    p.r(2, y0 + 8, 28, 2, '#6E4B2E');
    var x = 3, i = s * 3;
    while (x < 28) {
      final bw = 2 + (i * 7 % 3), bh = 5 + (i * 5 % 3);
      p.r(x, y0 + 8 - bh, bw, bh, cols[i % cols.length]);
      x += bw + (i % 4 == 0 ? 1 : 0);
      i++;
    }
  }
});

Sprite rack() => sprite('rack', 16, 44, (p) {
  p.r(0, 0, 16, 44, '#1B1E25');
  p.r(1, 1, 14, 42, '#262A33');
  for (var y = 3; y < 42; y += 4) p.r(2, y, 12, 3, '#30353F');
});

Sprite sofa(String col) => sprite('sofa$col', 40, 20, (p) {
  p.r(0, 4, 40, 14, col);
  p.r(2, 0, 36, 8, col);
  p.r(0, 4, 4, 14, '#00000022');
  p.r(36, 4, 4, 14, '#00000022');
  p.r(4, 8, 15, 6, '#FFFFFF22');
  p.r(21, 8, 15, 6, '#FFFFFF22');
  p.r(2, 18, 3, 2, '#2B2B2B');
  p.r(35, 18, 3, 2, '#2B2B2B');
});

Sprite armchair(String col) => sprite('arm$col', 16, 18, (p) {
  p.r(0, 4, 16, 12, col);
  p.r(2, 0, 12, 7, col);
  p.r(3, 8, 10, 5, '#FFFFFF22');
  p.r(1, 16, 2, 2, '#2B2B2B');
  p.r(13, 16, 2, 2, '#2B2B2B');
});

Sprite meetingTable() => sprite('mtable', 76, 34, (p) {
  for (var i = 0; i < 4; i++) {
    p.r(8 + i * 17, 0, 10, 9, '#D59A55');
    p.r(9 + i * 17, 0, 8, 1, '#E8B371');
  }
  p.r(2, 8, 72, 13, '#B48A5C');
  p.r(2, 8, 72, 2, '#C9A06D');
  p.r(2, 21, 72, 4, '#7E5F3C');
  for (var i = 0; i < 4; i++) {
    p.r(8 + i * 17, 26, 10, 8, '#D59A55');
    p.r(9 + i * 17, 26, 8, 1, '#E8B371');
  }
  p.r(20, 11, 6, 4, '#F4F4F4');
  p.r(46, 12, 5, 3, '#F4F4F4');
  p.r(60, 10, 3, 3, '#E2A23A');
});

Sprite roundTable() => sprite('rtable', 28, 22, (p) {
  p.r(0, 10, 6, 6, '#D59A55');
  p.r(22, 10, 6, 6, '#D59A55');
  p.r(6, 4, 16, 10, '#D8D2C2');
  p.r(6, 4, 16, 2, '#EEE9DD');
  p.r(13, 14, 2, 6, '#7A7A7A');
  p.r(9, 20, 10, 2, '#7A7A7A');
  p.r(10, 6, 3, 3, '#FFFFFF');
});

Sprite longTable() => sprite('ltable', 66, 26, (p) {
  p.r(0, 6, 66, 10, '#C9A06D');
  p.r(0, 6, 66, 2, '#D9B37F');
  p.r(0, 16, 66, 3, '#8E6A42');
  for (var i = 0; i < 5; i++) {
    p.r(4 + i * 13, 0, 6, 5, '#5A606E');
    p.r(4 + i * 13, 20, 6, 5, '#5A606E');
  }
  p.r(10, 8, 3, 3, '#FFFFFF');
  p.r(40, 8, 4, 3, '#E5655D');
});

Sprite counter() => sprite('counter', 56, 36, (p) {
  p.r(0, 14, 56, 22, '#8A6A45');
  p.r(0, 12, 56, 3, '#D8D2C2');
  p.r(4, 18, 22, 14, '#7A5C3A');
  p.r(30, 18, 22, 14, '#7A5C3A');
  p.r(14, 24, 2, 3, '#C9A15A');
  p.r(40, 24, 2, 3, '#C9A15A');
  p.r(4, 0, 12, 13, '#2A2E37');
  p.r(6, 2, 8, 3, '#3A3F4B');
  p.r(13, 8, 1, 1, '#E5655D');
  p.r(8, 9, 3, 3, '#FFFFFF');
  p.r(22, 6, 14, 7, '#C9CFD6');
  p.r(24, 7, 10, 4, '#9AA3AF');
  p.r(28, 3, 2, 4, '#9AA3AF');
  p.r(40, 3, 12, 10, '#E9ECEF');
  p.r(41, 4, 7, 6, '#2B303B');
});

Sprite fridge() => sprite('fridge', 16, 40, (p) {
  p.r(0, 0, 16, 40, '#E9ECEF');
  p.r(0, 14, 16, 1, '#C5CBD2');
  p.r(13, 0, 3, 40, '#D5DAE0');
  p.r(2, 5, 1, 6, '#9AA0A8');
  p.r(2, 18, 1, 8, '#9AA0A8');
  p.r(5, 22, 4, 4, '#F2CF72');
});

Sprite water() => sprite('water', 10, 32, (p) {
  p.r(2, 0, 6, 9, '#8FC7EA');
  p.r(3, 0, 4, 1, '#6FAED8');
  p.r(1, 9, 8, 23, '#EDEFF2');
  p.r(7, 9, 2, 23, '#D2D6DC');
  p.r(3, 15, 1, 2, '#C2413A');
  p.r(6, 15, 1, 2, '#3B7DD8');
});

Sprite vending() => sprite('vending', 18, 36, (p) {
  p.r(0, 0, 18, 36, '#B23A3A');
  p.r(2, 3, 10, 24, '#1E2A38');
  for (var y = 5; y < 26; y += 5)
    for (var x = 3; x < 11; x += 3)
      p.r(
        x,
        y,
        2,
        3,
        ['#F2CF72', '#7FD3C9', '#E5655D', '#9FD67F'][(x + y) % 4],
      );
  p.r(13, 5, 3, 6, '#2B2B2B');
  p.r(13, 13, 3, 2, '#7FD3C9');
  p.r(2, 29, 10, 4, '#2B2B2B');
});

Sprite bench() => sprite('bench', 32, 12, (p) {
  p.r(0, 0, 32, 4, '#9C7046');
  p.r(0, 4, 32, 2, '#7A5532');
  p.r(2, 6, 2, 6, '#555B66');
  p.r(28, 6, 2, 6, '#555B66');
});

Sprite reception() => sprite('recep', 58, 28, (p) {
  p.r(0, 6, 58, 22, '#7E5F3C');
  p.r(0, 4, 58, 4, '#D8D2C2');
  p.r(4, 12, 50, 12, '#9C7046');
  p.r(18, 14, 22, 8, '#A9620F');
  p.r(20, 16, 18, 4, '#F2CF72');
  p.r(6, 0, 8, 5, '#2A2F3A');
  p.r(7, 1, 6, 3, '#16303F');
  p.r(46, 1, 4, 4, '#C2413A');
});

Sprite printer() => sprite('printer', 18, 18, (p) {
  p.r(0, 6, 18, 12, '#D5D9DE');
  p.r(0, 6, 18, 2, '#EEF0F2');
  p.r(3, 2, 12, 5, '#F7F7F2');
  p.r(4, 10, 10, 2, '#2B303B');
  p.r(14, 13, 2, 1, '#2C8452');
});

Sprite cabinet() => sprite('cabinet', 14, 24, (p) {
  p.r(0, 0, 14, 24, '#8E959F');
  for (var y = 2; y < 24; y += 7) {
    p.r(1, y, 12, 6, '#A3AAB4');
    p.r(5, y + 2, 4, 1, '#5A606E');
  }
});

Sprite arcade() => sprite('arcade', 18, 38, (p) {
  p.r(1, 0, 16, 38, '#2F2A6B');
  p.r(0, 4, 18, 30, '#3B3584');
  p.r(3, 6, 12, 10, '#0E1218');
  p.r(4, 7, 10, 8, '#173042');
  p.r(6, 9, 3, 3, '#E2A23A');
  p.r(10, 11, 2, 2, '#7FD3C9');
  p.r(3, 19, 12, 5, '#1E1E24');
  p.r(5, 20, 2, 2, '#E5655D');
  p.r(10, 21, 2, 2, '#7FD3C9');
  p.r(2, 0, 14, 3, '#E5655D');
});

Sprite beanbag(String col) => sprite('bean$col', 18, 12, (p) {
  p.r(2, 2, 14, 10, col);
  p.r(0, 5, 18, 7, col);
  p.r(4, 3, 6, 3, '#FFFFFF33');
});

Sprite qaBench() => sprite('qabench', 66, 26, (p) {
  p.r(0, 12, 66, 4, '#C9CDD4');
  p.r(0, 16, 66, 3, '#9AA3AF');
  p.r(2, 19, 2, 7, '#7A808A');
  p.r(62, 19, 2, 7, '#7A808A');
  for (var i = 0; i < 7; i++) {
    p.r(4 + i * 9, 2, 6, 10, '#1B1F27');
    p.r(5 + i * 9, 3, 4, 7, '#2A4A5C');
  }
});

Sprite boxes() => sprite('boxes', 20, 20, (p) {
  p.r(0, 8, 12, 12, '#C49A62');
  p.r(0, 8, 12, 2, '#D9B37F');
  p.r(5, 8, 2, 12, '#A47A47');
  p.r(8, 0, 12, 10, '#B88B55');
  p.r(8, 0, 12, 2, '#D0A570');
  p.r(13, 0, 2, 10, '#9C7046');
  p.r(11, 10, 9, 10, '#C49A62');
});

Sprite sheet() => sprite('sheet', 40, 22, (p) {
  p.r(1, 4, 38, 16, '#E8E8E4');
  p.r(4, 0, 14, 6, '#F2F2EE');
  p.r(1, 18, 38, 4, '#CFCFC9');
  p.r(10, 8, 1, 10, '#D5D5CF');
  p.r(26, 6, 1, 12, '#D5D5CF');
});

Sprite stall() => sprite('stall', 24, 34, (p) {
  p.r(0, 0, 24, 34, '#A9B4C2');
  p.r(2, 2, 20, 30, '#BCC6D2');
  p.r(18, 16, 2, 2, '#5A606E');
  p.r(0, 0, 2, 34, '#8E99A8');
  p.r(22, 0, 2, 34, '#8E99A8');
});

Sprite sink() => sprite('sink', 18, 16, (p) {
  p.r(0, 4, 18, 12, '#E9ECEF');
  p.r(3, 5, 12, 5, '#C9D3DC');
  p.r(8, 0, 2, 5, '#9AA3AF');
  p.r(0, 14, 18, 2, '#C5CBD2');
});

Sprite globe() => sprite('globe', 12, 18, (p) {
  p.disc(6, 6, 5, '#3E6BA8');
  p.r(3, 4, 4, 3, '#4F8F5B');
  p.r(7, 7, 3, 2, '#4F8F5B');
  p.r(5, 12, 2, 4, '#7A5532');
  p.r(2, 16, 8, 2, '#7A5532');
});

Sprite wbStand() => sprite('wbstand', 30, 30, (p) {
  p.r(0, 0, 30, 20, '#9AA0A8');
  p.r(1, 1, 28, 18, '#F7F7F2');
  p.line(4, 5, 18, 5, '#3E6BA8');
  p.line(4, 9, 22, 9, '#3E6BA8');
  p.line(4, 13, 14, 13, '#C2413A');
  p.r(20, 11, 6, 5, '#F2CF72');
  p.r(4, 20, 2, 10, '#7A808A');
  p.r(24, 20, 2, 10, '#7A808A');
});

Sprite cooling() => sprite('cooling', 24, 36, (p) {
  p.r(0, 0, 24, 36, '#D5DAE0');
  p.r(2, 4, 20, 14, '#B9C0C8');
  for (var y = 6; y < 17; y += 2) p.r(3, y, 18, 1, '#9AA3AF');
  p.r(4, 22, 6, 3, '#2C8452');
});

Sprite trash() => sprite('trash', 10, 12, (p) {
  p.r(0, 0, 10, 12, '#8E959F');
  p.r(1, 1, 8, 10, '#6B727C');
  for (var x = 1; x < 9; x += 2) p.r(x, 1, 1, 10, '#8E959F');
  p.r(2, 0, 3, 2, '#F4F4F4');
});

Sprite phoneBooth() => sprite('pbooth', 26, 30, (p) {
  p.r(0, 0, 26, 30, '#2F5D6E');
  p.r(2, 2, 22, 20, '#BFD9E6');
  p.r(8, 12, 10, 8, '#3C4250');
  p.r(0, 24, 26, 6, '#264B59');
});

Sprite speaker() => sprite('speaker', 16, 26, (p) {
  p.r(0, 0, 16, 26, '#2A2D35');
  p.r(1, 1, 14, 24, '#3A3E48');
  p.r(1, 1, 14, 1, '#555B68');
  p.disc(8, 6, 2, '#555B68');
  p.disc(8, 6, 1, '#1B1E25');
  p.disc(8, 17, 6, '#555B68');
  p.disc(8, 17, 5, '#1B1E25');
  p.r(2, 24, 12, 1, '#2A2D35');
});

Sprite piano() => sprite('piano', 48, 24, (p) {
  p.r(0, 0, 48, 5, '#6B4535');
  p.r(0, 0, 48, 1, '#8A5C45');
  p.r(1, 5, 46, 8, '#4B2F26');
  p.r(17, 6, 14, 6, '#F4F0E4');
  for (var k = 0; k < 3; k++) p.r(19, 7 + k * 2, 10, 1, '#9AA0A8');
  p.r(4, 7, 3, 3, '#E2B04A');
  p.r(41, 7, 3, 3, '#E2B04A');
  p.r(2, 13, 44, 6, '#F4F4EE');
  for (var k = 0; k < 11; k++) {
    p.r(2 + k * 4, 13, 1, 6, '#BDBDB5');
    if (const [0, 1, 3, 4, 5].contains(k % 7))
      p.r(2 + k * 4 + 3, 13, 2, 4, '#1B1B22');
  }
  p.r(0, 19, 48, 3, '#4B2F26');
  p.r(2, 22, 3, 2, '#3A2A22');
  p.r(43, 22, 3, 2, '#3A2A22');
  p.r(22, 22, 4, 2, '#E2B04A');
});

Sprite musicBench() => sprite('pbench', 16, 8, (p) {
  p.r(0, 0, 16, 5, '#6B4535');
  p.r(1, 1, 14, 3, '#8A2F3A');
  p.r(1, 1, 14, 1, '#A9434F');
  p.r(1, 5, 2, 3, '#3A2A22');
  p.r(13, 5, 2, 3, '#3A2A22');
});

Sprite drums() => sprite('drums', 40, 30, (p) {
  p.r(4, 7, 1, 16, '#8A8A92');
  p.r(35, 6, 1, 17, '#8A8A92');
  p.r(0, 5, 10, 2, '#E3B94A');
  p.r(0, 5, 10, 1, '#F5D878');
  p.r(30, 4, 10, 2, '#E3B94A');
  p.r(30, 4, 10, 1, '#F5D878');
  p.disc(14, 10, 4, '#E8E4DA');
  p.disc(14, 10, 3, '#3E6BA8');
  p.disc(26, 10, 4, '#E8E4DA');
  p.disc(26, 10, 3, '#3E6BA8');
  p.disc(20, 21, 9, '#E8E4DA');
  p.disc(20, 21, 7, '#B93838');
  p.disc(20, 21, 2, '#F2CF72');
  p.r(11, 28, 2, 2, '#6B6B72');
  p.r(27, 28, 2, 2, '#6B6B72');
  p.r(3, 20, 9, 5, '#D8D2C2');
  p.r(3, 20, 9, 2, '#FFFFFF');
  p.r(4, 25, 1, 3, '#8A8A92');
  p.r(10, 25, 1, 3, '#8A8A92');
  p.disc(34, 24, 3, '#2A2F3A');
  p.disc(34, 24, 2, '#4A4F5C');
  p.r(34, 27, 1, 3, '#8A8A92');
});

Sprite guitar() => sprite('guitar', 14, 28, (p) {
  p.line(7, 22, 2, 27, '#555B66');
  p.line(7, 22, 12, 27, '#555B66');
  p.r(6, 20, 2, 3, '#555B66');
  p.r(6, 2, 2, 10, '#6B4535');
  p.r(5, 0, 4, 3, '#3A2A22');
  p.r(7, 2, 1, 10, '#D8D2C2');
  p.disc(7, 12, 3, '#C98A3F');
  p.disc(7, 18, 5, '#C98A3F');
  p.disc(7, 18, 2, '#2A1F1A');
  p.r(4, 18, 1, 3, '#E2B06A');
  p.r(5, 22, 5, 1, '#6B4535');
});

Sprite turntable() => sprite('turntable', 32, 22, (p) {
  p.r(0, 0, 32, 13, '#2A2D35');
  p.r(1, 1, 30, 11, '#1E2129');
  p.r(0, 0, 32, 1, '#555B68');
  p.disc(9, 6, 6, '#3A3E48');
  p.r(20, 8, 2, 2, '#E5655D');
  p.r(24, 9, 2, 2, '#7FD3C9');
  p.r(28, 9, 2, 2, '#F2CF72');
  p.r(27, 1, 3, 3, '#555B68');
  p.r(0, 13, 32, 9, '#7A5532');
  p.r(0, 13, 32, 2, '#9C7046');
  p.r(2, 16, 13, 5, '#6A4828');
  p.r(17, 16, 13, 5, '#6A4828');
  p.r(7, 18, 3, 1, '#C9A15A');
  p.r(22, 18, 3, 1, '#C9A15A');
});

Sprite part() => sprite('part', 8, 64, (p) {
  p.r(1, 8, 6, 56, '#8E959F');
  p.r(1, 8, 6, 2, '#B3B9C2');
  p.r(0, 0, 8, 10, '#3E8E4E');
  p.r(2, 0, 4, 3, '#58A867');
});

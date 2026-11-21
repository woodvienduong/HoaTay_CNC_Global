# encoding: UTF-8
# TEST TOÀN BỘ HOATAY GIA CÔNG (luật 05/11: sửa xong phải test lại mọi chức năng của plugin).
# Chạy trên plugin ĐÃ CÀI trong SketchUp 2024 (cài bằng du-an\cai-hoatay.ps1 -Chi giacong -KhongNap hoặc rbz):
#   output\048-sua-box-3-loi\chay-that.ps1 -Script test-giacong-toanbo.rb -Out giacong-toanbo-ket-qua.txt -Giay 300
# Tự dựng tủ mẫu trên bản sao mô hình (xoá hết rồi dựng), so KẾT QUẢ HÌNH HỌC / THUỘC TÍNH với số tính tay, gồm cả bấm thật bằng công cụ.
# Cài đặt / luật dùng BẢN SAO (không đụng dữ liệu thật). Icon so từng byte với icon-gc-duyet\.
# Cuối bài: ghi san-sang-chup.txt, đợi da-chup.txt (tối đa 90 giây) để chụp thanh công cụ + Ruby Console, rồi mới test đổi thứ tự nút.
require 'sketchup.rb'
require 'fileutils'
require 'json'
require 'tmpdir'
DIR = File.dirname(__FILE__)
OUT = File.join(DIR, 'giacong-toanbo-ket-qua.txt')
ICON_DUYET = File.join(DIR, 'icon-gc-duyet')
TMP = File.join(Dir.tmpdir, "hoatay-test-gc-#{Process.pid}")
FileUtils.mkdir_p(TMP)
GCVER = '1.1.3'
$kq = []; $dat = 0; $tong = 0; $msg = []; $loi_log = []; $dlgs = []; $ox = 0.0
File.delete(File.join(DIR, 'san-sang-chup.txt')) rescue nil
File.delete(File.join(DIR, 'da-chup.txt')) rescue nil

def luu; File.write(OUT, $kq.join("\n"), encoding: 'UTF-8'); end
def kiem(t, ok, ct = nil) $tong += 1; $dat += 1 if ok; $kq << format('%-10s| %s%s', ok ? 'ĐẠT' : 'KHÔNG ĐẠT', t, ct ? " | #{ct}" : ''); luu; end
def muc(t)
  $kq << "\n== #{t} =="
  luu
  File.write(File.join(DIR, 'dang-chay.txt'), t, encoding: 'UTF-8')
  yield
rescue Exception => e
  kiem("#{t}: lỗi Ruby #{e.class}: #{e.message}", false, (e.backtrace || []).first(4).join(' / '))
ensure
  $dlgs.each { |d| d.close rescue nil }; $dlgs.clear
  Sketchup.active_model.select_tool(nil) rescue nil
  Sketchup.active_model.selection.clear rescue nil
end
def gan(a, b, tol = 0.05) (a.to_f - b.to_f).abs <= tol end

# ---- chặn hộp thoại chờ người bấm ----
$tra_loi_input = false
module UI
  class << self
    alias_method :mb_goc, :messagebox
    def messagebox(*a) $msg << a.first.to_s; 6 end
    def inputbox(*a) $msg << "inputbox #{a.first.inspect[0, 60]}"; $tra_loi_input ? a[1] : false end
    def savepanel(*a) nil end
    def openpanel(*a) nil end
  end
end
class UI::HtmlDialog
  alias_method :show_goc, :show
  def show(*a) $dlgs << self; ($mo ||= []) << self; show_goc(*a) end
end

M = 25.4
def p3(a) Geom::Point3d.new(*a.map { |x| x / M }) end
def m_; Sketchup.active_model; end

# tấm hộp lo..hi (mm, trong toạ độ khối tủ)
def tam(ents, ten, lo, hi)
  s = (0..2).map { |i| (hi[i] - lo[i]) / M }
  g = ents.add_group
  f = g.entities.add_face([0, 0, 0], [s[0], 0, 0], [s[0], s[1], 0], [0, s[1], 0])
  f.reverse! if f.normal.z < 0
  f.pushpull(s[2])
  g.transformation = Geom::Transformation.translation(Geom::Vector3d.new(*lo.map { |x| x / M }))
  g.name = ten
  g.set_attribute('hoatay_build', 'type', 'part')
  g
end

# khối tủ mới, cách xa tủ trước; yield entities -> trả [khối tủ, kết quả khối lệnh]
def tu
  $ox += 4000.0
  m_.start_operation('dựng mẫu', true)
  cab = m_.entities.add_group
  cab.set_attribute('hoatay_build', 'type', 'cabinet')
  r = yield cab.entities
  cab.transformation = Geom::Transformation.translation(Geom::Vector3d.new($ox / M, 0, 0))
  m_.commit_operation
  [cab, r]
end

def vol(g) v = g.volume; v < 0 ? -1.0 : v * M**3 end
def nhom(p, ten) p.definition.entities.grep(Sketchup::Group).select { |g| g.name == ten } end
def tam_nhom(g) c = g.bounds.center; [c.x * M, c.y * M, c.z * M] end
def dung(a, b, tol = 0.05) a.zip(b).all? { |x, y| gan(x, y, tol) } end
def sap(ds) ds.sort_by { |x| x.map { |v| v.round(2) } } end
def co_diem?(ds, want, tol = 0.05) want.all? { |w| ds.any? { |d| dung(d, w, tol) } } end
def mat_dien(g) g.entities.grep(Sketchup::Face).sum(&:area) * M * M end

# đặt camera nhìn thẳng vào điểm (mm, toạ độ khối tủ) theo hướng dir từ điểm ra mắt -> toạ độ màn hình
def nhin(cab, pt, dir)
  v = m_.active_view
  t = p3(pt).transform(cab.transformation)
  eye = t.offset(Geom::Vector3d.new(*dir), 3000 / M)
  up = dir[2].abs > 0.9 ? Y_AXIS : Z_AXIS
  v.camera = Sketchup::Camera.new(eye, t, up)
  v.refresh
  s = v.screen_coords(t)
  [s.x.to_f, s.y.to_f]
end
def bam(tl, s, flags = 0)
  v = m_.active_view
  tl.onMouseMove(flags, s[0], s[1], v)
  tl.onLButtonDown(flags, s[0], s[1], v)
  tl.onLButtonUp(flags, s[0], s[1], v) if tl.respond_to?(:onLButtonUp)
end

def chay_test
  $LK = HoaTay::LienKet; $F = $LK::Features
  cam = $F::LienKetCam; mong = $F::Mong; build = mong::Build; khu = $F::Khu; khau = $F::Khau; ngam = $F::Ngam
  ad = $F::AmDuong; ranh = $F::Ranh; ray = $F::Ray; store = $LK::Store; cut = $LK::Cut; panel = $LK::Panel; core = $LK::Core
  vl = HoaTay::MaterialPlugin; vc = vl::Core; mat = vl::Features::Material; edge = vl::Features::Edge
  gc = HoaTay::GiaCong
  ident = Geom::Transformation.new
  # ---- dữ liệu thử: cài đặt + luật bản sao ----
  tmp_set = File.join(TMP, 'settings.json')
  store.define_singleton_method(:path) { tmp_set }
  store.reload!
  rules_tmp = File.join(TMP, 'rules.json')
  FileUtils.cp(HoaTay::Rules.file, rules_tmp) if File.exist?(HoaTay::Rules.file)
  HoaTay::Rules.define_singleton_method(:file) { rules_tmp }
  HoaTay::Rules.reload!
  [core, vc, HoaTay::Rules].each do |c|
    goc = c.method(:log_error)
    c.define_singleton_method(:log_error) { |w, e| $loi_log << "#{w}: #{e.class}: #{e.message}"; goc.call(w, e) }
  end
  m = m_
  m.active_view.camera.perspective = false rescue nil
  m.entities.clear!
  m.selection.clear

  muc('Nạp plugin') do
    ex = Sketchup.extensions.find { |e| e.name.to_s == 'HoaTay Gia công' }
    kiem("Tiện ích HoaTay Gia công #{GCVER} đã nạp", ex && ex.version == GCVER && ex.loaded?, ex && "#{ex.version} nạp=#{ex.loaded?}")
    kiem("core.rb VERSION = #{GCVER}", gc::Core::VERSION == GCVER, gc::Core::VERSION)
    kiem('Liên kết: không tính năng nào lỗi nạp, đủ 9', $LK.failed.empty? && $LK.loaded.size == 9, "#{$LK.loaded.keys.join(',')} lỗi=#{$LK.failed.inspect}")
    kiem('Vật liệu: không tính năng nào lỗi nạp, đủ 2', vl.failed.empty? && vl.loaded.size == 2, "#{vl.loaded.keys.join(',')} lỗi=#{vl.failed.inspect}")
    $msg.clear
    gc.show_about
    kiem('Thông tin phiên bản hiện đúng bản', $msg.join.include?("HoaTay Gia công #{GCVER}"), $msg.join.lines.first.to_s.strip)
  end

  muc('Liên kết cam') do
    cab, ps = tu { |e| [tam(e, 'Hồi trái', [0, 0, 0], [18, 500, 700]), tam(e, 'Đáy', [18, 0, 0], [582, 500, 18]), tam(e, 'Hồi phải', [582, 0, 0], [600, 500, 700]), tam(e, 'Hậu 8', [18, 500, 0], [582, 508, 700])] }
    l, b, r, hau = ps
    par = cab.transformation
    cfg = store.get('lienket')
    all = ngam.all_panels(m)
    js = cam.joints_of(b, par, all)
    kiem('Tìm đủ 2 mối đáy – 2 hồi', js.size == 2, js.map { |j| "#{j[:a].name}/#{j[:b].name}" }.join(', '))
    kiem('Ván mỏng hơn tối thiểu (hậu 8) không tính mối', cam.joint(l, par, hau, par, cfg).nil? && cam.joint(hau, par, b, par, cfg).nil?)
    jt = js.find { |j| j[:a] == l }
    e = :x
    core.operation('t') { e = cam.apply(jt, false, cfg); true }
    kiem('Tạo 1 mối không lỗi', e.nil?, e.inspect)
    cams = nhom(b, 'ABF_OK'); bolts = nhom(l, 'ABF_CC')
    kiem('Số lượng cố định 2: 2 ốc khóa trên đáy, 2 chốt trên hồi', cams.size == 2 && bolts.size == 2, "#{cams.size}/#{bolts.size}")
    kiem('Ốc khóa: cách mặt hồi 35, cách 2 đầu 50, ở mặt trên đáy', co_diem?(cams.map { |g| tam_nhom(g) }, [[35, 50, 18], [35, 450, 18]]), cams.map { |g| tam_nhom(g).map { |x| x.round(1) } }.inspect)
    kiem('Chốt: trên mặt hồi, tâm cách mặt có ốc khóa 7', co_diem?(bolts.map { |g| tam_nhom(g) }, [[18, 50, 11], [18, 450, 11]]), bolts.map { |g| tam_nhom(g).map { |x| x.round(1) } }.inspect)
    dk = ->(g) { [g.bounds.width, g.bounds.height, g.bounds.depth].max * M }
    kiem('Đường kính ốc khóa 15, chốt 5', cams.all? { |g| gan(dk.(g), 15, 0.1) } && bolts.all? { |g| gan(dk.(g), 5, 0.1) }, "#{dk.(cams[0]).round(2)}/#{dk.(bolts[0]).round(2)}")
    kiem('Tag ABF_OK / ABF_CC + thuộc tính ABF như ZSU', cams.all? { |g| g.layer.name == 'ABF_OK' && g.get_attribute('ABF', 'is-minifix-part-b') == true } && bolts.all? { |g| g.layer.name == 'ABF_CC' })
    kiem('Ốc khóa và chốt cùng mã mối', cam.shared_ids(l, b).size == 1)
    core.operation('t') { e = cam.apply(jt, false, cfg); true }
    kiem('Luật không chồng liên kết: tạo lại mối đó bị từ chối', e.to_s.include?('chồng') && nhom(b, 'ABF_OK').size == 2, e.to_s)
    core.operation('t') { e = cam.flip_joint(jt, cfg); true }
    kiem('Đảo mặt: ốc khóa sang mặt dưới, chốt cách mặt dưới 7', e.nil? && co_diem?(nhom(b, 'ABF_OK').map { |g| tam_nhom(g) }, [[35, 50, 0], [35, 450, 0]]) && co_diem?(nhom(l, 'ABF_CC').map { |g| tam_nhom(g) }, [[18, 50, 7], [18, 450, 7]]), e.inspect)
    n = 0
    core.operation('t') { n = cam.remove(b, all); true }
    kiem('Xóa liên kết: sạch cả 2 tấm', n == 1 && cam.marks(b).empty? && cam.marks(l).empty?, n.to_s)
    # bấm thật
    cam.start
    tl = m.tools.active_tool
    kiem('Nút Liên kết cam mở đúng công cụ', tl.is_a?(cam::CamTool), tl.class.to_s)
    s = nhin(cab, [300, 250, 18], [0, 0, 1])
    bam(tl, s, CONSTRAIN_MODIFIER_MASK)
    kiem('Bấm thật + Shift: đánh hết 2 mối của đáy', nhom(b, 'ABF_OK').size == 4 && nhom(l, 'ABF_CC').size == 2 && nhom(r, 'ABF_CC').size == 2, "#{nhom(b, 'ABF_OK').size}/#{nhom(l, 'ABF_CC').size}/#{nhom(r, 'ABF_CC').size}")
    Sketchup.undo
    kiem('Undo 1 bước trả lại', nhom(b, 'ABF_OK').empty? && nhom(l, 'ABF_CC').empty?)
    tl.onUserText('3/60', m.active_view)
    cfg = store.get('lienket')
    kiem('Ô đo "3/60": 3 liên kết, cách đầu 60', cfg['so_luong'] == 3 && cfg['cach_hai_dau'] == 60)
    bam(tl, nhin(cab, [100, 250, 18], [0, 0, 1]))
    kiem('Bấm thật gần hồi trái: 3 ốc khóa đúng vị trí', nhom(b, 'ABF_OK').size == 3 && co_diem?(nhom(b, 'ABF_OK').map { |g| tam_nhom(g) }, [[35, 60, 18], [35, 250, 18], [35, 440, 18]]), nhom(b, 'ABF_OK').map { |g| tam_nhom(g).map { |x| x.round(1) } }.inspect)
    v = m.active_view
    tl.onKeyDown(9, 0, 0, v); tl.onKeyDown(9, 0, 0, v) # Tab Tab -> Xóa
    bam(tl, nhin(cab, [300, 250, 18], [0, 0, 1]))
    kiem('Tab sang Xóa, bấm thật: xóa hết', nhom(b, 'ABF_OK').empty? && nhom(l, 'ABF_CC').empty?)
    store.reset('lienket')
  end

  muc('Mộng gỗ') do
    cab, ps = tu { |e| [tam(e, 'Hồi trái', [0, 0, 0], [18, 500, 700]), tam(e, 'Đáy', [18, 0, 0], [582, 500, 18]), tam(e, 'Hồi phải', [582, 0, 0], [600, 500, 700])] }
    l, b, r = ps
    cfg = store.get('mong')
    kiem('Tìm 2 cạnh có tấm áp vào', build.candidate_sides(b).size == 2)
    v0 = vol(b); w0 = b.bounds.width * M
    pl = build.plan(b, cfg, ->(a) { a.select { |x| x[:s] > 0 } })
    kiem('Kế hoạch 1 cạnh: 2 mộng ở 50–100, 400–450', pl[:items].size == 1 && dung(pl[:items][0][:pos].flatten.map { |x| x * M }, [50, 100, 400, 450]), pl[:errors].join(';'))
    n = core.operation('t') { build.apply(b, pl, cfg) }
    kiem('Tạo 2 mộng', n == 2, n.inspect)
    kiem('Lưỡi: thò ra 12, thể tích tăng đúng 2 × 575 × 18 (khử dao vuông 5)', gan(b.bounds.width * M - w0, 12) && gan(vol(b) - v0, 2 * 575 * 18, 2), "dài +#{(b.bounds.width * M - w0).round(2)}, thể tích +#{(vol(b) - v0).round(1)}")
    kiem('Hộp lõi tấm không đổi (bỏ lưỡi)', gan((panel.core_box(b.definition)[1][0] - panel.core_box(b.definition)[0][0]) * M, 564))
    am = nhom(r, 'ABF_'); moi = nhom(r, 'ABF_KM')
    kiem('Mộng âm trên hồi: 2 nhóm ABF_, layer MONGXUONGCHO, is-intersect', am.size == 2 && am.all? { |g| g.layer.name == 'MONGXUONGCHO' && g.get_attribute('ABF', 'is-intersect') == true }, am.size.to_s)
    kiem('Mộng âm diện tích đúng (dài 50 + 2×0,2, dày 18 + 2×0,1, tai khử dao)', am.all? { |g| gan(mat_dien(g), 967.28, 0.5) }, am.map { |g| mat_dien(g).round(2) }.inspect)
    kiem('Lỗ mồi: Ø3, layer ABF_KM, cách mộng 7 về phía giữa, giữa chiều dày', moi.size == 2 && moi.all? { |g| g.layer.name == 'ABF_KM' } && co_diem?(moi.map { |g| tam_nhom(g) }, [[0, 107, 9], [0, 393, 9]]), moi.map { |g| tam_nhom(g).map { |x| x.round(1) } }.inspect)
    kiem('Hồi trái không bị đụng', l.definition.entities.grep(Sketchup::Group).empty?)
    n = core.operation('t') { build.apply(b, build.plan(b, cfg, ->(a) { a.select { |x| x[:s] > 0 } }), cfg) }
    kiem('Đánh lại cùng cạnh: thay mộng cũ, không chồng thêm', nhom(r, 'ABF_').size == 2 && gan(vol(b) - v0, 2 * 575 * 18, 2), "#{nhom(r, 'ABF_').size} mộng âm")
    n = core.operation('t') { build.remove_all(b) }
    kiem('Xóa mộng: trả cạnh như cũ, sạch mộng âm + lỗ mồi', n == 2 && gan(vol(b), v0, 1) && gan(b.bounds.width * M, w0) && nhom(r, 'ABF_').empty? && nhom(r, 'ABF_KM').empty? && !build.has_mong?(b), "xóa #{n}, thể tích #{(vol(b) - v0).round(2)}")
    # không chồng liên kết: chốt cam đã có ở vị trí mộng âm
    core.operation('t') { cam.apply(cam.joints_of(b, cab.transformation, ngam.all_panels(m), store.get('lienket')).find { |j| j[:a] == r }, false, store.get('lienket')); true }
    pl = build.plan(b, cfg, ->(a) { a.select { |x| x[:s] > 0 } })
    kiem('Luật không chồng: cạnh có chốt cam thì không tạo mộng', pl[:items].empty? && pl[:errors].join.include?('Chồng'), pl[:errors].join(';')[0, 80])
    core.operation('t') { cam.remove(b, ngam.all_panels(m)); true }
    # bấm thật
    mong.start
    tl = m.tools.active_tool
    bam(tl, nhin(cab, [60, 250, 18], [0, 0, 1]))
    kiem('Bấm thật gần hồi trái: mộng vào hồi trái', nhom(l, 'ABF_').size == 2 && nhom(r, 'ABF_').empty?, "#{nhom(l, 'ABF_').size}/#{nhom(r, 'ABF_').size}")
    Sketchup.undo
    kiem('Undo trả lại', nhom(l, 'ABF_').empty? && gan(vol(b), v0, 1))
    bam(tl, nhin(cab, [60, 250, 18], [0, 0, 1]), COPY_MODIFIER_MASK)
    kiem('Bấm thật + Ctrl: đối xứng 2 cạnh', nhom(l, 'ABF_').size == 2 && nhom(r, 'ABF_').size == 2)
    tl.onKeyDown(9, 0, 0, m.active_view)
    bam(tl, nhin(cab, [300, 250, 18], [0, 0, 1]))
    kiem('Tab sang Xóa, bấm thật: xóa hết', nhom(l, 'ABF_').empty? && nhom(r, 'ABF_').empty? && gan(vol(b), v0, 1))
    tl.onKeyDown(9, 0, 0, m.active_view)
    tl.onUserText('3/x', m.active_view)
    kiem('Ô đo "3/x": 3 mộng', store.get('mong')['so_mong'] == 3)
    store.reset('mong')
    c2 = store.get('mong').merge('khu_dao' => false, 'bo_dau' => 3)
    pl = build.plan(b, c2, ->(a) { a.select { |x| x[:s] > 0 } })
    v1 = vol(b)
    core.operation('t') { build.apply(b, pl, c2) }
    want = 2 * (50 * 12 - 2 * (9 - 0.5 * 12 * 9 * Math.sin(Math::PI / 6) / 4)) * 18
    kiem('Tùy chọn bo đầu 3, không khử dao: thể tích lưỡi đúng', gan(vol(b) - v1, want, 3), "+#{(vol(b) - v1).round(1)} / tính tay #{want.round(1)}")
    core.operation('t') { build.remove_all(b) }
  end

  khoet = lambda do |p, u0, u1, v0, v1|
    core.operation('khoét mẫu') { cut.cut(p.definition, panel.core_box(p.definition), khau::Plan.rect_segs([u0 / M, u1 / M, v0 / M, v1 / M]), 'khau', 'mau'); true }
  end
  tam_ngang = ->(e, t, ox = 0) { tam(e, t, [ox, 0, 0], [ox + 400, 300, 18]) }

  muc('1.1.3 Liên kết: X-ray, rê chuột, hậu mỏng, khoảng cách, bỏ ô chưa làm') do
    ro = m.rendering_options
    ro['ModelTransparency'] = false
    mong.start
    kiem('Vào lệnh Mộng gỗ: tự bật X-ray', ro['ModelTransparency'] == true)
    m.select_tool(nil)
    kiem('Thoát lệnh: X-ray trả về tắt như cũ', ro['ModelTransparency'] == false)
    ro['ModelTransparency'] = true
    mong.start; m.select_tool(nil)
    kiem('Đang bật X-ray sẵn: thoát lệnh vẫn giữ X-ray', ro['ModelTransparency'] == true)
    ro['ModelTransparency'] = false
    [[$F::LienKetCam, 'Liên kết cam'], [khu, 'Khử dao'], [khau, 'Khấu ván'], [ngam, 'Ngàm'], [ad, 'Âm dương'], [ranh, 'Rãnh hậu'], [ray, 'Ray']].each do |mod, ten|
      mod.start rescue nil
      on = ro['ModelTransparency'] == true
      m.select_tool(nil)
      kiem("#{ten}: vào lệnh bật X-ray, thoát trả như cũ", on && ro['ModelTransparency'] == false)
    end
    # hậu 8 sau đáy: không phải tấm nhận mộng
    cab, ps = tu { |e| [tam(e, 'Hồi trái', [0, 0, 0], [18, 500, 700]), tam(e, 'Đáy', [18, 0, 0], [582, 500, 18]), tam(e, 'Hồi phải', [582, 0, 0], [600, 500, 700]), tam(e, 'Hậu', [18, 500, 0], [582, 508, 700])] }
    l, b, r, hau = ps
    cs = build.candidate_sides(b)
    kiem('Hậu 8 (< ván dày tối thiểu 17,5) không được nhận mộng', cs.size == 2 && cs.none? { |sd| sd[:recvs].any? { |x| x[:r] == hau } }, cs.size.to_s)
    store.set('mong', 'van_day_toi_thieu', 0)
    kiem('Ván dày tối thiểu = 0: hậu được xét lại (tắt điều kiện)', build.candidate_sides(b).size == 3)
    store.reset('mong')
    mong.start
    tl = m.tools.active_tool
    bam(tl, nhin(cab, [300, 250, 18], [0, 0, 1]), CONSTRAIN_MODIFIER_MASK)
    kiem('Bấm thật + Shift (mọi cạnh): mộng vào 2 hồi, KHÔNG vào hậu', nhom(l, 'ABF_').size == 2 && nhom(r, 'ABF_').size == 2 && nhom(hau, 'ABF_').empty?, "#{nhom(l, 'ABF_').size}/#{nhom(r, 'ABF_').size}/#{nhom(hau, 'ABF_').size}")
    Sketchup.undo
    m.select_tool(nil)
    # chia theo khoảng cách: cạnh 500, cách đầu 50, dài 50 -> 400 dùng; khoảng 200 -> 3 mộng
    c3 = store.get('mong').merge('so_luong_co_dinh' => false, 'khoang_cach' => 200)
    pos = mong::Plan.positions(0.0, 500 / M, c3)
    kiem('Chia theo khoảng cách 200: 3 mộng 50–100, 225–275, 400–450', pos.is_a?(Array) && pos.size == 3 && dung(pos.flatten.map { |x| x * M }, [50, 100, 225, 275, 400, 450]), pos.inspect[0, 80])
    pos = mong::Plan.positions(0.0, 500 / M, c3.merge('khoang_cach' => 350))
    kiem('Khoảng cách 350 (>= 350 giữa 2 tâm): 2 mộng', pos.is_a?(Array) && pos.size == 2, pos.inspect[0, 60])
    kiem('Khoảng cách 0: báo lỗi, không tự đặt số', mong::Plan.positions(0.0, 500 / M, c3.merge('khoang_cach' => 0)).is_a?(String))
    # ô chưa làm đã xoá hẳn
    kiem('Mộng: không còn Bào mộng, Lỗ mồi tiết diện vuông', !store.get('mong').key?('bao_mong') && !store.get('mong').key?('moi_vuong'))
    kiem('Khấu: không còn Sử dụng tiết diện / Instance / Layer', (store.get('khau').keys & %w[tiet_dien kv_instance kv_layer]).empty?)
    kiem('Ray: không còn Loại ray', !store.get('ray').key?('loai_ray'))
    src = Dir[File.join(core::ROOT_DIR, 'features', '**', '*.rb')].map { |f| File.read(f, encoding: 'UTF-8') }.join
    kiem('Không còn câu "chưa làm" trong code Liên kết', !src.include?('chưa làm'))
    # Pick xét mọi tấm dưới chuột
    s = nhin(cab, [300, 250, 18], [0, 0, 1])
    li = $LK::Pick.panels(m.active_view, s[0], s[1])
    kiem('Bắt chuột: tấm gần nhất trước (đáy), có cả tấm khác dưới chuột', li.first && li.first[0] == b, li.map { |x| x[0].name }.inspect)
  end

  muc('Khử dao') do
    cab, ps = tu { |e| [tam_ngang.(e, 'K1'), tam_ngang.(e, 'K2', 500), tam_ngang.(e, 'K3', 1000), tam_ngang.(e, 'K4', 1500), tam_ngang.(e, 'K5', 2000)] }
    k1, k2, k3, k4, k5 = ps
    [k1, k2, k4, k5].each { |p| khoet.(p, 0, 100, 0, 100) }
    khoet.(k3, 0, 8, 0, 8)
    cfg = store.get('khu')
    pl = khu.plan(k1, cfg, false)
    kiem('Tìm đúng 1 góc âm của tấm khoét góc', pl[:ok].size == 1, pl[:skip].inspect[0, 80])
    v0 = vol(k1)
    r = core.operation('t') { khu.apply(k1, cfg, false) }
    kiem('Khử vuông: 1 góc, khoét đúng 5 × 2,5 × 18', r && r[0] == 1 && gan(v0 - vol(k1), 225, 0.5), "#{r.inspect} −#{(v0 - vol(k1)).round(2)} mm³")
    kiem('Tấm vẫn là khối kín', k1.manifold?)
    kiem('Mặt khoét có dấu hoatay_lk.khu', k1.definition.entities.grep(Sketchup::Face).any? { |f| !f.get_attribute(core::DICT, 'khu').nil? })
    kiem('Góc đã khử không khử lại', khu.plan(k1, cfg, false)[:ok].empty?)
    v0 = vol(k2)
    r = core.operation('t') { khu.apply(k2, cfg.merge('tiet_dien_vuong' => false), false) }
    kiem('Khử tròn: nửa vòng tròn Ø5', r && r[0] == 1 && gan(v0 - vol(k2), 168.75, 1), "−#{(v0 - vol(k2)).round(2)}")
    pl = khu.plan(k3, cfg, false)
    kiem('Góc có cạnh ngắn hơn tối thiểu thì bỏ qua', pl[:ok].empty? && pl[:skip].size == 1 && pl[:skip][0][2].include?('ngắn'), pl[:skip].map { |x| x[2] }.inspect)
    v0 = vol(k4)
    r = core.operation('t') { khu.apply(k4, cfg.merge('khu_sau_them' => 1), false) }
    kiem('Khử sâu thêm 1: 5 × 3,5 × 18', r && r[0] == 1 && gan(v0 - vol(k4), 315, 0.5), "−#{(v0 - vol(k4)).round(2)}")
    c = khu.plan(k5, cfg, false)[:ok][0][0]
    a = cut.points(khu::Plan.relief(c, cfg, false)); b2 = cut.points(khu::Plan.relief(c, cfg, true))
    kiem('Tab: đổi sang cạnh kia của góc', sap(a) != sap(b2))
    khu.start
    tl = m.tools.active_tool
    v0 = vol(k5)
    bam(tl, nhin(cab, [2250, 200, 18], [0, 0, 1]))
    kiem('Bấm thật vào tấm: khử hết góc âm', gan(v0 - vol(k5), 225, 0.5), "−#{(v0 - vol(k5)).round(2)}")
    Sketchup.undo
    kiem('Undo trả lại', gan(vol(k5), v0, 0.5))
  end

  muc('Khấu ván') do
    cab, ps = tu do |e|
      [tam(e, 'Bị khấu', [0, 0, 0], [600, 400, 18]), tam(e, 'Dao', [200, 0, -100], [218, 150, 300]),
       tam(e, 'Bị khấu 2', [0, 0, 1000], [600, 400, 1018]), tam(e, 'Dao 2', [200, 0, 900], [218, 150, 1300]),
       tam(e, 'Rãnh', [300, 300, 10], [308, 380, 300]), tam(e, 'Bị khấu 3', [0, 0, 2000], [600, 400, 2018]), tam(e, 'Dao 3', [200, 0, 1900], [218, 150, 2300])]
    end
    t, c, t2, c2, rn, t3, c3 = ps
    cfg = store.get('khau')
    auto = khau.auto_cutters(t)
    kiem('Tự tìm dao chồng lên ván', auto.include?(c) && auto.include?(rn), auto.map(&:name).join(', '))
    pl = khau.plan(t, auto, cfg)
    kiem('Dao không xuyên hết chiều dày (rãnh) bị bỏ qua', pl[:skip].any? { |x, w| x == rn && w.include?('xuyên') } && pl[:ok].size == 1, pl[:skip].map { |_x, w| w }.inspect)
    v0 = vol(t)
    r = core.operation('t') { khau.apply(t, [c], cfg.merge('khu_sau_khau' => false)) }
    kiem('Khấu xuyên: khoét đúng 18 × 150 × 18, không khử dao', r && r[0] == 1 && r[1] == 0 && gan(v0 - vol(t), 48600, 1), "#{r.inspect} −#{(v0 - vol(t)).round(1)}")
    kiem('Dao giữ nguyên', gan(vol(c), 18 * 150 * 400, 2))
    kiem('Khấu lại chỗ đã trống: báo không còn gì để cắt', (x = core.operation('t') { khau.apply(t, [c], cfg) }) && x[0] == 0, x.inspect[0, 90])
    v0 = vol(t2)
    r = core.operation('t') { khau.apply(t2, [c2], cfg) }
    kiem('Khử dao sau khấu: 2 góc âm vừa tạo', r && r[0] == 1 && r[1] == 2 && gan(v0 - vol(t2), 48600 + 450, 1), "#{r.inspect} −#{(v0 - vol(t2)).round(1)}")
    kiem('Tấm sau khấu vẫn kín', t.manifold? && t2.manifold?)
    v0 = vol(t3)
    r = core.operation('t') { khau.apply(t3, [c3], cfg.merge('khu_sau_khau' => false, 'khau_them' => 1)) }
    kiem('Khấu thêm 1: vùng rộng 20 × 151', gan(v0 - vol(t3), 20 * 151 * 18, 1), "−#{(v0 - vol(t3)).round(1)}")
    cab2, ps2 = tu { |e| [tam(e, 'Ván', [0, 0, 0], [600, 400, 18]), tam(e, 'Dao', [200, 0, -100], [218, 150, 300])] }
    tv, tc = ps2
    panel.mark_ngam!(tv, tc, 'x')
    kiem('Cặp đã làm ngàm: Khấu ván bỏ qua, giữ ngàm', khau.plan(tv, [tc], cfg)[:skip].any? { |_x, w| w.include?('ngàm') })
    tv.delete_attribute(core::DICT, 'ngam'); tc.delete_attribute(core::DICT, 'ngam')
    khau.start
    tl = m.tools.active_tool
    v0 = vol(tv)
    bam(tl, nhin(cab2, [450, 300, 18], [0, 0, 1]))
    tl.onReturn(m.active_view)
    kiem('Bấm thật tấm + Enter: tự tìm dao, khấu + khử 2 góc', gan(v0 - vol(tv), 48600 + 450, 1), "−#{(v0 - vol(tv)).round(1)}")
    Sketchup.undo
    kiem('Undo trả lại 1 bước', gan(vol(tv), v0, 1))
  end

  muc('Ngàm định vị') do
    mau = ->(e) { [tam(e, 'Hồi', [0, 0, 0], [18, 500, 700]), tam(e, 'Giằng', [0, 0, 682], [600, 100, 700])] }
    cab, (p, r) = tu { |e| mau.(e) }
    par = cab.transformation
    cfg = store.get('ngam')
    kiem('Tự tìm giằng xuyên qua hồi', ngam.auto_rails(p, par).map(&:first).include?(r))
    vp = vol(p); vr = vol(r)
    x = core.operation('t') { ngam.apply(p, par, [[r, par]], cfg.merge('khu_sau' => false), false) }
    kiem('Khoét hồi (100 − 10) × 18 × 18', x && x[0] == 1 && gan(vp - vol(p), 90 * 18 * 18, 1), "#{x.inspect} −#{(vp - vol(p)).round(1)}")
    kiem('Khoét giằng 10 × 18 × 18 (ngàm)', gan(vr - vol(r), 10 * 18 * 18, 1), "−#{(vr - vol(r)).round(1)}")
    trong = ->(y, z) { cut.in_material?(p.definition.entities, 0, 1, 2, 18 / M, [y / M, z / M]) }
    kiem('Ngàm nằm phía trong tủ: còn thịt ở y 95, trống ở y 50', trong.(95, 690) && !trong.(50, 690))
    kiem('Đánh dấu cặp ngàm', panel.ngam_pair?(p, r))
    y = core.operation('t') { ngam.apply(p, par, [[r, par]], cfg, false) }
    kiem('Làm lại cặp đã có ngàm: không khoét thêm', y && y[0] == 0 && y[2].join.include?('đã có ngàm'), y.inspect[0, 80])
    kiem('2 tấm vẫn kín', p.manifold? && r.manifold?)
    cab2, (p2, r2) = tu { |e| mau.(e) }
    par2 = cab2.transformation
    core.operation('t') { ngam.apply(p2, par2, [[r2, par2]], cfg.merge('khu_sau' => false), true) }
    tr2 = ->(yy, zz) { cut.in_material?(p2.definition.entities, 0, 1, 2, 18 / M, [yy / M, zz / M]) }
    kiem('Tab đổi hướng: ngàm sang đầu kia (y 5)', tr2.(5, 690) && !tr2.(50, 690))
    cab3, (p3a, r3) = tu { |e| mau.(e) }
    par3 = cab3.transformation
    vp = vol(p3a); vr = vol(r3)
    x = core.operation('t') { ngam.apply(p3a, par3, [[r3, par3]], cfg, false) }
    kiem('Khử dao sau khoét: 2 góc', x && x[1] == 2 && gan(vp - vol(p3a), 90 * 18 * 18 + 225, 1) && gan(vr - vol(r3), 10 * 18 * 18 + 225, 1), x.inspect[0, 60])
    cab4, (p4, r4) = tu { |e| mau.(e) }
    ngam.start
    tl = m.tools.active_tool
    vp = vol(p4)
    bam(tl, nhin(cab4, [0, 300, 300], [-1, 0, 0]))
    tl.onReturn(m.active_view)
    kiem('Bấm thật tấm đứng + Enter: tự tìm giằng, làm ngàm', panel.ngam_pair?(p4, r4) && gan(vp - vol(p4), 90 * 18 * 18 + 225, 1), "−#{(vp - vol(p4)).round(1)}")
    Sketchup.undo
    kiem('Undo trả lại', !panel.ngam_pair?(p4, r4) && gan(vol(p4), vp, 1))
  end

  muc('Âm dương (khấu âm dương)') do
    mau = ->(e) { [tam(e, 'Vách', [300, 0, 0], [318, 500, 700]), tam(e, 'Đợt', [0, 0, 300], [600, 500, 318])] }
    cab, (a, b) = tu { |e| mau.(e) }
    par = cab.transformation
    cfg = store.get('amduong')
    kiem('Nhận 2 tấm chéo', ad.crossing(a, par, b, par).is_a?(Hash))
    va = vol(a); vb = vol(b)
    p, pp, r, rp = ad.order(a, par, b, par)
    kiem('Tấm 1 = tấm đứng', p == a)
    e = :x
    core.operation('t') { e = ad.apply(p, pp, r, rp, cfg, false); true }
    want = (18.2 * 250.5 + 2 * 5 * 2.5) * 18
    kiem('Khe vách: rộng 18,2, sâu 250,5, 2 góc khử', e.nil? && gan(va - vol(a), want, 2), "#{e.inspect} −#{(va - vol(a)).round(1)} / #{want.round(1)}")
    kiem('Khe đợt: bằng khe vách', gan(vb - vol(b), want, 2), "−#{(vb - vol(b)).round(1)}")
    tr = ->(pa, y, z) { cut.in_material?(pa.definition.entities, 0, 1, 2, 18 / M, [y / M, z / M]) }
    kiem('Vách mở từ đầu sau (y 500): trống ở y 400, còn thịt ở y 200', !tr.(a, 400, 309) && tr.(a, 200, 309))
    kiem('Đánh dấu cặp, Khấu ván không khấu nữa', ad.done?(a, b) && panel.ngam_pair?(a, b))
    core.operation('t') { e = ad.apply(p, pp, r, rp, cfg, false); true }
    kiem('Làm lại cặp đã làm: từ chối', e.to_s.include?('đã làm'), e.to_s)
    kiem('2 tấm vẫn kín', a.manifold? && b.manifold?)
    cab2, (a2, b2) = tu { |e2| mau.(e2) }
    par2 = cab2.transformation
    core.operation('t') { e = ad.apply(a2, par2, b2, par2, cfg, true); true }
    tr2 = ->(y) { cut.in_material?(a2.definition.entities, 0, 1, 2, 18 / M, [y / M, 309 / M]) }
    kiem('Tab đổi đầu mở khe: vách mở từ đầu trước', e.nil? && !tr2.(100) && tr2.(400), e.inspect)
    cab3, (a3, b3) = tu { |e2| mau.(e2) }
    m.selection.clear; m.selection.add([a3, b3])
    ad.start
    tl = m.tools.active_tool
    va = vol(a3)
    tl.onReturn(m.active_view)
    kiem('Chọn sẵn 2 tấm, bấm nút + Enter: khấu', ad.done?(a3, b3) && gan(va - vol(a3), want, 2), "−#{(va - vol(a3)).round(1)}")
    Sketchup.undo
    kiem('Undo trả lại', !ad.done?(a3, b3) && gan(vol(a3), va, 1))
  end

  muc('Phay rãnh (rãnh hậu)') do
    cab, ps = tu { |e| [tam(e, 'Hồi trái', [0, 0, 0], [18, 500, 700]), tam(e, 'Hồi phải', [582, 0, 0], [600, 500, 700]), tam(e, 'Hậu', [10, 480, 10], [590, 488, 690])] }
    l, r, hau = ps
    par = cab.transformation
    cfg = store.get('ranh')
    rv = ranh.receivers(hau, par, cfg)
    kiem('Tìm 2 tấm nhận (2 hồi)', rv.size == 2 && rv.all? { |x| x[2].is_a?(Hash) }, rv.map { |x| x[0].name }.join(', '))
    e = :x
    core.operation('t') { e = ranh.build(l, par, hau, par, cfg); true }
    g = nhom(l, 'ABF_Intersect')
    kiem('Tạo nhóm ABF_Intersect, layer ABF_Groove', e.nil? && g.size == 1 && g[0].layer.name == 'ABF_Groove', e.inspect)
    f = g[0].entities.grep(Sketchup::Face).first
    kiem('Mặt tiết diện 8 × (680 + 2×2,5), trên mặt hồi nơi hậu vào, hướng ra', gan(f.area * M * M, 8 * 685, 1) && gan(g[0].bounds.center.x * M, 18) && f.normal.x > 0.99, "#{(f.area * M * M).round(1)} mm²")
    kiem('Vật liệu Orange', f.material && f.material.name == 'Orange')
    at = ->(k) { g[0].get_attribute('ABF', k) }
    kiem('Thuộc tính ABF: is-intersect, group-b-id = hậu, nới giãn 2,5', at.('is-intersect') == true && at.('intersect-group-b-id').to_s == hau.persistent_id.to_s && gan(at.('intersect-x').to_f * M, 2.5))
    kiem('Không cắt hình tấm (giữ 6 mặt)', l.definition.entities.grep(Sketchup::Face).size == 6)
    kiem('Tấm đã có rãnh của hậu: không tạo lại', ranh.plan_one(l, par, hau, par, cfg).to_s.include?('đã có rãnh'))
    pb = [[0, 0, 0], [18, 500, 700]].map { |a| a.map { |x| x / M } }
    bb = [[-5, 480, 10], [30, 488, 690]].map { |a| a.map { |x| x / M } }
    kiem('Xuyên hết chiều dày: bảo dùng Khấu ván', ranh::Plan.groove(pb, bb, 0, 0, panel::TOL).to_s.include?('Khấu ván'))
    ranh.start
    tl = m.tools.active_tool
    bam(tl, nhin(cab, [300, 488, 350], [0, 1, 0]))
    tl.onReturn(m.active_view)
    gr = nhom(r, 'ABF_Intersect')
    kiem('Bấm thật hậu + Enter: rãnh hồi phải, hướng về hậu', gr.size == 1 && gr[0].entities.grep(Sketchup::Face).first.normal.x < -0.99 && nhom(l, 'ABF_Intersect').size == 1, gr.size.to_s)
    Sketchup.undo
    kiem('Undo trả lại', nhom(r, 'ABF_Intersect').empty?)
  end

  muc('Đánh dấu ray') do
    cab, ps = tu { |e| [tam(e, 'Hông', [0, 0, 0], [18, 500, 700]), tam(e, 'Hộc', [40, 0, 100], [52, 400, 250])] }
    c, d = ps
    par = cab.transformation
    cfg = store.get('ray')
    cao = cfg['cao_tu_day'].to_f
    pl = ray.plan(d, par, c, par, cfg)
    kiem('Kế hoạch được', pl.is_a?(Hash), pl.to_s[0, 60])
    e = :x
    core.operation('t') { e = ray.apply(d, par, c, par, cfg); true }
    gd = ray.marks(d); gh = ray.marks(c)
    kiem('Tạo 1 dấu trên hộc + 1 dấu trên hông', e.nil? && gd.size == 1 && gh.size == 1, e.inspect)
    kiem('Nhóm ABF_PTL Tools, layer0, vật liệu ABF_RAY, is-user-nesting-obj', (gd + gh).all? { |g| g.name == 'ABF_PTL Tools' && g.material && g.material.name == 'ABF_RAY' && g.get_attribute('ABF', 'is-user-nesting-obj') == true })
    ed = gd[0].entities.grep(Sketchup::Edge)
    kiem('Cạnh dấu trên tag ABF_RAY, dài hết sâu hộc 400', ed.size == 1 && ed[0].layer.name == cfg['tag'] && gan(ed[0].length.to_f * M, 400), ed[0] && "#{ed[0].layer.name} #{(ed[0].length.to_f * M).round(1)}")
    o = gd[0].transformation.origin
    kiem("Trên hộc: cao #{cao} từ đáy hộc, mặt quay về hông", gan(o.z * M, cao) && gan(o.x * M, 0), [o.x, o.y, o.z].map { |x| (x * M).round(1) }.inspect)
    o2 = gh[0].transformation.origin
    kiem('Trên hông: chiếu sang mặt quay về hộc, cùng độ cao thật', gan(o2.x * M, 18) && gan(o2.z * M, 100 + cao), [o2.x, o2.y, o2.z].map { |x| (x * M).round(1) }.inspect)
    core.operation('t') { e = ray.apply(d, par, c, par, cfg); true }
    kiem('Hộc đã có dấu: từ chối', e.to_s.include?('đã có dấu'), e.to_s)
    n = 0
    core.operation('t') { n = ray.remove(d) + ray.remove(c); true }
    kiem('Xóa dấu: sạch 2 tấm', n == 2 && ray.marks(d).empty? && ray.marks(c).empty?)
    kiem('Cao vượt tấm hộc: báo lỗi', ray.plan(d, par, c, par, cfg.merge('cao_tu_day' => 999)).to_s.include?('vượt'))
    ray.start
    tl = m.tools.active_tool
    bam(tl, nhin(cab, [52, 200, 175], [1, 0, 0]))
    bam(tl, nhin(cab, [18, 450, 600], [1, 0, 0]))
    kiem('Bấm thật hộc rồi hông: tạo dấu', ray.marks(d).size == 1 && ray.marks(c).size == 1)
    tl.onKeyDown(9, 0, 0, m.active_view)
    bam(tl, nhin(cab, [52, 200, 175], [1, 0, 0]))
    kiem('Tab sang Xóa, bấm thật: xóa dấu hộc', ray.marks(d).empty?)
  end

  muc('Cài đặt (Liên kết)') do
    tools = store.tools
    kiem('Đủ 8 công cụ trong bảng', (%w[mong khu khau ngam lienket amduong ranh ray] - tools).empty?, tools.join(','))
    tools.each { |t| store.reset(t) }
    kiem('Giá trị gốc đúng (ZSU xưởng)', store.value('lienket', 'd_cam') == 15 && store.value('mong', 'chieu_dai') == 50 && store.value('ngam', 'be_rong_ngam') == 10 && store.value('khu', 'duong_kinh_dao') == 5)
    store.set('mong', 'chieu_dai', 70)
    store.reload!
    kiem('Đổi 1 ô: lưu ra file, đọc lại đúng', store.value('mong', 'chieu_dai') == 70)
    kiem('Lưu mẫu', store.save_preset('mong', 'Mẫu thử') && store.presets('mong').any? { |x| x['name'] == 'Mẫu thử' } && store.selected('mong') == 'Mẫu thử')
    store.apply_preset('mong', 'Mộng 50')
    kiem('Áp mẫu khác', store.value('mong', 'chieu_dai') == 50)
    store.apply_preset('mong', 'Mẫu thử')
    kiem('Áp lại mẫu đã lưu', store.value('mong', 'chieu_dai') == 70)
    kiem('Xóa mẫu', store.delete_preset('mong', 'Mẫu thử') && store.presets('mong').none? { |x| x['name'] == 'Mẫu thử' })
    store.reset('mong')
    kiem('Đặt lại cài đặt gốc', store.value('mong', 'chieu_dai') == 50)
    st = $F::Settings
    st.open('mong')
    kiem('Bảng Cài đặt mở, có đủ ô', !$dlgs.empty? && st.state[:tools].size >= 8 && !st.state[:full].empty?, "#{st.state[:tools].size} mục")
    html = File.read(File.join(core::ROOT_DIR, 'features/settings/dialog.html'), encoding: 'UTF-8')
    kiem('Có dòng Luật trong Cài đặt', html.include?('Luật xưởng'))
  end

  muc('Thư viện vật liệu + Tô + Gỡ') do
    root = File.join(TMP, 'thu-vien')
    d = File.join(root, 'An Cường - Melamine')
    FileUtils.mkdir_p(d)
    FileUtils.cp(File.join(gc::Core::ROOT_DIR, 'assets', 'logo.png'), File.join(d, 'MAU01.png'))
    FileUtils.cp(File.join(gc::Core::ROOT_DIR, 'assets', 'logo.png'), File.join(d, 'MAU02.png'))
    lib = mat::Library
    sc = lib.scan(root, true)
    kiem('Quét thư viện: nhận hãng + mã', sc[:error].nil? && sc[:items].size == 2 && sc[:brands].any? { |b| b[:name] == 'An Cường' }, sc[:brands].map { |b| b[:name] }.inspect)
    kiem('Thư mục không có: báo lỗi', !lib.scan(File.join(TMP, 'khong-co'), true)[:error].nil?)
    mat.define_singleton_method(:root) { root }
    mat.define_singleton_method(:roots) { [root] }
    mat.define_singleton_method(:img_size) { [600.0, 600.0] }
    li = mat.lib_items('An Cường', 'mau02', 0, 10)
    kiem('Tìm mã trong bảng', li[:total] == 1 && li[:items][0][:code] == 'MAU02', li[:total].to_s)
    mat.open_dialog
    kiem('Mở bảng Thư viện vật liệu', !$dlgs.empty?)
    cab, ps = tu { |e| [tam(e, 'Hồi', [0, 0, 0], [18, 500, 700]), tam(e, 'Đáy', [18, 0, 0], [582, 500, 18])] }
    l, b = ps
    mat.current = nil
    $msg.clear
    m.selection.add(cab)
    mat.apply_to_selection
    kiem('Chưa chọn vật liệu: báo, không gán', l.material.nil? && $msg.join.include?('Chưa chọn vật liệu'))
    item = sc[:items].find { |x| x[:code] == 'MAU01' }
    mat.current = { src: 'lib', item: item }
    kiem('Nhãn vật liệu đang chọn', mat.current_label == 'MAU01')
    mat.apply_to_selection
    kiem('Gán cả khối tủ: mọi tấm có vật liệu, có vân', l.material && b.material && l.material.name == 'MAU01' && !l.material.texture.nil?, l.material && l.material.name)
    kiem('Kích thước vân 600 mm', l.material && gan(l.material.texture.width.to_f * M, 600, 0.5))
    kiem('Khối tủ không bị gán', cab.material.nil?)
    kiem('Danh sách vật liệu trong mô hình có mã vừa gán', mat.model_items('MAU01')[:total] == 1)
    Sketchup.undo
    kiem('Undo 1 bước gỡ cả khối', l.material.nil? && b.material.nil?)
    mat.apply_to_selection
    mat.rotate_selection(90, false)
    kiem('Xoay vân 90° (ghi góc, mặt được tô riêng)', gan(mat::Mapping.rot_of(l), 90) && l.definition.entities.grep(Sketchup::Face).all? { |f| f.material && f.material.name == 'MAU01' })
    mat.scale_selection(50)
    kiem('Tỉ lệ vân 50 %', gan(mat::Mapping.scale_of(l), 50))
    mat.reset_selection
    kiem('Bỏ chỉnh vân: giữ vật liệu tấm, sạch mặt', !mat::Mapping.styled?(l) && l.material && l.definition.entities.grep(Sketchup::Face).all? { |f| f.material.nil? })
    mat.remove_from_selection
    kiem('Gỡ vật liệu vùng chọn', l.material.nil? && b.material.nil?)
    m.selection.clear
    mat.start_paint
    tl = m.tools.active_tool
    kiem('Nút Tô tấm mở công cụ', tl.is_a?(mat.singleton_class::PaintTool), tl.class.to_s)
    bam(tl, nhin(cab, [300, 250, 18], [0, 0, 1]))
    kiem('1.1.2 Bấm thật vào khối tủ chưa mở: tô cả khối', b.material && b.material.name == 'MAU01' && l.material && l.material.name == 'MAU01' && cab.material.nil?)
    Sketchup.undo
    kiem('Undo tô (1 bước cả khối)', b.material.nil? && l.material.nil?)
    bam(tl, nhin(cab, [300, 250, 18], [0, 0, 1]), COPY_MODIFIER_MASK)
    kiem('1.1.2 Ctrl + bấm: chỉ tô đúng 1 tấm (không cần mở khối)', b.material && b.material.name == 'MAU01' && l.material.nil?)
    Sketchup.undo
    kiem('Undo tô', b.material.nil?)
    mat.current = { src: 'model', name: 'MAU01' }
    m.selection.add(l)
    mat.apply_to_selection
    kiem('Chọn 1 tấm + vật liệu trong mô hình: chỉ gán tấm đó', l.material && b.material.nil?)
  end

  muc('1.1.2 Thư viện vật liệu: bảng nhỏ, nhiều thư mục, tô nhanh, xoá màu cũ, lấy mẫu') do
    src = File.read(File.join(mat::DIR, 'material.rb'), encoding: 'UTF-8')
    kiem('Bảng mở 600×560, thu được tới 400×380, khoá nhớ cỡ mới', src.include?('width: 600, height: 560, min_width: 400, min_height: 380') && src.include?("'HoaTay_VatLieu_Dialog2'"))
    html = File.read(File.join(mat::DIR, 'dialog.html'), encoding: 'UTF-8')
    kiem('Bảng có + Thêm thư mục, ✕ bỏ thư mục, không còn nút Tô tấm', html.include?('+ Thêm thư mục') && html.include?('drop_root') && !html.include?('bPaint'))
    # 2 thư mục: thư mục chung nhiều hãng + thư mục riêng 1 hãng (tên hãng) có thư mục con dòng ván
    r1 = File.join(TMP, 'tv1'); r2 = File.join(TMP, 'tv2', 'Ba Thanh')
    FileUtils.mkdir_p(File.join(r1, 'An Cường - Melamine')); FileUtils.mkdir_p(File.join(r2, 'Laminate'))
    logo = File.join(gc::Core::ROOT_DIR, 'assets', 'logo.png')
    FileUtils.cp(logo, File.join(r1, 'An Cường - Melamine', 'AC01.png'))
    FileUtils.cp(logo, File.join(r2, 'Laminate', 'BT01.png'))
    FileUtils.cp(logo, File.join(r2, 'Laminate', 'BT02.png'))
    al = mat::Library.scan_all([r1, r2], true)
    bt = al[:brands].find { |x| x[:name] == 'Ba Thanh' }
    kiem('2 thư mục: đủ 2 hãng, 3 mã', al[:error].nil? && al[:items].size == 3 && al[:brands].map { |x| x[:name] }.sort == ['An Cường', 'Ba Thanh'], al[:brands].map { |x| x[:name] }.inspect)
    kiem('Thư mục 1 hãng: thư mục con = dòng ván', bt && bt[:count] == 2 && bt[:groups].map { |g| g[:name] } == ['Laminate'], bt.inspect[0, 120])
    mat.define_singleton_method(:roots) { [r1, r2] }
    li = mat.lib_items('Ba Thanh', '', 0, 10)
    kiem('Bảng lấy mã từ cả 2 thư mục', li[:total] == 2, li[:total].to_s)
    mat.define_singleton_method(:roots) { [r1, File.join(TMP, 'khong-co')] }
    kiem('1 thư mục mất: vẫn đọc thư mục còn lại, báo lỗi thư mục mất', mat.library(true)[:items].size == 1 && !mat.library[:error].nil?)
    mat.define_singleton_method(:roots) { [r1, r2] }

    # xoá màu cũ trước khi tô
    cab, ps = tu { |e| [tam(e, 'Hồi', [0, 0, 0], [18, 500, 700]), tam(e, 'Đáy', [18, 0, 0], [582, 500, 18])] }
    l, b = ps
    m.start_operation('màu cũ', true)
    red = m.materials['Đỏ thử'] || m.materials.add('Đỏ thử'); red.color = 'red'
    fs = b.definition.entities.grep(Sketchup::Face)
    fs.each { |f| f.material = red; f.back_material = red }
    band = fs.find { |f| f.normal.x.abs > 0.99 }
    band.set_attribute('fuji_dict', 'edge_banding', 'true')
    sub = b.definition.entities.add_group; sub.entities.add_face([1, 1, 0], [2, 1, 0], [2, 2, 0]); sub.material = red
    abf = b.definition.entities.add_group; abf.name = 'ABF_Intersect'; abf.set_attribute('ABF', 'is-intersect', true)
    af = abf.entities.add_face([3, 3, 0], [4, 3, 0], [4, 4, 0]); af.material = red
    m.commit_operation
    item = al[:items].find { |x| x[:code] == 'BT01' }
    mat.current = { src: 'lib', item: item }
    mat.start_paint(false)
    tl = m.tools.active_tool
    kiem('Bấm màu (start_paint) vào công cụ Tô ngay, không hỏi', tl.is_a?(mat.singleton_class::PaintTool))
    mat.start_paint(false)
    kiem('Đang tô bấm màu khác: giữ công cụ, không mở lại', m.tools.active_tool.equal?(tl))
    bam(tl, nhin(cab, [300, 250, 18], [0, 0, 1]), COPY_MODIFIER_MASK)
    fs2 = b.definition.entities.grep(Sketchup::Face)
    kiem('Tô: tấm nhận màu mới', b.material && b.material.name == 'BT01', b.material && b.material.name)
    kiem('Tô: xoá màu cũ trên các mặt (trừ mặt dán cạnh)', fs2.reject { |f| f.get_attribute('fuji_dict', 'edge_banding') == 'true' }.all? { |f| f.material.nil? && f.back_material.nil? })
    kiem('Giữ màu mặt dán cạnh', fs2.any? { |f| f.get_attribute('fuji_dict', 'edge_banding') == 'true' && f.material && f.material.name == 'Đỏ thử' })
    gs = b.definition.entities.grep(Sketchup::Group)
    kiem('Xoá màu group con thường', gs.find { |g| g.name != 'ABF_Intersect' }.material.nil?)
    kiem('Giữ màu nhóm liên kết ABF', gs.find { |g| g.name == 'ABF_Intersect' }.entities.grep(Sketchup::Face).all? { |f| f.material && f.material.name == 'Đỏ thử' })
    kiem('Tấm kia không bị đụng', l.material.nil?)
    Sketchup.undo
    kiem('Undo trả lại màu cũ', b.material.nil? && b.definition.entities.grep(Sketchup::Face).count { |f| f.material && f.material.name == 'Đỏ thử' } == 6)

    # gán cho vùng chọn cũng xoá màu cũ
    m.selection.clear; m.selection.add(cab)
    mat.apply_to_selection
    kiem('Gán cho vùng chọn cũng xoá màu cũ', b.material && b.definition.entities.grep(Sketchup::Face).count { |f| f.material && f.material.name == 'Đỏ thử' } == 1)
    m.selection.clear

    # lấy mẫu màu (Alt)
    mat.current = { src: 'model', name: 'MAU01' }
    mat.start_paint(false)
    tl = m.tools.active_tool
    bam(tl, nhin(cab, [300, 250, 18], [0, 0, 1]), ALT_MODIFIER_MASK)
    kiem('Alt + bấm: lấy mẫu màu tấm', mat.current_label == 'BT01', mat.current_label.to_s)
    kiem('Lấy mẫu không tô gì', l.material && l.material.name == 'BT01')
    # tấm không có màu tấm nhưng mặt có màu -> lấy màu mặt
    cab2, ps2 = tu { |e| [tam(e, 'Nóc', [0, 0, 0], [600, 500, 18])] }
    n = ps2[0]
    m.start_operation('mặt đỏ', true); n.definition.entities.grep(Sketchup::Face).each { |f| f.material = red }; m.commit_operation
    bam(tl, nhin(cab2, [300, 250, 18], [0, 0, 1]), ALT_MODIFIER_MASK)
    kiem('Alt + bấm tấm chỉ có màu mặt: lấy màu mặt', mat.current_label == 'Đỏ thử', mat.current_label.to_s)
    bam(tl, nhin(cab2, [300, 250, 18], [0, 0, 1]))
    kiem('Tô tiếp màu vừa lấy mẫu', n.material && n.material.name == 'Đỏ thử')

    # tấm rời ngoài khối tủ
    $ox += 4000.0
    m.start_operation('tấm rời', true); lo = tam(m.entities, 'Rời', [$ox, 0, 0], [$ox + 600, 400, 18]); m.commit_operation
    mat.current = { src: 'model', name: 'MAU01' }
    v = m.active_view
    t = p3([$ox + 300, 200, 18]); v.camera = Sketchup::Camera.new(t.offset(Z_AXIS, 3000 / M), t, Y_AXIS); v.refresh
    s = v.screen_coords(t)
    bam(tl, [s.x, s.y])
    kiem('Bấm tấm rời: tô tấm đó', lo.material && lo.material.name == 'MAU01')
    Sketchup.active_model.select_tool(nil)
  end

  muc('Dán cạnh') do
    cab, ps = tu { |e| [tam(e, 'Hồi', [0, 0, 0], [18, 500, 700]), tam(e, 'Đáy', [18, 0, 0], [582, 500, 18]), tam(e, 'Hậu', [18, 500, 0], [582, 508, 700])] }
    l, b, hau = ps
    wt = ->(p) { cab.transformation * p.transformation }
    list = edge.types
    kiem('Loại nẹp lấy từ luật D-05', !list.empty? && list.all? { |t| t['name'] && t['thick'] && t['color'] }, list.map { |t| t['name'] }.join(', '))
    so = ->(p) { edge::S.edge_faces(p, wt.(p), false).count { |f, _| edge.banded?(f) } }
    kiem('Tấm có 4 mặt cạnh', edge::S.edge_faces(b, wt.(b)).size == 4)
    # chạm tấm khác thì không dán: đáy chạm hồi (trái) + hậu (sau) -> dán 2 cạnh còn lại
    $tra_loi_input = true
    m.selection.add(cab)
    edge.auto_selection
    $tra_loi_input = false
    kiem('Dán tự động cả tủ: đáy dán 2 cạnh không chạm tấm khác', so.(b) == 2, so.(b).to_s)
    kiem('Hồi: không cạnh nào chạm mặt tấm khác nên dán đủ 4', so.(l) == 4, so.(l).to_s)
    dmax = edge.skip_max
    kiem("Luật D-06 (#{dmax.inspect}): hậu 8 không tự dán", dmax && dmax >= 8 ? so.(hau) == 0 : true, so.(hau).to_s)
    f = edge::S.edge_faces(b, wt.(b)).map(&:first).find { |x| edge.banded?(x) }
    t0 = list.first
    kiem('Chuẩn OneClick: lớp + fuji_dict đủ 4 thuộc tính', f.layer.name == 'OneClick_edge_banding' && f.get_attribute('fuji_dict', 'edge_banding') == 'true' && !f.get_attribute('fuji_dict', 'edge_type_name').to_s.empty? && !f.get_attribute('fuji_dict', 'edge_type_thick').to_s.empty? && !f.get_attribute('fuji_dict', 'edge_color').to_s.empty?, f.get_attribute('fuji_dict', 'edge_type_name').to_s)
    kiem('Mặt nẹp có màu nẹp', !f.material.nil?)
    Sketchup.undo
    kiem('Undo 1 bước gỡ cả đợt dán', so.(b) == 0 && so.(l) == 0)
    $tra_loi_input = true
    edge.auto_selection
    $tra_loi_input = false
    edge.remove_selection
    kiem('Gỡ nẹp vùng chọn: sạch', so.(b) == 0 && so.(l) == 0 && edge::S.edge_faces(b, wt.(b)).none? { |x, _| x.layer.name == 'OneClick_edge_banding' })
    m.selection.clear
    # dán tay
    tl = edge.singleton_class::HandTool.new(t0)
    m.select_tool(tl)
    s = nhin(cab, [300, 0, 9], [0, -1, 0])
    bam(tl, s)
    kiem("Dán tay: bấm cạnh đáy -> dán #{t0['name']}", so.(b) == 1, so.(b).to_s)
    bam(tl, s)
    kiem('Bấm lại: gỡ', so.(b) == 0)
    # bảng Dán cạnh
    html = edge.panel_html(list)
    kiem('Bảng Dán cạnh: tick loại, Không dán, Dán tất cả, Tự động', html.include?('name="t"') && html.include?('Không dán cạnh') && html.include?('Dán tất cả các cạnh') && html.include?('Tự động'))
    edge.open_panel
    kiem('Nút Dán cạnh mở bảng', !$dlgs.empty?)
    tl = edge.singleton_class::PanelTool.new(t0, false)
    m.select_tool(tl)
    s = nhin(cab, [300, 0, 9], [0, -1, 0])
    bam(tl, s)
    kiem('Bảng: bấm cạnh dán', so.(b) == 1, so.(b).to_s)
    tl.all = true
    bam(tl, s)
    kiem('Dán tất cả các cạnh: bấm tấm dán 4 cạnh', so.(b) == 4, so.(b).to_s)
    tl.type = :remove
    bam(tl, s)
    kiem('Không dán cạnh + tất cả: gỡ hết', so.(b) == 0, so.(b).to_s)
    Sketchup.undo
    kiem('Undo trả lại', so.(b) == 4, so.(b).to_s)
    m.select_tool(nil)
  end

  muc('Nhãn đã chuyển sang CNC') do
    pth = File.join(File.dirname(gc::Core::ROOT_DIR), 'hoatay_giacong', 'vatlieu', 'features', 'label')
    kiem('Không còn thư mục label trong Gia công', !File.exist?(pth), pth)
    kiem('Không còn module Label', !vl::Features.const_defined?(:Label, false))
    ten = vc.commands.map { |q| q[:cmd].menu_text }
    kiem('Không còn lệnh Gắn nhãn, Xóa nhãn', (ten & ['Gắn nhãn', 'Xóa nhãn']).empty?, ten.inspect[0, 120])
    van = HoaTay::CNC::Features::Van
    cab, ps = tu { |e| [tam(e, 'Đáy', [18, 0, 0], [582, 500, 18])] }
    b = ps[0]
    m.selection.clear; m.selection.add(cab)
    van.make_selection
    kiem('CNC gắn nhãn trên tấm', van.labels(b).size == 1)
    mat.current = { src: 'model', name: 'MAU01' }
    m.selection.clear; m.selection.add(b)
    mat.apply_to_selection
    mat.rotate_selection(90, false)
    x = van.labels(b)[0].transformation.xaxis
    kiem('Xoay vân 90° ở Gia công: mũi tên CNC xoay theo', x.parallel?(Y_AXIS), [x.x, x.y, x.z].map { |v| v.round(3) }.inspect)
    kiem('Xoay vân ghi custom_grain', b.get_attribute('fuji_dict', 'custom_grain').to_f == 90.0, b.get_attribute('fuji_dict', 'custom_grain').inspect)
    van.remove(b)
    mat.rotate_selection(0, false)
    kiem('Tấm chưa gắn nhãn: xoay vân không tự tạo nhãn', van.labels(b).empty?)
  end

  muc('Luật') do
    r = HoaTay::Rules
    sec = r.sections_for(gc::Core::LUAT)
    codes = sec.flat_map { |s| s['groups'].flat_map { |g| g['rules'].map(&:first) } }
    kiem('Bảng luật Gia công chỉ hiện D-, L-, V-', !codes.empty? && codes.all? { |c| c =~ /\A[DLV]-/ } && codes.include?('L-02') && codes.include?('D-05'), "#{codes.size} mã")
    kiem('Đọc được luật đang có', r.get('D-05').is_a?(Array), r.active_name)
    goc = r.active['values']['L-02']
    fired = 0
    r.on_change { fired += 1 }
    kiem('Sửa 1 luật', r.set_value('L-02', '41').nil? && r.get('L-02') == 41 && fired > 0, r.get('L-02').inspect)
    kiem('Giá trị sai: báo lỗi, không ghi', !r.set_value('L-02', 'abc').nil? && r.get('L-02') == 41)
    r.reload!
    kiem('Lưu ra file (bản sao), đọc lại đúng', r.get('L-02') == 41)
    r.set_value('L-02', '')
    kiem('Luật trống: báo thiếu, không tự nghĩ số', r.missing(['L-02']) == ['L-02'] && (begin; r.get('L-02'); false; rescue HoaTay::Rules::Missing; true; end))
    r.set_value('L-02', goc.to_s)
    n0 = r.sets.size
    s = r.add_set('Bộ thử', r.active['id'])
    kiem('Thêm bộ luật (chép từ bộ đang dùng)', r.sets.size == n0 + 1 && s['values']['D-05'] == r.active['values']['D-05'])
    id0 = r.active['id']
    r.activate(s['id'])
    kiem('Đổi bộ đang dùng', r.active['id'] == s['id'])
    r.rename_set(s['id'], 'Bộ thử 2')
    kiem('Đổi tên bộ', r.active_name == 'Bộ thử 2')
    f = File.join(TMP, 'xuat.json')
    r.export_set(s['id'], f)
    n = r.import_set(f)
    kiem('Xuất / nhập bộ luật', File.exist?(f) && r.sets.size == n0 + 2 && n['values'].size > 0, n['name'])
    r.activate(id0)
    r.remove_set(n['id']); r.remove_set(s['id'])
    kiem('Xóa bộ', r.sets.size == n0)
    r.show(nil, only: gc::Core::LUAT, title: 'Luật – HoaTay Gia công')
    kiem('Mở cửa sổ Luật của Gia công', !$dlgs.empty?)
    own = gc.commands.find { |c| c[:cmd].menu_text == 'Luật...' }
    kiem('Lệnh Luật có trong menu, không ở thanh công cụ', own && own[:toolbar] == false)
  end

  muc('16 icon mới') do
    map = {
      'vatlieu/features/material/icons/paint.svg' => 'to-vat-lieu', 'vatlieu/features/material/icons/remove.svg' => 'go-vat-lieu', 'vatlieu/features/material/icons/library.svg' => 'thu-vien-vat-lieu',
      'vatlieu/features/edge/icons/edge_auto.svg' => 'dan-canh-tu-dong', 'vatlieu/features/edge/icons/edge_hand.svg' => 'dan-canh-tay', 'vatlieu/features/edge/icons/edge_remove.svg' => 'go-dan-canh',
            'lienket/features/lienket/icons/lienket.svg' => 'lien-ket-cam', 'lienket/features/mong/icons/mong.svg' => 'mong-go', 'lienket/features/amduong/icons/amduong.svg' => 'am-duong',
      'lienket/features/ngam/icons/ngam.svg' => 'ngam-dinh-vi', 'lienket/features/ranh/icons/ranh.svg' => 'phay-ranh', 'lienket/features/khau/icons/khau.svg' => 'khau-van',
      'lienket/features/khu/icons/khu.svg' => 'khu-dao', 'lienket/features/ray/icons/ray.svg' => 'danh-dau-ray', 'lienket/features/settings/icons/settings.svg' => 'cai-dat', 'lib/luat/icons/rules.svg' => 'luat'
    }
    root = gc::Core::ROOT_DIR
    sai = map.reject { |rel, ten| File.binread(File.join(root, rel)) == File.binread(File.join(ICON_DUYET, "#{ten}.svg")) }
    kiem('16 file icon trong plugin đã cài giống từng byte bản Dương duyệt', map.size == 16 && sai.empty?, sai.keys.join(', '))
    khong = map.keys.reject { |rel| s = File.read(File.join(root, rel), encoding: 'UTF-8'); s.include?('viewBox="0 0 48 48"') && !s.include?('<style') }
    kiem('Icon viewBox 48, không CSS', khong.empty?, khong.join(', '))
    cmds = gc.commands.map { |c| c[:cmd] }
    dung_icon = cmds.map { |c| File.expand_path(c.small_icon.to_s).downcase }.uniq
    chua = map.keys.reject { |rel| dung_icon.include?(File.expand_path(File.join(root, rel)).downcase) }
    kiem('Mọi icon đều có lệnh dùng (nút hoặc menu)', chua.empty?, chua.join(', '))
    kiem('Lệnh dùng icon lớn = nhỏ, file có thật', cmds.all? { |c| c.small_icon == c.large_icon && File.exist?(c.small_icon.to_s) })
  end
end

def thu_tu_nut
  gc = HoaTay::GiaCong
  muc('Thanh công cụ + thứ tự nút') do
    ht = gc.hien_thi
    ten_nut = ->(h) { h.instance_variable_get(:@tb).select { |x| x.respond_to?(:menu_text) }.map(&:menu_text) } # bỏ dấu phân cách
    giu = Sketchup.read_default('HoaTay_HienThi', 'giacong_thu_tu', '')
    an = Sketchup.read_default('HoaTay_HienThi', 'giacong', '')
    Sketchup.write_default('HoaTay_HienThi', 'giacong', '')
    ht.reset_order
    tb = ht.instance_variable_get(:@tb)
    nut = tb.select { |x| x.respond_to?(:small_icon) }.map { |c| File.basename(c.small_icon.to_s, '.svg') }
    goc = %w[mong khu khau ngam lienket amduong ranh ray settings]
    cuoi = %w[library paint remove edge_hand label label_remove]
    kiem('Thứ tự nút gốc: Liên kết rồi Vật liệu', (nut - goc - cuoi).empty? && nut.select { |x| goc.include?(x) } == nut.select { |x| goc.include?(x) }.sort_by { |x| goc.index(x) } && nut.first(goc.size).sort == goc.sort, nut.join(' '))
    $kq << "  (thanh công cụ có #{nut.size} nút; 3 lệnh chỉ ở menu từ 1.0.7/1.0.8: Dán nẹp tự động, Gỡ nẹp, Luật)"
    st0 = ht.state
    tb0 = st0.select { |s| s[:tb] }.map { |s| s[:name] }
    ht.move(st0.index { |s| s[:tb] }, 1)
    tb1 = ht.state.select { |s| s[:tb] }.map { |s| s[:name] }
    kiem('▼ nút đầu: đổi chỗ nút 2', tb1[0] == tb0[1] && tb1[1] == tb0[0], tb1.first(2).inspect)
    st1 = ht.state
    ht.move(st1.rindex { |s| s[:tb] }, -1)
    tb2 = ht.state.select { |s| s[:tb] }.map { |s| s[:name] }
    kiem('▲ nút cuối: lên 1 bậc', tb2[-2] == tb1[-1] && tb2[-1] == tb1[-2])
    shown = ten_nut.(ht)
    kiem('Thanh công cụ dựng lại ngay đúng thứ tự mới', shown == tb2, shown.inspect[0, 80])
    kiem('Nhớ thứ tự cho lần sau', !Sketchup.read_default('HoaTay_HienThi', 'giacong_thu_tu', '').to_s.empty?)
    ht.reset_order
    kiem('Về thứ tự gốc', ht.state.select { |s| s[:tb] }.map { |s| s[:name] } == tb0)
    ten = tb0.last
    ht.set(ten, false)
    sh = ten_nut.(ht)
    kiem('Hiển thị tính năng: tắt nút thì ẩn ngay', sh.size == tb0.size - 1 && !sh.include?(ten), "#{ten}: còn #{sh.size} nút")
    ht.set(ten, true)
    kiem('Bật lại thì hiện', ten_nut.(ht) == tb0, "#{ten_nut.(ht).size} nút")
    ht.show
    kiem('Mở bảng Hiển thị tính năng', !$dlgs.empty?)
    Sketchup.write_default('HoaTay_HienThi', 'giacong_thu_tu', giu)
    Sketchup.write_default('HoaTay_HienThi', 'giacong', an)
  end
  muc('Ruby Console') do
    kiem('Không có lỗi plugin ghi ra console', $loi_log.empty?, $loi_log.first(3).join(' / '))
    bad = $msg.select { |x| x.start_with?('Lỗi (') }
    kiem('Không có hộp báo "Lỗi (...)"', bad.empty?, bad.first(3).join(' / '))
  end
  $kq << "\nTỔNG: #{$dat}/#{$tong} ĐẠT"
  luu
  FileUtils.rm_rf(TMP) rescue nil
  File.write(File.join(DIR, 'ket-qua.txt'), 'xong')
end

UI.start_timer(10, false) do
  HoaTay::CapNhat.define_singleton_method(:check) { |*| nil } if defined?(HoaTay::CapNhat)
  begin
    chay_test
  rescue Exception => e
    kiem('Lỗi test: ' + e.message, false, (e.backtrace || []).first(4).join(' / '))
  end
  # chụp thanh công cụ gốc lúc khởi động + Ruby Console, rồi mới test đổi thứ tự nút
  begin
    SKETCHUP_CONSOLE.show
    puts "HoaTay Gia công #{HoaTay::GiaCong::Core::VERSION} – test xong phần chức năng: #{$dat}/#{$tong} ĐẠT"
    tb = UI::Toolbar.new('HoaTay Gia công')
    tb.show
    ($mo || []).each { |d| d.close rescue nil }
    Sketchup.active_model.active_view.zoom_extents
    UI.start_timer(3, false) { File.write(File.join(DIR, 'san-sang-chup.txt'), 'ok') } # đợi hộp thoại đóng hẳn
  rescue Exception => e
    kiem('Lỗi chuẩn bị chụp: ' + e.message, false)
  end
  t0 = Time.now
  id = nil
  id = UI.start_timer(1, true) do
    if File.exist?(File.join(DIR, 'da-chup.txt')) || Time.now - t0 > 90
      UI.stop_timer(id)
      thu_tu_nut
    end
  end
end

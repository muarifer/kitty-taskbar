import CoreGraphics

/// Popover'ın menü çubuğu altındaki dikey konumu için saf hesaplama.
///
/// macOS 26 (Tahoe) bazı kurulumlarda popover'ı simgenin epey altında açıyor
/// (issue #1: simge ile açılır pencere arasında büyük boşluk). Sağlıklı davranışta
/// popover penceresinin üst kenarı menü çubuğunun alt kenarına yapışık olur; burada
/// ölçülen sapma bu eşikten büyükse pencereyi yukarı çekiyoruz.
enum PopoverLayout {
    /// Doğru konumda popover penceresinin üstü menü çubuğunun 1pt içine taşar.
    static let menuBarOverlap: CGFloat = 1
    /// Bu kadar puana kadar sapmalar (gölge/ok ölçüsü farkları) yok sayılır.
    static let tolerance: CGFloat = 8

    /// Popover olması gerekenden aşağıda açıldıysa düzeltilmiş `origin.y` değerini,
    /// konum zaten doğruysa `nil` döner. Yalnızca aşağı kaymayı düzeltir; popover'ı
    /// hiçbir zaman menü çubuğunun içine doğru yukarı itmez.
    static func correctedOriginY(popoverFrame: CGRect, menuBarBottom: CGFloat) -> CGFloat? {
        let delta = (menuBarBottom + menuBarOverlap) - popoverFrame.maxY
        guard delta > tolerance else { return nil }
        return popoverFrame.origin.y + delta
    }
}
